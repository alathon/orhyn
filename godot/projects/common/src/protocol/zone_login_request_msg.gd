class_name ZoneLoginRequestMsg
extends RefCounted

const MAGIC: int = MessageHeaders.ZoneLoginRequestMsgHeader
const HEADER_SIZE: int = 8

var character_id: int = 0
var transfer_token: String = ""

static func create(new_character_id: int, new_transfer_token: String) -> ZoneLoginRequestMsg:
	var msg: ZoneLoginRequestMsg = ZoneLoginRequestMsg.new()
	msg.character_id = new_character_id
	msg.transfer_token = new_transfer_token
	return msg

static func encode(character_id_: int, transfer_token_: String) -> PackedByteArray:
	var token_bytes: PackedByteArray = transfer_token_.to_utf8_buffer()
	var token_size: int = mini(token_bytes.size(), 0xFFFF)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(HEADER_SIZE + token_size)

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, token_size)
	offset = ProtocolUtils.write_u32(bytes, offset, character_id_)
	for index: int in range(token_size):
		bytes[offset + index] = token_bytes[index]
	return bytes

static func decode(bytes: PackedByteArray) -> ZoneLoginRequestMsg:
	var msg: ZoneLoginRequestMsg = ZoneLoginRequestMsg.new()
	if bytes.size() < HEADER_SIZE:
		return msg

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return ZoneLoginRequestMsg.new()

	offset += 1
	var token_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	msg.character_id = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	if bytes.size() < HEADER_SIZE + token_size:
		return ZoneLoginRequestMsg.new()

	var token_bytes: PackedByteArray = bytes.slice(offset, offset + token_size)
	msg.transfer_token = token_bytes.get_string_from_utf8()
	return msg

static func encode_packet(character_id_: int, transfer_token_: String) -> PackedByteArray:
	return encode(character_id_, transfer_token_)

static func decode_packet(bytes: PackedByteArray) -> ZoneLoginRequestMsg:
	return decode(bytes)
