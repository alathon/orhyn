class_name Player
extends BaseEntity

@onready var body: PhysicsBody = $PhysicsBody
@onready var input: PlayerInput = $PlayerInput
@onready var movement_reconciliation: PlayerMovementReconciliation = $PlayerMovementReconciliation
@onready var model_manager: ModelManager = %ModelContainer
@onready var equipment: Equipment = $Equipment
@onready var camera_pivot: Node3D = $CameraPivot

const tmp_wizard_scene: PackedScene = preload("uid://dvj64bdlnoc46")

func _ready():
	# TODO: Temporary
	model_manager.load_base_model(tmp_wizard_scene)

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

func freeze_for_loading(is_frozen: bool) -> void:
	if is_frozen:
		body.velocity = Vector3.ZERO
		input.clear_current_input()

func simulate(input_frame: MovementInputFrame, delta: float) -> void:
	body.simulate(input_frame, delta)
