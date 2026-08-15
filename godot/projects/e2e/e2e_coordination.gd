class_name E2ECoordination
extends RefCounted

const ACTOR_READY_FILE: String = "actor-ready.json"
const ACTOR_AUTHORITATIVE_MOVEMENT_FILE: String = "actor-authoritative-movement.json"
const ACTOR_SEES_OBSERVER_FILE: String = "actor-sees-observer.json"
const ACTOR_SEES_JOINER_FILE: String = "actor-sees-joiner.json"
const OBSERVER_READY_FILE: String = "observer-ready.json"
const OBSERVER_SEES_ACTOR_FILE: String = "observer-sees-actor.json"
const OBSERVER_SEES_JOINER_FILE: String = "observer-sees-joiner.json"
const OBSERVER_ACTIONS_OBSERVED_FILE: String = "observer-actions-observed.json"
const FIRST_TWO_CLIENTS_VERIFIED_FILE: String = "first-two-clients-verified.json"
const JOINER_READY_FILE: String = "joiner-ready.json"
const JOINER_SEES_EXISTING_CLIENTS_FILE: String = "joiner-sees-existing-clients.json"
const THREE_CLIENTS_READY_FILE: String = "three-clients-ready.json"

const IMPAIRED_OBSERVER_READY_FILE: String = "impaired-observer-ready.json"
const IMPAIRED_ACTOR_READY_FILE: String = "impaired-actor-ready.json"
const IMPAIRED_OBSERVER_SEES_ACTOR_FILE: String = "impaired-observer-sees-actor.json"
const IMPAIRED_FIRST_TWO_VERIFIED_FILE: String = "impaired-first-two-verified.json"
const IMPAIRED_JOINER_READY_FILE: String = "impaired-joiner-ready.json"
const IMPAIRED_OBSERVER_SEES_ALL_FILE: String = "impaired-observer-sees-all.json"
const IMPAIRED_JOINER_SEES_ALL_FILE: String = "impaired-joiner-sees-all.json"
const IMPAIRED_ALL_CLIENTS_READY_FILE: String = "impaired-all-clients-ready.json"
const IMPAIRED_OBSERVER_ACTION_READY_FILE: String = "impaired-observer-action-ready.json"
const IMPAIRED_JOINER_ACTION_READY_FILE: String = "impaired-joiner-action-ready.json"
const IMPAIRED_ACTOR_STATE_FILE: String = "impaired-actor-state.json"
const IMPAIRED_OBSERVER_CONVERGED_FILE: String = "impaired-observer-converged.json"
const IMPAIRED_JOINER_CONVERGED_FILE: String = "impaired-joiner-converged.json"

const NETWORK_QUALITY_LOW_READY_FILE: String = "network-quality-low-ready.json"
const NETWORK_QUALITY_HIGH_READY_FILE: String = "network-quality-high-ready.json"
const NETWORK_QUALITY_LOW_OBSERVER_READY_FILE: String = "network-quality-low-observer-ready.json"
const NETWORK_QUALITY_LOW_MOVEMENT_DONE_FILE: String = "network-quality-low-movement-done.json"
const NETWORK_QUALITY_LOW_OBSERVED_FILE: String = "network-quality-low-observed.json"
const NETWORK_QUALITY_HIGH_OBSERVER_READY_FILE: String = "network-quality-high-observer-ready.json"
const NETWORK_QUALITY_HIGH_MOVEMENT_DONE_FILE: String = "network-quality-high-movement-done.json"
const NETWORK_QUALITY_HIGH_OBSERVED_FILE: String = "network-quality-high-observed.json"

static func write_json(path: String, payload: Dictionary) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload) + "\n")
	file.close()
	return OK

static func vector3_to_dictionary(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}

static func vector3_from_dictionary(value: Dictionary) -> Vector3:
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)

static func wait_for_json(
		context: Node,
		path: String,
		timeout_seconds: float) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < timeout_seconds:
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				if typeof(parsed) == TYPE_DICTIONARY:
					return {
						"ok": true,
						"payload": parsed,
					}
		await context.get_tree().process_frame
	return {
		"ok": false,
		"reason": "Timed out waiting for coordination file.",
		"path": path,
	}

static func _elapsed_seconds(started_msec: int) -> float:
	return float(Time.get_ticks_msec() - started_msec) / 1000.0
