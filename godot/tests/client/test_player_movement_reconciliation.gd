extends GutTest

const TEST_DELTA: float = 0.05

func test_player_scene_wires_reconciliation_component() -> void:
	var scene: PackedScene = load("res://scripts/client/player_entity.tscn") as PackedScene
	var player: Player = add_child_autoqfree(scene.instantiate()) as Player
	var reconciliation: PlayerMovementReconciliation = player.get_movement_reconciliation()

	assert_true(reconciliation != null, "Player scene should include reconciliation component")
	assert_eq(reconciliation.body, player.get_body(), "Reconciliation should reference the player body")
	assert_eq(
		reconciliation.player_input,
		player.get_player_input(),
		"Reconciliation should reference player input"
	)

func test_reconcile_reuses_result_instance() -> void:
	var body: PhysicsBody = add_child_autofree(PhysicsBody.new()) as PhysicsBody
	var player_input: PlayerInput = add_child_autofree(PlayerInput.new()) as PlayerInput
	var reconciliation: PlayerMovementReconciliation = add_child_autofree(
		PlayerMovementReconciliation.new()
	) as PlayerMovementReconciliation
	reconciliation.body = body
	reconciliation.player_input = player_input

	var first_result: PlayerMovementReconciliation.Result = reconciliation.reconcile(
		_make_snapshot(MovementSnapshotMsg.NO_PROCESSED_SEQ, Vector3.ZERO, Vector3.ZERO),
		TEST_DELTA
	)
	var second_result: PlayerMovementReconciliation.Result = reconciliation.reconcile(
		_make_snapshot(MovementSnapshotMsg.NO_PROCESSED_SEQ, Vector3.ZERO, Vector3.ZERO),
		TEST_DELTA
	)

	assert_same(first_result, second_result, "Reconciliation should reuse its result object")

