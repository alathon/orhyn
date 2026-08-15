class_name ClientNetworkMetricsCollector
extends Node

const MAX_METRIC_SAMPLE_COUNT: int = 8192

class FixedFloatSamples:
	var values: PackedFloat64Array = PackedFloat64Array()
	var count: int = 0

	func _init(capacity: int) -> void:
		values.resize(capacity)

	func reset() -> void:
		count = 0

	func record(value: float) -> bool:
		if count >= values.size():
			return false
		values[count] = value
		count += 1
		return true

	func percentile(percentile_value: float) -> float:
		if count <= 0:
			return 0.0
		var sorted_values: PackedFloat64Array = values.duplicate()
		sorted_values.resize(count)
		sorted_values.sort()
		var index: int = ceili(percentile_value * float(count)) - 1
		return sorted_values[clampi(index, 0, count - 1)]

class RemoteMotionState:
	var previous_position: Vector3 = Vector3.ZERO
	var has_previous_position: bool = false
	var was_stalled: bool = false
	var was_catching_up: bool = false

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
var _ack_position_drifts: FixedFloatSamples = null
var _body_correction_distances: FixedFloatSamples = null
var _dropped_metric_value_count: int = 0
var _collect_local_reconciliation: bool = true
var _metric_sample_capacity: int = MAX_METRIC_SAMPLE_COUNT
var _sample_storage_capacity: int = 0
var _remote_buffers: Array[RemoteInterpolationBuffer] = []
var _remote_buffer_callbacks: Array[Callable] = []
var _remote_motion_states: Array[RemoteMotionState] = []
var _remote_entity_id: int = -1
var _remote_entity_count: int = 0
var _remote_render_sample_count: int = 0
var _remote_motion_sample_count: int = 0
var _remote_interpolated_sample_count: int = 0
var _remote_extrapolated_sample_count: int = 0
var _remote_buffer_underrun_sample_count: int = 0
var _remote_stall_episode_count: int = 0
var _remote_catch_up_episode_count: int = 0
var _remote_hard_snap_count: int = 0
var _remote_rejected_stale_snapshot_count: int = 0
var _remote_observed_seconds: float = 0.0
var _remote_expected_motion_seconds: float = 0.0
var _remote_extrapolated_seconds: float = 0.0
var _remote_stalled_seconds: float = 0.0
var _remote_catch_up_seconds: float = 0.0
var _remote_buffer_underrun_seconds: float = 0.0
var _remote_total_rendered_distance: float = 0.0
var _remote_total_rendered_speed: float = 0.0
var _remote_total_speed_error: float = 0.0
var _remote_max_rendered_speed: float = 0.0
var _remote_max_speed_error: float = 0.0
var _remote_max_frame_distance: float = 0.0
var _remote_total_correction_distance: float = 0.0
var _remote_max_correction_distance: float = 0.0
var _remote_total_correction_speed: float = 0.0
var _remote_max_correction_speed: float = 0.0
var _remote_total_playout_delay: float = 0.0
var _remote_max_playout_delay: float = 0.0
var _remote_total_target_playout_delay: float = 0.0
var _remote_max_target_playout_delay: float = 0.0
var _remote_rendered_speeds: FixedFloatSamples = null
var _remote_speed_errors: FixedFloatSamples = null
var _remote_frame_distances: FixedFloatSamples = null
var _remote_correction_distances: FixedFloatSamples = null
var _remote_correction_speeds: FixedFloatSamples = null
var _remote_playout_delays: FixedFloatSamples = null

func _ready() -> void:
	if enabled:
		reset_collection()

func start_collection() -> void:
	_disconnect_remote_buffers()
	enabled = true
	reset_collection()
	_collect_local_reconciliation = true

func start_remote_motion_collection(remote: RemoteEntity) -> bool:
	var remotes: Array[RemoteEntity] = []
	remotes.append(remote)
	return start_remote_motion_collection_many(remotes)

