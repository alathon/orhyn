package orchestrator

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	placeholderCharacterID = 1
	placeholderModelName   = "Wizard"
)

var (
	errUnknownDestinationZone = errors.New("destination zone is not registered")
	errUnknownTransferToken   = errors.New("transfer token is unknown")
	errCharacterReserved      = errors.New("character is still disconnecting")
)

type zone struct {
	ZoneID         string
	PeerID         int64
	Address        string
	Port           int
	MaxPlayers     int
	CurrentPlayers int
}

type transfer struct {
	Token        string
	FromZoneID   string
	ToZoneID     string
	PeerID       int64
	OriginPeerID int64
	DestPeerID   int64
	CreatedAt    time.Time
	IsLogin      bool
	ClientPeerID int64
}

type disconnectedCharacter struct {
	ZoneID      string
	ExpiresUnix int64
}

type queuedCharacterSelect struct {
	ClientPeerID int64
	CharacterID  int64
	ZoneID       string
	RetryAt      time.Time
}

type state struct {
	mu sync.Mutex

	cfg Config
	now func() time.Time

	zones                  map[string]zone
	peerZones              map[int64]string
	gamePeers              map[int64]*peer
	clientPeers            map[int64]*peer
	clientDisplayNames     map[int64]string
	disconnectedCharacters map[int64]disconnectedCharacter
	pendingTransfers       map[string]transfer
	pendingCharacterQueue  []queuedCharacterSelect
	lastHeartbeatAck       map[int64]time.Time

	nextGamePeerID   int64
	nextClientPeerID int64
	nextPingID       int64
}

func newState(cfg Config) *state {
	return &state{
		cfg:                    cfg,
		now:                    time.Now,
		zones:                  make(map[string]zone),
		peerZones:              make(map[int64]string),
		gamePeers:              make(map[int64]*peer),
		clientPeers:            make(map[int64]*peer),
		clientDisplayNames:     make(map[int64]string),
		disconnectedCharacters: make(map[int64]disconnectedCharacter),
		pendingTransfers:       make(map[string]transfer),
		lastHeartbeatAck:       make(map[int64]time.Time),
		nextGamePeerID:         1,
		nextClientPeerID:       10000,
	}
}

func (s *state) addGamePeer(conn socket) *peer {
	s.mu.Lock()
	defer s.mu.Unlock()

	p := &peer{id: s.nextGamePeerID, conn: conn}
	s.nextGamePeerID++
	s.gamePeers[p.id] = p
	s.lastHeartbeatAck[p.id] = s.now()
	return p
}

func (s *state) addClientPeer(conn socket) *peer {
	s.mu.Lock()
	defer s.mu.Unlock()

	p := &peer{id: s.nextClientPeerID, conn: conn}
	s.nextClientPeerID++
	s.clientPeers[p.id] = p
	return p
}

func (s *state) removeGamePeer(peerID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if zoneID, ok := s.peerZones[peerID]; ok {
		delete(s.zones, zoneID)
		delete(s.peerZones, peerID)
	}
	delete(s.gamePeers, peerID)
	delete(s.lastHeartbeatAck, peerID)
}

func (s *state) removeClientPeer(peerID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.clientPeers, peerID)
	delete(s.clientDisplayNames, peerID)
}

func (s *state) registerZone(peerID int64, msg Message) zone {
	s.mu.Lock()
	defer s.mu.Unlock()

	z := zone{
		ZoneID:         msg.ZoneID,
		PeerID:         peerID,
		Address:        msg.Address,
		Port:           msg.Port,
		MaxPlayers:     msg.MaxPlayers,
		CurrentPlayers: msg.CurrentPlayers,
	}
	s.zones[z.ZoneID] = z
	s.peerZones[peerID] = z.ZoneID
	return z
}

func (s *state) handleLoginRequest(clientPeerID int64, username string) (Message, string) {
	displayName := placeholderDisplayName(username)

	s.mu.Lock()
	s.clientDisplayNames[clientPeerID] = displayName
	s.mu.Unlock()

	return Message{
		Type: TypeLoginResponse,
		Characters: []Character{{
			CharacterID: placeholderCharacterID,
			DisplayName: displayName,
			ZoneID:      s.cfg.DefaultZoneID,
			ModelName:   placeholderModelName,
			Level:       1,
		}},
	}, displayName
}

