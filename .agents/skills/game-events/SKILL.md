---
name: game-events
description: Use when adding or changing non-movement network events, specialized protocol messages, game event classes, protocol-to-game-event adapters, GameEventBus subscriptions, or gameplay event consumers in the Godot MMORPG project.
---

# Game Events

## Core Rule

Use this split:

- `godot/projects/common/src/protocol/`: compact specialized wire messages.
- `godot/projects/common/src/game_events/`: semantic facts consumed by gameplay/UI/presentation.
- `godot/projects/common/src/protocol_event_sources/`: protocol-to-game-event mapping helpers.
- `godot/projects/client/src/api/protocol/`: client protocol routers. Route by channel first, then by message header byte.
- Godot signals: local node/component/UI facts only.

Movement is not a game event. Keep movement input and movement snapshots as stream/state protocol and direct client/server processing.

## Event Shape

Game events should be named as facts that would still make sense without networking:

- Good: `EntitySpawnedGameEvent`, `EntityDespawnedGameEvent`, `CastStartedGameEvent`, `DamageAppliedGameEvent`.
- Bad: `EntityLifecycleReceivedGameEvent`, `PacketReceivedGameEvent`, `MovementSnapshotGameEvent`.

Entity ids are valid game-domain identity. Do not replace ids with scene nodes in protocol or game events. Consumers that need nodes should query a client registry/spawner from the id.

## Adding A Non-Movement Network Event

1. Add or update the compact protocol message in `common/src/protocol/`.
2. Add semantic event class(es) in `common/src/game_events/`.
3. Add a `GameEvent.TYPE_*` constant and update `TYPE_COUNT`.
4. Add mapping in `common/src/protocol_event_sources/`.
5. In the relevant client protocol router, add a `match` branch for the message header, decode the specialized packet, and call the event source helper.
6. Consumers subscribe to `GameEventBus` by exact event type.
7. Use Godot signals only after a local node/component fact happens, such as an entity node being instantiated or an animation finishing.

## Performance Rules

- Keep wire messages specialized; do not introduce a generic network event batch.
- Keep `GameEventBus.publish()` hot: no dictionary lookup, no catch-all subscriber fanout, no per-subscriber validity checks.
- Do not do scene lookups in publish paths or protocol mappings.
- Avoid creating temporary arrays/dictionaries in per-event mapping code.
- Prefer `match` over dictionaries for protocol routing. Every router `match` must include `_:` that calls `push_error()` and returns an error for unhandled messages.
- Benchmark with `godot --headless --path godot -s res://tools/bench/game_event_bus_bench.gd` after changing dispatch or event creation behavior.
