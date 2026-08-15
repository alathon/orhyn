class_name RemoteInterpolationBuffer
extends Node

const SNAPSHOT_BUFFER_SIZE: int = 16
const MIN_INTERPOLATION_SNAPSHOTS: int = 3

enum RenderMode {
	STARTUP,
	HOLDING_OLDEST,
	INTERPOLATING,
	EXTRAPOLATING,
	BUFFER_UNDERRUN,
}

class MovementSnapshot:
	var valid: bool = false
	var time: float = 0.0
	var server_tick: int = -1
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var is_on_floor: bool = false

class RenderObservation:
	var position: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
	var server_position: Vector3 = Vector3.ZERO
	var expected_velocity: Vector3 = Vector3.ZERO
	var render_mode: int = RenderMode.STARTUP
	var delta: float = 0.0
	var correction_distance: float = 0.0
	var correction_speed: float = 0.0
	var playout_delay_seconds: float = 0.0
	var target_playout_delay_seconds: float = 0.0
	var extrapolation_seconds: float = 0.0
	var hard_snap_applied: bool = false

signal remote_transform_rendered(observation: RenderObservation)

@export_group("Snapshot Timeline")
@export_range(0.001, 1.0, 0.001, "or_greater") var tick_seconds: float = \
	Ticker.DEFAULT_TICK_SECONDS
@export_range(0.0, 1.0, 0.01, "or_greater") var maximum_extrapolation_seconds: float = 0.20
@export_range(0.0, 10.0, 0.01, "or_greater") var maximum_interpolation_gap_seconds: float = 0.50
@export var use_velocity_interpolation: bool = true

@export_group("Adaptive Playout")
@export var adaptive_playout_enabled: bool = true
@export_range(0.0, 1.0, 0.001, "or_greater") var adaptive_delay_activation_seconds: float = 0.025
@export_range(0.0, 1.0, 0.01, "or_greater") var maximum_adaptive_delay_seconds: float = 0.20
@export_range(1.0, 10.0, 0.1, "or_greater") var jitter_delay_multiplier: float = 4.0
@export_range(0.0, 1.0, 0.01) var jitter_smoothing_weight: float = 0.20
@export_range(0.0, 1.0, 0.001, "or_greater") var adaptive_delay_decay_per_second: float = 0.025
@export_range(0.0, 10.0, 0.1, "or_greater") var playback_rate_gain: float = 2.0
@export_range(0.0, 0.5, 0.01) var maximum_playback_rate_adjustment: float = 0.20

@export_group("Presentation Correction")
@export_range(0.0, 1.0, 0.001, "or_greater") var correction_dead_zone: float = 0.01
@export_range(0.001, 2.0, 0.001, "or_greater") var slow_correction_half_life: float = 0.15
@export_range(0.001, 2.0, 0.001, "or_greater") var fast_correction_half_life: float = 0.05
@export_range(0.001, 100.0, 0.01, "or_greater") var fast_correction_distance: float = 1.0
@export_range(0.0, 100.0, 0.1, "or_greater") var maximum_correction_speed: float = 5.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var rapid_correction_distance: float = 10.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var rapid_correction_full_speed_distance: float = 20.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_rapid_correction_speed: float = 50.0
# Normal network error is always smoothed; only a gross world-state discontinuity may snap.
@export_range(0.0, 1000.0, 1.0, "or_greater") var teleport_distance: float = 100.0
@export_range(0.001, 2.0, 0.001, "or_greater") var rotation_half_life: float = 0.08

@onready var body: RemoteBody = %Body
@onready var model: Node3D = %Model

var _snapshots: Array[MovementSnapshot] = []
var _snapshot_write_index: int = 0
var _snapshot_count: int = 0
var _latest_server_tick: int = -1
var _snapshot_generation: int = 0
var _processed_snapshot_generation: int = -1
var _rejected_stale_snapshot_count: int = 0

