extends GutTest

var _received: Array[GameEvent] = []


func before_each() -> void:
	_received.clear()


func test_entity_lifecycle_source_publishes_ordered_game_events() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	_subscribe_lifecycle_events(bus)

	var despawn: EntityLifecycleMsg.DespawnRecord = EntityLifecycleMsg.DespawnRecord.new()
	despawn.entity_id = 3
	despawn.reason = 9

	var spawn: EntityLifecycleMsg.SpawnRecord = EntityLifecycleMsg.SpawnRecord.new()
	spawn.entity_id = 7
	spawn.entity_kind = EntityLifecycleMsg.EntityKind.Player
	spawn.position = Vector3(1.0, 2.0, 3.0)
	spawn.rotation = Quaternion(0.0, 0.0, 0.0, 1.0)
	spawn.equipment_revision = 4
	spawn.equipment_entries = [{
		"slot_id": Equippable.SlotId.Right_Hand,
		"item_instance_id": "weapon_1",
		"template_resource_path": "res://items/sword.tres",
	}]

	var lifecycle: EntityLifecycleMsg = EntityLifecycleMsg.new()
	lifecycle.controlled_entity_id = 7
	lifecycle.entities_despawned = [despawn]
	lifecycle.entities_spawned = [spawn]

	EntityLifecycleEventSource.publish(lifecycle, bus)

	assert_eq(_received.size(), 3)
	assert_true(_received[0] is ControlledEntityAssignedGameEvent)
	assert_true(_received[1] is EntityDespawnedGameEvent)
	assert_true(_received[2] is EntitySpawnedGameEvent)
	assert_eq(_received[0].local_sequence, 1)
	assert_eq(_received[1].local_sequence, 2)
	assert_eq(_received[2].local_sequence, 3)

	var controlled: ControlledEntityAssignedGameEvent = _received[0] as ControlledEntityAssignedGameEvent
	var despawned: EntityDespawnedGameEvent = _received[1] as EntityDespawnedGameEvent
	var spawned: EntitySpawnedGameEvent = _received[2] as EntitySpawnedGameEvent

	assert_eq(controlled.entity_id, 7)
	assert_eq(controlled.source, GameEvent.Source.SERVER_AUTHORITATIVE)
	assert_eq(despawned.entity_id, 3)
	assert_eq(despawned.reason, 9)
	assert_eq(spawned.entity_id, 7)
	assert_eq(spawned.entity_kind, EntitySpawnedGameEvent.ENTITY_KIND_PLAYER)
	assert_eq(spawned.position, Vector3(1.0, 2.0, 3.0))
	assert_eq(spawned.equipment_revision, 4)
	assert_eq(spawned.equipment_entries[0].get("item_instance_id"), "weapon_1")


func test_equipment_changed_source_publishes_game_event() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	bus.subscribe(GameEvent.TYPE_ENTITY_EQUIPMENT_CHANGED, _record_event)

	var message: EntityEquipmentChangedMsg = EntityEquipmentChangedMsg.create(7, 4, [{
		"slot_id": Equippable.SlotId.Right_Hand,
		"operation": EntityEquipmentChangedMsg.OPERATION_UNSET,
	}])

	EntityEquipmentEventSource.publish(message, bus)

	assert_eq(_received.size(), 1)
	assert_true(_received[0] is EntityEquipmentChangedGameEvent)
	var event: EntityEquipmentChangedGameEvent = _received[0] as EntityEquipmentChangedGameEvent
	assert_eq(event.entity_id, 7)
	assert_eq(event.equipment_revision, 4)
	assert_eq(event.changes[0].get("operation"), EntityEquipmentChangedMsg.OPERATION_UNSET)


func test_entity_lifecycle_source_ignores_empty_messages() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	_subscribe_lifecycle_events(bus)

	EntityLifecycleEventSource.publish(EntityLifecycleMsg.new(), bus)

	assert_true(_received.is_empty())


func test_character_loaded_source_publishes_character_loaded_event() -> void:
	var bus: GameEventBus = autofree(GameEventBus.new()) as GameEventBus
	bus.subscribe(GameEvent.TYPE_CHARACTER_LOADED, _record_event)
	var message: CharacterLoadedMsg = CharacterLoadedMsg.create(
		11,
		22,
		"Player",
		"zone_forest",
		"Wizard",
		7
	)

	CharacterLoadedEventSource.publish(message, bus)

	assert_eq(_received.size(), 1)
	assert_true(_received[0] is CharacterLoadedGameEvent)
	var event: CharacterLoadedGameEvent = _received[0] as CharacterLoadedGameEvent
	assert_eq(event.character_id, 11)
	assert_eq(event.entity_id, 22)
	assert_eq(event.display_name, "Player")
	assert_eq(event.zone_id, "zone_forest")
	assert_eq(event.model_name, "Wizard")
	assert_eq(event.level, 7)
	assert_eq(event.source, GameEvent.Source.SERVER_AUTHORITATIVE)


func _record_event(event: GameEvent) -> void:
	_received.append(event)


func _subscribe_lifecycle_events(bus: GameEventBus) -> void:
	bus.subscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _record_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _record_event)
	bus.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _record_event)
