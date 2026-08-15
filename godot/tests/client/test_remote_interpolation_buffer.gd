extends GutTest

const TEST_DELTA: float = 0.01

func test_authoritative_body_updates_without_teleporting_visual_and_rejects_stale_ticks() -> void:
	var remote: RemoteEntity = _make_remote()
	var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
	buffer.adaptive_playout_enabled = false

	assert_true(buffer.push_movement_snapshot(
		_make_snapshot(10, Vector3(1.0, 0.0, 0.0), Vector3.ZERO),
		0.0
	))
	assert_almost_eq(remote.body.global_position.x, 1.0, 0.0001)
	assert_almost_eq(
		remote.get_node("Model").global_position.x,
		0.0,
		0.0001,
		"The visual should only move from the per-frame presentation path"
	)

	assert_false(buffer.push_movement_snapshot(
		_make_snapshot(9, Vector3(99.0, 0.0, 0.0), Vector3.ZERO),
		0.01
	))
	assert_almost_eq(remote.body.global_position.x, 1.0, 0.0001)
	assert_eq(buffer.get_rejected_stale_snapshot_count(), 1)

func test_stable_stream_extrapolates_without_fixed_playout_delay() -> void:
	var remote: RemoteEntity = _make_remote()
	var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
	buffer.adaptive_playout_enabled = false
	var last_observation: Array[RemoteInterpolationBuffer.RenderObservation] = []
	buffer.remote_transform_rendered.connect(func(
		observation: RemoteInterpolationBuffer.RenderObservation
	) -> void:
		last_observation.assign([_copy_observation(observation)])
	)

	buffer.push_movement_snapshot(
		_make_snapshot(0, Vector3.ZERO, Vector3(10.0, 0.0, 0.0)),
		0.0
	)
	buffer.advance(0.05)
	assert_almost_eq(remote.get_node("Model").global_position.x, 0.5, 0.001)

	buffer.push_movement_snapshot(
		_make_snapshot(1, Vector3(0.5, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)),
		0.05
	)
	buffer.advance(TEST_DELTA)

	assert_almost_eq(remote.body.global_position.x, 0.5, 0.001)
	assert_almost_eq(remote.get_node("Model").global_position.x, 0.6, 0.001)
	assert_eq(last_observation[0].render_mode, RemoteInterpolationBuffer.RenderMode.EXTRAPOLATING)
	assert_almost_eq(last_observation[0].playout_delay_seconds, 0.0, 0.0001)

func test_new_snapshot_error_accrues_while_existing_correction_is_smoothed() -> void:
	var remote: RemoteEntity = _make_remote()
	var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
	buffer.adaptive_playout_enabled = false
	buffer.maximum_correction_speed = 5.0
	var correction_distances: Array[float] = []
	buffer.remote_transform_rendered.connect(func(
		observation: RemoteInterpolationBuffer.RenderObservation
	) -> void:
		correction_distances.append(observation.correction_distance)
	)

	buffer.push_movement_snapshot(
		_make_snapshot(0, Vector3.ZERO, Vector3(10.0, 0.0, 0.0)),
		0.0
	)
	buffer.advance(0.05)
	buffer.push_movement_snapshot(
		_make_snapshot(1, Vector3(1.5, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)),
		0.05
	)
	buffer.advance(TEST_DELTA)
	var first_corrected_position: float = remote.get_node("Model").global_position.x
	var first_correction_distance: float = correction_distances[-1]

	buffer.push_movement_snapshot(
		_make_snapshot(2, Vector3(3.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)),
		0.10
	)
	buffer.advance(TEST_DELTA)
	var second_corrected_position: float = remote.get_node("Model").global_position.x
	var second_correction_distance: float = correction_distances[-1]

	assert_true(first_correction_distance > 0.9)
	assert_true(
		second_correction_distance > first_correction_distance,
		"A new target error should accrue instead of replacing the unfinished correction"
	)
	assert_true(
		second_corrected_position - first_corrected_position <= 0.151,
		"Visual motion should contain base movement plus at most the correction-speed cap"
	)
	assert_true(second_corrected_position < remote.body.global_position.x)

func test_extrapolation_is_bounded_before_buffer_underrun() -> void:
	var remote: RemoteEntity = _make_remote()
	var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
	buffer.adaptive_playout_enabled = false
	buffer.maximum_extrapolation_seconds = 0.20
	var last_observation: Array[RemoteInterpolationBuffer.RenderObservation] = []
	buffer.remote_transform_rendered.connect(func(
		observation: RemoteInterpolationBuffer.RenderObservation
	) -> void:
		last_observation.assign([_copy_observation(observation)])
	)

	buffer.push_movement_snapshot(
		_make_snapshot(0, Vector3.ZERO, Vector3(10.0, 0.0, 0.0)),
		0.0
	)
	buffer.advance(0.25)

	assert_eq(last_observation[0].render_mode, RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN)
	assert_almost_eq(last_observation[0].target_position.x, 2.0, 0.001)
	assert_almost_eq(last_observation[0].extrapolation_seconds, 0.20, 0.001)

