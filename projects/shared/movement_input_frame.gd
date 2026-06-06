class_name MovementInputFrame
extends RefCounted

var seq: int = 0
var input_x: float = 0.0
var input_z: float = 0.0
var jump_pressed: bool = false
var jump_down: bool = false

func copy_from(other: MovementInputFrame) -> void:
	seq = other.seq
	input_x = other.input_x
	input_z = other.input_z
	jump_pressed = other.jump_pressed
	jump_down = other.jump_down

static func empty(seq_value: int) -> MovementInputFrame:
	var frame = MovementInputFrame.new()
	frame.seq = seq_value
	return frame
