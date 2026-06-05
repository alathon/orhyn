class_name ServerPlayerEntity
extends BaseEntity

@onready var body: PhysicsBody = $Body
@onready var model: Node3D = %Model # TODO: Only keeping the model for now for debugging.

var peer_id: int = -1

var current_tick_context: Dictionary = {}

func get_rid() -> RID:
	return body.get_rid()

func is_alive():
	return true

func get_body():
	return body
