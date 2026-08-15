class_name PlayerMovementSystem
extends BaseSystem

@export var entity_tracker: EntityTracker
@export var systems: TickSystems

func _on_tick(_tick: int, delta: float):
	var players: Dictionary = entity_tracker.get_players()
	for player: ServerPlayerEntity in players.values():
		var input: MovementInputFrame = player.current_tick_context.get("input") as MovementInputFrame
		if input == null:
			continue

		player.get_body().simulate(input, delta)
		systems.tick_context.entities_with_processed_input.append(player)
