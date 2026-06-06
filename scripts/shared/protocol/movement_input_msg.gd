class_name MovementInputMsg
extends RefCounted

const MAGIC: int = MessageHeaders.MovementInputMsgHeader
const HEADER_SIZE := 2
const FRAME_SIZE := 9
const MAX_PREVIOUS_INPUTS := 3

const FRAME_FLAG_JUMP_PRESSED := 1
const FRAME_FLAG_JUMP_DOWN := 2
const AXIS_SCALE := 32767.0

static func encode(current_input: Variant, previous_inputs: Variant = []) -> PackedByteArray:
	var previous_frames: Array = _normalize_previous_inputs(previous_inputs)
	var previous_count: int = mini(previous_frames.size(), MAX_PREVIOUS_INPUTS)

	var frame_count = 1 + previous_count
	var bytes = PackedByteArray()
	bytes.resize(HEADER_SIZE + frame_count * FRAME_SIZE)

	var offset = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, previous_count)

	for i in previous_count:
		offset = _write_frame(bytes, offset, previous_frames[i])
	offset = _write_frame(bytes, offset, current_input)

	return bytes

static func decode(bytes: PackedByteArray) -> MovementInputMsg:
	var msg = MovementInputMsg.new()
	if bytes.size() < HEADER_SIZE:
		return msg

	var offset = 0
	var magic = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return msg

	var previous_count = ProtocolUtils.read_u8(bytes, offset)
	offset += 1

	if previous_count > MAX_PREVIOUS_INPUTS:
		return MovementInputMsg.new()

	var expected_size = HEADER_SIZE + (previous_count + 1) * FRAME_SIZE
	if bytes.size() < expected_size:
		return MovementInputMsg.new()

	for i in previous_count:
		msg.inputs.append(_read_frame(bytes, offset))
		offset += FRAME_SIZE

	msg.inputs.append(_read_frame(bytes, offset))

	return msg

static func encode_packet(current_input: Variant, previous_inputs: Variant = []) -> PackedByteArray:
	return encode(current_input, previous_inputs)

static func decode_packet(bytes: PackedByteArray) -> MovementInputMsg:
	return decode(bytes)

var inputs: Array[MovementInputFrame] = []

static func _normalize_previous_inputs(previous_inputs: Variant) -> Array:
	if previous_inputs == null:
		return []
	if previous_inputs is Array:
		return previous_inputs
	return [previous_inputs]

static func _write_frame(bytes: PackedByteArray, offset: int, input: Variant) -> int:
	offset = ProtocolUtils.write_u32(bytes, offset, ProtocolUtils.get_int(input, "seq", 0))
	offset = ProtocolUtils.write_i16(
		bytes,
		offset,
		ProtocolUtils.quantize_unit_float(ProtocolUtils.get_float(input, "input_x", 0.0), AXIS_SCALE)
	)
	offset = ProtocolUtils.write_i16(
		bytes,
		offset,
		ProtocolUtils.quantize_unit_float(ProtocolUtils.get_float(input, "input_z", 0.0), AXIS_SCALE)
	)

	var flags = 0
	if ProtocolUtils.get_bool(input, "jump_pressed", false):
		flags |= FRAME_FLAG_JUMP_PRESSED
	if ProtocolUtils.get_bool(input, "jump_down", false):
		flags |= FRAME_FLAG_JUMP_DOWN
	return ProtocolUtils.write_u8(bytes, offset, flags)

static func _read_frame(bytes: PackedByteArray, offset: int) -> MovementInputFrame:
	var frame = MovementInputFrame.new()
	frame.seq = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	frame.input_x = ProtocolUtils.dequantize_float(ProtocolUtils.read_i16(bytes, offset), AXIS_SCALE)
	offset += 2
	frame.input_z = ProtocolUtils.dequantize_float(ProtocolUtils.read_i16(bytes, offset), AXIS_SCALE)
	offset += 2
	var flags = ProtocolUtils.read_u8(bytes, offset)
	frame.jump_pressed = bool(flags & FRAME_FLAG_JUMP_PRESSED)
	frame.jump_down = bool(flags & FRAME_FLAG_JUMP_DOWN)
	return frame