var _has_latest_arrival: bool = false
var _latest_arrival_time: float = 0.0
var _arrival_jitter_seconds: float = 0.0
var _desired_playout_delay_seconds: float = 0.0
var _current_target_playout_delay_seconds: float = 0.0
var _playback_rate: float = 1.0

var _has_render_time: bool = false
var _render_server_time: float = 0.0
var _has_render_sample: bool = false
var _sample_position: Vector3 = Vector3.ZERO
var _sample_velocity: Vector3 = Vector3.ZERO
var _sample_rotation: Quaternion = Quaternion.IDENTITY
var _sample_render_mode: int = RenderMode.STARTUP
var _sample_extrapolation_seconds: float = 0.0

var _presentation_offset: Vector3 = Vector3.ZERO
var _last_sample_velocity: Vector3 = Vector3.ZERO
var _render_observation: RenderObservation = RenderObservation.new()

func _ready() -> void:
	_ensure_snapshot_buffer()

func _process(delta: float) -> void:
	advance(delta)

func push_movement_snapshot(
	snapshot: MovementSnapshotMsg.EntitySnapshot,
	arrival_time_seconds: float = -1.0
) -> bool:
	_ensure_snapshot_buffer()
	var arrival_time: float = arrival_time_seconds
	if arrival_time < 0.0:
		arrival_time = _get_time_seconds()

	if _latest_server_tick >= 0 and snapshot.server_tick <= _latest_server_tick:
		_rejected_stale_snapshot_count += 1
		_record_reordered_arrival()
		return false

	var tick_gap: int = snapshot.server_tick - _latest_server_tick \
		if _latest_server_tick >= 0 else 0
	_record_newest_arrival(snapshot.server_tick, arrival_time)
	body.apply_authoritative_snapshot(snapshot)
	if maximum_interpolation_gap_seconds > 0.0 \
			and float(tick_gap) * tick_seconds > maximum_interpolation_gap_seconds:
		_reset_snapshot_timeline()

	var buffered_snapshot: MovementSnapshot = _snapshots[_snapshot_write_index]
	buffered_snapshot.valid = true
	buffered_snapshot.time = float(snapshot.server_tick) * tick_seconds
	buffered_snapshot.server_tick = snapshot.server_tick
	buffered_snapshot.position = snapshot.position
	buffered_snapshot.velocity = snapshot.velocity
	buffered_snapshot.rotation = snapshot.rotation.normalized()
	buffered_snapshot.is_on_floor = snapshot.is_on_floor

	_snapshot_write_index = (_snapshot_write_index + 1) % SNAPSHOT_BUFFER_SIZE
	_snapshot_count = mini(_snapshot_count + 1, SNAPSHOT_BUFFER_SIZE)
	_latest_server_tick = snapshot.server_tick
	_snapshot_generation += 1

	if not _has_render_time:
		_render_server_time = buffered_snapshot.time
		_has_render_time = true
	return true

func advance(delta: float) -> void:
	if _snapshot_count == 0 or delta <= 0.0:
		return

	_update_adaptive_playout_delay(delta)
	_advance_render_clock(delta)
	_sample_at_render_time()
	_apply_visual_sample(delta)

func is_ready_for_observation() -> bool:
	return _snapshot_count >= MIN_INTERPOLATION_SNAPSHOTS

func get_rejected_stale_snapshot_count() -> int:
	return _rejected_stale_snapshot_count

func get_arrival_jitter_seconds() -> float:
	return _arrival_jitter_seconds

func get_target_playout_delay_seconds() -> float:
	return _current_target_playout_delay_seconds

func get_playback_rate() -> float:
	return _playback_rate

