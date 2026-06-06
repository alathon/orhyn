# Game Server

Start the game server scene with Godot and pass runtime options after `--`.

```powershell
godot --path ./godot --scene res://projects/game-server/src/main.tscn -- `
  --zone mvp `
  --port 4242 `
  --advertise-address 127.0.0.1 `
  --orchestrator-url ws://127.0.0.1:9000/ws
```

Add `--headless` before `--path` only when you want a headless server.

Supported options:

- `--zone`, `--zone-name`, or `--zone-id`
- `--port`
- `--bind-address`
- `--advertise-address`
- `--max-peers`
- `--orchestrator-url` or `--orchestrator`

On startup the server binds ENet on the configured port, connects to the
orchestrator WebSocket, sends `zone_register`, and replies to orchestrator
`heartbeat` messages with `heartbeat_ack`.
