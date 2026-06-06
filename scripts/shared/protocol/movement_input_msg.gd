class_name MovementInputMsg
extends RefCounted

const MAGIC: int = MessageHeaders.MovementInputMsgHeader
const HEADER_SIZE := 6
const FRAME_SIZE := 5
const MAX_PREVIOUS_INPUTS := 3

const FRAME_FLAG_JUMP_PRESSED := 1
const FRAME_FLAG_JUMP_DOWN := 2
const AXIS_SCALE := 32767.0

static func encode(current_input: Variant, previous_inputs: Variant = []) -> PackedByteArray:
	var current_seq: int = ProtocolUtils.get_int(current_input, "seq", 0)
	var previous_frames: Array = _select_previous_inputs(
		_normalize_previous_inputs(previous_inputs),
		current_seq
	)
	var previous_count: int = previous_frames.size()

	var frame_count = 1 + previous_count
	var bytes = PackedByteArray()
	bytes.resize(HEADER_SIZE + frame_count * FRAME_SIZE)

	var offset = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, previous_count)
	offset = ProtocolUtils.write_u32(bytes, offset, current_seq)

	for i in previous_count:
		offset = _write_frame_payload(bytes, offset, previous_frames[i])
	offset = _write_frame_payload(bytes, offset, current_input)

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

	var current_seq: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	var expected_size = HEADER_SIZE + (previous_count + 1) * FRAME_SIZE
	if bytes.size() < expected_size:
		return MovementInputMsg.new()

	for i in previous_count:
		var seq: int = current_seq - previous_count + i
		msg.inputs.append(_read_frame_payload(bytes, offset, seq))
		offset += FRAME_SIZE

	msg.inputs.append(_read_frame_payload(bytes, offset, current_seq))

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

static func _select_previous_inputs(previous_inputs: Array, current_seq: int) -> Array:
	var selected: Array = []
	var expected_seq: int = current_seq - 1
	for i in range(previous_inputs.size() - 1, -1, -1):
		if selected.size() >= MAX_PREVIOUS_INPUTS:
			break

		var input: Variant = previous_inputs[i]
		if ProtocolUtils.get_int(input, "seq", -1) != expected_seq:
			break

		selected.push_front(input)
		expected_seq -= 1

	return selected

static func _write_frame_payload(bytes: PackedByteArray, offset: int, input: Variant) -> int:
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

static func _read_frame_payload(bytes: PackedByteArray, offset: int, seq: int) -> MovementInputFrame:
	var frame = MovementInputFrame.new()
	frame.seq = seq
	frame.input_x = ProtocolUtils.dequantize_float(ProtocolUtils.read_i16(bytes, offset), AXIS_SCALE)
	offset += 2
	frame.input_z = ProtocolUtils.dequantize_float(ProtocolUtils.read_i16(bytes, offset), AXIS_SCALE)
	offset += 2
	var flags = ProtocolUtils.read_u8(bytes, offset)
	frame.jump_pressed = bool(flags & FRAME_FLAG_JUMP_PRESSED)
	frame.jump_down = bool(flags & FRAME_FLAG_JUMP_DOWN)
	return frame
