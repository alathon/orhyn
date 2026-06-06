class_name PlayerInputBuffers
extends Node

const INVALID_INPUT_SEQ := 0xFFFFFFFF

@onready var network: Network = %Network
@onready var entity_tracker: EntityTracker = %EntityTracker

func _ready() -> void:
	network.player_input_received.connect(_on_player_input_received)

func _on_player_input_received(peer_id: int, input: MovementInputFrame) -> void:
	var player: ServerPlayerEntity = entity_tracker.get_player(peer_id)
	var peer_buffer: PlayerInputBuffer.PeerBuffer = player.input_buffer.peer_buffer
	
	var seq = input.seq
	if seq == INVALID_INPUT_SEQ:
		return

	if seq <= peer_buffer.last_seen_seq:
		return

	peer_buffer.last_seen_seq = seq
	peer_buffer.inputs_by_seq[seq] = input
