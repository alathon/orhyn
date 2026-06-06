package orchestrator

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type socket interface {
	ReadMessage() (int, []byte, error)
	WriteJSON(v interface{}) error
	Close() error
}

type peer struct {
	id   int64
	conn socket
	mu   sync.Mutex
}

func (p *peer) send(msg Message) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.conn.WriteJSON(msg)
}

func (p *peer) close() error {
	return p.conn.Close()
}

type websocketAcceptor struct {
	upgrader websocket.Upgrader
}

func newWebsocketAcceptor() websocketAcceptor {
	return websocketAcceptor{
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

func (a websocketAcceptor) accept(w http.ResponseWriter, r *http.Request) (socket, error) {
	return a.upgrader.Upgrade(w, r, nil)
}

func readJSONMessages(ctx context.Context, p *peer, handle func(Message)) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		_, bytes, err := p.conn.ReadMessage()
		if err != nil {
			return
		}
		var msg Message
		if err := json.Unmarshal(bytes, &msg); err != nil {
			_ = p.send(Message{Type: "error", Reason: "invalid json message"})
			continue
		}
		handle(msg)
	}
}
