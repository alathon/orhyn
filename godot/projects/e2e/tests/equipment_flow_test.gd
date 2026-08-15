extends E2ETestCase

const SWORD_TEMPLATE_PATH: String = "res://projects/e2e/fixtures/equipment/e2e_sword.tres"
const HELMET_TEMPLATE_PATH: String = "res://projects/e2e/fixtures/equipment/e2e_helmet.tres"

func run(session: E2ESession, _config: Dictionary = {}) -> Dictionary:
	var result: Dictionary = await _equip_one_item(session)
	if not bool(result.get("ok", false)):
		return result

	result = await _unequip_item(session)
	if not bool(result.get("ok", false)):
		return result

	result = await _equip_multiple_items(session)
	if not bool(result.get("ok", false)):
		return result

	result = await _reject_invalid_slot_locally(session)
	if not bool(result.get("ok", false)):
		return result

	await _cleanup(session)
	return passed()

func _equip_one_item(session: E2ESession) -> Dictionary:
	var request_id: int = session.try_equip_item(
		_make_item(SWORD_TEMPLATE_PATH, "e2e_sword_1"),
		Equippable.SlotId.Right_Hand
	)
	if request_id <= 0:
		return failed("equip_one_item", "Could not send equip request.")

	var result_code: int = await session.wait_for_action_result(request_id, timeout_seconds)
	if result_code == E2ESession.ACTION_RESULT_TIMEOUT:
		return failed("equip_one_item", "Timed out waiting for equipment result.", {
			"request_id": request_id,
		})
	if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return failed("equip_one_item", "Server rejected valid equip request.", {
			"request_id": request_id,
			"result_code": result_code,
		})

	var item: EquippableItem = await session.wait_for_equipped(
		Equippable.SlotId.Right_Hand,
		"e2e_sword_1",
		timeout_seconds
	)
	if item == null:
		return failed("equip_one_item", "Timed out waiting for replicated equipment state.", {
			"request_id": request_id,
			"slot_id": Equippable.SlotId.Right_Hand,
		})

	return passed()

func _unequip_item(session: E2ESession) -> Dictionary:
	var request_id: int = session.try_unequip_slot(Equippable.SlotId.Right_Hand)
	if request_id <= 0:
		return failed("unequip_item", "Could not send unequip request.")

	var result_code: int = await session.wait_for_action_result(request_id, timeout_seconds)
	if result_code == E2ESession.ACTION_RESULT_TIMEOUT:
		return failed("unequip_item", "Timed out waiting for equipment result.", {
			"request_id": request_id,
		})
	if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return failed("unequip_item", "Server rejected valid unequip request.", {
			"request_id": request_id,
			"result_code": result_code,
		})

	if not await session.wait_for_unequipped(Equippable.SlotId.Right_Hand, timeout_seconds):
		return failed("unequip_item", "Timed out waiting for replicated unequip state.", {
			"request_id": request_id,
		})

	return passed()

func _equip_multiple_items(session: E2ESession) -> Dictionary:
	var request_id: int = session.try_equip_item(
		_make_item(SWORD_TEMPLATE_PATH, "e2e_sword_2"),
		Equippable.SlotId.Right_Hand
	)
	var result: Dictionary = await _expect_ok_action_result(session, request_id, "equip_multiple_items")
	if not bool(result.get("ok", false)):
		return result

	request_id = session.try_equip_item(
		_make_item(HELMET_TEMPLATE_PATH, "e2e_helmet_1"),
		Equippable.SlotId.Head
	)
	result = await _expect_ok_action_result(session, request_id, "equip_multiple_items")
	if not bool(result.get("ok", false)):
		return result

	var sword: EquippableItem = await session.wait_for_equipped(
		Equippable.SlotId.Right_Hand,
		"e2e_sword_2",
		timeout_seconds
	)
	var helmet: EquippableItem = await session.wait_for_equipped(
		Equippable.SlotId.Head,
		"e2e_helmet_1",
		timeout_seconds
	)
	if sword == null or helmet == null:
		return failed("equip_multiple_items", "Timed out waiting for replicated multi-slot equipment.", {
			"has_sword": sword != null,
			"has_helmet": helmet != null,
		})

	return passed()

func _reject_invalid_slot_locally(session: E2ESession) -> Dictionary:
	var request_id: int = session.try_equip_item(
		_make_item(HELMET_TEMPLATE_PATH, "e2e_invalid_helmet"),
		Equippable.SlotId.Right_Hand
	)
	if request_id > 0:
		return failed("reject_invalid_slot_locally", "Client sent an invalid equip request.", {
			"request_id": request_id,
		})

	var player: Player = session.local_player()
	var right_hand: EquippableItem = player.equipment.get_equipped(Equippable.SlotId.Right_Hand)
	if right_hand == null or right_hand.instance_id != "e2e_sword_2":
		return failed("reject_invalid_slot_locally", "Invalid request changed right hand equipment.", {
			"current_item": right_hand.instance_id if right_hand != null else "",
		})

	return passed()

func _expect_ok_action_result(
		session: E2ESession,
		request_id: int,
		step: String) -> Dictionary:
	if request_id <= 0:
		return failed(step, "Could not send equipment request.")

	var result_code: int = await session.wait_for_action_result(request_id, timeout_seconds)
	if result_code == E2ESession.ACTION_RESULT_TIMEOUT:
		return failed(step, "Timed out waiting for equipment result.", {
			"request_id": request_id,
		})
	if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return failed(step, "Server rejected valid equipment request.", {
			"request_id": request_id,
			"result_code": result_code,
		})
	return passed()

func _cleanup(session: E2ESession) -> void:
	session.try_unequip_slot(Equippable.SlotId.Right_Hand)
	session.try_unequip_slot(Equippable.SlotId.Head)

func _make_item(template_path: String, item_instance_id: String) -> EquippableItem:
	var template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
	return EquippableItem.create(template, 1, item_instance_id)
