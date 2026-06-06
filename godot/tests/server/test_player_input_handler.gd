extends GutTest

func test_invalid_unsigned_seq_does_not_poison_peer_buffer() -> void:
	var handler: PlayerInputBuffers = autofree(PlayerInputBuffers.new()) as PlayerInputBuffers
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player_scene: PackedScene = load("res://scripts/server/server_player_entity.tscn") as PackedScene
	var player: ServerPlayerEntity = add_child_autofree(player_scene.instantiate()) as ServerPlayerEntity
	player.entity_id = 1
	tracker.track_player(3, player)
	handler.entity_tracker = tracker

	var invalid_input: MovementInputFrame = _make_input(0xFFFFFFFF, -0.7, -0.7)
	handler._on_player_input_received(3, invalid_input)

	var valid_input: MovementInputFrame = _make_input(76, -0.7, -0.7)
	handler._on_player_input_received(3, valid_input)

	var next_input: MovementInputFrame = player.input_buffer.get_next_input()
	assert_eq(next_input.seq, 76, "Invalid unsigned sentinel should not poison last_seen_seq")
	assert_almost_eq(next_input.input_x, -0.7, 0.001)
	assert_almost_eq(next_input.input_z, -0.7, 0.001)

func _make_input(seq: int, input_x: float, input_z: float) -> MovementInputFrame:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.seq = seq
	input.input_x = input_x
	input.input_z = input_z
	return input
