class_name ClientNetworkMetricsCollector
extends Node

@export var enabled: bool = false
@export_range(0.0, 10.0, 0.01, "or_greater") var remote_moving_speed_epsilon: float = 0.10
@export_range(0.0, 1.0, 0.01, "or_greater") var remote_stall_speed_ratio: float = 0.10
@export_range(1.0, 10.0, 0.01, "or_greater") var remote_catch_up_speed_ratio: float = 2.0

var _started_usec: int = 0
var _stopped_usec: int = 0
var _acknowledged_snapshot_count: int = 0
var _stale_acknowledgement_count: int = 0
var _prediction_frame_sample_count: int = 0
var _missing_prediction_frame_count: int = 0
var _ignored_tiny_drift_count: int = 0
var _correction_count: int = 0
var _replayed_input_frame_count: int = 0
var _total_ack_position_drift: float = 0.0
var _max_ack_position_drift: float = 0.0
var _total_body_correction_distance: float = 0.0
var _max_body_correction_distance: float = 0.0
var _ack_position_drifts: Array[float] = []
var _body_correction_distances: Array[float] = []
var _collect_local_reconciliation: bool = true
var _remote_buffer: RemoteInterpolationBuffer = null
var _remote_entity_id: int = -1
var _remote_render_sample_count: int = 0
var _remote_motion_sample_count: int = 0
var _remote_interpolated_sample_count: int = 0
var _remote_buffer_underrun_sample_count: int = 0
var _remote_stall_episode_count: int = 0
var _remote_catch_up_episode_count: int = 0
var _remote_observed_seconds: float = 0.0
var _remote_expected_motion_seconds: float = 0.0
var _remote_stalled_seconds: float = 0.0
var _remote_catch_up_seconds: float = 0.0
var _remote_buffer_underrun_seconds: float = 0.0
var _remote_total_rendered_distance: float = 0.0
var _remote_total_rendered_speed: float = 0.0
var _remote_total_speed_error: float = 0.0
var _remote_max_rendered_speed: float = 0.0
var _remote_max_speed_error: float = 0.0
var _remote_max_frame_distance: float = 0.0
var _remote_rendered_speeds: Array[float] = []
var _remote_speed_errors: Array[float] = []
var _remote_frame_distances: Array[float] = []
var _remote_previous_position: Vector3 = Vector3.ZERO
var _remote_has_previous_position: bool = false
var _remote_was_stalled: bool = false
var _remote_was_catching_up: bool = false

func _ready() -> void:
	if enabled:
		reset_collection()

func start_collection() -> void:
	_disconnect_remote_buffer()
	enabled = true
	reset_collection()
	_collect_local_reconciliation = true

func start_remote_motion_collection(remote: RemoteEntity) -> bool:
	if remote == null or remote.interpolation_buffer == null:
		return false
	start_collection()
	_collect_local_reconciliation = false
	_remote_entity_id = remote.entity_id
	_remote_buffer = remote.interpolation_buffer
	_remote_buffer.remote_transform_rendered.connect(_on_remote_transform_rendered)
	return true

func stop_collection() -> void:
	if enabled:
		_stopped_usec = Time.get_ticks_usec()
	enabled = false
	_disconnect_remote_buffer()

func reset_collection() -> void:
	_started_usec = Time.get_ticks_usec()
	_stopped_usec = 0
	_acknowledged_snapshot_count = 0
	_stale_acknowledgement_count = 0
	_prediction_frame_sample_count = 0
	_missing_prediction_frame_count = 0
	_ignored_tiny_drift_count = 0
	_correction_count = 0
	_replayed_input_frame_count = 0
	_total_ack_position_drift = 0.0
	_max_ack_position_drift = 0.0
	_total_body_correction_distance = 0.0
	_max_body_correction_distance = 0.0
	_ack_position_drifts.clear()
	_body_correction_distances.clear()
	_remote_entity_id = -1
	_remote_render_sample_count = 0
	_remote_motion_sample_count = 0
	_remote_interpolated_sample_count = 0
	_remote_buffer_underrun_sample_count = 0
	_remote_stall_episode_count = 0
	_remote_catch_up_episode_count = 0
	_remote_observed_seconds = 0.0
	_remote_expected_motion_seconds = 0.0
	_remote_stalled_seconds = 0.0
	_remote_catch_up_seconds = 0.0
	_remote_buffer_underrun_seconds = 0.0
	_remote_total_rendered_distance = 0.0
	_remote_total_rendered_speed = 0.0
	_remote_total_speed_error = 0.0
	_remote_max_rendered_speed = 0.0
	_remote_max_speed_error = 0.0
	_remote_max_frame_distance = 0.0
	_remote_rendered_speeds.clear()
	_remote_speed_errors.clear()
	_remote_frame_distances.clear()
	_remote_previous_position = Vector3.ZERO
	_remote_has_previous_position = false
	_remote_was_stalled = false
	_remote_was_catching_up = false

