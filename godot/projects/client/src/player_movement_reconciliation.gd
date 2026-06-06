class_name PlayerMovementReconciliation
extends Node

class Result:
	var enabled: bool = true
	var ack_seq: int = MovementSnapshotMsg.NO_PROCESSED_SEQ
	var has_ack: bool = false
	var missing_prediction_frame: bool = false
	var correction_applied: bool = false
	var ignored_tiny_drift: bool = false
	var position_drift: float = 0.0
	var pruned_count: int = 0
	var replayed_count: int = 0

	func reset(is_enabled: bool, acknowledged_seq: int) -> void:
		enabled = is_enabled
		ack_seq = acknowledged_seq
		has_ack = false
		missing_prediction_frame = false
		correction_applied = false
		ignored_tiny_drift = false
		position_drift = 0.0
		pruned_count = 0
		replayed_count = 0

@export var enabled: bool = true
@export_range(0.0, 1.0, 0.001, "or_greater") var position_drift_epsilon: float = 0.01
@export var debug_corrections: bool = false
@export var body: PhysicsBody
@export var player_input: PlayerInput

var _last_result: Result = Result.new()
var _replay_frames: Array[PredictionRingBuffer.Frame] = []
var _replay_input: MovementInputFrame = MovementInputFrame.new()

func reconcile(snapshot: MovementSnapshotMsg.EntitySnapshot, delta: float) -> Result:
	var result: Result = _last_result
	result.reset(enabled, snapshot.last_processed_movement_seq)

	if not enabled:
		return result

	if result.ack_seq == MovementSnapshotMsg.NO_PROCESSED_SEQ:
		return result

	result.has_ack = true
	if body == null or player_input == null:
		push_warning("PlayerMovementReconciliation requires body and player_input references")
		return result

	var acked_frame: PredictionRingBuffer.Frame = player_input.get_prediction_frame(result.ack_seq)
	if acked_frame == null:
		result.missing_prediction_frame = true
		result.pruned_count = player_input.prune_acknowledged_prediction_frames(result.ack_seq)
		return result

	var drift: Vector3 = snapshot.position - acked_frame.predicted_position
	result.position_drift = drift.length()
	result.pruned_count = player_input.prune_acknowledged_prediction_frames(result.ack_seq)

	if result.position_drift <= position_drift_epsilon:
		result.ignored_tiny_drift = true
		return result

	player_input.write_unacknowledged_prediction_frames(result.ack_seq, _replay_frames)
	_apply_authoritative_state(snapshot)
	for frame in _replay_frames:
		frame.write_input_frame(_replay_input)
		body.simulate(_replay_input, delta)
		frame.write_predicted_state(body)
		result.replayed_count += 1

	result.correction_applied = true
	if debug_corrections:
		_print_correction(snapshot, acked_frame, result)

	return result

func _apply_authoritative_state(snapshot: MovementSnapshotMsg.EntitySnapshot) -> void:
	var transform: Transform3D = body.global_transform
	transform.origin = snapshot.position
	transform.basis = Basis(snapshot.rotation.normalized())
	body.global_transform = transform
	body.velocity = snapshot.velocity

	if snapshot.is_on_floor:
		body.apply_floor_snap()

func _print_correction(
	snapshot: MovementSnapshotMsg.EntitySnapshot,
	acked_frame: PredictionRingBuffer.Frame,
	result: Result
) -> void:
	print(
		"reconcile seq=%d drift=%.3f replayed=%d predicted=%s authoritative=%s velocity=%s" %
		[
			result.ack_seq,
			result.position_drift,
			result.replayed_count,
			acked_frame.predicted_position,
			snapshot.position,
			snapshot.velocity,
		]
	)
