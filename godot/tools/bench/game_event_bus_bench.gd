extends SceneTree

const DISPATCH_ITERATIONS: int = 1000000
const ALLOCATION_ITERATIONS: int = 250000
const PROTOCOL_ITERATIONS: int = 100000
const EVENTS_PER_LIFECYCLE_PACKET: int = 3

class SignalEmitter:
	extends Node

	signal event_published(event: GameEvent)

	func publish(event: GameEvent) -> void:
		event_published.emit(event)

var _noop_callbacks: Array[Callable] = []
var _entities_by_id: Dictionary[int, int] = {}
var _sink: int = 0
var _last_position: Vector3 = Vector3.ZERO


func _init() -> void:
	_setup()
	_run()
	quit()


func _setup() -> void:
	_noop_callbacks = [
		_on_event_0,
		_on_event_1,
		_on_event_2,
		_on_event_3,
		_on_event_4,
		_on_event_5,
		_on_event_6,
		_on_event_7,
		_on_event_8,
		_on_event_9,
	]
	for entity_id in 2048:
		_entities_by_id[entity_id] = entity_id * 3


func _run() -> void:
	print("")
	print("GameEventBus benchmark")
	print("Godot version: %s" % Engine.get_version_info().string)
	print("Dispatch iterations: %d" % DISPATCH_ITERATIONS)
	print("Allocation iterations: %d" % ALLOCATION_ITERATIONS)
	print("Protocol iterations: %d" % PROTOCOL_ITERATIONS)
	print("")
	print("%-42s %12s %12s %12s %14s %12s" % [
		"case",
		"iterations",
		"total ms",
		"us/op",
		"ops/sec",
		"sink",
	])
	print("-".repeat(112))

	_bench_direct_callable("Direct Callable.call, 1 subscriber", DISPATCH_ITERATIONS)
	_bench_signal("Godot signal.emit, 1 subscriber", DISPATCH_ITERATIONS, 1)
	_bench_signal("Godot signal.emit, 3 subscribers", DISPATCH_ITERATIONS, 3)

	_bench_bus_reused("Bus publish reused event, 0 subscribers", DISPATCH_ITERATIONS, 0, false)
	_bench_bus_reused("Bus publish reused event, 1 subscriber", DISPATCH_ITERATIONS, 1, false)
	var bus_3_us: float = _bench_bus_reused(
			"Bus publish reused event, 3 subscribers",
			DISPATCH_ITERATIONS,
			3,
			false)
	_bench_bus_reused("Bus publish reused event, 10 subscribers", DISPATCH_ITERATIONS, 10, false)
	var bus_3_seq_us: float = _bench_bus_reused(
			"Bus reused event + local sequence reset",
			DISPATCH_ITERATIONS,
			3,
			true)
	var bus_3_realistic_us: float = _bench_bus_realistic(
			"Bus publish, 3 light real subscribers",
			DISPATCH_ITERATIONS)
	_bench_event_allocation("EntitySpawnedGameEvent.new only", ALLOCATION_ITERATIONS)
	var alloc_publish_us: float = _bench_bus_allocate_and_publish(
			"new EntitySpawned + bus publish, 3 subs",
			ALLOCATION_ITERATIONS)
	_bench_protocol_decode_only("EntityLifecycleCodec.decode only", PROTOCOL_ITERATIONS)
	var protocol_packet_us: float = _bench_protocol_decode_and_publish(
			"decode lifecycle + publish 3 events",
			PROTOCOL_ITERATIONS)
	var routed_protocol_packet_us: float = _bench_protocol_router_lifecycle(
			"client router lifecycle packet",
			PROTOCOL_ITERATIONS)

	print("")
	_print_tick_budget("Bus reused event, 3 subscribers", bus_3_us)
	_print_tick_budget("Bus reused event + sequence reset", bus_3_seq_us)
	_print_tick_budget("Bus publish, 3 light real subscribers", bus_3_realistic_us)
	_print_tick_budget("new EntitySpawned + publish, 3 subs", alloc_publish_us)
	_print_tick_budget(
			"decode lifecycle + publish, per emitted event",
			protocol_packet_us / float(EVENTS_PER_LIFECYCLE_PACKET))
	_print_tick_budget(
			"client router lifecycle, per emitted event",
			routed_protocol_packet_us / float(EVENTS_PER_LIFECYCLE_PACKET))


func _bench_direct_callable(label: String, iterations: int) -> float:
	var event: EntitySpawnedGameEvent = _make_spawn_event()
	event.local_sequence = 1
	var callback: Callable = _noop_callbacks[0]
	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		callback.call(event)
	return _report(label, iterations, Time.get_ticks_usec() - started_usec)


func _bench_signal(label: String, iterations: int, subscriber_count: int) -> float:
	var emitter: SignalEmitter = SignalEmitter.new()
	for i in subscriber_count:
		emitter.event_published.connect(_noop_callbacks[i])
	var event: EntitySpawnedGameEvent = _make_spawn_event()
	event.local_sequence = 1
	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		emitter.publish(event)
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	emitter.free()
	return result


func _bench_bus_reused(
		label: String,
		iterations: int,
		subscriber_count: int,
		reset_sequence: bool) -> float:
	var bus: GameEventBus = GameEventBus.new()
	_connect_noop_subscribers(bus, subscriber_count)
	var event: EntitySpawnedGameEvent = _make_spawn_event()
	if not reset_sequence:
		event.local_sequence = 1

	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		if reset_sequence:
			event.local_sequence = 0
		bus.publish(event)
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	bus.free()
	return result


func _bench_bus_realistic(label: String, iterations: int) -> float:
	var bus: GameEventBus = GameEventBus.new()
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_lookup_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_position_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_branch_event)
	var event: EntitySpawnedGameEvent = _make_spawn_event()
	event.local_sequence = 1

	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		bus.publish(event)
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	bus.free()
	return result