func start_remote_motion_collection_many(remotes: Array[RemoteEntity]) -> bool:
	if remotes.is_empty():
		return false
	for remote: RemoteEntity in remotes:
		if remote == null or remote.interpolation_buffer == null:
			return false
	start_collection()
	_collect_local_reconciliation = false
	_remote_entity_count = remotes.size()
	_remote_entity_id = remotes[0].entity_id if remotes.size() == 1 else -1
	for remote: RemoteEntity in remotes:
		var buffer: RemoteInterpolationBuffer = remote.interpolation_buffer
		var state_index: int = _remote_motion_states.size()
		var callback: Callable = _on_remote_transform_rendered.bind(state_index)
		_remote_buffers.append(buffer)
		_remote_buffer_callbacks.append(callback)
		_remote_motion_states.append(RemoteMotionState.new())
		buffer.remote_transform_rendered.connect(callback)
	return true

func set_metric_sample_capacity(sample_capacity: int) -> bool:
	if enabled or sample_capacity <= 0:
		return false
	_metric_sample_capacity = sample_capacity
	return true

func stop_collection() -> void:
	if enabled:
		_stopped_usec = Time.get_ticks_usec()
	_remote_rejected_stale_snapshot_count = 0
	for buffer: RemoteInterpolationBuffer in _remote_buffers:
		if is_instance_valid(buffer):
			_remote_rejected_stale_snapshot_count += \
				buffer.get_rejected_stale_snapshot_count()
	enabled = false
	_disconnect_remote_buffers()

func reset_collection() -> void:
	_ensure_sample_storage()
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
	_ack_position_drifts.reset()
	_body_correction_distances.reset()
	_dropped_metric_value_count = 0
	_remote_entity_id = -1
	_remote_entity_count = 0
	_remote_render_sample_count = 0
	_remote_motion_sample_count = 0
	_remote_interpolated_sample_count = 0
	_remote_extrapolated_sample_count = 0
	_remote_buffer_underrun_sample_count = 0
	_remote_stall_episode_count = 0
	_remote_catch_up_episode_count = 0
	_remote_hard_snap_count = 0
	_remote_rejected_stale_snapshot_count = 0
	_remote_observed_seconds = 0.0
	_remote_expected_motion_seconds = 0.0
	_remote_extrapolated_seconds = 0.0
	_remote_stalled_seconds = 0.0
	_remote_catch_up_seconds = 0.0
	_remote_buffer_underrun_seconds = 0.0
	_remote_total_rendered_distance = 0.0
	_remote_total_rendered_speed = 0.0
	_remote_total_speed_error = 0.0
	_remote_max_rendered_speed = 0.0
	_remote_max_speed_error = 0.0
	_remote_max_frame_distance = 0.0
	_remote_total_correction_distance = 0.0
	_remote_max_correction_distance = 0.0
	_remote_total_correction_speed = 0.0
	_remote_max_correction_speed = 0.0
	_remote_total_playout_delay = 0.0
	_remote_max_playout_delay = 0.0
	_remote_total_target_playout_delay = 0.0
	_remote_max_target_playout_delay = 0.0
	_remote_rendered_speeds.reset()
	_remote_speed_errors.reset()
	_remote_frame_distances.reset()
	_remote_correction_distances.reset()
	_remote_correction_speeds.reset()
	_remote_playout_delays.reset()

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
	_record_metric_value(_ack_position_drifts, result.position_drift)
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
	_record_metric_value(_body_correction_distances, result.body_correction_distance)

