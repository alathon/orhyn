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

	var ix = input.input_x
	var iz = input.input_z
	var movement = Vector3(ix, 0.0, iz)

	if movement != Vector3.ZERO:
		velocity.x = movement.x * Speed
		velocity.z = movement.z * Speed
		rotation.y = atan2(-movement.x, -movement.z)
	else:
		velocity.x = move_toward(velocity.x, 0, Speed)
		velocity.z = move_toward(velocity.z, 0, Speed)

	move_and_slide()
