class_name CharacterLoadedMsg
extends RefCounted

const MAGIC: int = MessageHeaders.CharacterLoadedMsgHeader
const HEADER_SIZE: int = 18

var character_id: int = 0
var entity_id: int = 0
var level: int = 1
var display_name: String = ""
var zone_id: String = ""
var model_name: String = ""

static func create(
	new_character_id: int,
	new_entity_id: int,
	new_display_name: String,
	new_zone_id: String,
	new_model_name: String,
	new_level: int
) -> CharacterLoadedMsg:
	var msg: CharacterLoadedMsg = CharacterLoadedMsg.new()
	msg.character_id = new_character_id
	msg.entity_id = new_entity_id
	msg.display_name = new_display_name
	msg.zone_id = new_zone_id
	msg.model_name = new_model_name
	msg.level = new_level
	return msg

static func encode(
	character_id_: int,
	entity_id_: int,
	display_name_: String,
	zone_id_: String,
	model_name_: String,
	level_: int
) -> PackedByteArray:
	var zone_bytes: PackedByteArray = zone_id_.to_utf8_buffer()
	var display_bytes: PackedByteArray = display_name_.to_utf8_buffer()
	var model_bytes: PackedByteArray = model_name_.to_utf8_buffer()
	var zone_size: int = mini(zone_bytes.size(), 0xFFFF)
	var display_size: int = mini(display_bytes.size(), 0xFFFF)
	var model_size: int = mini(model_bytes.size(), 0xFFFF)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(HEADER_SIZE + zone_size + display_size + model_size)

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u32(bytes, offset, character_id_)
	offset = ProtocolUtils.write_u32(bytes, offset, entity_id_)
	offset = ProtocolUtils.write_u16(bytes, offset, level_)
	offset = ProtocolUtils.write_u16(bytes, offset, zone_size)
	offset = ProtocolUtils.write_u16(bytes, offset, display_size)
	offset = ProtocolUtils.write_u16(bytes, offset, model_size)
	offset = _write_bytes(bytes, offset, zone_bytes, zone_size)
	offset = _write_bytes(bytes, offset, display_bytes, display_size)
	_write_bytes(bytes, offset, model_bytes, model_size)
	return bytes

static func decode(bytes: PackedByteArray) -> CharacterLoadedMsg:
	var msg: CharacterLoadedMsg = CharacterLoadedMsg.new()
	if bytes.size() < HEADER_SIZE:
		return msg

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return CharacterLoadedMsg.new()

	offset += 1
	msg.character_id = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	msg.entity_id = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	msg.level = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var zone_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var display_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var model_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2

	var expected_size: int = HEADER_SIZE + zone_size + display_size + model_size
	if bytes.size() < expected_size:
		return CharacterLoadedMsg.new()

	msg.zone_id = bytes.slice(offset, offset + zone_size).get_string_from_utf8()
	offset += zone_size
	msg.display_name = bytes.slice(offset, offset + display_size).get_string_from_utf8()
	offset += display_size
	msg.model_name = bytes.slice(offset, offset + model_size).get_string_from_utf8()
	return msg

static func encode_packet(
	character_id_: int,
	entity_id_: int,
	display_name_: String,
	zone_id_: String,
	model_name_: String,
	level_: int
) -> PackedByteArray:
	return encode(character_id_, entity_id_, display_name_, zone_id_, model_name_, level_)

static func decode_packet(bytes: PackedByteArray) -> CharacterLoadedMsg:
	return decode(bytes)

static func _write_bytes(
	target: PackedByteArray,
	offset: int,
	source: PackedByteArray,
	source_size: int
) -> int:
	for index: int in range(source_size):
		target[offset + index] = source[index]
	return offset + source_size