func _bench_event_allocation(label: String, iterations: int) -> float:
	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		var event: EntitySpawnedGameEvent = _make_spawn_event()
		_sink += event.entity_id
	return _report(label, iterations, Time.get_ticks_usec() - started_usec)


func _bench_bus_allocate_and_publish(label: String, iterations: int) -> float:
	var bus: GameEventBus = GameEventBus.new()
	_connect_noop_subscribers(bus, 3)
	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		bus.publish(_make_spawn_event())
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	bus.free()
	return result


func _bench_protocol_decode_only(label: String, iterations: int) -> float:
	var bytes: PackedByteArray = _make_lifecycle_packet()
	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		var events: Array[GameEvent] = EntityLifecycleCodec.decode(bytes)
		_sink += events.size()
	return _report(label, iterations, Time.get_ticks_usec() - started_usec)


func _bench_protocol_decode_and_publish(label: String, iterations: int) -> float:
	var bytes: PackedByteArray = _make_lifecycle_packet()
	var bus: GameEventBus = GameEventBus.new()
	bus.subscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _on_lifecycle_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _on_lifecycle_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_lifecycle_event)

	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		var events: Array[GameEvent] = EntityLifecycleCodec.decode(bytes)
		for event: GameEvent in events:
			event.source = GameEvent.Source.SERVER_AUTHORITATIVE
			bus.publish(event)
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	bus.free()
	return result


func _bench_protocol_router_lifecycle(label: String, iterations: int) -> float:
	var bytes: PackedByteArray = _make_lifecycle_packet()
	var bus: GameEventBus = GameEventBus.new()
	bus.subscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _on_lifecycle_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _on_lifecycle_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_lifecycle_event)

	_sink = 0
	var started_usec: int = Time.get_ticks_usec()
	for i in iterations:
		ClientProtocolRouter.route(GameServerAPI.CHANNEL_ENTITY_LIFECYCLE, bytes, null, bus)
	var result: float = _report(label, iterations, Time.get_ticks_usec() - started_usec)
	bus.free()
	return result


func _connect_noop_subscribers(bus: GameEventBus, subscriber_count: int) -> void:
	for i in subscriber_count:
		bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _noop_callbacks[i])


func _make_spawn_event() -> EntitySpawnedGameEvent:
	return EntitySpawnedGameEvent.new(
			7,
			EntitySpawnedGameEvent.ENTITY_KIND_PLAYER,
			Vector3(1.0, 2.0, 3.0),
			Quaternion.IDENTITY,
			GameEvent.Source.SERVER_AUTHORITATIVE)


func _make_lifecycle_packet() -> PackedByteArray:
	var despawn: EntityDespawnedGameEvent = EntityDespawnedGameEvent.new(3, 9)
	var spawn: EntitySpawnedGameEvent = EntitySpawnedGameEvent.new(
		7,
		EntitySpawnedGameEvent.ENTITY_KIND_PLAYER,
		Vector3(1.0, 2.0, 3.0),
		Quaternion.IDENTITY
	)

	return EntityLifecycleCodec.encode([spawn], [despawn], 7)


func _report(label: String, iterations: int, elapsed_usec: int) -> float:
	var total_ms: float = float(elapsed_usec) / 1000.0
	var usec_per_op: float = float(elapsed_usec) / float(iterations)
	var ops_per_second: float = 1000000.0 / usec_per_op
	print("%-42s %12d %12.3f %12.4f %14.0f %12d" % [
		label,
		iterations,
		total_ms,
		usec_per_op,
		ops_per_second,
		_sink,
	])
	return usec_per_op


func _print_tick_budget(label: String, usec_per_event: float) -> void:
	var tick_usec: float = Ticker.DEFAULT_TICK_SECONDS * 1000000.0
	var one_ms_events: int = int(1000.0 / usec_per_event)
	var five_ms_events: int = int(5000.0 / usec_per_event)
	var full_tick_events: int = int(tick_usec / usec_per_event)
	print("%s:" % label)
	print("  ~%d events in 1 ms, ~%d in 5 ms, ~%d in a %.0f ms tick" % [
		one_ms_events,
		five_ms_events,
		full_tick_events,
		tick_usec / 1000.0,
	])


func _on_event_0(event: GameEvent) -> void:
	_sink += event.type


func _on_event_1(event: GameEvent) -> void:
	_sink += event.type


func _on_event_2(event: GameEvent) -> void:
	_sink += event.type


func _on_event_3(event: GameEvent) -> void:
	_sink += event.type


func _on_event_4(event: GameEvent) -> void:
	_sink += event.type


func _on_event_5(event: GameEvent) -> void:
	_sink += event.type


func _on_event_6(event: GameEvent) -> void:
	_sink += event.type


func _on_event_7(event: GameEvent) -> void:
	_sink += event.type


func _on_event_8(event: GameEvent) -> void:
	_sink += event.type


func _on_event_9(event: GameEvent) -> void:
	_sink += event.type


func _on_lookup_event(event: GameEvent) -> void:
	var spawn: EntitySpawnedGameEvent = event as EntitySpawnedGameEvent
	_sink += int(_entities_by_id.get(spawn.entity_id, 0))


func _on_position_event(event: GameEvent) -> void:
	var spawn: EntitySpawnedGameEvent = event as EntitySpawnedGameEvent
	_last_position = spawn.position
	if _last_position.x > 0.0:
		_sink += 1


func _on_branch_event(event: GameEvent) -> void:
	if event.source == GameEvent.Source.SERVER_AUTHORITATIVE:
		_sink += 1


func _on_lifecycle_event(event: GameEvent) -> void:
	_sink += event.type
