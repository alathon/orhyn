class_name PlayerInputsSystem
extends BaseSystem

@onready var entity_tracker: EntityTracker = %EntityTracker
@onready var player_input_buffers: PlayerInputBuffers = %PlayerInputBuffers

func _on_tick(_n: int, _delta: float):
	var players: Dictionary = entity_tracker.get_players()
	for peer_id in players:
		var player: ServerPlayerEntity = players[peer_id]
		player.current_tick_context["input"] = player_input_buffers.get_next_input(peer_id)
