class_name MovementSnapshotMsg
extends RefCounted

const MAGIC: int = MessageHeaders.MovementSnapshotMsgHeader
const HEADER_SIZE := 8
const ENTITY_SIZE := 34

const FLAG_ON_FLOOR := 1

const POSITION_SCALE := 1000.0
const VELOCITY_SCALE := 100.0
const QUAT_COMPONENT_LIMIT := 0.7071067811865476
const QUAT_SCALE := 32767.0 / QUAT_COMPONENT_LIMIT
const NO_PROCESSED_SEQ := 0xFFFFFFFF

var server_tick = 0
var entities: Array[EntitySnapshot] = []

class EntitySnapshot:
	var entity_id = 0
	var server_tick = 0
	var last_processed_movement_seq = 0xFFFFFFFF
	var position = Vector3.ZERO
	var velocity = Vector3.ZERO
	var rotation = Quaternion.IDENTITY
	var is_on_floor = false

static func encode(entities_: Array, server_tick_: int = 0) -> PackedByteArray:
	var count = mini(entities_.size(), 0xFFFF)
	var bytes = PackedByteArray()
	bytes.resize(HEADER_SIZE + count * ENTITY_SIZE)

	var offset = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, count)
	offset = ProtocolUtils.write_u32(bytes, offset, server_tick_)

	for i in count:
		var entity: Variant = entities_[i]
		var position = ProtocolUtils.quantize_vector3_i32(
			ProtocolUtils.get_vector3(entity, "position", Vector3.ZERO),
			POSITION_SCALE
		)
		var velocity = ProtocolUtils.quantize_vector3_i16(
			ProtocolUtils.get_vector3(entity, "velocity", Vector3.ZERO),
			VELOCITY_SCALE
		)
		var rotation = ProtocolUtils.get_quaternion(
			ProtocolUtils.get_value(entity, "rotation", Quaternion.IDENTITY)
		)
		var last_processed_seq = ProtocolUtils.get_int(
			entity,
			"last_processed_movement_seq",
			NO_PROCESSED_SEQ
		)

		offset = ProtocolUtils.write_u32(bytes, offset, ProtocolUtils.get_int(entity, "entity_id", 0))
		offset = ProtocolUtils.write_u32(bytes, offset, last_processed_seq)
		offset = ProtocolUtils.write_i32(bytes, offset, position.x)
		offset = ProtocolUtils.write_i32(bytes, offset, position.y)
		offset = ProtocolUtils.write_i32(bytes, offset, position.z)
		offset = ProtocolUtils.write_i16(bytes, offset, velocity.x)
		offset = ProtocolUtils.write_i16(bytes, offset, velocity.y)
		offset = ProtocolUtils.write_i16(bytes, offset, velocity.z)
		offset = _write_quaternion(bytes, offset, rotation)
		offset = ProtocolUtils.write_u8(
			bytes,
			offset,
			FLAG_ON_FLOOR if ProtocolUtils.get_bool(entity, "is_on_floor", false) else 0
		)

	return bytes

static func decode(bytes: PackedByteArray) -> MovementSnapshotMsg:
	var msg = MovementSnapshotMsg.new()
	if bytes.size() < HEADER_SIZE:
		return msg

	var offset = 0
	var magic = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return msg

	offset += 1 # reserved flags
	var count = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	msg.server_tick = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	if bytes.size() < HEADER_SIZE + count * ENTITY_SIZE:
		return MovementSnapshotMsg.new()

	msg.entities.resize(count)
	for i in count:
		var entity = EntitySnapshot.new()
		entity.entity_id = ProtocolUtils.read_u32(bytes, offset)
		offset += 4
		entity.last_processed_movement_seq = ProtocolUtils.read_u32(bytes, offset)
		offset += 4

		var position = Vector3i(
			ProtocolUtils.read_i32(bytes, offset),
			ProtocolUtils.read_i32(bytes, offset + 4),
			ProtocolUtils.read_i32(bytes, offset + 8)
		)
		offset += 12

		var velocity = Vector3i(
			ProtocolUtils.read_i16(bytes, offset),
			ProtocolUtils.read_i16(bytes, offset + 2),
			ProtocolUtils.read_i16(bytes, offset + 4)
		)
		offset += 6

		entity.rotation = _read_quaternion(bytes, offset)
		offset += 7

		var flags = ProtocolUtils.read_u8(bytes, offset)
		offset += 1

		entity.server_tick = msg.server_tick
		entity.position = ProtocolUtils.dequantize_vector3(position, POSITION_SCALE)
		entity.velocity = ProtocolUtils.dequantize_vector3(velocity, VELOCITY_SCALE)
		entity.is_on_floor = bool(flags & FLAG_ON_FLOOR)
		msg.entities[i] = entity

	return msg

static func encode_packet(entities: Array, server_tick: int = 0) -> PackedByteArray:
	return encode(entities, server_tick)

static func decode_packet(bytes: PackedByteArray) -> MovementSnapshotMsg:
	return decode(bytes)

static func _write_quaternion(bytes: PackedByteArray, offset: int, value: Quaternion) -> int:
	var q = value.normalized()
	var components = [q.x, q.y, q.z, q.w]
	var largest_index = 0
	var largest_abs = absf(components[0])

	for i in range(1, 4):
		var component_abs = absf(components[i])
		if component_abs > largest_abs:
			largest_abs = component_abs
			largest_index = i

	if components[largest_index] < 0.0:
		for i in 4:
			components[i] = -components[i]

	offset = ProtocolUtils.write_u8(bytes, offset, largest_index)
	for i in 4:
		if i == largest_index:
			continue
		offset = ProtocolUtils.write_i16(
			bytes,
			offset,
			ProtocolUtils.clamp_i16(roundi(components[i] * QUAT_SCALE))
		)

	return offset

static func _read_quaternion(bytes: PackedByteArray, offset: int) -> Quaternion:
	var largest_index = ProtocolUtils.read_u8(bytes, offset)
	offset += 1

	var components = [0.0, 0.0, 0.0, 0.0]
	var sum_squares = 0.0
	for i in 4:
		if i == largest_index:
			continue

		var component = ProtocolUtils.dequantize_float(ProtocolUtils.read_i16(bytes, offset), QUAT_SCALE)
		offset += 2
		components[i] = component
		sum_squares += component * component

	components[largest_index] = sqrt(maxf(0.0, 1.0 - sum_squares))
	return Quaternion(components[0], components[1], components[2], components[3]).normalized()
