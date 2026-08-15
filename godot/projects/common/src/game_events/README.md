# Network gameplay events

Gameplay codecs decode one packet directly into zero or more semantic `GameEvent`s. Do not create an intermediate message object for gameplay facts.

## File locations

- `common/src/protocol/message_headers.gd`: wire header bytes.
- `common/src/protocol/*_codec.gd`: gameplay packets; `decode()` returns `Array[GameEvent]`.
- `common/src/protocol/*_msg.gd`: request/result packets and state streams that are not gameplay facts.
- `common/src/game_events/*_game_event.gd`: facts published on `GameEventBus`.
- `client/src/api/protocol/client_*_protocol_router.gd`: channel/header routing, source assignment, and publication.
- `client/src/systems/` and `client/src/screens/`: event consumers.

Every event inherits the no-argument `GameEvent.toString()` representation. Set a bus's exported `log_level` to `DEBUG` to write every published event through the timestamped project logger; the client bus is configured this way in `ingame_screen.tscn`.

## Choose the path

One packet can produce one fact:

```text
EntityEquipmentChangedCodec.decode(bytes)
  -> [EntityEquipmentChangedGameEvent]
  -> GameEventBus
```

Or several facts through the same codec path:

```text
EntityLifecycleCodec.decode(bytes)
  -> [ControlledEntityAssignedGameEvent,
      EntityDespawnedGameEvent(s),
      EntitySpawnedGameEvent(s)]
  -> GameEventBus
```

Correlated action results use the primitive `GameServerAPI.action_result_received` signal. Movement remains a direct state stream; neither belongs on `GameEventBus`.

## Add or remove a network fact

Add/remove its header, `GameEvent.TYPE_*`, event class, codec, router branch, consumer subscription, and codec/router tests. The codec performs any decomposition or normalization and returns events in publication order.