func test_large_tick_gap_rebases_timeline_without_teleporting_visual() -> void:
	var remote: RemoteEntity = _make_remote()
	var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
	buffer.adaptive_playout_enabled = false
	var last_observation: Array[RemoteInterpolationBuffer.RenderObservation] = []
	buffer.remote_transform_rendered.connect(func(
		observation: RemoteInterpolationBuffer.RenderObservation
	) -> void:
		last_observation.assign([_copy_observation(observation)])
	)

	buffer.push_movement_snapshot(
		_make_snapshot(0, Vector3.ZERO, Vector3.ZERO),
		0.0
	)
	buffer.advance(TEST_DELTA)
	buffer.push_movement_snapshot(
		_make_snapshot(400, Vector3(10.0, 0.0, 0.0), Vector3.ZERO),
		20.0
	)
	buffer.advance(TEST_DELTA)

	assert_almost_eq(remote.body.global_position.x, 10.0, 0.001)
	assert_true(
		remote.get_node("Model").global_position.x <= 0.051,
		"A timeline rebase should preserve visual continuity and smooth the correction"
	)
	assert_almost_eq(last_observation[0].playout_delay_seconds, 0.0, 0.001)
	assert_false(last_observation[0].hard_snap_applied)

func test_adaptive_delay_responds_to_jitter_but_stays_zero_for_stable_arrivals() -> void:
	var stable_remote: RemoteEntity = _make_remote()
	var stable_buffer: RemoteInterpolationBuffer = stable_remote.interpolation_buffer
	_push_arrivals(stable_buffer, [0.0, 0.050, 0.101, 0.150])
	stable_buffer.advance(TEST_DELTA)
	assert_almost_eq(stable_buffer.get_target_playout_delay_seconds(), 0.0, 0.0001)

	var jittered_remote: RemoteEntity = _make_remote()
	var jittered_buffer: RemoteInterpolationBuffer = jittered_remote.interpolation_buffer
	_push_arrivals(jittered_buffer, [0.0, 0.050, 0.140, 0.150])
	jittered_buffer.advance(TEST_DELTA)
	assert_true(jittered_buffer.get_arrival_jitter_seconds() > 0.01)
	assert_true(jittered_buffer.get_target_playout_delay_seconds() > 0.05)
	assert_true(
		jittered_buffer.get_playback_rate() > 1.0,
		"An overfilled jitter buffer should gently catch its render cursor up"
	)

func _make_remote() -> RemoteEntity:
	var scene: PackedScene = load(
		"res://projects/client/src/entities/remote/remote_entity.tscn"
	) as PackedScene
	var remote: RemoteEntity = add_child_autoqfree(scene.instantiate()) as RemoteEntity
	remote.interpolation_buffer.set_process(false)
	remote.apply_remote_transform(Vector3.ZERO, Quaternion.IDENTITY)
	return remote

func _push_arrivals(buffer: RemoteInterpolationBuffer, arrivals: Array[float]) -> void:
	for index: int in arrivals.size():
		buffer.push_movement_snapshot(
			_make_snapshot(index, Vector3.ZERO, Vector3.ZERO),
			arrivals[index]
		)

func _make_snapshot(
	server_tick: int,
	position: Vector3,
	velocity: Vector3
) -> MovementSnapshotMsg.EntitySnapshot:
	var snapshot: MovementSnapshotMsg.EntitySnapshot = \
		MovementSnapshotMsg.EntitySnapshot.new()
	snapshot.server_tick = server_tick
	snapshot.position = position
	snapshot.velocity = velocity
	snapshot.rotation = Quaternion.IDENTITY
	return snapshot

func _copy_observation(
	source: RemoteInterpolationBuffer.RenderObservation
) -> RemoteInterpolationBuffer.RenderObservation:
	var copy: RemoteInterpolationBuffer.RenderObservation = \
		RemoteInterpolationBuffer.RenderObservation.new()
	copy.position = source.position
	copy.target_position = source.target_position
	copy.server_position = source.server_position
	copy.expected_velocity = source.expected_velocity
	copy.render_mode = source.render_mode
	copy.delta = source.delta
	copy.correction_distance = source.correction_distance
	copy.correction_speed = source.correction_speed
	copy.playout_delay_seconds = source.playout_delay_seconds
	copy.target_playout_delay_seconds = source.target_playout_delay_seconds
	copy.extrapolation_seconds = source.extrapolation_seconds
	copy.hard_snap_applied = source.hard_snap_applied
	return copy
