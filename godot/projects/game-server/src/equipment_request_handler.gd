class_name EquipmentRequestHandler
extends Node

@export var network: GameServerNetwork
@export var entity_tracker: EntityTracker


class RequestOutcome:
	var result: EntityEquipmentActionResultMsg
	var changes: Array[Dictionary] = []


func _ready() -> void:
	network.entity_equipment_action_requested.connect(_on_entity_equipment_action_requested)


func handle_request(peer_id: int, request: EntityEquipmentActionRequestMsg) -> RequestOutcome:
	var player: ServerPlayerEntity = entity_tracker.get_player(peer_id)
	if player == null:
		return _make_outcome(
			request.request_id,
			EntityEquipmentActionResultMsg.RESULT_ENTITY_NOT_FOUND,
			0,
			0
		)

	if request.request_id <= 0 or request.actions.is_empty():
		return _make_outcome(
			request.request_id,
			EntityEquipmentActionResultMsg.RESULT_INVALID_REQUEST,
			player.entity_id,
			player.equipment.revision
		)

	var validated_actions: Array[Dictionary] = []
	for action in request.actions:
		var validation: Dictionary = _validate_action(player.equipment, action)
		var result_code: int = int(validation.get(
			"result_code",
			EntityEquipmentActionResultMsg.RESULT_INVALID_REQUEST
		))
		if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
			return _make_outcome(
				request.request_id,
				result_code,
				player.entity_id,
				player.equipment.revision
			)
		validated_actions.append(validation)

	var changes: Array[Dictionary] = _apply_actions(player.equipment, validated_actions)
	return _make_outcome(
		request.request_id,
		EntityEquipmentActionResultMsg.RESULT_OK,
		player.entity_id,
		player.equipment.revision,
		changes
	)


func _on_entity_equipment_action_requested(
		peer_id: int,
		request: EntityEquipmentActionRequestMsg) -> void:
	var outcome: RequestOutcome = handle_request(peer_id, request)
	network.send_entity_equipment_action_result(
		peer_id,
		EntityEquipmentActionResultMsg.encode(
			outcome.result.request_id,
			outcome.result.result_code,
			outcome.result.entity_id,
			outcome.result.equipment_revision
		)
	)

	if outcome.result.result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return
	if outcome.changes.is_empty():
		return

	network.broadcast_entity_equipment_changed(
		EntityEquipmentChangedMsg.encode(
			outcome.result.entity_id,
			outcome.result.equipment_revision,
			outcome.changes
		)
	)


func _validate_action(equipment: Equipment, action: Dictionary) -> Dictionary:
	var operation: int = int(action.get("operation", -1))
	var slot_id_value: int = int(action.get("slot_id", -1))
	if not _is_valid_slot_id(slot_id_value):
		return {"result_code": EntityEquipmentActionResultMsg.RESULT_INVALID_REQUEST}
	var slot_id: Equippable.SlotId = slot_id_value
	match operation:
		EntityEquipmentActionRequestMsg.OPERATION_UNEQUIP:
			return {
				"result_code": EntityEquipmentActionResultMsg.RESULT_OK,
				"operation": operation,
				"slot_id": slot_id,
			}
		EntityEquipmentActionRequestMsg.OPERATION_EQUIP:
			var item_instance_id: String = str(action.get("item_instance_id", ""))
			var template_resource_path: String = str(action.get("template_resource_path", ""))
			if item_instance_id.is_empty() or template_resource_path.is_empty():
				return {"result_code": EntityEquipmentActionResultMsg.RESULT_INVALID_REQUEST}

			var template: ItemTemplate = ResourceLoader.load(template_resource_path) as ItemTemplate
			if template == null:
				return {"result_code": EntityEquipmentActionResultMsg.RESULT_TEMPLATE_NOT_FOUND}
			if template.equippable == null:
				return {"result_code": EntityEquipmentActionResultMsg.RESULT_NOT_EQUIPPABLE}

			var item: EquippableItem = EquippableItem.create(template, 1, item_instance_id)
			if not equipment.can_equip(item, slot_id):
				return {"result_code": EntityEquipmentActionResultMsg.RESULT_SLOT_NOT_ALLOWED}

			return {
				"result_code": EntityEquipmentActionResultMsg.RESULT_OK,
				"operation": operation,
				"slot_id": slot_id,
				"item": item,
			}
		_:
			return {"result_code": EntityEquipmentActionResultMsg.RESULT_INVALID_REQUEST}


func _is_valid_slot_id(slot_id: int) -> bool:
	return slot_id >= int(Equippable.SlotId.Head) \
			and slot_id <= int(Equippable.SlotId.Right_Hand)


func _apply_actions(
		equipment: Equipment,
		validated_actions: Array[Dictionary]) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for action in validated_actions:
		var operation: int = int(action.get("operation", EntityEquipmentActionRequestMsg.OPERATION_UNEQUIP))
		var slot_id: Equippable.SlotId = int(action.get("slot_id", 0))
		match operation:
			EntityEquipmentActionRequestMsg.OPERATION_UNEQUIP:
				var previous: EquippableItem = equipment.unset_equipped(slot_id)
				if previous == null:
					continue
				changes.append({
					"slot_id": slot_id,
					"operation": EntityEquipmentChangedMsg.OPERATION_UNSET,
				})
			EntityEquipmentActionRequestMsg.OPERATION_EQUIP:
				var item: EquippableItem = action.get("item") as EquippableItem
				equipment.set_equipped(item, slot_id)
				changes.append({
					"slot_id": slot_id,
					"operation": EntityEquipmentChangedMsg.OPERATION_SET,
					"item_instance_id": item.instance_id,
					"template_resource_path": item.get_template_resource_path(),
				})
	return changes


func _make_outcome(
		request_id: int,
		result_code: int,
		entity_id: int,
		equipment_revision: int,
		changes: Array[Dictionary] = []) -> RequestOutcome:
	var outcome: RequestOutcome = RequestOutcome.new()
	outcome.result = EntityEquipmentActionResultMsg.create(
		request_id,
		result_code,
		entity_id,
		equipment_revision
	)
	outcome.changes = changes
	return outcome
