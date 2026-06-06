class_name PredictionRingBuffer
extends RefCounted

class Frame:
	var valid: bool = false
	var seq: int = -1
	var input_x: float = 0.0
	var input_z: float = 0.0
	var jump_pressed: bool = false
	var jump_down: bool = false
	var predicted_position: Vector3 = Vector3.ZERO
	var predicted_velocity: Vector3 = Vector3.ZERO
	var predicted_rotation: Quaternion = Quaternion.IDENTITY
	var predicted_is_on_floor: bool = false

	func write_from_input(input: MovementInputFrame) -> void:
		valid = true
		seq = input.seq
		input_x = input.input_x
		input_z = input.input_z
		jump_pressed = input.jump_pressed
		jump_down = input.jump_down

	func write_predicted_state(body: PhysicsBody) -> void:
		predicted_position = body.global_position
		predicted_velocity = body.velocity
		predicted_rotation = body.global_transform.basis.get_rotation_quaternion()
		predicted_is_on_floor = body.is_on_floor()

	func write_input_frame(input: MovementInputFrame) -> void:
		input.seq = seq
		input.input_x = input_x
		input.input_z = input_z
		input.jump_pressed = jump_pressed
		input.jump_down = jump_down

	func clear() -> void:
		valid = false
		seq = -1
		input_x = 0.0
		input_z = 0.0
		jump_pressed = false
		jump_down = false
		predicted_position = Vector3.ZERO
		predicted_velocity = Vector3.ZERO
		predicted_rotation = Quaternion.IDENTITY
		predicted_is_on_floor = false

var _frames: Array[Frame] = []
var _size: int = 0

func _init(size := 30) -> void:
	_size = maxi(size, 1)
	_frames.resize(_size)

	for i in _size:
		_frames[i] = Frame.new()

func store(input: MovementInputFrame) -> Frame:
	var seq: int = input.seq
	var frame: Frame = _frames[_index_for_seq(seq)]
	frame.write_from_input(input)
	return frame

func get_frame(seq: int) -> Frame:
	var frame: Frame = _frames[_index_for_seq(seq)]
	if frame.valid and frame.seq == seq:
		return frame
	return null

func get_previous_frame(seq: int) -> Frame:
	return get_frame(seq - 1)

func get_predicted_position(seq: int):
	var frame = get_frame(seq)
	if frame == null:
		return null
	return frame.predicted_position

func get_unacknowledged_frames(ack_seq: int) -> Array[Frame]:
	var frames: Array[Frame] = []
	write_unacknowledged_frames(ack_seq, frames)
	return frames

func write_unacknowledged_frames(ack_seq: int, frames: Array[Frame]) -> void:
	frames.clear()
	for frame in _frames:
		if frame.valid and frame.seq > ack_seq:
			frames.append(frame)

	frames.sort_custom(_sort_frames_by_seq)

func prune_acknowledged(ack_seq: int) -> int:
	var pruned_count: int = 0
	for frame in _frames:
		if frame.valid and frame.seq <= ack_seq:
			frame.clear()
			pruned_count += 1
	return pruned_count

func _index_for_seq(seq: int) -> int:
	return posmod(seq, _size)

static func _sort_frames_by_seq(a: Frame, b: Frame) -> bool:
	return a.seq < b.seq