func (s *state) handleCharacterSelectRequest(clientPeerID, characterID int64) (Message, *Message, error) {
	if characterID != placeholderCharacterID {
		return Message{Type: TypeCharacterSelectFailure, Reason: "Selected character is not available."}, nil, nil
	}
	if s.isCharacterDisconnectReserved(characterID) {
		return Message{Type: TypeCharacterSelectFailure, Reason: "That character is still disconnecting. Try again shortly."}, nil, errCharacterReserved
	}

	msg, err := s.createInitialZoneRedirect(clientPeerID, characterID, s.cfg.DefaultZoneID)
	if err == nil {
		return msg, nil, nil
	}
	if errors.Is(err, errUnknownDestinationZone) {
		s.queueCharacterSelect(clientPeerID, characterID, s.cfg.DefaultZoneID)
		return Message{}, nil, err
	}
	return Message{Type: TypeCharacterSelectFailure, Reason: err.Error()}, nil, err
}

func (s *state) createInitialZoneRedirect(clientPeerID, characterID int64, zoneID string) (Message, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	dest, ok := s.zones[zoneID]
	if !ok {
		return Message{}, errUnknownDestinationZone
	}

	token, err := generateToken()
	if err != nil {
		return Message{}, err
	}

	s.pendingTransfers[token] = transfer{
		Token:        token,
		ToZoneID:     zoneID,
		DestPeerID:   dest.PeerID,
		CreatedAt:    s.now(),
		IsLogin:      true,
		ClientPeerID: clientPeerID,
	}

	return Message{
		Type:          TypeZoneRedirect,
		ZoneID:        zoneID,
		Address:       dest.Address,
		Port:          dest.Port,
		CharacterID:   characterID,
		TransferToken: token,
	}, nil
}

func (s *state) handleZoneTransferRequest(originPeerID int64, msg Message) (*Message, int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	dest, ok := s.zones[msg.ToZoneID]
	if !ok {
		return nil, 0, errUnknownDestinationZone
	}
	token, err := generateToken()
	if err != nil {
		return nil, 0, err
	}

	s.pendingTransfers[token] = transfer{
		Token:        token,
		FromZoneID:   msg.FromZoneID,
		ToZoneID:     msg.ToZoneID,
		PeerID:       msg.PeerID,
		OriginPeerID: originPeerID,
		DestPeerID:   dest.PeerID,
		CreatedAt:    s.now(),
	}

	return &Message{
		Type:           TypePreparePlayer,
		TransferToken:  token,
		EntrySpawnPath: msg.EntrySpawnPath,
		PlayerState:    msg.PlayerState,
	}, dest.PeerID, nil
}

func (s *state) handlePreparePlayerAck(destPeerID int64, msg Message) (*Message, int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	t, ok := s.pendingTransfers[msg.TransferToken]
	if !ok {
		return nil, 0, errUnknownTransferToken
	}
	if !msg.Accepted {
		delete(s.pendingTransfers, msg.TransferToken)
		return nil, 0, nil
	}

	dest, ok := s.zones[t.ToZoneID]
	if !ok {
		delete(s.pendingTransfers, msg.TransferToken)
		return nil, 0, errUnknownDestinationZone
	}
	if t.DestPeerID != destPeerID {
		return nil, 0, errors.New("prepare ack came from a peer that does not own the transfer")
	}
	delete(s.pendingTransfers, msg.TransferToken)

	if t.IsLogin {
		return &Message{
			Type:          TypeZoneRedirect,
			ZoneID:        t.ToZoneID,
			Address:       dest.Address,
			Port:          dest.Port,
			TransferToken: msg.TransferToken,
		}, t.ClientPeerID, nil
	}

	return &Message{
		Type:          TypeZoneTransferResponse,
		PeerID:        t.PeerID,
		TransferToken: msg.TransferToken,
		TargetAddress: dest.Address,
		TargetPort:    dest.Port,
		ZoneID:        t.ToZoneID,
	}, t.OriginPeerID, nil
}

