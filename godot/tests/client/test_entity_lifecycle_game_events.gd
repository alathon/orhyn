extends GutTest


func test_lifecycle_codec_decodes_ordered_game_events() -> void:
	var despawn: EntityDespawnedGameEvent = EntityDespawnedGameEvent.new(3, 9)
	var spawn: EntitySpawnedGameEvent = EntitySpawnedGameEvent.new(
		7,
		EntitySpawnedGameEvent.ENTITY_KIND_PLAYER,
		Vector3(1.0, 2.0, 3.0),
		Quaternion.IDENTITY,
		4,
		[{
			"slot_id": Equippable.SlotId.Right_Hand,
			"item_instance_id": "weapon_1",
			"template_resource_path": "res://items/sword.tres",
		}]
	)

	var events: Array[GameEvent] = EntityLifecycleCodec.decode(
		EntityLifecycleCodec.encode([spawn], [despawn], 7)
	)

	assert_eq(events.size(), 3)
	assert_true(events[0] is ControlledEntityAssignedGameEvent)
	assert_true(events[1] is EntityDespawnedGameEvent)
	assert_true(events[2] is EntitySpawnedGameEvent)

	var controlled: ControlledEntityAssignedGameEvent = events[0] as ControlledEntityAssignedGameEvent
	var despawned: EntityDespawnedGameEvent = events[1] as EntityDespawnedGameEvent
	var spawned: EntitySpawnedGameEvent = events[2] as EntitySpawnedGameEvent

	assert_eq(controlled.entity_id, 7)
	assert_eq(despawned.entity_id, 3)
	assert_eq(despawned.reason, 9)
	assert_eq(spawned.entity_id, 7)
	assert_eq(spawned.position, Vector3(1.0, 2.0, 3.0))
	assert_eq(spawned.equipment_revision, 4)
	assert_eq(spawned.equipment_entries[0].get("item_instance_id"), "weapon_1")


func test_lifecycle_codec_returns_no_events_for_empty_packet() -> void:
	var events: Array[GameEvent] = EntityLifecycleCodec.decode(
		EntityLifecycleCodec.encode([], [])
	)

	assert_true(events.is_empty())
