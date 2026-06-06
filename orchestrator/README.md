# Orchestrator

Go control-plane service for MMO zone registration, login routing, zone transfers,
heartbeats, and health checks.

## Run

```powershell
cd orchestrator
go run ./cmd/orchestrator
```

Default ports:

- `9000` game/zone server WebSocket endpoint at `/ws`
- `9001` client login WebSocket endpoint at `/ws`
- `9100` health endpoints at `/healthz` and `/readyz`

Useful flags:

```powershell
go run ./cmd/orchestrator --default-zone mvp --game-server-port 9000 --client-port 9001 --health-port 9100
```

## Protocol

Messages are JSON objects with a `type` field over WebSocket. This replaces the
old Godot-only protobuf preload with an explicit service contract that can be
adapted from GDScript.

Game server messages:

- `zone_register`
- `zone_transfer_request`
- `prepare_player_ack`
- `heartbeat_ack`
- `character_disconnected_reserve`
- `character_disconnected_clear`

Messages sent to game servers:

- `prepare_player`
- `zone_transfer_response`
- `heartbeat`

Client messages:

- `login_request`
- `character_select_request`

Messages sent to clients:

- `login_response`
- `login_failure`
- `character_select_failure`
- `zone_redirect`

Example zone registration:

```json
{
  "type": "zone_register",
  "zone_id": "mvp",
  "address": "127.0.0.1",
  "port": 4242,
  "max_players": 32,
  "current_players": 0
}
```
