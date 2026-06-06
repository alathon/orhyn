package orchestrator

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"
)

type Service struct {
	cfg      Config
	state    *state
	log      *log.Logger
	acceptor websocketAcceptor

	gameServer   *http.Server
	clientServer *http.Server
	healthServer *http.Server

	started sync.Once
}

func NewService(cfg Config, logger *log.Logger) *Service {
	if logger == nil {
		logger = log.Default()
	}
	return &Service{
		cfg:      cfg,
		state:    newState(cfg),
		log:      logger,
		acceptor: newWebsocketAcceptor(),
	}
}

func (s *Service) Start(ctx context.Context) error {
	var err error
	s.started.Do(func() {
		s.gameServer = s.newHTTPServer(s.cfg.GameServerPort, s.handleGameServerSocket())
		s.clientServer = s.newHTTPServer(s.cfg.ClientPort, s.handleClientSocket())
		s.healthServer = s.newHTTPServer(s.cfg.HealthPort, s.handleHealth())

		var gameListener net.Listener
		var clientListener net.Listener
		var healthListener net.Listener
		gameListener, err = s.listen("game-server", s.gameServer)
		if err != nil {
			return
		}
		clientListener, err = s.listen("client", s.clientServer)
		if err != nil {
			_ = gameListener.Close()
			return
		}
		healthListener, err = s.listen("health", s.healthServer)
		if err != nil {
			_ = gameListener.Close()
			_ = clientListener.Close()
			return
		}

		go s.serve("game-server", s.gameServer, gameListener)
		go s.serve("client", s.clientServer, clientListener)
		go s.serve("health", s.healthServer, healthListener)
		go s.runMaintenance(ctx)
	})
	if err != nil {
		return err
	}

	<-ctx.Done()
	return nil
}

func (s *Service) Shutdown(ctx context.Context) error {
	var errs []error
	for _, srv := range []*http.Server{s.gameServer, s.clientServer, s.healthServer} {
		if srv == nil {
			continue
		}
		if err := srv.Shutdown(ctx); err != nil {
			errs = append(errs, err)
		}
	}
	if len(errs) > 0 {
		return errs[0]
	}
	return nil
}

func (s *Service) newHTTPServer(port int, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              net.JoinHostPort(s.cfg.ListenAddress, fmt.Sprintf("%d", port)),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
}

func (s *Service) listen(name string, srv *http.Server) (net.Listener, error) {
	listener, err := net.Listen("tcp", srv.Addr)
	if err != nil {
		return nil, fmt.Errorf("%s listen on %s: %w", name, srv.Addr, err)
	}
	return listener, nil
}

func (s *Service) serve(name string, srv *http.Server, listener net.Listener) {
	s.log.Printf("area=network message=listening service=%s address=%s", name, listener.Addr())
	if err := srv.Serve(listener); err != nil && err != http.ErrServerClosed {
		s.log.Printf("area=network message=listen_failed service=%s error=%q", name, err)
	}
}

func (s *Service) handleGameServerSocket() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := s.acceptor.accept(w, r)
		if err != nil {
			s.log.Printf("area=network message=game_server_upgrade_failed error=%q", err)
			return
		}
		p := s.state.addGamePeer(conn)
		s.log.Printf("area=network message=game_server_connected peer=%d", p.id)
		defer func() {
			s.state.removeGamePeer(p.id)
			_ = p.close()
			s.log.Printf("area=network message=game_server_disconnected peer=%d", p.id)
		}()
		readJSONMessages(r.Context(), p, func(msg Message) {
			s.handleGameServerMessage(p, msg)
		})
	})
	return mux
}

func (s *Service) handleClientSocket() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := s.acceptor.accept(w, r)
		if err != nil {
			s.log.Printf("area=network message=client_upgrade_failed error=%q", err)
			return
		}
		p := s.state.addClientPeer(conn)
		s.log.Printf("area=network message=client_connected peer=%d", p.id)
		defer func() {
			s.state.removeClientPeer(p.id)
			_ = p.close()
			s.log.Printf("area=network message=client_disconnected peer=%d", p.id)
		}()
		readJSONMessages(r.Context(), p, func(msg Message) {
			s.handleClientMessage(p, msg)
		})
	})
	return mux
}

func (s *Service) handleHealth() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":      true,
			"service": "orchestrator",
			"details": s.state.healthSnapshot(),
		})
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"ready":   true,
			"service": "orchestrator",
		})
	})
	return mux
}

