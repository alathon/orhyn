extends Node

@onready var ticker: Ticker = %Ticker
@onready var entity_tracker: EntityTracker = %EntityTracker
@onready var server_network: Network = %Network
@onready var player_inputs_system: PlayerInputsSystem = %PlayerInputsSystem
@onready var player_movement_system: PlayerMovementSystem = %PlayerMovementSystem
@onready var movement_snapshot_system: MovementSnapshotSystem = %MovementSnapshotSystem

@export var debug_force_reconciliation_drift: bool = false
@export var debug_drift_interval_ticks: int = 60
@export var debug_drift_offset: Vector3 = Vector3(1.0, 0.0, 0.0)

var _tick_context: Dictionary[int, Dictionary] = {}

func _ready() -> void:
	ticker.tick.connect(_on_tick)

func _on_tick(n: int, delta: float) -> void:
	player_inputs_system._on_tick(n, delta)
	player_movement_system._on_tick(n, delta)
	_apply_debug_reconciliation_drift(n)
	movement_snapshot_system._on_tick(n, delta)

func _apply_debug_reconciliation_drift(tick: int) -> void:
	if not debug_force_reconciliation_drift:
		return
	if debug_drift_interval_ticks <= 0 or tick % debug_drift_interval_ticks != 0:
		return

	var players: Dictionary = entity_tracker.get_players()
	for peer_id in _tick_context:
		var input: MovementInputFrame = _tick_context[peer_id]["input"]
		if not _has_movement_input(input):
			continue

		var player: ServerPlayerEntity = players[peer_id]
		var body: PhysicsBody = player.get_body()
		body.global_position += debug_drift_offset
		print(
			"debug_reconciliation_drift tick=%d peer=%d entity=%d offset=%s position=%s" %
			[tick, peer_id, player.entity_id, debug_drift_offset, body.global_position]
		)

func _has_movement_input(input: MovementInputFrame) -> bool:
	return absf(input.input_x) > 0.001 or absf(input.input_z) > 0.001 or input.jump_pressed
