class_name Systems
extends Node

@onready var ticker: Ticker = %Ticker
@onready var entity_tracker: EntityTracker = %EntityTracker
@onready var server_network: Network = %Network
@onready var player_inputs_system: PlayerInputsSystem = %PlayerInputsSystem
@onready var player_movement_system: PlayerMovementSystem = %PlayerMovementSystem
@onready var movement_snapshot_system: MovementSnapshotSystem = %MovementSnapshotSystem

const MAX_ENTITIES: int = 500

var tick_context: TickContext

enum TickPhase {
	Before, During, After
}

class TickContext:
	var tick: int
	var delta: float
	var phase: TickPhase
	var entities_moved: Array[BaseEntity]

	func clear():
		entities_moved.clear()

func _ready() -> void:
	ticker.before_tick.connect(_on_before_tick)
	ticker.tick.connect(_on_tick)
	ticker.after_tick.connect(_on_after_tick)
	tick_context = TickContext.new()

func _on_before_tick(tick: int, delta: float):
	tick_context.clear()
	tick_context.phase = TickPhase.Before
	tick_context.tick = tick
	tick_context.delta = delta

func _on_after_tick(_tick: int, _delta: float):
	tick_context.phase = TickPhase.After

func _on_tick(tick: int, delta: float) -> void:
	tick_context.phase = TickPhase.During
	player_inputs_system._on_tick(tick, delta)
	player_movement_system._on_tick(tick, delta)
	movement_snapshot_system._on_tick(tick, delta)