func (s *state) reserveDisconnectedCharacter(msg Message) {
	if msg.CharacterID <= 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.disconnectedCharacters[msg.CharacterID] = disconnectedCharacter{
		ZoneID:      msg.ZoneID,
		ExpiresUnix: msg.ExpiresUnix,
	}
}

func (s *state) clearDisconnectedCharacter(characterID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.disconnectedCharacters, characterID)
}

func (s *state) recordHeartbeatAck(peerID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastHeartbeatAck[peerID] = s.now()
}

func (s *state) nextHeartbeat() (Message, []*peer) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.nextPingID++
	peers := make([]*peer, 0, len(s.gamePeers))
	for _, p := range s.gamePeers {
		peers = append(peers, p)
	}
	return Message{Type: TypeHeartbeat, PingID: s.nextPingID}, peers
}

func (s *state) timedOutGamePeers() []*peer {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	var timedOut []*peer
	for peerID, lastAck := range s.lastHeartbeatAck {
		if now.Sub(lastAck) > s.cfg.HeartbeatTimeout {
			if p, ok := s.gamePeers[peerID]; ok {
				timedOut = append(timedOut, p)
			}
		}
	}
	return timedOut
}

func (s *state) expireTransfers() int {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	expired := 0
	for token, t := range s.pendingTransfers {
		if now.Sub(t.CreatedAt) > s.cfg.TransferTTL {
			delete(s.pendingTransfers, token)
			expired++
		}
	}
	return expired
}

func (s *state) retryQueuedCharacterSelects() []queuedCharacterSelect {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	var ready []queuedCharacterSelect
	remaining := s.pendingCharacterQueue[:0]
	for _, entry := range s.pendingCharacterQueue {
		if _, ok := s.clientPeers[entry.ClientPeerID]; !ok {
			continue
		}
		if now.Before(entry.RetryAt) {
			remaining = append(remaining, entry)
			continue
		}
		if _, ok := s.zones[entry.ZoneID]; !ok {
			entry.RetryAt = now.Add(s.cfg.LoginRetryInterval)
			remaining = append(remaining, entry)
			continue
		}
		ready = append(ready, entry)
	}
	s.pendingCharacterQueue = remaining
	return ready
}

func (s *state) getGamePeer(peerID int64) *peer {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.gamePeers[peerID]
}

func (s *state) getClientPeer(peerID int64) *peer {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.clientPeers[peerID]
}

func (s *state) getZonePeerID(zoneID string) (int64, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	z, ok := s.zones[zoneID]
	if !ok {
		return 0, false
	}
	return z.PeerID, true
}

func (s *state) healthSnapshot() map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()

	zoneIDs := make([]string, 0, len(s.zones))
	for zoneID := range s.zones {
		zoneIDs = append(zoneIDs, zoneID)
	}
	sort.Strings(zoneIDs)

	return map[string]interface{}{
		"game_server_port":  s.cfg.GameServerPort,
		"client_port":       s.cfg.ClientPort,
		"registered_zones":  len(s.zones),
		"zone_ids":          zoneIDs,
		"game_server_peers": len(s.gamePeers),
		"client_peers":      len(s.clientPeers),
		"pending_transfers": len(s.pendingTransfers),
	}
}

func (s *state) isCharacterDisconnectReserved(characterID int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	reserved, ok := s.disconnectedCharacters[characterID]
	if !ok {
		return false
	}
	if s.now().Unix() >= reserved.ExpiresUnix {
		delete(s.disconnectedCharacters, characterID)
		return false
	}
	return true
}

func (s *state) queueCharacterSelect(clientPeerID, characterID int64, zoneID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.pendingCharacterQueue = append(s.pendingCharacterQueue, queuedCharacterSelect{
		ClientPeerID: clientPeerID,
		CharacterID:  characterID,
		ZoneID:       zoneID,
		RetryAt:      s.now().Add(s.cfg.LoginRetryInterval),
	})
}

func generateToken() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func placeholderDisplayName(username string) string {
	trimmed := strings.TrimSpace(username)
	if trimmed == "" {
		return "Player"
	}
	return trimmed
}
