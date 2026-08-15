extends E2ETestCase

const ARM_FILE: String = "network-scale-arm.json"
const START_FILE: String = "network-scale-start.json"
const FINISH_FILE: String = "network-scale-finish.json"
const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_right",
	&"move_back",
	&"move_left",
]
const MINIMUM_CLIENT_COUNT: int = 2
const MINIMUM_MOVEMENT_DURATION_SECONDS: float = 1.0
const MINIMUM_TRAVEL_DISTANCE: float = 0.25
const MINIMUM_DIRECTION_SECONDS: float = 0.35
const MAXIMUM_DIRECTION_SECONDS: float = 1.10

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	var client_index: int = int(config.get("client_index", -1))
	var client_count: int = int(config.get("client_count", 0))
	var movement_seed: int = int(config.get("movement_seed", 1))
	var network_profile: String = str(config.get("network_profile", "unspecified"))
	var movement_duration_seconds: float = float(
		config.get("movement_duration_seconds", 30.0)
	)
	var metric_sample_capacity: int = int(config.get("metric_sample_capacity", 8192))
	var wait_timeout: float = session.timeout_seconds
	if coordination_dir.is_empty():
		return failed("configure", "Network-scale clients require a coordination directory.")
	if client_count < MINIMUM_CLIENT_COUNT:
		return failed("configure", "Network-scale workload requires at least two clients.")
	if client_index < 0 or client_index >= client_count:
		return failed("configure", "Network-scale client index is outside the client count.")
	if movement_duration_seconds < MINIMUM_MOVEMENT_DURATION_SECONDS:
		return failed("configure", "Network-scale movement duration is too short.")
	if metric_sample_capacity <= 0:
		return failed("configure", "Network-scale metric sample capacity must be positive.")

	var write_error: Error = _write_client_file(
		coordination_dir,
		"connected",
		client_index,
		{"entity_id": session.loaded_character.entity_id}
	)
	if write_error != OK:
		return failed("publish_connected", "Could not publish entered-world readiness.")
	if not await session.wait_for_entity_count(client_count, wait_timeout):
		return failed("wait_for_entities", "The full client population did not become visible.", {
			"client_index": client_index,
			"expected_entity_count": client_count,
			"observed_entity_count": session.get_entity_ids().size(),
		})
	if not await session.wait_for_all_remote_interpolation_ready(client_count - 1, wait_timeout):
		return failed(
			"warm_remote_interpolation",
			"Not every remote interpolation buffer became observable.",
			{"client_index": client_index, "expected_remote_count": client_count - 1}
		)

	write_error = _write_client_file(
		coordination_dir,
		"ready",
		client_index,
		{"entity_id": session.loaded_character.entity_id}
	)
	if write_error != OK:
		return failed("publish_ready", "Could not publish network-scale readiness.")
	if not await _wait_for_file(coordination_dir, ARM_FILE, wait_timeout):
		return failed("wait_for_arm", "The network-scale arm barrier was not released.")

	var is_observer: bool = client_index == 0 or client_index == client_count - 1
	if is_observer and not session.start_all_remote_network_metrics_collection(
		metric_sample_capacity
	):
		return failed("start_observer", "Could not collect every remote presentation stream.")
	write_error = _write_client_file(
		coordination_dir,
		"armed",
		client_index,
		{"observer": is_observer}
	)
	if write_error != OK:
		return failed("publish_armed", "Could not publish network-scale arm readiness.")
	if not await _wait_for_file(coordination_dir, START_FILE, wait_timeout):
		return failed("wait_for_start", "The network-scale start barrier was not released.")

	var travel_distance: float = await _run_random_movement(
		session,
		movement_duration_seconds,
		movement_seed
	)
	write_error = _write_client_file(
		coordination_dir,
		"movement-done",
		client_index,
		{"travel_distance": travel_distance}
	)
	if write_error != OK:
		return failed("publish_movement", "Could not publish movement completion.")
	if not await _wait_for_file(coordination_dir, FINISH_FILE, wait_timeout):
		return failed("wait_for_finish", "The network-scale drain barrier was not released.")

	var metrics: Dictionary = {}
	if is_observer:
		metrics = session.stop_network_metrics_collection()
		var metrics_error: String = _validate_metrics(metrics, client_count, config)
		if not metrics_error.is_empty():
			return failed("remote_motion_metrics", metrics_error, {"metrics": metrics})
	if travel_distance < MINIMUM_TRAVEL_DISTANCE:
		return failed("exercise_movement", "The random movement workload did not travel.", {
			"client_index": client_index,
			"travel_distance": travel_distance,
		})

	return passed({
		"client_index": client_index,
		"client_count": client_count,
		"observer": is_observer,
		"network_profile": network_profile,
		"movement_seed": movement_seed,
		"movement_duration_seconds": movement_duration_seconds,
		"travel_distance": travel_distance,
		"metrics": metrics,
	})