func snapshot() -> Dictionary:
	var duration_seconds: float = _duration_seconds()
	return {
		"enabled": enabled,
		"duration_seconds": duration_seconds,
		"metric_sample_capacity": _metric_sample_capacity,
		"dropped_metric_value_count": _dropped_metric_value_count,
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
		"p95_ack_position_drift": _sample_percentile(_ack_position_drifts, 0.95),
		"max_ack_position_drift": _max_ack_position_drift,
		"total_body_correction_distance": _total_body_correction_distance,
		"average_body_correction_distance": _average(
			_total_body_correction_distance,
			_correction_count
		),
		"p95_body_correction_distance": _sample_percentile(
			_body_correction_distances,
			0.95
		),
		"max_body_correction_distance": _max_body_correction_distance,
		"remote_entity_id": _remote_entity_id,
		"remote_entity_count": _remote_entity_count,
		"remote_render_sample_count": _remote_render_sample_count,
		"remote_motion_sample_count": _remote_motion_sample_count,
		"remote_interpolated_sample_count": _remote_interpolated_sample_count,
		"remote_extrapolated_sample_count": _remote_extrapolated_sample_count,
		"remote_buffer_underrun_sample_count": _remote_buffer_underrun_sample_count,
		"remote_stall_episode_count": _remote_stall_episode_count,
		"remote_stall_episodes_per_minute": 60.0 * _rate(
			_remote_stall_episode_count,
			_remote_expected_motion_seconds
		),
		"remote_catch_up_episode_count": _remote_catch_up_episode_count,
		"remote_catch_up_episodes_per_minute": 60.0 * _rate(
			_remote_catch_up_episode_count,
			_remote_expected_motion_seconds
		),
		"remote_motion_discontinuity_count": (
			_remote_stall_episode_count + _remote_catch_up_episode_count
		),
		"remote_motion_discontinuities_per_minute": 60.0 * _rate(
			_remote_stall_episode_count + _remote_catch_up_episode_count,
			_remote_expected_motion_seconds
		),
		"remote_hard_snap_count": _remote_hard_snap_count,
		"remote_observed_seconds": _remote_observed_seconds,
		"remote_expected_motion_seconds": _remote_expected_motion_seconds,
		"remote_extrapolated_seconds": _remote_extrapolated_seconds,
		"remote_extrapolated_ratio": _float_ratio(
			_remote_extrapolated_seconds,
			_remote_observed_seconds
		),
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
		"remote_p95_rendered_speed": _sample_percentile(_remote_rendered_speeds, 0.95),
		"remote_max_rendered_speed": _remote_max_rendered_speed,
		"remote_average_speed_error": _average(
			_remote_total_speed_error,
			_remote_motion_sample_count
		),
		"remote_p95_speed_error": _sample_percentile(_remote_speed_errors, 0.95),
		"remote_max_speed_error": _remote_max_speed_error,
		"remote_p95_frame_distance": _sample_percentile(_remote_frame_distances, 0.95),
		"remote_max_frame_distance": _remote_max_frame_distance,
		"remote_average_correction_distance": _average(
			_remote_total_correction_distance,
			_remote_render_sample_count
		),
		"remote_p95_correction_distance": _sample_percentile(
			_remote_correction_distances,
			0.95
		),
		"remote_max_correction_distance": _remote_max_correction_distance,
		"remote_average_correction_speed": _average(
			_remote_total_correction_speed,
			_remote_render_sample_count
		),
		"remote_p95_correction_speed": _sample_percentile(_remote_correction_speeds, 0.95),
		"remote_max_correction_speed": _remote_max_correction_speed,
		"remote_average_playout_delay": _average(
			_remote_total_playout_delay,
			_remote_render_sample_count
		),
		"remote_p95_playout_delay": _sample_percentile(_remote_playout_delays, 0.95),
		"remote_max_playout_delay": _remote_max_playout_delay,
		"remote_average_target_playout_delay": _average(
			_remote_total_target_playout_delay,
			_remote_render_sample_count
		),
		"remote_max_target_playout_delay": _remote_max_target_playout_delay,
		"remote_rejected_stale_snapshot_count": _remote_rejected_stale_snapshot_count,
	}

