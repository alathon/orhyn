class_name PlayerInputBuffer
extends Node

const INVALID_INPUT_SEQ := 0xFFFFFFFF

enum MissingInputPolicy {
	REPLAY_LAST_HELD,
	SKIP_SIMULATION,
	EMPTY_INPUT,
}

class PeerBuffer:
	var last_seen_seq = -1
	var last_processed_seq = -1
	var last_held_input: MovementInputFrame
	var synthetic_input: MovementInputFrame
	var empty_input: MovementInputFrame
	var inputs_by_seq: Dictionary = {}

	func _init() -> void:
		last_held_input = MovementInputFrame.empty(-1)
		synthetic_input = MovementInputFrame.empty(-1)
		empty_input = MovementInputFrame.empty(-1)

@export_enum("Replay Last Held", "Skip Simulation", "Empty Input") var missing_input_policy: int = MissingInputPolicy.SKIP_SIMULATION

var peer_buffer: PeerBuffer = PeerBuffer.new()
var _missing_peer_input: MovementInputFrame = MovementInputFrame.empty(-1)

func get_next_input() -> MovementInputFrame:
	if peer_buffer == null:
		return _missing_peer_input

	if not peer_buffer.inputs_by_seq.is_empty():
		var seq: int = _get_lowest_buffered_seq(peer_buffer.inputs_by_seq)
		var input: MovementInputFrame = peer_buffer.inputs_by_seq[seq]
		peer_buffer.inputs_by_seq.erase(seq)
		peer_buffer.last_processed_seq = seq
		peer_buffer.last_held_input = input
		return input

	match missing_input_policy:
		MissingInputPolicy.REPLAY_LAST_HELD:
			var synthetic: MovementInputFrame = _make_last_held_input()
			peer_buffer.last_held_input = synthetic
			return synthetic
		MissingInputPolicy.SKIP_SIMULATION:
			return null
		MissingInputPolicy.EMPTY_INPUT:
			return _make_empty_input()

	return null

func get_last_processed_seq() -> int:
	if peer_buffer == null:
		return -1
	return peer_buffer.last_processed_seq

func _get_lowest_buffered_seq(buffer: Dictionary) -> int:
	var lowest_seq = 0
	var has_lowest = false
	for seq in buffer.keys():
		var input_seq = int(seq)
		if not has_lowest or input_seq < lowest_seq:
			lowest_seq = input_seq
			has_lowest = true
	return lowest_seq

func _make_last_held_input() -> MovementInputFrame:
	var input = peer_buffer.synthetic_input
	input.copy_from(peer_buffer.last_held_input)
	input.seq = peer_buffer.last_processed_seq
	input.jump_pressed = false
	return input

func _make_empty_input() -> MovementInputFrame:
	var input = peer_buffer.empty_input
	input.seq = peer_buffer.last_processed_seq
	input.input_x = 0.0
	input.input_z = 0.0
	input.jump_pressed = false
	input.jump_down = false
	return input
