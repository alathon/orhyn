class_name PlayerInput
extends Node

@export var body: PhysicsBody
@export var model: Node3D
@export var camera_pivot: Node3D

var _jump_was_down = false
var _movement_seq = 0
var _prediction_buffer = PredictionRingBuffer.new(30)
var _prediction_frame: Variant = null
var current_input: MovementInputFrame = MovementInputFrame.new()

func record() -> void:
	_write_current_input()
	current_input.seq = _movement_seq
	_movement_seq += 1
	_prediction_frame = _prediction_buffer.store(current_input)

func record_predicted_state() -> void:
	if _prediction_frame == null:
		return

	_prediction_frame.write_predicted_state(body)
	_prediction_frame = null

func clear_current_input() -> void:
	current_input.input_x = 0.0
	current_input.input_z = 0.0
	current_input.jump_pressed = false
	current_input.jump_down = false
	_jump_was_down = false

func get_previous_inputs_for_resend(max_count: int = 3) -> Array[PredictionRingBuffer.Frame]:
	var frames: Array[PredictionRingBuffer.Frame] = []
	var count: int = maxi(max_count, 0)
	for offset in range(count, 0, -1):
		var frame: PredictionRingBuffer.Frame = _prediction_buffer.get_frame(current_input.seq - offset)
		if frame == null or not frame.valid or frame.seq < 0:
			continue
		frames.append(frame)
	return frames

func get_predicted_position(seq: int) -> Variant:
	return _prediction_buffer.get_predicted_position(seq)

func get_prediction_frame(seq: int) -> PredictionRingBuffer.Frame:
	return _prediction_buffer.get_frame(seq)

func get_unacknowledged_prediction_frames(ack_seq: int) -> Array[PredictionRingBuffer.Frame]:
	return _prediction_buffer.get_unacknowledged_frames(ack_seq)

func write_unacknowledged_prediction_frames(
	ack_seq: int,
	frames: Array[PredictionRingBuffer.Frame]
) -> void:
	_prediction_buffer.write_unacknowledged_frames(ack_seq, frames)

func prune_acknowledged_prediction_frames(ack_seq: int) -> int:
	return _prediction_buffer.prune_acknowledged(ack_seq)

func _write_current_input() -> void:
	var left = _is_pressed(&"move_left", KEY_A)
	var right = _is_pressed(&"move_right", KEY_D)
	var forward = _is_pressed(&"move_forward", KEY_W)
	var back = _is_pressed(&"move_back", KEY_S)
	var jump_down = _is_pressed(&"jump", KEY_SPACE)

	var local_input = Vector2(
		float(right) - float(left),
		float(back) - float(forward)
	)

	if local_input.length_squared() > 1.0:
		local_input = local_input.normalized()

	var movement = _to_world_movement(local_input)
	current_input.input_x = movement.x
	current_input.input_z = movement.z
	current_input.jump_pressed = jump_down and not _jump_was_down
	current_input.jump_down = jump_down

	_jump_was_down = jump_down

func _to_world_movement(local_input: Vector2) -> Vector3:
	if local_input == Vector2.ZERO:
		return Vector3.ZERO

	var right = camera_pivot.global_transform.basis.x
	var forward = -camera_pivot.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()

	return (right * local_input.x + forward * -local_input.y).normalized()

func _is_pressed(action: StringName, key: Key) -> bool:
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	return Input.is_physical_key_pressed(key)