func _on_remote_transform_rendered(
	observation: RemoteInterpolationBuffer.RenderObservation,
	state_index: int
) -> void:
	var delta: float = observation.delta
	if not enabled or delta <= 0.0 \
			or state_index < 0 or state_index >= _remote_motion_states.size():
		return
	var motion_state: RemoteMotionState = _remote_motion_states[state_index]

	_remote_render_sample_count += 1
	_remote_observed_seconds += delta
	if observation.render_mode == RemoteInterpolationBuffer.RenderMode.INTERPOLATING:
		_remote_interpolated_sample_count += 1
	if observation.render_mode == RemoteInterpolationBuffer.RenderMode.EXTRAPOLATING:
		_remote_extrapolated_sample_count += 1
		_remote_extrapolated_seconds += delta
	if observation.render_mode == RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN:
		_remote_buffer_underrun_sample_count += 1
		_remote_buffer_underrun_seconds += delta
	if observation.hard_snap_applied:
		_remote_hard_snap_count += 1

	_remote_total_correction_distance += observation.correction_distance
	_remote_max_correction_distance = maxf(
		_remote_max_correction_distance,
		observation.correction_distance
	)
	_record_metric_value(_remote_correction_distances, observation.correction_distance)
	_remote_total_correction_speed += observation.correction_speed
	_remote_max_correction_speed = maxf(
		_remote_max_correction_speed,
		observation.correction_speed
	)
	_record_metric_value(_remote_correction_speeds, observation.correction_speed)
	_remote_total_playout_delay += observation.playout_delay_seconds
	_remote_max_playout_delay = maxf(
		_remote_max_playout_delay,
		observation.playout_delay_seconds
	)
	_record_metric_value(_remote_playout_delays, observation.playout_delay_seconds)
	_remote_total_target_playout_delay += observation.target_playout_delay_seconds
	_remote_max_target_playout_delay = maxf(
		_remote_max_target_playout_delay,
		observation.target_playout_delay_seconds
	)

	if not motion_state.has_previous_position:
		motion_state.previous_position = observation.position
		motion_state.has_previous_position = true
		return

	var frame_distance: float = observation.position.distance_to(motion_state.previous_position)
	var rendered_speed: float = frame_distance / delta
	var expected_speed: float = observation.expected_velocity.length()
	motion_state.previous_position = observation.position
	_remote_total_rendered_distance += frame_distance
	_remote_max_frame_distance = maxf(_remote_max_frame_distance, frame_distance)
	_record_metric_value(_remote_frame_distances, frame_distance)

	var expected_movement: bool = expected_speed > remote_moving_speed_epsilon
	if not expected_movement:
		motion_state.was_stalled = false
		motion_state.was_catching_up = false
		return

	_remote_motion_sample_count += 1
	_remote_expected_motion_seconds += delta
	_remote_total_rendered_speed += rendered_speed
	_remote_max_rendered_speed = maxf(_remote_max_rendered_speed, rendered_speed)
	_record_metric_value(_remote_rendered_speeds, rendered_speed)
	var speed_error: float = absf(rendered_speed - expected_speed)
	_remote_total_speed_error += speed_error
	_remote_max_speed_error = maxf(_remote_max_speed_error, speed_error)
	_record_metric_value(_remote_speed_errors, speed_error)

	var stalled: bool = (
		observation.render_mode == RemoteInterpolationBuffer.RenderMode.BUFFER_UNDERRUN
		or rendered_speed <= expected_speed * remote_stall_speed_ratio
	)
	var catching_up: bool = rendered_speed >= expected_speed * remote_catch_up_speed_ratio
	if stalled:
		_remote_stalled_seconds += delta
		if not motion_state.was_stalled:
			_remote_stall_episode_count += 1
	if catching_up:
		_remote_catch_up_seconds += delta
		if not motion_state.was_catching_up:
			_remote_catch_up_episode_count += 1
	motion_state.was_stalled = stalled
	motion_state.was_catching_up = catching_up

func _disconnect_remote_buffers() -> void:
	for index: int in range(_remote_buffers.size()):
		var buffer: RemoteInterpolationBuffer = _remote_buffers[index]
		var callback: Callable = _remote_buffer_callbacks[index]
		if is_instance_valid(buffer) \
				and buffer.remote_transform_rendered.is_connected(callback):
			buffer.remote_transform_rendered.disconnect(callback)
	_remote_buffers.clear()
	_remote_buffer_callbacks.clear()
	_remote_motion_states.clear()

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

func _ensure_sample_storage() -> void:
	if _ack_position_drifts != null and _sample_storage_capacity == _metric_sample_capacity:
		return
	_sample_storage_capacity = _metric_sample_capacity
	_ack_position_drifts = FixedFloatSamples.new(_sample_storage_capacity)
	_body_correction_distances = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_rendered_speeds = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_speed_errors = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_frame_distances = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_correction_distances = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_correction_speeds = FixedFloatSamples.new(_sample_storage_capacity)
	_remote_playout_delays = FixedFloatSamples.new(_sample_storage_capacity)

func _record_metric_value(samples: FixedFloatSamples, value: float) -> void:
	if samples == null or not samples.record(value):
		_dropped_metric_value_count += 1

func _sample_percentile(samples: FixedFloatSamples, percentile: float) -> float:
	if samples == null:
		return 0.0
	return samples.percentile(percentile)