func record_reconciliation(result: PlayerMovementReconciliation.Result) -> void:
	if not enabled or not _collect_local_reconciliation or not result.has_ack:
		return

	_acknowledged_snapshot_count += 1
	if result.stale_ack:
		_stale_acknowledgement_count += 1
		return
	if result.missing_prediction_frame:
		_missing_prediction_frame_count += 1
		return

	_prediction_frame_sample_count += 1
	_total_ack_position_drift += result.position_drift
	_max_ack_position_drift = maxf(_max_ack_position_drift, result.position_drift)
	_ack_position_drifts.append(result.position_drift)
	_replayed_input_frame_count += result.replayed_count

	if result.ignored_tiny_drift:
		_ignored_tiny_drift_count += 1
	if not result.correction_applied:
		return

	_correction_count += 1
	_total_body_correction_distance += result.body_correction_distance
	_max_body_correction_distance = maxf(
		_max_body_correction_distance,
		result.body_correction_distance
	)
	_body_correction_distances.append(result.body_correction_distance)

func snapshot() -> Dictionary:
	var duration_seconds: float = _duration_seconds()
	return {
		"enabled": enabled,
		"duration_seconds": duration_seconds,
		"acknowledged_snapshot_count": _acknowledged_snapshot_count,
		"new_acknowledgement_count": (
			_acknowledged_snapshot_count - _stale_acknowledgement_count
		),
		"stale_acknowledgement_count": _stale_acknowledgement_count,
		"prediction_frame_sample_count": _prediction_frame_sample_count,
		"missing_prediction_frame_count": _missing_prediction_frame_count,
		"missing_prediction_frame_ratio": _ratio(
			_missing_prediction_frame_count,
			_acknowledged_snapshot_count - _stale_acknowledgement_count
		),
		"ignored_tiny_drift_count": _ignored_tiny_drift_count,
		"correction_count": _correction_count,
		"corrections_per_second": _rate(_correction_count, duration_seconds),
		"correction_ratio": _ratio(_correction_count, _prediction_frame_sample_count),
		"replayed_input_frame_count": _replayed_input_frame_count,
		"average_ack_position_drift": _average(
			_total_ack_position_drift,
			_prediction_frame_sample_count
		),
		"p95_ack_position_drift": _percentile(_ack_position_drifts, 0.95),
		"max_ack_position_drift": _max_ack_position_drift,
		"total_body_correction_distance": _total_body_correction_distance,
		"average_body_correction_distance": _average(
			_total_body_correction_distance,
			_correction_count
		),
		"p95_body_correction_distance": _percentile(
			_body_correction_distances,
			0.95
		),
		"max_body_correction_distance": _max_body_correction_distance,
		"remote_entity_id": _remote_entity_id,
		"remote_render_sample_count": _remote_render_sample_count,
		"remote_motion_sample_count": _remote_motion_sample_count,
		"remote_interpolated_sample_count": _remote_interpolated_sample_count,
		"remote_buffer_underrun_sample_count": _remote_buffer_underrun_sample_count,
		"remote_stall_episode_count": _remote_stall_episode_count,
		"remote_catch_up_episode_count": _remote_catch_up_episode_count,
		"remote_motion_discontinuity_count": (
			_remote_stall_episode_count + _remote_catch_up_episode_count
		),
		"remote_observed_seconds": _remote_observed_seconds,
		"remote_expected_motion_seconds": _remote_expected_motion_seconds,
		"remote_stalled_seconds": _remote_stalled_seconds,
		"remote_stall_ratio": _float_ratio(
			_remote_stalled_seconds,
			_remote_expected_motion_seconds
		),
		"remote_catch_up_seconds": _remote_catch_up_seconds,
		"remote_catch_up_ratio": _float_ratio(
			_remote_catch_up_seconds,
			_remote_expected_motion_seconds
		),
		"remote_buffer_underrun_seconds": _remote_buffer_underrun_seconds,
		"remote_buffer_underrun_ratio": _float_ratio(
			_remote_buffer_underrun_seconds,
			_remote_observed_seconds
		),
		"remote_total_rendered_distance": _remote_total_rendered_distance,
		"remote_average_rendered_speed": _average(
			_remote_total_rendered_speed,
			_remote_motion_sample_count
		),
		"remote_p95_rendered_speed": _percentile(_remote_rendered_speeds, 0.95),
		"remote_max_rendered_speed": _remote_max_rendered_speed,
		"remote_average_speed_error": _average(
			_remote_total_speed_error,
			_remote_motion_sample_count
		),
		"remote_p95_speed_error": _percentile(_remote_speed_errors, 0.95),
		"remote_max_speed_error": _remote_max_speed_error,
		"remote_p95_frame_distance": _percentile(_remote_frame_distances, 0.95),
		"remote_max_frame_distance": _remote_max_frame_distance,
	}

