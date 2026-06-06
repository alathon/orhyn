class_name PlayerInputBuffer
extends Node

const INVALID_INPUT_SEQ := 0xFFFFFFFF
const DEFAULT_MAX_INPUT_SEQUENCE_GAP: int = MovementInputMsg.MAX_PREVIOUS_INPUTS + 1

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
## Maximum distance between last_processed_seq and the oldest buffered input before fast-forwarding.
@export_range(0, 256, 1, "or_greater") var max_input_sequence_gap: int = DEFAULT_MAX_INPUT_SEQUENCE_GAP

var peer_buffer: PeerBuffer = PeerBuffer.new()
var _missing_peer_input: MovementInputFrame = MovementInputFrame.empty(-1)

func push_input(input: MovementInputFrame) -> bool:
	if input == null or peer_buffer == null:
		return false

	var seq: int = input.seq
	if seq == INVALID_INPUT_SEQ:
		return false

	if seq <= peer_buffer.last_processed_seq:
		return false

	if peer_buffer.inputs_by_seq.has(seq):
		return false

	peer_buffer.last_seen_seq = maxi(peer_buffer.last_seen_seq, seq)
	peer_buffer.inputs_by_seq[seq] = input
	_fast_forward_if_sequence_gap_too_large()
	return true

func get_next_input() -> MovementInputFrame:
	if peer_buffer == null:
		return _missing_peer_input

	_fast_forward_if_sequence_gap_too_large()

	var next_seq: int = peer_buffer.last_processed_seq + 1
	if peer_buffer.inputs_by_seq.has(next_seq):
		var input: MovementInputFrame = peer_buffer.inputs_by_seq[next_seq]
		peer_buffer.inputs_by_seq.erase(next_seq)
		peer_buffer.last_processed_seq = next_seq
		peer_buffer.last_held_input = input
		return input

	if peer_buffer.inputs_by_seq.is_empty() and missing_input_policy == MissingInputPolicy.SKIP_SIMULATION:
		return null

	match missing_input_policy:
		MissingInputPolicy.REPLAY_LAST_HELD:
			var synthetic: MovementInputFrame = _make_last_held_input(next_seq)
			peer_buffer.last_held_input = synthetic
			return synthetic
		MissingInputPolicy.SKIP_SIMULATION:
			peer_buffer.last_processed_seq = next_seq
			return null
		MissingInputPolicy.EMPTY_INPUT:
			return _make_empty_input(next_seq)

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

func _fast_forward_if_sequence_gap_too_large() -> void:
	if peer_buffer == null or peer_buffer.inputs_by_seq.is_empty():
		return

	var lowest_seq: int = _get_lowest_buffered_seq(peer_buffer.inputs_by_seq)
	var sequence_gap: int = lowest_seq - peer_buffer.last_processed_seq
	if sequence_gap <= maxi(max_input_sequence_gap, 0):
		return

	peer_buffer.last_processed_seq = lowest_seq - 1

func _make_last_held_input(seq: int) -> MovementInputFrame:
	var input: MovementInputFrame = peer_buffer.synthetic_input
	input.copy_from(peer_buffer.last_held_input)
	input.seq = seq
	input.jump_pressed = false
	peer_buffer.last_processed_seq = seq
	return input

func _make_empty_input(seq: int) -> MovementInputFrame:
	var input: MovementInputFrame = peer_buffer.empty_input
	input.seq = seq
	input.input_x = 0.0
	input.input_z = 0.0
	input.jump_pressed = false
	input.jump_down = false
	peer_buffer.last_processed_seq = seq
	return input
