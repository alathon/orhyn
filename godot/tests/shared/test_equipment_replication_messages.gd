extends GutTest


func test_entity_lifecycle_spawn_round_trips_equipment_snapshot() -> void:
	var spawn: EntityLifecycleMsg.SpawnRecord = EntityLifecycleMsg.SpawnRecord.new()
	spawn.entity_id = 7
	spawn.entity_kind = EntityLifecycleMsg.EntityKind.Player
	spawn.position = Vector3(1.0, 2.0, 3.0)
	spawn.rotation = Quaternion.IDENTITY
	spawn.equipment_revision = 5
	spawn.equipment_entries = [{
		"slot_id": Equippable.SlotId.Right_Hand,
		"item_instance_id": "weapon_1",
		"template_resource_path": "res://items/sword.tres",
	}]

	var decoded: EntityLifecycleMsg = EntityLifecycleMsg.decode(EntityLifecycleMsg.encode([spawn], [], 7))

	assert_eq(decoded.controlled_entity_id, 7)
	assert_eq(decoded.entities_spawned.size(), 1)
	var decoded_spawn: EntityLifecycleMsg.SpawnRecord = decoded.entities_spawned[0]
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
			"operation": EntityEquipmentChangedMsg.OPERATION_SET,
			"item_instance_id": "weapon_1",
			"template_resource_path": "res://items/sword.tres",
		},
		{
			"slot_id": Equippable.SlotId.Left_Hand,
			"operation": EntityEquipmentChangedMsg.OPERATION_UNSET,
		},
	]

	var decoded: EntityEquipmentChangedMsg = EntityEquipmentChangedMsg.decode(
		EntityEquipmentChangedMsg.encode(9, 12, changes)
	)

	assert_eq(decoded.entity_id, 9)
	assert_eq(decoded.equipment_revision, 12)
	assert_eq(decoded.changes.size(), 2)
	assert_eq(decoded.changes[0].get("operation"), EntityEquipmentChangedMsg.OPERATION_SET)
	assert_eq(decoded.changes[0].get("template_resource_path"), "res://items/sword.tres")
	assert_eq(decoded.changes[1].get("slot_id"), Equippable.SlotId.Left_Hand)
	assert_eq(decoded.changes[1].get("operation"), EntityEquipmentChangedMsg.OPERATION_UNSET)


func test_equipment_snapshot_can_set_authoritative_revision() -> void:
	var equipment: Equipment = autofree(Equipment.new())

	equipment.apply_snapshot_entries([], 8)

	assert_eq(equipment.revision, 8)
