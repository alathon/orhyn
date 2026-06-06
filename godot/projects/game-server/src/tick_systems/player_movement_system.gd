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

		var before: Vector3 = player.get_body().global_position
		player.get_body().simulate(input, delta)
		if not before.is_equal_approx(player.get_body().global_position):
			systems.tick_context.entities_moved.append(player)
