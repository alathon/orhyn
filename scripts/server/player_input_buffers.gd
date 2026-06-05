class_name PlayerInputBuffers
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

@onready var server_network: Network = %Network

var _buffers_by_peer_id: Dictionary = {}
var _missing_peer_input: MovementInputFrame = MovementInputFrame.empty(-1)

func _ready() -> void:
	server_network.player_input_received.connect(_on_player_input_received)
	server_network.player_connected.connect(_on_player_connected)
	server_network.player_disconnected.connect(_on_player_disconnected)

func get_next_input(peer_id: int) -> MovementInputFrame:
	var peer_buffer = _get_peer_buffer(peer_id)
	if peer_buffer == null:
		return _missing_peer_input

	if not peer_buffer.inputs_by_seq.is_empty():
		var seq: int = _get_lowest_buffered_seq(peer_buffer.inputs_by_seq)
		var input: MovementInputFrame = peer_buffer.inputs_by_seq[seq]
		peer_buffer.inputs_by_seq.erase(seq)
		peer_buffer.last_processed_seq = seq
		peer_buffer.last_held_input = input
		return input

	var synthetic: MovementInputFrame = _make_synthetic_input(peer_buffer)
	peer_buffer.last_held_input = synthetic
	return synthetic

func get_last_processed_seq(peer_id: int) -> int:
	var peer_buffer = _get_peer_buffer(peer_id)
	if peer_buffer == null:
		return -1
	return peer_buffer.last_processed_seq

func _on_player_input_received(peer_id: int, input: MovementInputFrame) -> void:
	var peer_buffer = _get_peer_buffer(peer_id)
	if peer_buffer == null:
		return

	var seq = input.seq
	if seq == INVALID_INPUT_SEQ:
		return

	if seq <= peer_buffer.last_seen_seq:
		return

	peer_buffer.last_seen_seq = seq
	peer_buffer.inputs_by_seq[seq] = input

func _on_player_connected(peer_id: int) -> void:
	_buffers_by_peer_id[peer_id] = PeerBuffer.new(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	_buffers_by_peer_id.erase(peer_id)

func _get_peer_buffer(peer_id: int) -> PeerBuffer:
	return _buffers_by_peer_id.get(peer_id) as PeerBuffer

func _get_lowest_buffered_seq(buffer: Dictionary) -> int:
	var lowest_seq = 0
	var has_lowest = false
	for seq in buffer.keys():
		var input_seq = int(seq)
		if not has_lowest or input_seq < lowest_seq:
			lowest_seq = input_seq
			has_lowest = true
	return lowest_seq

func _make_synthetic_input(peer_buffer: PeerBuffer) -> MovementInputFrame:
	var input = peer_buffer.synthetic_input
	input.copy_from(peer_buffer.last_held_input)
	input.seq = peer_buffer.last_processed_seq
	input.jump_pressed = false
	return input
