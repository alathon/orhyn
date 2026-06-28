class_name EntityEquipmentActionRequestMsg
extends RefCounted

const MAGIC: int = MessageHeaders.EntityEquipmentActionRequestMsgHeader
const HEADER_SIZE: int = 8
const ACTION_FIXED_SIZE: int = 6

const OPERATION_UNEQUIP: int = 0
const OPERATION_EQUIP: int = 1

var request_id: int = 0
var actions: Array[Dictionary] = []


static func create(
		new_request_id: int,
		new_actions: Array[Dictionary]) -> EntityEquipmentActionRequestMsg:
	var msg: EntityEquipmentActionRequestMsg = EntityEquipmentActionRequestMsg.new()
	msg.request_id = new_request_id
	msg.actions = new_actions
	return msg


static func make_equip_action(
		slot_id: Equippable.SlotId,
		item_instance_id: String,
		template_resource_path: String) -> Dictionary:
	return {
		"operation": OPERATION_EQUIP,
		"slot_id": slot_id,
		"item_instance_id": item_instance_id,
		"template_resource_path": template_resource_path,
	}


static func make_unequip_action(slot_id: Equippable.SlotId) -> Dictionary:
	return {
		"operation": OPERATION_UNEQUIP,
		"slot_id": slot_id,
	}


static func encode(request_id_: int, actions_: Array[Dictionary]) -> PackedByteArray:
	var action_count: int = mini(actions_.size(), 0xFFFF)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_encoded_size(actions_, action_count))

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, action_count)
	offset = ProtocolUtils.write_u32(bytes, offset, request_id_)

	for i in action_count:
		offset = _write_action(bytes, offset, actions_[i])

	return bytes


static func decode(bytes: PackedByteArray) -> EntityEquipmentActionRequestMsg:
	if bytes.size() < HEADER_SIZE:
		return EntityEquipmentActionRequestMsg.new()

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return EntityEquipmentActionRequestMsg.new()

	offset += 1 # flags
	var action_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var decoded_request_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	var decoded_actions: Array[Dictionary] = []
	decoded_actions.resize(action_count)
	for i in action_count:
		var result: Dictionary = _read_action(bytes, offset)
		if result.is_empty():
			return EntityEquipmentActionRequestMsg.new()
		decoded_actions[i] = result.action
		offset = result.offset

	return create(decoded_request_id, decoded_actions)


static func encode_packet(request_id_: int, actions_: Array[Dictionary]) -> PackedByteArray:
	return encode(request_id_, actions_)


static func decode_packet(bytes: PackedByteArray) -> EntityEquipmentActionRequestMsg:
	return decode(bytes)


static func _encoded_size(actions_: Array[Dictionary], action_count: int) -> int:
	var size: int = HEADER_SIZE
	for i in action_count:
		var action: Dictionary = actions_[i]
		var item_instance_bytes: PackedByteArray = str(
			action.get("item_instance_id", "")
		).to_utf8_buffer()
		var template_bytes: PackedByteArray = str(
			action.get("template_resource_path", "")
		).to_utf8_buffer()
		size += ACTION_FIXED_SIZE \
				+ mini(item_instance_bytes.size(), 0xFFFF) \
				+ mini(template_bytes.size(), 0xFFFF)
	return size


static func _write_action(bytes: PackedByteArray, offset: int, action: Dictionary) -> int:
	var item_instance_bytes: PackedByteArray = str(
		action.get("item_instance_id", "")
	).to_utf8_buffer()
	var template_bytes: PackedByteArray = str(
		action.get("template_resource_path", "")
	).to_utf8_buffer()
	var item_instance_size: int = mini(item_instance_bytes.size(), 0xFFFF)
	var template_size: int = mini(template_bytes.size(), 0xFFFF)

	offset = ProtocolUtils.write_u8(bytes, offset, int(action.get("operation", OPERATION_UNEQUIP)))
	offset = ProtocolUtils.write_u8(bytes, offset, int(action.get("slot_id", 0)))
	offset = ProtocolUtils.write_u16(bytes, offset, item_instance_size)
	offset = ProtocolUtils.write_u16(bytes, offset, template_size)
	offset = _write_bytes(bytes, offset, item_instance_bytes, item_instance_size)
	return _write_bytes(bytes, offset, template_bytes, template_size)


static func _read_action(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() < offset + ACTION_FIXED_SIZE:
		return {}

	var operation: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	var slot_id: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	var item_instance_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var template_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2

	var expected_size: int = offset + item_instance_size + template_size
	if bytes.size() < expected_size:
		return {}

	var item_instance_id: String = bytes.slice(offset, offset + item_instance_size).get_string_from_utf8()
	offset += item_instance_size
	var template_resource_path: String = bytes.slice(offset, offset + template_size).get_string_from_utf8()
	offset += template_size

	return {
		"action": {
			"operation": operation,
			"slot_id": slot_id,
			"item_instance_id": item_instance_id,
			"template_resource_path": template_resource_path,
		},
		"offset": offset,
	}


static func _write_bytes(
		target: PackedByteArray,
		offset: int,
		source: PackedByteArray,
		source_size: int) -> int:
	for index: int in range(source_size):
		target[offset + index] = source[index]
	return offset + source_size
