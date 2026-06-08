class_name PlayerInputBuffers
extends Node

@export var network: GameServerNetwork
@export var entity_tracker: EntityTracker

func _ready() -> void:
	network.player_input_received.connect(_on_player_input_received)

func _on_player_input_received(peer_id: int, input: MovementInputFrame) -> void:
	var player: ServerPlayerEntity = entity_tracker.get_player(peer_id)
	if player == null:
		return

	player.input_buffer.push_input(input)
