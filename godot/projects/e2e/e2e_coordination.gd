class_name E2ECoordination
extends RefCounted

const ACTOR_READY_FILE: String = "actor-ready.json"
const ACTOR_AUTHORITATIVE_MOVEMENT_FILE: String = "actor-authoritative-movement.json"
const OBSERVER_READY_FILE: String = "observer-ready.json"
const OBSERVER_SEES_ACTOR_FILE: String = "observer-sees-actor.json"
const OBSERVER_ACTIONS_OBSERVED_FILE: String = "observer-actions-observed.json"

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