func _on_remote_transform_rendered(
	position: Vector3,
	expected_velocity: Vector3,
	render_mode: int,
	delta: float
) -> void:
	if not enabled or delta <= 0.0:
		return

	_remote_render_sample_count += 1
	_remote_observed_seconds += delta
	if render_mode == RemoteInterpolationBuffer.RenderMode.INTERPOLATING:
		_remote_interpolated_sample_count += 1
	if render_mode == RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN:
		_remote_buffer_underrun_sample_count += 1
		_remote_buffer_underrun_seconds += delta

	if not _remote_has_previous_position:
		_remote_previous_position = position
		_remote_has_previous_position = true
		return

	var frame_distance: float = position.distance_to(_remote_previous_position)
	var rendered_speed: float = frame_distance / delta
	var expected_speed: float = expected_velocity.length()
	_remote_previous_position = position
	_remote_total_rendered_distance += frame_distance
	_remote_max_frame_distance = maxf(_remote_max_frame_distance, frame_distance)
	_remote_frame_distances.append(frame_distance)

	var expected_movement: bool = expected_speed > remote_moving_speed_epsilon
	if not expected_movement:
		_remote_was_stalled = false
		_remote_was_catching_up = false
		return

	_remote_motion_sample_count += 1
	_remote_expected_motion_seconds += delta
	_remote_total_rendered_speed += rendered_speed
	_remote_max_rendered_speed = maxf(_remote_max_rendered_speed, rendered_speed)
	_remote_rendered_speeds.append(rendered_speed)
	var speed_error: float = absf(rendered_speed - expected_speed)
	_remote_total_speed_error += speed_error
	_remote_max_speed_error = maxf(_remote_max_speed_error, speed_error)
	_remote_speed_errors.append(speed_error)

	var stalled: bool = (
		render_mode == RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN
		or rendered_speed <= expected_speed * remote_stall_speed_ratio
	)
	var catching_up: bool = rendered_speed >= expected_speed * remote_catch_up_speed_ratio
	if stalled:
		_remote_stalled_seconds += delta
		if not _remote_was_stalled:
			_remote_stall_episode_count += 1
	if catching_up:
		_remote_catch_up_seconds += delta
		if not _remote_was_catching_up:
			_remote_catch_up_episode_count += 1
	_remote_was_stalled = stalled
	_remote_was_catching_up = catching_up

func _disconnect_remote_buffer() -> void:
	if is_instance_valid(_remote_buffer) and _remote_buffer.remote_transform_rendered.is_connected(
		_on_remote_transform_rendered
	):
		_remote_buffer.remote_transform_rendered.disconnect(_on_remote_transform_rendered)
	_remote_buffer = null

func _duration_seconds() -> float:
	if _started_usec <= 0:
		return 0.0
	var ended_usec: int = Time.get_ticks_usec() if enabled else _stopped_usec
	return maxf(float(ended_usec - _started_usec) / 1000000.0, 0.0)

func _rate(count: int, duration_seconds: float) -> float:
	if duration_seconds <= 0.0:
		return 0.0
	return float(count) / duration_seconds

func _ratio(numerator: int, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return float(numerator) / float(denominator)

func _float_ratio(numerator: float, denominator: float) -> float:
	if denominator <= 0.0:
		return 0.0
	return numerator / denominator

func _average(total: float, count: int) -> float:
	if count <= 0:
		return 0.0
	return total / float(count)

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var index: int = ceili(percentile * float(sorted_values.size())) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]
