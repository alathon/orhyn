class_name RemoteInterpolationBuffer
extends Node

const SNAPSHOT_BUFFER_SIZE := 16
const INTERPOLATION_DELAY_SECONDS := 0.1
const MIN_INTERPOLATION_SNAPSHOTS := 3

class MovementSnapshot:
	var valid = false
	var time = 0.0
	var server_tick = -1
	var position = Vector3.ZERO
	var velocity = Vector3.ZERO
	var rotation = Quaternion.IDENTITY
	var is_on_floor = false

@onready var body: RemoteBody = %Body
@onready var model: Node3D = %Model

var _snapshots: Array = []
var _snapshot_write_index = 0
var _snapshot_count = 0

func _ready() -> void:
	_ensure_snapshot_buffer()

func _process(_delta: float) -> void:
	_interpolate_remote_transform()

func push_movement_snapshot(snapshot: MovementSnapshotMsg.EntitySnapshot) -> void:
	_ensure_snapshot_buffer()

	var buffer_was_empty = _snapshot_count == 0
	var buffered_snapshot: MovementSnapshot = _snapshots[_snapshot_write_index]
	buffered_snapshot.valid = true
	buffered_snapshot.time = _get_time_seconds()
	buffered_snapshot.server_tick = snapshot.server_tick
	buffered_snapshot.position = snapshot.position
	buffered_snapshot.velocity = snapshot.velocity
	buffered_snapshot.rotation = snapshot.rotation
	buffered_snapshot.is_on_floor = snapshot.is_on_floor

	_snapshot_write_index = (_snapshot_write_index + 1) % SNAPSHOT_BUFFER_SIZE
	_snapshot_count = mini(_snapshot_count + 1, SNAPSHOT_BUFFER_SIZE)

	if buffer_was_empty:
		_apply_snapshot(buffered_snapshot)

func _interpolate_remote_transform() -> void:
	if _snapshot_count == 0:
		return

	if _snapshot_count < MIN_INTERPOLATION_SNAPSHOTS:
		_apply_snapshot(_get_snapshot_by_age(_snapshot_count - 1))
		return

	var render_time = _get_time_seconds() - INTERPOLATION_DELAY_SECONDS
	var oldest_snapshot = _get_snapshot_by_age(0)
	if render_time <= oldest_snapshot.time:
		_apply_snapshot(oldest_snapshot)
		return

	var last_renderable_snapshot_offset = _snapshot_count - 2
	for offset in range(1, last_renderable_snapshot_offset + 1):
		var to_snapshot = _get_snapshot_by_age(offset)
		if render_time > to_snapshot.time:
			continue

		var from_snapshot = _get_snapshot_by_age(offset - 1)
		var duration = maxf(to_snapshot.time - from_snapshot.time, 0.001)
		var weight = clampf((render_time - from_snapshot.time) / duration, 0.0, 1.0)
		_apply_interpolated_snapshot(from_snapshot, to_snapshot, weight)
		return

	_apply_snapshot(_get_snapshot_by_age(last_renderable_snapshot_offset))

func _ensure_snapshot_buffer() -> void:
	if not _snapshots.is_empty():
		return

	_snapshots.resize(SNAPSHOT_BUFFER_SIZE)
	for i in SNAPSHOT_BUFFER_SIZE:
		_snapshots[i] = MovementSnapshot.new()

func _get_snapshot_by_age(offset_from_oldest: int) -> MovementSnapshot:
	var oldest_index = posmod(_snapshot_write_index - _snapshot_count, SNAPSHOT_BUFFER_SIZE)
	var snapshot_index = (oldest_index + offset_from_oldest) % SNAPSHOT_BUFFER_SIZE
	return _snapshots[snapshot_index]

func _apply_snapshot(snapshot: MovementSnapshot) -> void:
	_apply_remote_transform(snapshot.position, snapshot.rotation)

func _apply_interpolated_snapshot(from_snapshot: MovementSnapshot, to_snapshot: MovementSnapshot, weight: float) -> void:
	var position = from_snapshot.position.lerp(to_snapshot.position, weight)
	var rotation = from_snapshot.rotation.slerp(to_snapshot.rotation, weight).normalized()
	_apply_remote_transform(position, rotation)

func _apply_remote_transform(position: Vector3, rotation: Quaternion) -> void:
	var remote_transform = Transform3D(Basis(rotation), position)
	body.global_transform = remote_transform
	model.global_transform = remote_transform

func _get_time_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
