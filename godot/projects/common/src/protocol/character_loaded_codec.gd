class_name CharacterLoadedCodec
extends RefCounted

const MAGIC: int = MessageHeaders.CharacterLoadedMsgHeader
const HEADER_SIZE: int = 18


static func encode(
		character_id: int,
		entity_id: int,
		display_name: String,
		zone_id: String,
		model_name: String,
		level: int) -> PackedByteArray:
	var zone_bytes: PackedByteArray = zone_id.to_utf8_buffer()
	var display_bytes: PackedByteArray = display_name.to_utf8_buffer()
	var model_bytes: PackedByteArray = model_name.to_utf8_buffer()
	var zone_size: int = mini(zone_bytes.size(), 0xFFFF)
	var display_size: int = mini(display_bytes.size(), 0xFFFF)
	var model_size: int = mini(model_bytes.size(), 0xFFFF)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(HEADER_SIZE + zone_size + display_size + model_size)

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u32(bytes, offset, character_id)
	offset = ProtocolUtils.write_u32(bytes, offset, entity_id)
	offset = ProtocolUtils.write_u16(bytes, offset, level)
	offset = ProtocolUtils.write_u16(bytes, offset, zone_size)
	offset = ProtocolUtils.write_u16(bytes, offset, display_size)
	offset = ProtocolUtils.write_u16(bytes, offset, model_size)
	offset = _write_bytes(bytes, offset, zone_bytes, zone_size)
	offset = _write_bytes(bytes, offset, display_bytes, display_size)
	_write_bytes(bytes, offset, model_bytes, model_size)
	return bytes


static func decode(bytes: PackedByteArray) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if bytes.size() < HEADER_SIZE:
		return events

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return events

	offset += 1 # message flags
	var character_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var level: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var zone_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var display_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var model_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2

	var expected_size: int = HEADER_SIZE + zone_size + display_size + model_size
	if bytes.size() < expected_size:
		return events

	var zone_id: String = bytes.slice(offset, offset + zone_size).get_string_from_utf8()
	offset += zone_size
	var display_name: String = bytes.slice(offset, offset + display_size).get_string_from_utf8()
	offset += display_size
	var model_name: String = bytes.slice(offset, offset + model_size).get_string_from_utf8()

	if character_id > 0 and entity_id > 0:
		events.append(CharacterLoadedGameEvent.new(
			character_id,
			entity_id,
			display_name,
			zone_id,
			model_name,
			level
		))
	return events


static func _write_bytes(
		target: PackedByteArray,
		offset: int,
		source: PackedByteArray,
		source_size: int) -> int:
	for index: int in range(source_size):
		target[offset + index] = source[index]
	return offset + source_size
