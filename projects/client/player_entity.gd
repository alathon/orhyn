class_name Player
extends BaseEntity

@onready var body: PhysicsBody = $PhysicsBody
@onready var input: PlayerInput = $PlayerInput
@onready var movement_reconciliation: PlayerMovementReconciliation = $PlayerMovementReconciliation
@onready var model: Node3D = %Model
@onready var camera_pivot: Node3D = $CameraPivot

func get_rid() -> RID:
	return body.get_rid()

func is_alive():
	return true

func get_body():
	return body

func get_player_input() -> PlayerInput:
	return input

func get_movement_reconciliation() -> PlayerMovementReconciliation:
	return movement_reconciliation

func simulate(input_frame: MovementInputFrame, delta: float) -> void:
	body.simulate(input_frame, delta)
