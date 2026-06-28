class_name EntityEquipmentChangedMsg
extends RefCounted

const MAGIC: int = MessageHeaders.EntityEquipmentChangedMsgHeader
const HEADER_SIZE: int = 12
const CHANGE_FIXED_SIZE: int = 6

const OPERATION_UNSET: int = 0
const OPERATION_SET: int = 1

var entity_id: int = 0
var equipment_revision: int = 0
var changes: Array[Dictionary] = []


static func create(
		new_entity_id: int,
		new_equipment_revision: int,
		new_changes: Array[Dictionary]) -> EntityEquipmentChangedMsg:
	var msg: EntityEquipmentChangedMsg = EntityEquipmentChangedMsg.new()
	msg.entity_id = new_entity_id
	msg.equipment_revision = new_equipment_revision
	msg.changes = new_changes
	return msg


static func encode(
		entity_id_: int,
		equipment_revision_: int,
		changes_: Array[Dictionary]) -> PackedByteArray:
	var change_count: int = mini(changes_.size(), 0xFFFF)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_encoded_size(changes_, change_count))

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, change_count)
	offset = ProtocolUtils.write_u32(bytes, offset, entity_id_)
	offset = ProtocolUtils.write_u32(bytes, offset, equipment_revision_)

	for i in change_count:
		offset = _write_change(bytes, offset, changes_[i])

	return bytes


static func decode(bytes: PackedByteArray) -> EntityEquipmentChangedMsg:
	if bytes.size() < HEADER_SIZE:
		return EntityEquipmentChangedMsg.new()

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return EntityEquipmentChangedMsg.new()

	offset += 1 # message flags
	var change_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var decoded_entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var decoded_revision: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	var decoded_changes: Array[Dictionary] = []
	decoded_changes.resize(change_count)
	for i in change_count:
		var result: Dictionary = _read_change(bytes, offset)
		if result.is_empty():
			return EntityEquipmentChangedMsg.new()
		decoded_changes[i] = result.change
		offset = result.offset

	return create(decoded_entity_id, decoded_revision, decoded_changes)


static func encode_packet(
		entity_id_: int,
		equipment_revision_: int,
		changes_: Array[Dictionary]) -> PackedByteArray:
	return encode(entity_id_, equipment_revision_, changes_)


static func decode_packet(bytes: PackedByteArray) -> EntityEquipmentChangedMsg:
	return decode(bytes)


static func _encoded_size(changes_: Array[Dictionary], change_count: int) -> int:
	var size: int = HEADER_SIZE
	for i in change_count:
		var change: Dictionary = changes_[i]
		var item_instance_bytes: PackedByteArray = str(
			change.get("item_instance_id", "")
		).to_utf8_buffer()
		var template_bytes: PackedByteArray = str(
			change.get("template_resource_path", "")
		).to_utf8_buffer()
		size += CHANGE_FIXED_SIZE \
				+ mini(item_instance_bytes.size(), 0xFFFF) \
				+ mini(template_bytes.size(), 0xFFFF)
	return size


static func _write_change(bytes: PackedByteArray, offset: int, change: Dictionary) -> int:
	var item_instance_bytes: PackedByteArray = str(
		change.get("item_instance_id", "")
	).to_utf8_buffer()
	var template_bytes: PackedByteArray = str(
		change.get("template_resource_path", "")
	).to_utf8_buffer()
	var item_instance_size: int = mini(item_instance_bytes.size(), 0xFFFF)
	var template_size: int = mini(template_bytes.size(), 0xFFFF)

	offset = ProtocolUtils.write_u8(bytes, offset, int(change.get("slot_id", 0)))
	offset = ProtocolUtils.write_u8(bytes, offset, int(change.get("operation", OPERATION_UNSET)))
	offset = ProtocolUtils.write_u16(bytes, offset, item_instance_size)
	offset = ProtocolUtils.write_u16(bytes, offset, template_size)
	offset = _write_bytes(bytes, offset, item_instance_bytes, item_instance_size)
	return _write_bytes(bytes, offset, template_bytes, template_size)


static func _read_change(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() < offset + CHANGE_FIXED_SIZE:
		return {}

	var slot_id: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	var operation: int = ProtocolUtils.read_u8(bytes, offset)
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
		"change": {
			"slot_id": slot_id,
			"operation": operation,
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
