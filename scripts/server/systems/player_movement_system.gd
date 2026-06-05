class_name PlayerMovementSystem
extends BaseSystem

@onready var entity_tracker: EntityTracker = %EntityTracker

func _on_tick(_n: int, delta: float):
	var players: Dictionary = entity_tracker.get_players()
	for player: ServerPlayerEntity in players.values():
		player.get_body().simulate(player.current_tick_context["input"], delta)