func _record_newest_arrival(server_tick: int, arrival_time: float) -> void:
	if _has_latest_arrival:
		var tick_delta: int = server_tick - _latest_server_tick
		var observed_interval: float = maxf(arrival_time - _latest_arrival_time, 0.0)
		var expected_interval: float = float(tick_delta) * tick_seconds
		var deviation: float = absf(observed_interval - expected_interval)
		if tick_delta > 1:
			deviation = maxf(deviation, float(tick_delta - 1) * tick_seconds)
		_arrival_jitter_seconds = lerpf(
			_arrival_jitter_seconds,
			deviation,
			jitter_smoothing_weight
		)
		_update_desired_playout_delay()
	_has_latest_arrival = true
	_latest_arrival_time = arrival_time

func _record_reordered_arrival() -> void:
	_arrival_jitter_seconds = maxf(_arrival_jitter_seconds, tick_seconds)
	_update_desired_playout_delay()

func _update_desired_playout_delay() -> void:
	if not adaptive_playout_enabled:
		_desired_playout_delay_seconds = 0.0
		return
	var desired_delay: float = minf(
		_arrival_jitter_seconds * jitter_delay_multiplier,
		maximum_adaptive_delay_seconds
	)
	_desired_playout_delay_seconds = desired_delay \
		if desired_delay >= adaptive_delay_activation_seconds else 0.0

func _update_adaptive_playout_delay(delta: float) -> void:
	if _desired_playout_delay_seconds >= _current_target_playout_delay_seconds:
		_current_target_playout_delay_seconds = _desired_playout_delay_seconds
		return
	_current_target_playout_delay_seconds = move_toward(
		_current_target_playout_delay_seconds,
		_desired_playout_delay_seconds,
		adaptive_delay_decay_per_second * delta
	)

func _advance_render_clock(delta: float) -> void:
	var oldest_snapshot: MovementSnapshot = _get_snapshot_by_age(0)
	var newest_snapshot: MovementSnapshot = _get_snapshot_by_age(_snapshot_count - 1)
	if _render_server_time < oldest_snapshot.time:
		_render_server_time = maxf(
			oldest_snapshot.time,
			newest_snapshot.time - _current_target_playout_delay_seconds
		)

	_playback_rate = 1.0
	if _current_target_playout_delay_seconds >= adaptive_delay_activation_seconds:
		var buffer_depth: float = newest_snapshot.time - _render_server_time
		var buffer_error: float = buffer_depth - _current_target_playout_delay_seconds
		var rate_adjustment: float = clampf(
			buffer_error * playback_rate_gain,
			-maximum_playback_rate_adjustment,
			maximum_playback_rate_adjustment
		)
		_playback_rate += rate_adjustment

	_render_server_time += delta * _playback_rate
	_render_server_time = minf(
		_render_server_time,
		newest_snapshot.time + maximum_extrapolation_seconds
	)

func _sample_at_render_time() -> void:
	var oldest_snapshot: MovementSnapshot = _get_snapshot_by_age(0)
	var newest_snapshot: MovementSnapshot = _get_snapshot_by_age(_snapshot_count - 1)
	_sample_extrapolation_seconds = 0.0

	if _render_server_time <= oldest_snapshot.time:
		_copy_sample(oldest_snapshot, RenderMode.HOLDING_OLDEST)
		return

	var offset: int = 1
	while offset < _snapshot_count:
		var to_snapshot: MovementSnapshot = _get_snapshot_by_age(offset)
		if _render_server_time > to_snapshot.time:
			offset += 1
			continue
		var from_snapshot: MovementSnapshot = _get_snapshot_by_age(offset - 1)
		_interpolate_sample(from_snapshot, to_snapshot)
		return

	var extrapolation_seconds: float = maxf(
		_render_server_time - newest_snapshot.time,
		0.0
	)
	_sample_extrapolation_seconds = minf(
		extrapolation_seconds,
		maximum_extrapolation_seconds
	)
	_sample_position = newest_snapshot.position \
		+ newest_snapshot.velocity * _sample_extrapolation_seconds
	_sample_velocity = newest_snapshot.velocity
	_sample_rotation = newest_snapshot.rotation
	_sample_render_mode = RenderMode.EXTRAPOLATING \
		if extrapolation_seconds < maximum_extrapolation_seconds \
		else RenderMode.BUFFER_UNDERRUN