func test_tiny_drift_prunes_acknowledged_frames_without_replay() -> void:
	var body: PhysicsBody = add_child_autofree(PhysicsBody.new()) as PhysicsBody
	var player_input: PlayerInput = add_child_autofree(PlayerInput.new()) as PlayerInput
	var reconciliation: PlayerMovementReconciliation = add_child_autofree(
		PlayerMovementReconciliation.new()
	) as PlayerMovementReconciliation
	reconciliation.body = body
	reconciliation.player_input = player_input
	reconciliation.position_drift_epsilon = 0.01

	_store_prediction(player_input, body, 1, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
	_store_prediction(player_input, body, 2, Vector3(2.0, 0.0, 0.0), Vector3.ZERO)
	_store_prediction(player_input, body, 3, Vector3(3.0, 0.0, 0.0), Vector3.ZERO)
	body.global_position = Vector3(100.0, 0.0, 0.0)

	var snapshot: MovementSnapshotMsg.EntitySnapshot = _make_snapshot(
		2,
		Vector3(2.005, 0.0, 0.0),
		Vector3.ZERO
	)
	var result: PlayerMovementReconciliation.Result = reconciliation.reconcile(snapshot, TEST_DELTA)

	assert_true(result.ignored_tiny_drift, "Tiny drift should be ignored")
	assert_false(result.correction_applied, "Tiny drift should not correct the body")
	assert_eq(result.pruned_count, 2, "Acked frames should be pruned")
	assert_eq(result.replayed_count, 0, "Tiny drift should not replay unacked inputs")
	assert_eq(player_input.get_prediction_frame(1), null, "Frame 1 should be pruned")
	assert_eq(player_input.get_prediction_frame(2), null, "Frame 2 should be pruned")
	assert_true(player_input.get_prediction_frame(3) != null, "Frame 3 should remain replayable")
	assert_almost_eq(body.global_position.x, 100.0, 0.001, "Body should not be snapped")

func test_large_drift_applies_authoritative_state_and_replays_unacked_inputs() -> void:
	var body: PhysicsBody = add_child_autofree(PhysicsBody.new()) as PhysicsBody
	var player_input: PlayerInput = add_child_autofree(PlayerInput.new()) as PlayerInput
	var reconciliation: PlayerMovementReconciliation = add_child_autofree(
		PlayerMovementReconciliation.new()
	) as PlayerMovementReconciliation
	reconciliation.body = body
	reconciliation.player_input = player_input
	reconciliation.position_drift_epsilon = 0.01

	_store_prediction(player_input, body, 1, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)
	_store_prediction(player_input, body, 2, Vector3(2.0, 0.0, 0.0), Vector3.ZERO)
	_store_prediction(player_input, body, 3, Vector3(3.0, 0.0, 0.0), Vector3.ZERO)

	var frame_2: PredictionRingBuffer.Frame = player_input.get_prediction_frame(2)
	var frame_3: PredictionRingBuffer.Frame = player_input.get_prediction_frame(3)
	frame_2.input_x = 1.0
	frame_3.input_x = 1.0
	body.global_position = Vector3(3.0, 0.0, 0.0)

	await wait_physics_frames(1)

	var snapshot: MovementSnapshotMsg.EntitySnapshot = _make_snapshot(
		1,
		Vector3(10.0, 0.0, 0.0),
		Vector3.ZERO
	)
	var result: PlayerMovementReconciliation.Result = reconciliation.reconcile(snapshot, TEST_DELTA)

	assert_true(result.correction_applied, "Large drift should correct the body")
	assert_eq(result.pruned_count, 1, "Only the acked frame should be pruned")
	assert_eq(result.replayed_count, 2, "Frames 2 and 3 should be replayed")
	assert_eq(player_input.get_prediction_frame(1), null, "Acked frame should be pruned")
	assert_true(player_input.get_prediction_frame(2) != null, "Unacked frame 2 should remain")
	assert_true(player_input.get_prediction_frame(3) != null, "Unacked frame 3 should remain")
	assert_almost_eq(body.global_position.x, 11.0, 0.001, "Replay should advance from authority")
	assert_almost_eq(
		player_input.get_prediction_frame(3).predicted_position.x,
		body.global_position.x,
		0.001,
		"Last replayed frame should store the corrected prediction"
	)

func test_missing_prediction_frame_prunes_acknowledged_frames_without_correction() -> void:
	var body: PhysicsBody = add_child_autofree(PhysicsBody.new()) as PhysicsBody
	var player_input: PlayerInput = add_child_autofree(PlayerInput.new()) as PlayerInput
	var reconciliation: PlayerMovementReconciliation = add_child_autofree(
		PlayerMovementReconciliation.new()
	) as PlayerMovementReconciliation
	reconciliation.body = body
	reconciliation.player_input = player_input

	_store_prediction(player_input, body, 3, Vector3(3.0, 0.0, 0.0), Vector3.ZERO)
	body.global_position = Vector3(50.0, 0.0, 0.0)

	var snapshot: MovementSnapshotMsg.EntitySnapshot = _make_snapshot(
		2,
		Vector3(2.0, 0.0, 0.0),
		Vector3.ZERO
	)
	var result: PlayerMovementReconciliation.Result = reconciliation.reconcile(snapshot, TEST_DELTA)

	assert_true(result.missing_prediction_frame, "Missing acked frame should be reported")
	assert_false(result.correction_applied, "Missing frame cannot be safely replayed")
	assert_eq(result.pruned_count, 0, "No existing frames were acknowledged")
	assert_almost_eq(body.global_position.x, 50.0, 0.001, "Body should not be changed")

func _store_prediction(
	player_input: PlayerInput,
	body: PhysicsBody,
	seq: int,
	position: Vector3,
	velocity: Vector3
) -> PredictionRingBuffer.Frame:
	var input: MovementInputFrame = MovementInputFrame.new()
	input.seq = seq
	var frame: PredictionRingBuffer.Frame = player_input._prediction_buffer.store(input)
	body.global_position = position
	body.velocity = velocity
	frame.write_predicted_state(body)
	return frame

func _make_snapshot(
	ack_seq: int,
	position: Vector3,
	velocity: Vector3
) -> MovementSnapshotMsg.EntitySnapshot:
	var snapshot: MovementSnapshotMsg.EntitySnapshot = MovementSnapshotMsg.EntitySnapshot.new()
	snapshot.entity_id = 1
	snapshot.last_processed_movement_seq = ack_seq
	snapshot.position = position
	snapshot.velocity = velocity
	snapshot.rotation = Quaternion.IDENTITY
	snapshot.is_on_floor = false
	return snapshot
