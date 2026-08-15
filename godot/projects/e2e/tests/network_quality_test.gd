extends E2ETestCase

const ROLE_LOW: String = "low"
const ROLE_HIGH: String = "high"
const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_right",
	&"move_back",
	&"move_left",
]
const MOVEMENT_SEGMENTS: Array[Array] = [
	[&"move_forward"],
	[&"move_forward", &"move_right"],
	[&"move_right"],
	[&"move_back", &"move_right"],
	[&"move_back"],
	[&"move_back", &"move_left"],
	[&"move_left"],
	[&"move_forward", &"move_left"],
]
const MINIMUM_MOVEMENT_DURATION_SECONDS: float = 1.0
const MINIMUM_WORKLOAD_TRAVEL_DISTANCE: float = 1.0

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	var client_role: String = str(config.get("client_role", ""))
	var network_profile: String = str(config.get("network_profile", "unspecified"))
	var movement_duration_seconds: float = float(
		config.get("movement_duration_seconds", 20.0)
	)
	var drain_seconds: float = maxf(float(config.get("metrics_drain_seconds", 2.0)), 0.0)
	var wait_timeout: float = session.timeout_seconds
	if coordination_dir.is_empty():
		return failed("configure", "Network-quality pair requires a coordination directory.")
	if client_role != ROLE_LOW and client_role != ROLE_HIGH:
		return failed("configure", "Network-quality client role must be low or high.")
	if movement_duration_seconds < MINIMUM_MOVEMENT_DURATION_SECONDS:
		return failed("configure", "Network-quality movement duration is too short.")

	var local_entity_id: int = session.loaded_character.entity_id
	var identity_result: Dictionary = await _exchange_identities(
		coordination_dir,
		client_role,
		local_entity_id,
		wait_timeout
	)
	if not bool(identity_result.get("ok", false)):
		return failed(
			"exchange_identities",
			str(identity_result.get("reason", "The peer identity was unavailable.")),
			identity_result
		)
	var peer_entity_id: int = int(identity_result.get("peer_entity_id", 0))
	if not await session.wait_for_remote_interpolation_ready(peer_entity_id, wait_timeout):
		return failed("warm_remote_interpolation", "The peer interpolation buffer did not warm up.", {
			"peer_entity_id": peer_entity_id,
		})

	if client_role == ROLE_LOW:
		return await _run_low_client(
			session,
			coordination_dir,
			local_entity_id,
			peer_entity_id,
			network_profile,
			movement_duration_seconds,
			drain_seconds,
			wait_timeout,
			config
		)
	return await _run_high_client(
		session,
		coordination_dir,
		local_entity_id,
		peer_entity_id,
		network_profile,
		movement_duration_seconds,
		drain_seconds,
		wait_timeout,
		config
	)

func _run_low_client(
	session: E2ESession,
	coordination_dir: String,
	local_entity_id: int,
	peer_entity_id: int,
	network_profile: String,
	movement_duration_seconds: float,
	drain_seconds: float,
	wait_timeout: float,
	config: Dictionary
) -> Dictionary:
	var observer_ready: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_OBSERVER_READY_FILE,
		wait_timeout
	)
	if not bool(observer_ready.get("ok", false)):
		return failed("wait_for_high_observer", "High-latency observer was not ready.")

	var movement_distance: float = await _run_movement_workload(
		session,
		movement_duration_seconds
	)
	var write_error: Error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_MOVEMENT_DONE_FILE,
		{"travel_distance": movement_distance}
	)
	if write_error != OK:
		return failed("publish_low_movement", "Could not publish low-client movement completion.")
	var observed: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_OBSERVED_FILE,
		wait_timeout
	)
	if not bool(observed.get("ok", false)):
		return failed("wait_for_high_observation", "High-latency client did not finish observing.")

	if not session.start_remote_network_metrics_collection(peer_entity_id):
		return failed("start_low_observer", "Could not observe the high-latency remote player.")
	write_error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_OBSERVER_READY_FILE,
		{"entity_id": local_entity_id}
	)
	if write_error != OK:
		return failed("publish_low_observer", "Could not publish low-observer readiness.")
	var high_done: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_MOVEMENT_DONE_FILE,
		wait_timeout
	)
	if not bool(high_done.get("ok", false)):
		return failed("wait_for_high_movement", "High-latency mover did not finish.")
	if drain_seconds > 0.0:
		await get_tree().create_timer(drain_seconds).timeout
	var metrics: Dictionary = session.stop_network_metrics_collection()
	var metrics_error: String = _validate_remote_metrics(metrics, config)
	var observation_details: Dictionary = _observation_details(
		"low_views_high",
		network_profile,
		local_entity_id,
		peer_entity_id,
		metrics,
		movement_duration_seconds,
		drain_seconds
	)
	write_error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_OBSERVED_FILE,
		observation_details
	)
	if write_error != OK:
		return failed("publish_low_observation", "Could not publish low-client metrics.")
	if not metrics_error.is_empty():
		return failed("remote_motion_metrics", metrics_error, observation_details)
	if movement_distance < MINIMUM_WORKLOAD_TRAVEL_DISTANCE:
		return failed("exercise_low_movement", "Low-latency mover did not exercise the route.")
	return passed(observation_details)

