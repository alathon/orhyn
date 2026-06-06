package orchestrator

import (
	"errors"
	"testing"
	"time"
)

type fakeSocket struct {
	writes []Message
	closed bool
}

func (f *fakeSocket) ReadMessage() (int, []byte, error) {
	return 0, nil, errors.New("not implemented")
}

func (f *fakeSocket) WriteJSON(v interface{}) error {
	msg, ok := v.(Message)
	if !ok {
		return errors.New("expected Message")
	}
	f.writes = append(f.writes, msg)
	return nil
}

func (f *fakeSocket) Close() error {
	f.closed = true
	return nil
}

func testState() (*state, func(time.Duration)) {
	cfg := DefaultConfig()
	cfg.DefaultZoneID = "mvp"
	cfg.TransferTTL = 30 * time.Second
	cfg.HeartbeatTimeout = 15 * time.Second

	current := time.Unix(1000, 0)
	s := newState(cfg)
	s.now = func() time.Time { return current }

	advance := func(d time.Duration) {
		current = current.Add(d)
	}
	return s, advance
}

func TestLoginCharacterSelectRedirectsClient(t *testing.T) {
	s, _ := testState()
	zonePeer := s.addGamePeer(&fakeSocket{})
	clientPeer := s.addClientPeer(&fakeSocket{})

	s.registerZone(zonePeer.id, Message{
		Type:       TypeZoneRegister,
		ZoneID:     "mvp",
		Address:    "127.0.0.1",
		Port:       4242,
		MaxPlayers: 32,
	})

	login, displayName := s.handleLoginRequest(clientPeer.id, " Martin ")
	if displayName != "Martin" {
		t.Fatalf("expected trimmed display name, got %q", displayName)
	}
	if login.Type != TypeLoginResponse || len(login.Characters) != 1 {
		t.Fatalf("unexpected login response: %#v", login)
	}

	redirect, prepare, err := s.handleCharacterSelectRequest(clientPeer.id, placeholderCharacterID)
	if err != nil {
		t.Fatalf("character select failed: %v", err)
	}
	if prepare != nil {
		t.Fatalf("did not expect prepare_player message: %#v", prepare)
	}
	if redirect.Type != TypeZoneRedirect {
		t.Fatalf("expected zone redirect, got %#v", redirect)
	}
	if redirect.TransferToken == "" {
		t.Fatal("expected transfer token")
	}
	if redirect.Address != "127.0.0.1" || redirect.Port != 4242 {
		t.Fatalf("unexpected redirect destination: %#v", redirect)
	}
}

func TestZoneTransferPrepareAckRespondsToOrigin(t *testing.T) {
	s, _ := testState()
	originPeer := s.addGamePeer(&fakeSocket{})
	destPeer := s.addGamePeer(&fakeSocket{})

	s.registerZone(originPeer.id, Message{Type: TypeZoneRegister, ZoneID: "forest", Address: "10.0.0.1", Port: 4242})
	s.registerZone(destPeer.id, Message{Type: TypeZoneRegister, ZoneID: "mvp", Address: "10.0.0.2", Port: 4243})

	prepare, destinationPeerID, err := s.handleZoneTransferRequest(originPeer.id, Message{
		Type:           TypeZoneTransferRequest,
		FromZoneID:     "forest",
		ToZoneID:       "mvp",
		PeerID:         7,
		EntrySpawnPath: "ZoneBorders/FromForestZone",
		PlayerState: PlayerState{
			HP:          80,
			DisplayName: "Runner",
			CharacterID: 1,
		},
	})
	if err != nil {
		t.Fatalf("transfer request failed: %v", err)
	}
	if destinationPeerID != destPeer.id {
		t.Fatalf("expected destination peer %d, got %d", destPeer.id, destinationPeerID)
	}
	if prepare.Type != TypePreparePlayer || prepare.TransferToken == "" {
		t.Fatalf("unexpected prepare message: %#v", prepare)
	}

	response, responsePeerID, err := s.handlePreparePlayerAck(destPeer.id, Message{
		Type:          TypePreparePlayerAck,
		TransferToken: prepare.TransferToken,
		Accepted:      true,
	})
	if err != nil {
		t.Fatalf("prepare ack failed: %v", err)
	}
	if responsePeerID != originPeer.id {
		t.Fatalf("expected response to origin peer %d, got %d", originPeer.id, responsePeerID)
	}
	if response.Type != TypeZoneTransferResponse || response.PeerID != 7 {
		t.Fatalf("unexpected transfer response: %#v", response)
	}
	if response.TargetAddress != "10.0.0.2" || response.TargetPort != 4243 {
		t.Fatalf("unexpected transfer target: %#v", response)
	}
}

func TestZoneTransferRejectsUnknownDestination(t *testing.T) {
	s, _ := testState()
	originPeer := s.addGamePeer(&fakeSocket{})

	_, _, err := s.handleZoneTransferRequest(originPeer.id, Message{
		Type:       TypeZoneTransferRequest,
		FromZoneID: "forest",
		ToZoneID:   "missing",
		PeerID:     7,
	})
	if !errors.Is(err, errUnknownDestinationZone) {
		t.Fatalf("expected unknown destination error, got %v", err)
	}
}

func TestHeartbeatTimeoutRemovesRegisteredZone(t *testing.T) {
	s, advance := testState()
	zonePeer := s.addGamePeer(&fakeSocket{})
	s.registerZone(zonePeer.id, Message{Type: TypeZoneRegister, ZoneID: "mvp", Address: "127.0.0.1", Port: 4242})

	advance(s.cfg.HeartbeatTimeout + time.Second)
	timedOut := s.timedOutGamePeers()
	if len(timedOut) != 1 || timedOut[0].id != zonePeer.id {
		t.Fatalf("expected timed out zone peer, got %#v", timedOut)
	}

	s.removeGamePeer(zonePeer.id)
	if _, ok := s.zones["mvp"]; ok {
		t.Fatal("expected zone registration to be removed")
	}
}

func TestQueuedCharacterSelectBecomesReadyWhenZoneRegisters(t *testing.T) {
	s, advance := testState()
	clientPeer := s.addClientPeer(&fakeSocket{})

	_, prepare, err := s.handleCharacterSelectRequest(clientPeer.id, placeholderCharacterID)
	if !errors.Is(err, errUnknownDestinationZone) {
		t.Fatalf("expected queue due to missing zone, got prepare=%#v err=%v", prepare, err)
	}
	if len(s.pendingCharacterQueue) != 1 {
		t.Fatalf("expected queued selection, got %d", len(s.pendingCharacterQueue))
	}

	zonePeer := s.addGamePeer(&fakeSocket{})
	s.registerZone(zonePeer.id, Message{Type: TypeZoneRegister, ZoneID: "mvp", Address: "127.0.0.1", Port: 4242})
	advance(s.cfg.LoginRetryInterval + time.Second)

	ready := s.retryQueuedCharacterSelects()
	if len(ready) != 1 {
		t.Fatalf("expected queued selection to become ready, got %d", len(ready))
	}
}

func TestExpiredDisconnectReservationIsCleared(t *testing.T) {
	s, advance := testState()
	s.reserveDisconnectedCharacter(Message{
		Type:        TypeCharacterDisconnectedReserve,
		CharacterID: 1,
		ZoneID:      "mvp",
		ExpiresUnix: s.now().Add(5 * time.Second).Unix(),
	})
	if !s.isCharacterDisconnectReserved(1) {
		t.Fatal("expected character to be reserved")
	}

	advance(6 * time.Second)
	if s.isCharacterDisconnectReserved(1) {
		t.Fatal("expected character reservation to expire")
	}
}
