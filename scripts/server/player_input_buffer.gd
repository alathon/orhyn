class_name PlayerInputBuffer
extends Node

const INVALID_INPUT_SEQ := 0xFFFFFFFF

class PeerBuffer:
	var peer_id = -1
	var last_seen_seq = -1
	var last_processed_seq = -1
	var last_held_input: MovementInputFrame
	var synthetic_input: MovementInputFrame
	var inputs_by_seq: Dictionary = {}

	func _init(p_peer_id: int) -> void:
		peer_id = p_peer_id
		last_held_input = MovementInputFrame.empty(-1)
		synthetic_input = MovementInputFrame.empty(-1)

var peer_buffer: PeerBuffer
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

	var synthetic: MovementInputFrame = _make_synthetic_input()
	peer_buffer.last_held_input = synthetic
	return synthetic

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

func _make_synthetic_input() -> MovementInputFrame:
	var input = peer_buffer.synthetic_input
	input.copy_from(peer_buffer.last_held_input)
	input.seq = peer_buffer.last_processed_seq
	input.jump_pressed = false
	return input