func _copy_sample(snapshot: MovementSnapshot, render_mode: int) -> void:
	_sample_position = snapshot.position
	_sample_velocity = snapshot.velocity
	_sample_rotation = snapshot.rotation
	_sample_render_mode = render_mode

func _interpolate_sample(
	from_snapshot: MovementSnapshot,
	to_snapshot: MovementSnapshot
) -> void:
	var duration: float = maxf(to_snapshot.time - from_snapshot.time, 0.001)
	var weight: float = clampf(
		(_render_server_time - from_snapshot.time) / duration,
		0.0,
		1.0
	)
	if use_velocity_interpolation:
		_sample_position = _hermite_position(from_snapshot, to_snapshot, weight, duration)
		_sample_velocity = _hermite_velocity(from_snapshot, to_snapshot, weight, duration)
	else:
		_sample_position = from_snapshot.position.lerp(to_snapshot.position, weight)
		_sample_velocity = from_snapshot.velocity.lerp(to_snapshot.velocity, weight)
	_sample_rotation = from_snapshot.rotation.slerp(to_snapshot.rotation, weight).normalized()
	_sample_render_mode = RenderMode.INTERPOLATING

func _hermite_position(
	from_snapshot: MovementSnapshot,
	to_snapshot: MovementSnapshot,
	weight: float,
	duration: float
) -> Vector3:
	var weight_squared: float = weight * weight
	var weight_cubed: float = weight_squared * weight
	var from_weight: float = 2.0 * weight_cubed - 3.0 * weight_squared + 1.0
	var from_tangent_weight: float = weight_cubed - 2.0 * weight_squared + weight
	var to_weight: float = -2.0 * weight_cubed + 3.0 * weight_squared
	var to_tangent_weight: float = weight_cubed - weight_squared
	return (
		from_snapshot.position * from_weight
		+ from_snapshot.velocity * duration * from_tangent_weight
		+ to_snapshot.position * to_weight
		+ to_snapshot.velocity * duration * to_tangent_weight
	)

func _hermite_velocity(
	from_snapshot: MovementSnapshot,
	to_snapshot: MovementSnapshot,
	weight: float,
	duration: float
) -> Vector3:
	var weight_squared: float = weight * weight
	var from_weight: float = 6.0 * weight_squared - 6.0 * weight
	var from_tangent_weight: float = 3.0 * weight_squared - 4.0 * weight + 1.0
	var to_weight: float = -6.0 * weight_squared + 6.0 * weight
	var to_tangent_weight: float = 3.0 * weight_squared - 2.0 * weight
	return (
		from_snapshot.position * from_weight / duration
		+ from_snapshot.velocity * from_tangent_weight
		+ to_snapshot.position * to_weight / duration
		+ to_snapshot.velocity * to_tangent_weight
	)

func _apply_visual_sample(delta: float) -> void:
	var hard_snap_applied: bool = false
	if not _has_render_sample:
		var continued_position: Vector3 = model.global_position \
			+ _sample_velocity * delta * _playback_rate
		_presentation_offset = continued_position - _sample_position
		_has_render_sample = true
	elif _processed_snapshot_generation != _snapshot_generation:
		var continued_position: Vector3 = model.global_position \
			+ _last_sample_velocity * delta * _playback_rate
		_presentation_offset = continued_position - _sample_position

	if teleport_distance > 0.0 and _presentation_offset.length() >= teleport_distance:
		_presentation_offset = Vector3.ZERO
		hard_snap_applied = true

	var correction_step_distance: float = _decay_presentation_offset(delta)
	var visual_position: Vector3 = _sample_position + _presentation_offset
	var rotation_weight: float = 1.0 - pow(0.5, delta / rotation_half_life)
	var visual_rotation: Quaternion = model.global_basis.get_rotation_quaternion().slerp(
		_sample_rotation,
		rotation_weight
	).normalized()
	model.global_transform = Transform3D(Basis(visual_rotation), visual_position)

	_processed_snapshot_generation = _snapshot_generation
	_last_sample_velocity = _sample_velocity
	if has_connections(&"remote_transform_rendered"):
		_emit_render_observation(
			visual_position,
			correction_step_distance / delta,
			hard_snap_applied,
			delta
		)

