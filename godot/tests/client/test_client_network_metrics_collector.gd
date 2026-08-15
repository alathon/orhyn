extends GutTest

func test_ingame_scene_wires_disabled_network_metrics_collector() -> void:
	var scene: PackedScene = load(
		"res://projects/client/src/screens/ingame/ingame_screen.tscn"
	) as PackedScene
	var screen: IngameScreen = add_child_autoqfree(scene.instantiate()) as IngameScreen
	var systems: ClientGameSystems = screen.get_node("GameSystems") as ClientGameSystems

	assert_true(screen.network_metrics != null, "In-game screen should expose network metrics")
	assert_same(
		screen.network_metrics,
		systems.network_metrics,
		"In-game screen and game systems should share the collector"
	)
	assert_false(screen.network_metrics.enabled, "Collection should be disabled by default")

func test_disabled_collector_ignores_reconciliation_results() -> void:
	var collector: ClientNetworkMetricsCollector = add_child_autofree(
		ClientNetworkMetricsCollector.new()
	) as ClientNetworkMetricsCollector
	collector.record_reconciliation(_make_result(1, 0.25, true, 0.20, 3))

	var metrics: Dictionary = collector.snapshot()
	assert_eq(metrics.get("acknowledged_snapshot_count"), 0)
	assert_eq(metrics.get("correction_count"), 0)

func test_collection_summarizes_reconciliation_quality_and_can_stop() -> void:
	var collector: ClientNetworkMetricsCollector = add_child_autofree(
		ClientNetworkMetricsCollector.new()
	) as ClientNetworkMetricsCollector
	collector.start_collection()

	collector.record_reconciliation(_make_result(1, 0.01, false, 0.0, 0, true))
	collector.record_reconciliation(_make_result(2, 0.10, true, 0.08, 2))
	collector.record_reconciliation(_make_result(3, 0.30, true, 0.24, 4))
	collector.record_reconciliation(_make_missing_frame_result(4))
	collector.stop_collection()

	var metrics: Dictionary = collector.snapshot()
	assert_false(bool(metrics.get("enabled")))
	assert_eq(
		metrics.get("metric_sample_capacity"),
		ClientNetworkMetricsCollector.MAX_METRIC_SAMPLE_COUNT
	)
	assert_eq(metrics.get("dropped_metric_value_count"), 0)
	assert_eq(metrics.get("acknowledged_snapshot_count"), 4)
	assert_eq(metrics.get("new_acknowledgement_count"), 4)
	assert_eq(metrics.get("stale_acknowledgement_count"), 0)
	assert_eq(metrics.get("prediction_frame_sample_count"), 3)
	assert_eq(metrics.get("missing_prediction_frame_count"), 1)
	assert_almost_eq(float(metrics.get("missing_prediction_frame_ratio")), 0.25, 0.0001)
	assert_eq(metrics.get("ignored_tiny_drift_count"), 1)
	assert_eq(metrics.get("correction_count"), 2)
	assert_almost_eq(float(metrics.get("correction_ratio")), 2.0 / 3.0, 0.0001)
	assert_eq(metrics.get("replayed_input_frame_count"), 6)
	assert_almost_eq(float(metrics.get("average_ack_position_drift")), 0.41 / 3.0, 0.0001)
	assert_almost_eq(float(metrics.get("p95_ack_position_drift")), 0.30, 0.0001)
	assert_almost_eq(float(metrics.get("max_ack_position_drift")), 0.30, 0.0001)
	assert_almost_eq(float(metrics.get("total_body_correction_distance")), 0.32, 0.0001)
	assert_almost_eq(float(metrics.get("average_body_correction_distance")), 0.16, 0.0001)
	assert_almost_eq(float(metrics.get("p95_body_correction_distance")), 0.24, 0.0001)
	assert_almost_eq(float(metrics.get("max_body_correction_distance")), 0.24, 0.0001)

	collector.record_reconciliation(_make_result(5, 1.0, true, 1.0, 1))
	assert_eq(
		collector.snapshot().get("correction_count"),
		2,
		"Stopped collection should ignore later reconciliations"
	)

func test_start_collection_resets_previous_window() -> void:
	var collector: ClientNetworkMetricsCollector = add_child_autofree(
		ClientNetworkMetricsCollector.new()
	) as ClientNetworkMetricsCollector
	collector.start_collection()
	collector.record_reconciliation(_make_result(1, 0.25, true, 0.20, 3))
	collector.start_collection()

	var metrics: Dictionary = collector.snapshot()
	assert_true(bool(metrics.get("enabled")))
	assert_eq(metrics.get("acknowledged_snapshot_count"), 0)
	assert_eq(metrics.get("correction_count"), 0)

func test_stale_acknowledgement_is_not_counted_as_missing_prediction_history() -> void:
	var collector: ClientNetworkMetricsCollector = add_child_autofree(
		ClientNetworkMetricsCollector.new()
	) as ClientNetworkMetricsCollector
	collector.start_collection()
	var stale_result: PlayerMovementReconciliation.Result = _make_result(
		1,
		0.0,
		false,
		0.0,
		0
	)
	stale_result.stale_ack = true
	collector.record_reconciliation(stale_result)
	collector.stop_collection()

	var metrics: Dictionary = collector.snapshot()
	assert_eq(metrics.get("acknowledged_snapshot_count"), 1)
	assert_eq(metrics.get("new_acknowledgement_count"), 0)
	assert_eq(metrics.get("stale_acknowledgement_count"), 1)
	assert_eq(metrics.get("missing_prediction_frame_count"), 0)

