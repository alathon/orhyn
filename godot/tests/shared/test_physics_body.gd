extends GutTest


func test_movement_direction_preserves_valid_input() -> void:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.input_x = 0.6
	input.input_z = 0.8

	var direction: Vector3 = PhysicsBody.get_movement_direction(input)

	assert_almost_eq(direction.x, 0.6, 0.0001)
	assert_almost_eq(direction.z, 0.8, 0.0001)
	assert_almost_eq(direction.length(), 1.0, 0.0001)


func test_movement_direction_normalizes_out_of_range_diagonal_input() -> void:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.input_x = 1.0
	input.input_z = 1.0

	var direction: Vector3 = PhysicsBody.get_movement_direction(input)

	assert_almost_eq(direction.length(), 1.0, 0.0001)
	assert_almost_eq(direction.x, sqrt(0.5), 0.0001)
	assert_almost_eq(direction.z, sqrt(0.5), 0.0001)
