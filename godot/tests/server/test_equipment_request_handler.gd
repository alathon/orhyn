extends GutTest


func test_equip_request_sets_equipment_and_returns_change() -> void:
	var fixture: Dictionary = _make_fixture()
	var handler: EquipmentRequestHandler = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	var template_path: String = _save_equippable_template(
		"user://test_equipment_request_handler_sword.tres",
		[Equippable.SlotId.Right_Hand]
	)
	var request: EntityEquipmentActionRequestMsg = EntityEquipmentActionRequestMsg.create(9, [
		EntityEquipmentActionRequestMsg.make_equip_action(
			Equippable.SlotId.Right_Hand,
			"weapon_1",
			template_path
		),
	])

	var outcome: EquipmentRequestHandler.RequestOutcome = handler.handle_request(42, request)

	assert_eq(outcome.result.result_code, EntityEquipmentActionResultMsg.RESULT_OK)
	assert_eq(outcome.result.request_id, 9)
	assert_eq(outcome.result.entity_id, player.entity_id)
	assert_eq(outcome.result.equipment_revision, 1)
	assert_true(player.equipment.has_equipped_slot(Equippable.SlotId.Right_Hand))
	assert_eq(outcome.changes.size(), 1)
	assert_eq(outcome.changes[0].get("operation"), EntityEquipmentChangedMsg.OPERATION_SET)
	assert_eq(outcome.changes[0].get("item_instance_id"), "weapon_1")


func test_batch_rejects_invalid_action_without_partial_apply() -> void:
	var fixture: Dictionary = _make_fixture()
	var handler: EquipmentRequestHandler = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	var template_path: String = _save_equippable_template(
		"user://test_equipment_request_handler_atomic_sword.tres",
		[Equippable.SlotId.Right_Hand]
	)
	var request: EntityEquipmentActionRequestMsg = EntityEquipmentActionRequestMsg.create(10, [
		EntityEquipmentActionRequestMsg.make_equip_action(
			Equippable.SlotId.Right_Hand,
			"weapon_1",
			template_path
		),
		EntityEquipmentActionRequestMsg.make_equip_action(
			Equippable.SlotId.Left_Hand,
			"weapon_2",
			template_path
		),
	])

	var outcome: EquipmentRequestHandler.RequestOutcome = handler.handle_request(42, request)

	assert_eq(outcome.result.result_code, EntityEquipmentActionResultMsg.RESULT_SLOT_NOT_ALLOWED)
	assert_eq(outcome.result.equipment_revision, 0)
	assert_false(player.equipment.has_equipped_slot(Equippable.SlotId.Right_Hand))
	assert_true(outcome.changes.is_empty())


func test_batch_can_unequip_and_equip_in_one_request() -> void:
	var fixture: Dictionary = _make_fixture()
	var handler: EquipmentRequestHandler = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	var template_path: String = _save_equippable_template(
		"user://test_equipment_request_handler_swap_sword.tres",
		[Equippable.SlotId.Right_Hand]
	)
	var existing_template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
	player.equipment.set_equipped(
		EquippableItem.create(existing_template, 1, "old_weapon"),
		Equippable.SlotId.Right_Hand
	)

	var request: EntityEquipmentActionRequestMsg = EntityEquipmentActionRequestMsg.create(11, [
		EntityEquipmentActionRequestMsg.make_unequip_action(Equippable.SlotId.Right_Hand),
		EntityEquipmentActionRequestMsg.make_equip_action(
			Equippable.SlotId.Left_Hand,
			"new_weapon",
			_save_equippable_template(
				"user://test_equipment_request_handler_left_sword.tres",
				[Equippable.SlotId.Left_Hand]
			)
		),
	])

	var outcome: EquipmentRequestHandler.RequestOutcome = handler.handle_request(42, request)

	assert_eq(outcome.result.result_code, EntityEquipmentActionResultMsg.RESULT_OK)
	assert_eq(outcome.result.equipment_revision, 3)
	assert_false(player.equipment.has_equipped_slot(Equippable.SlotId.Right_Hand))
	assert_true(player.equipment.has_equipped_slot(Equippable.SlotId.Left_Hand))
	assert_eq(outcome.changes.size(), 2)
	assert_eq(outcome.changes[0].get("operation"), EntityEquipmentChangedMsg.OPERATION_UNSET)
	assert_eq(outcome.changes[1].get("operation"), EntityEquipmentChangedMsg.OPERATION_SET)


func _make_fixture() -> Dictionary:
	var handler: EquipmentRequestHandler = autofree(EquipmentRequestHandler.new()) as EquipmentRequestHandler
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player_scene: PackedScene = load("res://projects/game-server/src/entities/player/server_player_entity.tscn") as PackedScene
	var player: ServerPlayerEntity = add_child_autofree(player_scene.instantiate()) as ServerPlayerEntity
	player.entity_id = 7
	tracker.track_player(42, player)
	handler.entity_tracker = tracker
	return {
		"handler": handler,
		"player": player,
	}


func _save_equippable_template(path: String, slots: Array[Equippable.SlotId]) -> String:
	var equippable: Equippable = Equippable.new()
	equippable.slots = slots
	var template: ItemTemplate = ItemTemplate.new()
	template.equippable = equippable
	assert_eq(ResourceSaver.save(template, path), OK)
	return path