func (s *Service) handleGameServerMessage(p *peer, msg Message) {
	switch msg.Type {
	case TypeZoneRegister:
		z := s.state.registerZone(p.id, msg)
		s.log.Printf("area=orchestrator message=zone_registered zone=%s peer=%d address=%s port=%d", z.ZoneID, z.PeerID, z.Address, z.Port)
	case TypeZoneTransferRequest:
		prepare, destPeerID, err := s.state.handleZoneTransferRequest(p.id, msg)
		if err != nil {
			s.log.Printf("area=orchestrator message=transfer_rejected peer=%d to_zone=%s error=%q", p.id, msg.ToZoneID, err)
			return
		}
		s.sendToGamePeer(destPeerID, *prepare)
	case TypePreparePlayerAck:
		out, targetPeerID, err := s.state.handlePreparePlayerAck(p.id, msg)
		if err != nil {
			s.log.Printf("area=orchestrator message=prepare_ack_failed peer=%d token=%s error=%q", p.id, msg.TransferToken, err)
			return
		}
		if out == nil {
			return
		}
		if out.Type == TypeZoneRedirect {
			s.sendToClientPeer(targetPeerID, *out)
		} else {
			s.sendToGamePeer(targetPeerID, *out)
		}
	case TypeHeartbeatAck:
		s.state.recordHeartbeatAck(p.id)
	case TypeCharacterDisconnectedReserve:
		s.state.reserveDisconnectedCharacter(msg)
	case TypeCharacterDisconnectedClear:
		s.state.clearDisconnectedCharacter(msg.CharacterID)
	default:
		_ = p.send(Message{Type: "error", Reason: "unknown game server message type"})
	}
}

func (s *Service) handleClientMessage(p *peer, msg Message) {
	switch msg.Type {
	case TypeLoginRequest:
		response, displayName := s.state.handleLoginRequest(p.id, msg.Username)
		s.log.Printf("area=orchestrator message=login_response_sent client_peer=%d display_name=%q", p.id, displayName)
		_ = p.send(response)
	case TypeCharacterSelectRequest:
		response, prepare, err := s.state.handleCharacterSelectRequest(p.id, msg.CharacterID)
		if prepare != nil {
			s.sendToGamePeerForZone(s.cfg.DefaultZoneID, *prepare)
			return
		}
		if err == errUnknownDestinationZone {
			s.log.Printf("area=orchestrator message=character_select_queued client_peer=%d zone=%s", p.id, s.cfg.DefaultZoneID)
			return
		}
		if response.Type != "" {
			_ = p.send(response)
		}
	default:
		_ = p.send(Message{Type: "error", Reason: "unknown client message type"})
	}
}

func (s *Service) sendToGamePeer(peerID int64, msg Message) {
	p := s.state.getGamePeer(peerID)
	if p == nil {
		s.log.Printf("area=network message=missing_game_peer peer=%d type=%s", peerID, msg.Type)
		return
	}
	if err := p.send(msg); err != nil {
		s.log.Printf("area=network message=send_game_peer_failed peer=%d type=%s error=%q", peerID, msg.Type, err)
	}
}

func (s *Service) sendToGamePeerForZone(zoneID string, msg Message) {
	peerID, ok := s.state.getZonePeerID(zoneID)
	if !ok {
		s.log.Printf("area=network message=missing_zone zone=%s type=%s", zoneID, msg.Type)
		return
	}
	s.sendToGamePeer(peerID, msg)
}

func (s *Service) sendToClientPeer(peerID int64, msg Message) {
	p := s.state.getClientPeer(peerID)
	if p == nil {
		s.log.Printf("area=network message=missing_client_peer peer=%d type=%s", peerID, msg.Type)
		return
	}
	if err := p.send(msg); err != nil {
		s.log.Printf("area=network message=send_client_peer_failed peer=%d type=%s error=%q", peerID, msg.Type, err)
	}
}

func (s *Service) runMaintenance(ctx context.Context) {
	heartbeatTicker := time.NewTicker(s.cfg.HeartbeatInterval)
	expiryTicker := time.NewTicker(time.Second)
	retryTicker := time.NewTicker(time.Second)
	defer heartbeatTicker.Stop()
	defer expiryTicker.Stop()
	defer retryTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-heartbeatTicker.C:
			msg, peers := s.state.nextHeartbeat()
			for _, p := range peers {
				_ = p.send(msg)
			}
			for _, p := range s.state.timedOutGamePeers() {
				s.log.Printf("area=network message=game_server_heartbeat_timeout peer=%d", p.id)
				_ = p.close()
				s.state.removeGamePeer(p.id)
			}
		case <-expiryTicker.C:
			expired := s.state.expireTransfers()
			if expired > 0 {
				s.log.Printf("area=orchestrator message=transfers_expired count=%d", expired)
			}
		case <-retryTicker.C:
			for _, entry := range s.state.retryQueuedCharacterSelects() {
				_, prepare, err := s.state.prepareInitialZone(entry.ClientPeerID, entry.CharacterID, entry.ZoneID)
				if err != nil {
					continue
				}
				s.sendToGamePeerForZone(entry.ZoneID, *prepare)
			}
		}
	}
}
