extends GutTest

func test_encodes_current_plus_three_previous_inputs_in_sequence_order() -> void:
	var previous_inputs: Array[MovementInputFrame] = [
		_make_input(7, -1.0, 0.0),
		_make_input(8, 0.0, 1.0),
		_make_input(9, 1.0, 0.0),
	]
	var current_input: MovementInputFrame = _make_input(10, 0.25, -0.5)

	var bytes: PackedByteArray = MovementInputMsg.encode(current_input, previous_inputs)
	var msg: MovementInputMsg = MovementInputMsg.decode(bytes)

	assert_eq(bytes.size(), MovementInputMsg.HEADER_SIZE + 4 * MovementInputMsg.FRAME_SIZE)
	assert_eq(msg.inputs.size(), 4, "Packet should include three previous inputs plus current")
	assert_eq(msg.inputs[0].seq, 7)
	assert_eq(msg.inputs[1].seq, 8)
	assert_eq(msg.inputs[2].seq, 9)
	assert_eq(msg.inputs[3].seq, 10)
	assert_almost_eq(msg.inputs[3].input_x, 0.25, 0.001)
	assert_almost_eq(msg.inputs[3].input_z, -0.5, 0.001)

func test_limits_previous_inputs_to_three() -> void:
	var previous_inputs: Array[MovementInputFrame] = [
		_make_input(1, 0.0, 0.0),
		_make_input(2, 0.0, 0.0),
		_make_input(3, 0.0, 0.0),
		_make_input(4, 0.0, 0.0),
	]
	var current_input: MovementInputFrame = _make_input(5, 0.0, 0.0)

	var msg: MovementInputMsg = MovementInputMsg.decode(
		MovementInputMsg.encode(current_input, previous_inputs)
	)

	assert_eq(msg.inputs.size(), 4)
	assert_eq(msg.inputs[0].seq, 2)
	assert_eq(msg.inputs[3].seq, 5)

func test_ignores_noncontiguous_previous_inputs() -> void:
	var previous_inputs: Array[MovementInputFrame] = [
		_make_input(5, 0.0, 0.0),
		_make_input(7, 0.0, 0.0),
	]
	var current_input: MovementInputFrame = _make_input(8, 0.0, 0.0)

	var msg: MovementInputMsg = MovementInputMsg.decode(
		MovementInputMsg.encode(current_input, previous_inputs)
	)

	assert_eq(msg.inputs.size(), 2)
	assert_eq(msg.inputs[0].seq, 7)
	assert_eq(msg.inputs[1].seq, 8)

func test_accepts_single_previous_input_for_callsite_compatibility() -> void:
	var previous_input: MovementInputFrame = _make_input(3, -0.25, 0.75)
	var current_input: MovementInputFrame = _make_input(4, 0.5, -0.5)

	var msg: MovementInputMsg = MovementInputMsg.decode(
		MovementInputMsg.encode(current_input, previous_input)
	)

	assert_eq(msg.inputs.size(), 2)
	assert_eq(msg.inputs[0].seq, 3)
	assert_eq(msg.inputs[1].seq, 4)

func _make_input(seq: int, input_x: float, input_z: float) -> MovementInputFrame:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.seq = seq
	input.input_x = input_x
	input.input_z = input_z
	return input