func test_remote_motion_collection_reports_stall_and_catch_up_episodes() -> void:
	var collector: ClientNetworkMetricsCollector = add_child_autofree(
		ClientNetworkMetricsCollector.new()
	) as ClientNetworkMetricsCollector
	var scene: PackedScene = load(
		"res://projects/client/src/entities/remote/remote_entity.tscn"
	) as PackedScene
	var remote: RemoteEntity = add_child_autoqfree(scene.instantiate()) as RemoteEntity
	remote.entity_id = 42
	assert_true(collector.start_remote_motion_collection(remote))

	var moving_velocity: Vector3 = Vector3(10.0, 0.0, 0.0)
	_emit_remote_observation(
		remote,
		Vector3.ZERO,
		moving_velocity,
		RemoteInterpolationBuffer.RenderMode.INTERPOLATING,
		0.1
	)
	_emit_remote_observation(
		remote,
		Vector3.ZERO,
		moving_velocity,
		RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN,
		0.1,
		0.4,
		4.0,
		0.12
	)
	_emit_remote_observation(
		remote,
		Vector3(2.0, 0.0, 0.0),
		moving_velocity,
		RemoteInterpolationBuffer.RenderMode.EXTRAPOLATING,
		0.1
	)
	_emit_remote_observation(
		remote,
		Vector3(3.0, 0.0, 0.0),
		moving_velocity,
		RemoteInterpolationBuffer.RenderMode.INTERPOLATING,
		0.1,
		0.2,
		2.0,
		0.08,
		true
	)
	collector.stop_collection()

	var metrics: Dictionary = collector.snapshot()
	assert_eq(metrics.get("remote_entity_id"), 42)
	assert_eq(metrics.get("remote_render_sample_count"), 4)
	assert_eq(metrics.get("remote_motion_sample_count"), 3)
	assert_eq(metrics.get("remote_extrapolated_sample_count"), 1)
	assert_eq(metrics.get("remote_buffer_underrun_sample_count"), 1)
	assert_eq(metrics.get("remote_stall_episode_count"), 1)
	assert_eq(metrics.get("remote_catch_up_episode_count"), 1)
	assert_eq(metrics.get("remote_motion_discontinuity_count"), 2)
	assert_eq(metrics.get("remote_hard_snap_count"), 1)
	assert_almost_eq(float(metrics.get("remote_extrapolated_seconds")), 0.1, 0.0001)
	assert_almost_eq(float(metrics.get("remote_stalled_seconds")), 0.1, 0.0001)
	assert_almost_eq(float(metrics.get("remote_catch_up_seconds")), 0.1, 0.0001)
	assert_almost_eq(float(metrics.get("remote_average_rendered_speed")), 10.0, 0.0001)
	assert_almost_eq(float(metrics.get("remote_p95_rendered_speed")), 20.0, 0.0001)
	assert_almost_eq(float(metrics.get("remote_max_rendered_speed")), 20.0, 0.0001)
	assert_almost_eq(float(metrics.get("remote_average_correction_distance")), 0.15, 0.0001)
	assert_almost_eq(float(metrics.get("remote_max_correction_distance")), 0.4, 0.0001)
	assert_almost_eq(float(metrics.get("remote_average_correction_speed")), 1.5, 0.0001)
	assert_almost_eq(float(metrics.get("remote_max_correction_speed")), 4.0, 0.0001)
	assert_almost_eq(float(metrics.get("remote_average_playout_delay")), 0.05, 0.0001)
	assert_almost_eq(float(metrics.get("remote_max_playout_delay")), 0.12, 0.0001)

	_emit_remote_observation(
		remote,
		Vector3(4.0, 0.0, 0.0),
		moving_velocity,
		RemoteInterpolationBuffer.RenderMode.INTERPOLATING,
		0.1
	)
	assert_eq(
		collector.snapshot().get("remote_render_sample_count"),
		4,
		"Stopped remote collection should disconnect from interpolation samples"
	)

func _emit_remote_observation(
	remote: RemoteEntity,
	position: Vector3,
	expected_velocity: Vector3,
	render_mode: int,
	delta: float,
	correction_distance: float = 0.0,
	correction_speed: float = 0.0,
	playout_delay_seconds: float = 0.0,
	hard_snap_applied: bool = false
) -> void:
	var observation: RemoteInterpolationBuffer.RenderObservation = \
		RemoteInterpolationBuffer.RenderObservation.new()
	observation.position = position
	observation.expected_velocity = expected_velocity
	observation.render_mode = render_mode
	observation.delta = delta
	observation.correction_distance = correction_distance
	observation.correction_speed = correction_speed
	observation.playout_delay_seconds = playout_delay_seconds
	observation.hard_snap_applied = hard_snap_applied
	remote.interpolation_buffer.remote_transform_rendered.emit(observation)

func _make_result(
	ack_seq: int,
	position_drift: float,
	correction_applied: bool,
	body_correction_distance: float,
	replayed_count: int,
	ignored_tiny_drift: bool = false
) -> PlayerMovementReconciliation.Result:
	var result: PlayerMovementReconciliation.Result = PlayerMovementReconciliation.Result.new()
	result.reset(true, ack_seq)
	result.has_ack = true
	result.position_drift = position_drift
	result.correction_applied = correction_applied
	result.body_correction_distance = body_correction_distance
	result.replayed_count = replayed_count
	result.ignored_tiny_drift = ignored_tiny_drift
	return result

func _make_missing_frame_result(ack_seq: int) -> PlayerMovementReconciliation.Result:
	var result: PlayerMovementReconciliation.Result = PlayerMovementReconciliation.Result.new()
	result.reset(true, ack_seq)
	result.has_ack = true
	result.missing_prediction_frame = true
	return result
