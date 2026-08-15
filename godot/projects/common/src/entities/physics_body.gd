class_name PhysicsBody
extends CharacterBody3D

@export_range(2.0, 40.0) var Speed = 10.0
@export_range(4.5, 10.0) var JumpVelocity = 4.5

var face_angle: float:
	get: return rotation.y

func simulate(input: MovementInputFrame, delta: float) -> void:
	velocity += get_gravity() * delta  # always; move_and_slide zeroes it on floor contact

	if input.jump_pressed and is_on_floor():
		velocity.y = JumpVelocity

	var movement: Vector3 = get_movement_direction(input)

	if movement != Vector3.ZERO:
		velocity.x = movement.x * Speed
		velocity.z = movement.z * Speed
		rotation.y = atan2(-movement.x, -movement.z)
	else:
		velocity.x = move_toward(velocity.x, 0, Speed)
		velocity.z = move_toward(velocity.z, 0, Speed)

	move_and_slide()

static func get_movement_direction(input: MovementInputFrame) -> Vector3:
	var movement: Vector3 = Vector3(input.input_x, 0.0, input.input_z)
	if movement.length_squared() > 1.0:
		return movement.normalized()
	return movement