func _run_high_client(
	session: E2ESession,
	coordination_dir: String,
	local_entity_id: int,
	peer_entity_id: int,
	network_profile: String,
	movement_duration_seconds: float,
	drain_seconds: float,
	wait_timeout: float,
	config: Dictionary
) -> Dictionary:
	if not session.start_remote_network_metrics_collection(peer_entity_id):
		return failed("start_high_observer", "Could not observe the low-latency remote player.")
	var write_error: Error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_OBSERVER_READY_FILE,
		{"entity_id": local_entity_id}
	)
	if write_error != OK:
		return failed("publish_high_observer", "Could not publish high-observer readiness.")
	var low_done: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_MOVEMENT_DONE_FILE,
		wait_timeout
	)
	if not bool(low_done.get("ok", false)):
		return failed("wait_for_low_movement", "Low-latency mover did not finish.")
	if drain_seconds > 0.0:
		await get_tree().create_timer(drain_seconds).timeout
	var metrics: Dictionary = session.stop_network_metrics_collection()
	var metrics_error: String = _validate_remote_metrics(metrics, config)
	var observation_details: Dictionary = _observation_details(
		"high_views_low",
		network_profile,
		local_entity_id,
		peer_entity_id,
		metrics,
		movement_duration_seconds,
		drain_seconds
	)
	write_error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_OBSERVED_FILE,
		observation_details
	)
	if write_error != OK:
		return failed("publish_high_observation", "Could not publish high-client metrics.")
	if not metrics_error.is_empty():
		return failed("remote_motion_metrics", metrics_error, observation_details)

	var low_observer_ready: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_LOW_OBSERVER_READY_FILE,
		wait_timeout
	)
	if not bool(low_observer_ready.get("ok", false)):
		return failed("wait_for_low_observer", "Low-latency observer was not ready.")
	var movement_distance: float = await _run_movement_workload(
		session,
		movement_duration_seconds
	)
	write_error = _write_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_MOVEMENT_DONE_FILE,
		{"travel_distance": movement_distance}
	)
	if write_error != OK:
		return failed("publish_high_movement", "Could not publish high-client movement completion.")
	var high_observed: Dictionary = await _wait_for_file(
		coordination_dir,
		E2ECoordination.NETWORK_QUALITY_HIGH_OBSERVED_FILE,
		wait_timeout
	)
	if not bool(high_observed.get("ok", false)):
		return failed("wait_for_low_observation", "Low-latency client did not finish observing.")
	if movement_distance < MINIMUM_WORKLOAD_TRAVEL_DISTANCE:
		return failed("exercise_high_movement", "High-latency mover did not exercise the route.")
	return passed(observation_details)

func _exchange_identities(
	coordination_dir: String,
	client_role: String,
	local_entity_id: int,
	wait_timeout: float
) -> Dictionary:
	var own_file: String = E2ECoordination.NETWORK_QUALITY_LOW_READY_FILE \
		if client_role == ROLE_LOW else E2ECoordination.NETWORK_QUALITY_HIGH_READY_FILE
	var peer_file: String = E2ECoordination.NETWORK_QUALITY_HIGH_READY_FILE \
		if client_role == ROLE_LOW else E2ECoordination.NETWORK_QUALITY_LOW_READY_FILE
	var write_error: Error = _write_file(
		coordination_dir,
		own_file,
		{"entity_id": local_entity_id}
	)
	if write_error != OK:
		return {"ok": false, "reason": "Could not publish client identity."}
	var peer_result: Dictionary = await _wait_for_file(
		coordination_dir,
		peer_file,
		wait_timeout
	)
	if not bool(peer_result.get("ok", false)):
		return peer_result
	var payload: Dictionary = peer_result.get("payload", {})
	var peer_entity_id: int = int(payload.get("entity_id", 0))
	if peer_entity_id <= 0:
		return {"ok": false, "reason": "Peer published an invalid entity id."}
	return {"ok": true, "peer_entity_id": peer_entity_id}

func _run_movement_workload(session: E2ESession, duration_seconds: float) -> float:
	var segment_duration_seconds: float = duration_seconds / float(MOVEMENT_SEGMENTS.size())
	var previous_position: Vector3 = session.get_local_position()
	var travel_distance: float = 0.0
	for actions: Array in MOVEMENT_SEGMENTS:
		_release_all_movement_actions()
		for action: StringName in actions:
			Input.action_press(action)

		var segment_started_usec: int = Time.get_ticks_usec()
		while _elapsed_seconds(segment_started_usec) < segment_duration_seconds:
			await get_tree().process_frame
			var current_position: Vector3 = session.get_local_position()
			travel_distance += previous_position.distance_to(current_position)
			previous_position = current_position

	_release_all_movement_actions()
	return travel_distance

func _validate_remote_metrics(metrics: Dictionary, config: Dictionary) -> String:
	var minimum_samples: int = int(config.get("minimum_remote_motion_samples", 1))
	if int(metrics.get("remote_motion_sample_count", 0)) < minimum_samples:
		return "Too few rendered remote-motion samples were collected."
	if float(metrics.get("remote_total_rendered_distance", 0.0)) < MINIMUM_WORKLOAD_TRAVEL_DISTANCE:
		return "The observed remote entity did not render enough movement."
	return ""

func _observation_details(
	direction: String,
	network_profile: String,
	observer_entity_id: int,
	mover_entity_id: int,
	metrics: Dictionary,
	movement_duration_seconds: float,
	drain_seconds: float
) -> Dictionary:
	return {
		"observation_direction": direction,
		"observer_network_profile": network_profile,
		"observer_entity_id": observer_entity_id,
		"mover_entity_id": mover_entity_id,
		"movement_duration_seconds": movement_duration_seconds,
		"metrics_drain_seconds": drain_seconds,
		"metrics": metrics,
	}

func _write_file(coordination_dir: String, file_name: String, payload: Dictionary) -> Error:
	return E2ECoordination.write_json(coordination_dir.path_join(file_name), payload)

func _wait_for_file(
	coordination_dir: String,
	file_name: String,
	wait_timeout: float
) -> Dictionary:
	return await E2ECoordination.wait_for_json(
		self,
		coordination_dir.path_join(file_name),
		wait_timeout
	)

func _release_all_movement_actions() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)

func _elapsed_seconds(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000000.0
