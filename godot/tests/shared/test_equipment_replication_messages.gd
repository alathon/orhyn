extends GutTest


func test_entity_lifecycle_spawn_round_trips_equipment_snapshot() -> void:
	var spawn: EntitySpawnedGameEvent = EntitySpawnedGameEvent.new(
		7,
		EntitySpawnedGameEvent.ENTITY_KIND_PLAYER,
		Vector3(1.0, 2.0, 3.0),
		Quaternion.IDENTITY,
		5,
		[{
			"slot_id": Equippable.SlotId.Right_Hand,
			"item_instance_id": "weapon_1",
			"template_resource_path": "res://items/sword.tres",
		}]
	)

	var decoded: Array[GameEvent] = EntityLifecycleCodec.decode(
		EntityLifecycleCodec.encode([spawn], [], 7)
	)

	assert_eq(decoded.size(), 2)
	assert_true(decoded[0] is ControlledEntityAssignedGameEvent)
	var decoded_spawn: EntitySpawnedGameEvent = decoded[1] as EntitySpawnedGameEvent
	assert_eq(decoded_spawn.entity_id, 7)
	assert_eq(decoded_spawn.equipment_revision, 5)
	assert_eq(decoded_spawn.equipment_entries.size(), 1)
	assert_eq(decoded_spawn.equipment_entries[0].get("slot_id"), Equippable.SlotId.Right_Hand)
	assert_eq(decoded_spawn.equipment_entries[0].get("item_instance_id"), "weapon_1")
	assert_eq(decoded_spawn.equipment_entries[0].get("template_resource_path"), "res://items/sword.tres")


func test_entity_equipment_changed_round_trips_set_and_unset_changes() -> void:
	var changes: Array[Dictionary] = [
		{
			"slot_id": Equippable.SlotId.Right_Hand,
			"operation": EntityEquipmentChangedGameEvent.OPERATION_SET,
			"item_instance_id": "weapon_1",
			"template_resource_path": "res://items/sword.tres",
		},
		{
			"slot_id": Equippable.SlotId.Left_Hand,
			"operation": EntityEquipmentChangedGameEvent.OPERATION_UNSET,
		},
	]

	var decoded_events: Array[GameEvent] = EntityEquipmentChangedCodec.decode(
		EntityEquipmentChangedCodec.encode(9, 12, changes)
	)

	assert_eq(decoded_events.size(), 1)
	var decoded: EntityEquipmentChangedGameEvent = decoded_events[0] as EntityEquipmentChangedGameEvent
	assert_eq(decoded.entity_id, 9)
	assert_eq(decoded.equipment_revision, 12)
	assert_eq(decoded.changes.size(), 2)
	assert_eq(decoded.changes[0].get("operation"), EntityEquipmentChangedGameEvent.OPERATION_SET)
	assert_eq(decoded.changes[0].get("template_resource_path"), "res://items/sword.tres")
	assert_eq(decoded.changes[1].get("slot_id"), Equippable.SlotId.Left_Hand)
	assert_eq(decoded.changes[1].get("operation"), EntityEquipmentChangedGameEvent.OPERATION_UNSET)


func test_entity_equipment_action_request_round_trips_batch() -> void:
	var actions: Array[Dictionary] = [
		EntityEquipmentActionRequestMsg.make_equip_action(
			Equippable.SlotId.Right_Hand,
			"weapon_1",
			"res://items/sword.tres"
		),
		EntityEquipmentActionRequestMsg.make_unequip_action(Equippable.SlotId.Left_Hand),
	]

	var decoded: EntityEquipmentActionRequestMsg = EntityEquipmentActionRequestMsg.decode(
		EntityEquipmentActionRequestMsg.encode(99, actions)
	)

	assert_eq(decoded.request_id, 99)
	assert_eq(decoded.actions.size(), 2)
	assert_eq(decoded.actions[0].get("operation"), EntityEquipmentActionRequestMsg.OPERATION_EQUIP)
	assert_eq(decoded.actions[0].get("slot_id"), Equippable.SlotId.Right_Hand)
	assert_eq(decoded.actions[0].get("item_instance_id"), "weapon_1")
	assert_eq(decoded.actions[0].get("template_resource_path"), "res://items/sword.tres")
	assert_eq(decoded.actions[1].get("operation"), EntityEquipmentActionRequestMsg.OPERATION_UNEQUIP)
	assert_eq(decoded.actions[1].get("slot_id"), Equippable.SlotId.Left_Hand)


func test_entity_equipment_action_result_round_trips_request_status() -> void:
	var decoded: EntityEquipmentActionResultMsg = EntityEquipmentActionResultMsg.decode(
		EntityEquipmentActionResultMsg.encode(
			101,
			EntityEquipmentActionResultMsg.RESULT_SLOT_NOT_ALLOWED,
			7,
			12
		)
	)

	assert_eq(decoded.request_id, 101)
	assert_eq(decoded.result_code, EntityEquipmentActionResultMsg.RESULT_SLOT_NOT_ALLOWED)
	assert_eq(decoded.entity_id, 7)
	assert_eq(decoded.equipment_revision, 12)


func test_equipment_snapshot_can_set_authoritative_revision() -> void:
	var equipment: Equipment = autofree(Equipment.new())

	equipment.apply_snapshot_entries([], 8)

	assert_eq(equipment.revision, 8)
