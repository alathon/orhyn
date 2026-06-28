class_name EntityEquipmentActionResultMsg
extends RefCounted

const MAGIC: int = MessageHeaders.EntityEquipmentActionResultMsgHeader
const SIZE: int = 16

const RESULT_OK: int = 0
const RESULT_INVALID_REQUEST: int = 1
const RESULT_ENTITY_NOT_FOUND: int = 2
const RESULT_TEMPLATE_NOT_FOUND: int = 3
const RESULT_NOT_EQUIPPABLE: int = 4
const RESULT_SLOT_NOT_ALLOWED: int = 5

var request_id: int = 0
var result_code: int = RESULT_INVALID_REQUEST
var entity_id: int = 0
var equipment_revision: int = 0


static func create(
		new_request_id: int,
		new_result_code: int,
		new_entity_id: int,
		new_equipment_revision: int) -> EntityEquipmentActionResultMsg:
	var msg: EntityEquipmentActionResultMsg = EntityEquipmentActionResultMsg.new()
	msg.request_id = new_request_id
	msg.result_code = new_result_code
	msg.entity_id = new_entity_id
	msg.equipment_revision = new_equipment_revision
	return msg


static func encode(
		request_id_: int,
		result_code_: int,
		entity_id_: int,
		equipment_revision_: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SIZE)

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u32(bytes, offset, request_id_)
	offset = ProtocolUtils.write_u16(bytes, offset, result_code_)
	offset = ProtocolUtils.write_u32(bytes, offset, entity_id_)
	ProtocolUtils.write_u32(bytes, offset, equipment_revision_)
	return bytes


static func decode(bytes: PackedByteArray) -> EntityEquipmentActionResultMsg:
	if bytes.size() < SIZE:
		return EntityEquipmentActionResultMsg.new()

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return EntityEquipmentActionResultMsg.new()

	offset += 1 # flags
	var decoded_request_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var decoded_result_code: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var decoded_entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var decoded_revision: int = ProtocolUtils.read_u32(bytes, offset)

	return create(
		decoded_request_id,
		decoded_result_code,
		decoded_entity_id,
		decoded_revision
	)


static func encode_packet(
		request_id_: int,
		result_code_: int,
		entity_id_: int,
		equipment_revision_: int) -> PackedByteArray:
	return encode(request_id_, result_code_, entity_id_, equipment_revision_)


static func decode_packet(bytes: PackedByteArray) -> EntityEquipmentActionResultMsg:
	return decode(bytes)
