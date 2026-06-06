class_name PlayerInputsSystem
extends BaseSystem

@onready var entity_tracker: EntityTracker = %EntityTracker

func _on_tick(_tick: int, _delta: float):
	var players: Dictionary = entity_tracker.get_players()
	for peer_id in players:
		var player: ServerPlayerEntity = players[peer_id]
		player.current_tick_context["input"] = player.input_buffer.get_next_input()
