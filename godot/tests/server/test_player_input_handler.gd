extends GutTest

func test_invalid_unsigned_seq_does_not_poison_peer_buffer() -> void:
	var handler: PlayerInputBuffers = autofree(PlayerInputBuffers.new()) as PlayerInputBuffers
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player_scene: PackedScene = load("res://projects/game-server/src/entities/player/server_player_entity.tscn") as PackedScene
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

func test_late_gap_fill_is_accepted_when_newer_than_processed_seq() -> void:
	var fixture: Dictionary = _make_handler_fixture()
	var handler: PlayerInputBuffers = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	player.input_buffer.peer_buffer.last_processed_seq = 100

	handler._on_player_input_received(3, _make_input(102, 1.0, 0.0))
	handler._on_player_input_received(3, _make_input(101, -1.0, 0.0))

	var input_101: MovementInputFrame = player.input_buffer.get_next_input()
	var input_102: MovementInputFrame = player.input_buffer.get_next_input()
	assert_eq(input_101.seq, 101)
	assert_almost_eq(input_101.input_x, -1.0, 0.001)
	assert_eq(input_102.seq, 102)
	assert_almost_eq(input_102.input_x, 1.0, 0.001)

func test_missing_skip_policy_commits_one_gap_then_replays_buffered_inputs() -> void:
	var fixture: Dictionary = _make_handler_fixture()
	var handler: PlayerInputBuffers = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	player.input_buffer.peer_buffer.last_processed_seq = 100

	handler._on_player_input_received(3, _make_input(102, 0.2, 0.0))
	handler._on_player_input_received(3, _make_input(103, 0.3, 0.0))
	handler._on_player_input_received(3, _make_input(104, 0.4, 0.0))
	handler._on_player_input_received(3, _make_input(105, 0.5, 0.0))

	var missing_101: MovementInputFrame = player.input_buffer.get_next_input()
	assert_null(missing_101)
	assert_eq(player.input_buffer.get_last_processed_seq(), 101)

	for seq in range(102, 106):
		var next_input: MovementInputFrame = player.input_buffer.get_next_input()
		assert_eq(next_input.seq, seq)

func test_large_future_gap_fast_forwards_to_oldest_buffered_input() -> void:
	var fixture: Dictionary = _make_handler_fixture()
	var handler: PlayerInputBuffers = fixture.handler
	var player: ServerPlayerEntity = fixture.player
	player.input_buffer.peer_buffer.last_processed_seq = 105

	handler._on_player_input_received(3, _make_input(130, 0.3, 0.0))
	handler._on_player_input_received(3, _make_input(131, 0.4, 0.0))
	handler._on_player_input_received(3, _make_input(132, 0.5, 0.0))
	handler._on_player_input_received(3, _make_input(133, 0.6, 0.0))

	assert_eq(player.input_buffer.get_last_processed_seq(), 129)
	var next_input: MovementInputFrame = player.input_buffer.get_next_input()
	assert_eq(next_input.seq, 130)
	assert_almost_eq(next_input.input_x, 0.3, 0.001)

func _make_handler_fixture() -> Dictionary:
	var handler: PlayerInputBuffers = autofree(PlayerInputBuffers.new()) as PlayerInputBuffers
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player_scene: PackedScene = load("res://projects/game-server/src/entities/player/server_player_entity.tscn") as PackedScene
	var player: ServerPlayerEntity = add_child_autofree(player_scene.instantiate()) as ServerPlayerEntity
	player.entity_id = 1
	tracker.track_player(3, player)
	handler.entity_tracker = tracker
	return {
		"handler": handler,
		"player": player,
	}

func _make_input(seq: int, input_x: float, input_z: float) -> MovementInputFrame:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.seq = seq
	input.input_x = input_x
	input.input_z = input_z
	return input
