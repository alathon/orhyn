extends GutTest

var _received_events: Array[GameEvent] = []
var _received_snapshot: MovementSnapshotMsg = null


func before_each() -> void:
	_received_events.clear()
	_received_snapshot = null


func test_routes_entity_lifecycle_packets_to_game_events() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	bus.subscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _record_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _record_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _record_event)

	var err: Error = ClientProtocolRouter.route(
		GameServerAPI.CHANNEL_ENTITY_LIFECYCLE,
		_make_lifecycle_packet(),
		null,
		bus
	)

	assert_eq(err, OK)
	assert_eq(_received_events.size(), 3)
	assert_true(_received_events[0] is ControlledEntityAssignedGameEvent)
	assert_true(_received_events[1] is EntityDespawnedGameEvent)
	assert_true(_received_events[2] is EntitySpawnedGameEvent)


func test_routes_character_loaded_packets_to_game_events() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	bus.subscribe(GameEvent.TYPE_CHARACTER_LOADED, _record_event)

	var err: Error = ClientProtocolRouter.route(
		GameServerAPI.CHANNEL_ZONE_SESSION,
		CharacterLoadedMsg.encode(11, 22, "Player", "zone_forest", "Wizard", 7),
		null,
		bus
	)

	assert_eq(err, OK)
	assert_eq(_received_events.size(), 1)
	assert_true(_received_events[0] is CharacterLoadedGameEvent)
	var event: CharacterLoadedGameEvent = _received_events[0] as CharacterLoadedGameEvent
	assert_eq(event.character_id, 11)
	assert_eq(event.entity_id, 22)


func test_routes_entity_equipment_changed_packets_to_game_events() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	bus.subscribe(GameEvent.TYPE_ENTITY_EQUIPMENT_CHANGED, _record_event)

	var err: Error = ClientProtocolRouter.route(
		GameServerAPI.CHANNEL_ENTITY_LIFECYCLE,
		EntityEquipmentChangedMsg.encode(7, 3, [{
			"slot_id": Equippable.SlotId.Right_Hand,
			"operation": EntityEquipmentChangedMsg.OPERATION_SET,
			"item_instance_id": "weapon_1",
			"template_resource_path": "res://items/sword.tres",
		}]),
		null,
		bus
	)

	assert_eq(err, OK)
	assert_eq(_received_events.size(), 1)
	assert_true(_received_events[0] is EntityEquipmentChangedGameEvent)
	var event: EntityEquipmentChangedGameEvent = _received_events[0] as EntityEquipmentChangedGameEvent
	assert_eq(event.entity_id, 7)
	assert_eq(event.equipment_revision, 3)
	assert_eq(event.changes[0].get("item_instance_id"), "weapon_1")


func test_routes_movement_snapshot_packets_to_api_signal() -> void:
	var api: GameServerAPI = autofree(GameServerAPI.new()) as GameServerAPI
	api.movement_snapshot_received.connect(_record_snapshot)
	var snapshot: MovementSnapshotMsg.EntitySnapshot = MovementSnapshotMsg.EntitySnapshot.new()
	snapshot.entity_id = 9
	snapshot.position = Vector3(1.0, 2.0, 3.0)
	snapshot.rotation = Quaternion.IDENTITY

	var err: Error = ClientProtocolRouter.route(
		GameServerAPI.CHANNEL_MOVEMENT_SNAPSHOT,
		MovementSnapshotMsg.encode([snapshot], 17),
		api,
		null
	)

	assert_eq(err, OK)
	assert_true(_received_snapshot != null)
	assert_eq(_received_snapshot.entities.size(), 1)
	assert_eq(_received_snapshot.entities[0].entity_id, 9)


func _record_event(event: GameEvent) -> void:
	_received_events.append(event)


func _record_snapshot(snapshot: MovementSnapshotMsg) -> void:
	_received_snapshot = snapshot


func _make_lifecycle_packet() -> PackedByteArray:
	var despawn: EntityLifecycleMsg.DespawnRecord = EntityLifecycleMsg.DespawnRecord.new()
	despawn.entity_id = 3
	despawn.reason = 9

	var spawn: EntityLifecycleMsg.SpawnRecord = EntityLifecycleMsg.SpawnRecord.new()
	spawn.entity_id = 7
	spawn.entity_kind = EntityLifecycleMsg.EntityKind.Player
	spawn.position = Vector3(1.0, 2.0, 3.0)
	spawn.rotation = Quaternion.IDENTITY

	return EntityLifecycleMsg.encode([spawn], [despawn], 7)
