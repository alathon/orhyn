extends GutTest


class StubGameServerAPI:
	extends GameServerAPI

	var next_request_id: int = 23
	var equip_request_count: int = 0

	func request_equip_item(
			_slot_id: Equippable.SlotId,
			_item_instance_id: String,
			_template_resource_path: String) -> int:
		equip_request_count += 1
		return next_request_id

	func request_unequip_slot(_slot_id: Equippable.SlotId) -> int:
		return next_request_id


var _submitted_action_name: StringName = &""
var _submitted_request_id: int = -1
var _resolved_action_name: StringName = &""
var _resolved_request_id: int = -1
var _resolved_result_code: int = -1
var _rejected_action_name: StringName = &""
var _rejected_reason: StringName = &""


func before_each() -> void:
	_submitted_action_name = &""
	_submitted_request_id = -1
	_resolved_action_name = &""
	_resolved_request_id = -1
	_resolved_result_code = -1
	_rejected_action_name = &""
	_rejected_reason = &""


func test_owns_equipment_action_submission_and_resolution() -> void:
	var api: StubGameServerAPI = autofree(StubGameServerAPI.new()) as StubGameServerAPI
	api.auto_connect = false
	var spawner: ClientEntitySpawner = autofree(ClientEntitySpawner.new()) as ClientEntitySpawner
	var actions: ClientActions = ClientActions.new()
	actions.api = api
	actions.entity_spawner = spawner
	actions.action_submitted.connect(_record_submission)
	actions.action_resolved.connect(_record_resolution)
	add_child_autoqfree(actions)

	var player: Player = autofree(Player.new()) as Player
	spawner.local_player_spawned.emit(player)

	var request_id: int = actions.try_unequip_slot(Equippable.SlotId.Right_Hand)

	assert_eq(request_id, 23)
	assert_eq(_submitted_action_name, &"unequip_slot")
	assert_eq(_submitted_request_id, request_id)
	assert_eq(_resolved_request_id, -1)

	api.publish_action_result(
		request_id,
		EntityEquipmentActionResultMsg.RESULT_OK
	)

	assert_eq(_resolved_action_name, &"unequip_slot")
	assert_eq(_resolved_request_id, request_id)
	assert_eq(_resolved_result_code, EntityEquipmentActionResultMsg.RESULT_OK)


func test_ignores_results_for_actions_it_did_not_submit() -> void:
	var api: StubGameServerAPI = autofree(StubGameServerAPI.new()) as StubGameServerAPI
	api.auto_connect = false
	var spawner: ClientEntitySpawner = autofree(ClientEntitySpawner.new()) as ClientEntitySpawner
	var actions: ClientActions = ClientActions.new()
	actions.api = api
	actions.entity_spawner = spawner
	actions.action_resolved.connect(_record_resolution)
	add_child_autoqfree(actions)

	api.publish_action_result(
		99,
		EntityEquipmentActionResultMsg.RESULT_OK
	)

	assert_eq(_resolved_request_id, -1)


func test_rejects_incompatible_equipment_without_sending_request() -> void:
	var api: StubGameServerAPI = autofree(StubGameServerAPI.new()) as StubGameServerAPI
	api.auto_connect = false
	var spawner: ClientEntitySpawner = autofree(ClientEntitySpawner.new()) as ClientEntitySpawner
	var actions: ClientActions = ClientActions.new()
	actions.api = api
	actions.entity_spawner = spawner
	actions.action_rejected.connect(_record_rejection)
	add_child_autoqfree(actions)

	var player_scene: PackedScene = load(
		"res://projects/client/src/entities/player/player_entity.tscn"
	) as PackedScene
	var player: Player = add_child_autofree(player_scene.instantiate()) as Player
	spawner.local_player_spawned.emit(player)

	var equippable: Equippable = Equippable.new()
	equippable.slots = [Equippable.SlotId.Head]
	var template: ItemTemplate = ItemTemplate.new()
	template.equippable = equippable
	var item: EquippableItem = EquippableItem.create(template, 1, "helmet_1")

	var request_id: int = actions.try_equip_item(item, Equippable.SlotId.Right_Hand)

	assert_eq(request_id, -1)
	assert_eq(api.equip_request_count, 0)
	assert_eq(_rejected_action_name, &"equip_item")
	assert_eq(_rejected_reason, &"cannot_equip")


func _record_submission(action_name: StringName, request_id: int) -> void:
	_submitted_action_name = action_name
	_submitted_request_id = request_id


func _record_resolution(
		action_name: StringName,
		request_id: int,
		result_code: int) -> void:
	_resolved_action_name = action_name
	_resolved_request_id = request_id
	_resolved_result_code = result_code


func _record_rejection(action_name: StringName, reason: StringName) -> void:
	_rejected_action_name = action_name
	_rejected_reason = reason