func _run_random_movement(
	session: E2ESession,
	duration_seconds: float,
	movement_seed: int
) -> float:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = movement_seed
	var started_usec: int = Time.get_ticks_usec()
	var next_direction_seconds: float = 0.0
	var previous_position: Vector3 = session.get_local_position()
	var travel_distance: float = 0.0
	while _elapsed_seconds(started_usec) < duration_seconds:
		var elapsed_seconds: float = _elapsed_seconds(started_usec)
		if elapsed_seconds >= next_direction_seconds:
			_set_direction(random.randi_range(0, 7))
			next_direction_seconds = elapsed_seconds + random.randf_range(
				MINIMUM_DIRECTION_SECONDS,
				MAXIMUM_DIRECTION_SECONDS
			)
		await get_tree().process_frame
		var current_position: Vector3 = session.get_local_position()
		travel_distance += previous_position.distance_to(current_position)
		previous_position = current_position
	_release_all_movement_actions()
	return travel_distance

func _set_direction(direction: int) -> void:
	_release_all_movement_actions()
	match direction:
		0:
			Input.action_press(&"move_forward")
		1:
			Input.action_press(&"move_forward")
			Input.action_press(&"move_right")
		2:
			Input.action_press(&"move_right")
		3:
			Input.action_press(&"move_back")
			Input.action_press(&"move_right")
		4:
			Input.action_press(&"move_back")
		5:
			Input.action_press(&"move_back")
			Input.action_press(&"move_left")
		6:
			Input.action_press(&"move_left")
		7:
			Input.action_press(&"move_forward")
			Input.action_press(&"move_left")

func _validate_metrics(metrics: Dictionary, client_count: int, config: Dictionary) -> String:
	if int(metrics.get("remote_entity_count", 0)) != client_count - 1:
		return "The observer did not attach to every remote entity."
	if int(metrics.get("dropped_metric_value_count", 0)) != 0:
		return "The observer exhausted its preallocated metric sample storage."
	var minimum_samples: int = int(config.get("minimum_remote_motion_samples", 1))
	if int(metrics.get("remote_motion_sample_count", 0)) < minimum_samples:
		return "Too few aggregate remote-motion samples were collected."
	return ""

func _write_client_file(
	coordination_dir: String,
	phase: String,
	client_index: int,
	payload: Dictionary
) -> Error:
	var file_name: String = "network-scale-client-%03d-%s.json" % [client_index, phase]
	return E2ECoordination.write_json(coordination_dir.path_join(file_name), payload)

func _wait_for_file(
	coordination_dir: String,
	file_name: String,
	wait_timeout: float
) -> bool:
	var result: Dictionary = await E2ECoordination.wait_for_json(
		self,
		coordination_dir.path_join(file_name),
		wait_timeout
	)
	return bool(result.get("ok", false))

func _release_all_movement_actions() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)

func _elapsed_seconds(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000000.0
