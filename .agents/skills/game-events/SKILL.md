---
name: game-events
description: Use when adding or changing non-movement network events, specialized protocol messages, game event classes, protocol-to-game-event adapters, GameEventBus subscriptions, or gameplay event consumers in the Godot MMORPG project.
---

# Game Events

## Core Rule

Use this split:

- `godot/projects/common/src/protocol/`: gameplay codecs plus request/result and stream messages.
- `godot/projects/common/src/game_events/`: semantic facts consumed by gameplay/UI/presentation.
- `godot/projects/client/src/api/protocol/`: client protocol routers. Route by channel first, then by message header byte.
- Godot signals: local node/component/UI facts only.

Read `godot/projects/common/src/game_events/README.md` for the project file map and checklist.

Movement is not a game event. Keep movement input and movement snapshots as stream/state protocol and direct client/server processing.

## Event Shape

Game events should be named as facts that would still make sense without networking:

- Good: `EntitySpawnedGameEvent`, `EntityDespawnedGameEvent`, `CastStartedGameEvent`, `DamageAppliedGameEvent`.
- Bad: `EntityLifecycleReceivedGameEvent`, `PacketReceivedGameEvent`, `MovementSnapshotGameEvent`.

Entity ids are valid game-domain identity. Do not replace ids with scene nodes in protocol or game events. Consumers that need nodes should query a client registry/spawner from the id.

## Adding A Non-Movement Network Event

1. Add the wire header in `common/src/protocol/message_headers.gd`.
2. Add semantic event class(es) and `GameEvent.TYPE_*` constants.
3. Add a `*_codec.gd` whose decoder returns `Array[GameEvent]`; it may return zero, one, or several ordered facts.
4. Add a router `match` branch that decodes, assigns each event source, and publishes each event.
5. Consumers subscribe to `GameEventBus` by exact event type.
6. Add codec and router tests. Use local Godot signals only after a local node/component/UI fact happens.

## Performance Rules

- Keep wire messages specialized; do not introduce a generic network event batch.
- Keep `GameEventBus.publish()` hot: no dictionary lookup, no catch-all subscriber fanout, no per-subscriber validity checks.
- Do not do scene lookups in publish paths or protocol mappings.
- Keep codec output arrays compact and avoid additional temporary payload DTOs.
- Prefer `match` over dictionaries for protocol routing. Every router `match` must include `_:` that calls `push_error()` and returns an error for unhandled messages.
- Benchmark with `godot --headless --path godot -s res://tools/bench/game_event_bus_bench.gd` after changing dispatch or event creation behavior.
