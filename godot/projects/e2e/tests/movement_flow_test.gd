extends E2ETestCase

const MOVE_ACTION: StringName = &"move_forward"
const MIN_MOVEMENT_DISTANCE: float = 0.25
const MIN_ACK_SEQ: int = 2

func run(session: E2ESession, _config: Dictionary = {}) -> Dictionary:
	var origin: Vector3 = session.get_local_position()
	session.clear_movement_snapshots()

	Input.action_press(MOVE_ACTION)
	var snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_local_movement_snapshot(
		MIN_ACK_SEQ,
		timeout_seconds
	)
	Input.action_release(MOVE_ACTION)

	if snapshot == null:
		return failed("wait_for_snapshot", "Timed out waiting for authoritative movement snapshot.", {
			"min_processed_seq": MIN_ACK_SEQ,
			"origin": str(origin),
			"current": str(session.get_local_position()),
		})

	if not await session.wait_for_local_position_changed(origin, MIN_MOVEMENT_DISTANCE, timeout_seconds):
		return failed("wait_for_position_change", "Local player did not move after authoritative snapshots.", {
			"origin": str(origin),
			"current": str(session.get_local_position()),
			"last_processed_seq": snapshot.last_processed_movement_seq,
		})

	return passed({
		"origin": str(origin),
		"current": str(session.get_local_position()),
		"last_processed_seq": snapshot.last_processed_movement_seq,
	})