func _decay_presentation_offset(delta: float) -> float:
	var distance: float = _presentation_offset.length()
	if distance <= correction_dead_zone:
		var discarded_distance: float = distance
		_presentation_offset = Vector3.ZERO
		return discarded_distance

	var distance_weight: float = clampf(distance / fast_correction_distance, 0.0, 1.0)
	var half_life: float = lerpf(
		slow_correction_half_life,
		fast_correction_half_life,
		distance_weight
	)
	var decay_weight: float = 1.0 - pow(0.5, delta / half_life)
	var desired_offset: Vector3 = _presentation_offset.lerp(Vector3.ZERO, decay_weight)
	var correction_step: Vector3 = _presentation_offset - desired_offset
	var correction_speed_limit: float = _correction_speed_limit(distance)
	var maximum_step: float = correction_speed_limit * delta
	if correction_speed_limit > 0.0 and correction_step.length() > maximum_step:
		correction_step = correction_step.normalized() * maximum_step
	_presentation_offset -= correction_step
	return correction_step.length()

func _correction_speed_limit(distance: float) -> float:
	if maximum_correction_speed <= 0.0:
		return 0.0
	if rapid_correction_distance <= 0.0 \
			or distance <= rapid_correction_distance \
			or maximum_rapid_correction_speed <= maximum_correction_speed:
		return maximum_correction_speed
	var full_speed_distance: float = maxf(
		rapid_correction_full_speed_distance,
		rapid_correction_distance + 0.001
	)
	var rapid_weight: float = smoothstep(
		rapid_correction_distance,
		full_speed_distance,
		distance
	)
	return lerpf(
		maximum_correction_speed,
		maximum_rapid_correction_speed,
		rapid_weight
	)

func _emit_render_observation(
	visual_position: Vector3,
	correction_speed: float,
	hard_snap_applied: bool,
	delta: float
) -> void:
	var newest_snapshot: MovementSnapshot = _get_snapshot_by_age(_snapshot_count - 1)
	_render_observation.position = visual_position
	_render_observation.target_position = _sample_position
	_render_observation.server_position = body.global_position
	_render_observation.expected_velocity = _sample_velocity
	_render_observation.render_mode = _sample_render_mode
	_render_observation.delta = delta
	_render_observation.correction_distance = _presentation_offset.length()
	_render_observation.correction_speed = correction_speed
	_render_observation.playout_delay_seconds = maxf(
		newest_snapshot.time - _render_server_time,
		0.0
	)
	_render_observation.target_playout_delay_seconds = \
		_current_target_playout_delay_seconds
	_render_observation.extrapolation_seconds = _sample_extrapolation_seconds
	_render_observation.hard_snap_applied = hard_snap_applied
	remote_transform_rendered.emit(_render_observation)

func _ensure_snapshot_buffer() -> void:
	if not _snapshots.is_empty():
		return
	_snapshots.resize(SNAPSHOT_BUFFER_SIZE)
	for index: int in SNAPSHOT_BUFFER_SIZE:
		_snapshots[index] = MovementSnapshot.new()

func _reset_snapshot_timeline() -> void:
	_snapshot_write_index = 0
	_snapshot_count = 0
	_has_render_time = false

func _get_snapshot_by_age(offset_from_oldest: int) -> MovementSnapshot:
	var oldest_index: int = posmod(
		_snapshot_write_index - _snapshot_count,
		SNAPSHOT_BUFFER_SIZE
	)
	var snapshot_index: int = (oldest_index + offset_from_oldest) % SNAPSHOT_BUFFER_SIZE
	return _snapshots[snapshot_index]

func _get_time_seconds() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
