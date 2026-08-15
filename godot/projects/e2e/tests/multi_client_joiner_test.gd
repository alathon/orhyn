extends E2ETestCase

const SPAWN_POSITION_TOLERANCE: float = 0.002

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	if coordination_dir.is_empty():
		return failed("configure", "Multi-client joiner requires a coordination directory.")

	var observer_ready_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_READY_FILE
	)
	var observer_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		observer_ready_path,
		timeout_seconds
	)
	if not bool(observer_ready.get("ok", false)):
		return failed("wait_for_client_a", str(observer_ready.get("reason", "Client A was not ready.")), {
			"path": observer_ready_path,
		})
	var observer_payload: Dictionary = observer_ready.get("payload", {})
	var observer_entity_id: int = int(observer_payload.get("entity_id", 0))

	var actor_ready_path: String = coordination_dir.path_join(E2ECoordination.ACTOR_READY_FILE)
	var actor_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actor_ready_path,
		timeout_seconds
	)
	if not bool(actor_ready.get("ok", false)):
		return failed("wait_for_client_b", str(actor_ready.get("reason", "Client B was not ready.")), {
			"path": actor_ready_path,
		})
	var actor_payload: Dictionary = actor_ready.get("payload", {})
	var actor_entity_id: int = int(actor_payload.get("entity_id", 0))
	var joiner_entity_id: int = session.loaded_character.entity_id
	if observer_entity_id <= 0 or actor_entity_id <= 0 or joiner_entity_id <= 0:
		return failed("read_client_identities", "One or more clients published an invalid entity id.", {
			"client_a_entity_id": observer_entity_id,
			"client_b_entity_id": actor_entity_id,
			"client_c_entity_id": joiner_entity_id,
		})

	var joiner_ready_path: String = coordination_dir.path_join(E2ECoordination.JOINER_READY_FILE)
	var write_error: Error = E2ECoordination.write_json(joiner_ready_path, {
		"entity_id": joiner_entity_id,
	})
	if write_error != OK:
		return failed("publish_client_c_ready", "Could not publish client C's identity.", {
			"path": joiner_ready_path,
			"error": error_string(write_error),
		})

	var observer_spawn: EntitySpawnedGameEvent = await session.wait_for_entity_spawned_event(
		observer_entity_id,
		timeout_seconds
	)
	var observer_spawn_error: String = _validate_remote_player_spawn(
		observer_spawn,
		observer_entity_id
	)
	if not observer_spawn_error.is_empty():
		return failed("observe_client_a_spawn", observer_spawn_error, {
			"client_a_entity_id": observer_entity_id,
		})
	var actor_spawn: EntitySpawnedGameEvent = await session.wait_for_entity_spawned_event(
		actor_entity_id,
		timeout_seconds
	)
	var actor_spawn_error: String = _validate_remote_player_spawn(actor_spawn, actor_entity_id)
	if not actor_spawn_error.is_empty():
		return failed("observe_client_b_spawn", actor_spawn_error, {
			"client_b_entity_id": actor_entity_id,
		})

	var three_client_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
	if not await session.wait_for_exact_entity_ids(three_client_ids, timeout_seconds):
		return failed("verify_three_entities", "Client C did not have exactly clients A, B, and C.", {
			"expected_entity_ids": three_client_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})
	if not (session.get_entity(joiner_entity_id) is Player):
		return failed("verify_client_c_local", "Client C did not represent itself as the local player.", {
			"client_c_entity_id": joiner_entity_id,
		})
	if not (session.get_entity(observer_entity_id) is RemoteEntity):
		return failed("verify_client_a_remote", "Client C did not represent client A as a remote entity.", {
			"client_a_entity_id": observer_entity_id,
		})
	if not (session.get_entity(actor_entity_id) is RemoteEntity):
		return failed("verify_client_b_remote", "Client C did not represent client B as a remote entity.", {
			"client_b_entity_id": actor_entity_id,
		})
	if not await session.wait_for_entities_near_spawn_positions(
		three_client_ids,
		SPAWN_POSITION_TOLERANCE,
		timeout_seconds
	):
		return failed("verify_three_spawn_positions", "Client C placed a client away from its spawn event position.", {
			"max_distance": SPAWN_POSITION_TOLERANCE,
			"positions": session.get_entity_spawn_position_details(three_client_ids),
		})
	var three_client_spawn_positions: Array[Dictionary] = session.get_entity_spawn_position_details(
		three_client_ids
	)

	var joiner_verified_path: String = coordination_dir.path_join(
		E2ECoordination.JOINER_SEES_EXISTING_CLIENTS_FILE
	)
	write_error = E2ECoordination.write_json(joiner_verified_path, {
		"client_a_entity_id": observer_entity_id,
		"client_b_entity_id": actor_entity_id,
		"client_c_entity_id": joiner_entity_id,
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_client_c_verification", "Client C could not publish its A+B+C verification.", {
			"path": joiner_verified_path,
			"error": error_string(write_error),
		})

	var three_clients_ready_path: String = coordination_dir.path_join(
		E2ECoordination.THREE_CLIENTS_READY_FILE
	)
	var three_clients_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		three_clients_ready_path,
		timeout_seconds
	)
	if not bool(three_clients_ready.get("ok", false)):
		return failed("wait_for_three_clients", str(
			three_clients_ready.get("reason", "The three-client spawn checks did not finish.")
		), {
			"path": three_clients_ready_path,
		})

	var actions_observed_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_ACTIONS_OBSERVED_FILE
	)
	var actions_observed: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actions_observed_path,
		timeout_seconds
	)
	if not bool(actions_observed.get("ok", false)):
		return failed("wait_for_suite_completion", str(
			actions_observed.get("reason", "The existing multi-client assertions did not finish.")
		), {
			"path": actions_observed_path,
		})

	return passed({
		"client_a_entity_id": observer_entity_id,
		"client_b_entity_id": actor_entity_id,
		"client_c_entity_id": joiner_entity_id,
		"three_client_entity_ids": three_client_ids,
		"three_client_spawn_positions": three_client_spawn_positions,
		"client_a_spawn_sequence": observer_spawn.local_sequence,
		"client_b_spawn_sequence": actor_spawn.local_sequence,
	})

func _validate_remote_player_spawn(
		event: EntitySpawnedGameEvent,
		expected_entity_id: int
) -> String:
	if event == null:
		return "Timed out waiting for the remote player spawn event."
	if event.entity_id != expected_entity_id:
		return "Remote player spawn event targeted the wrong entity."
	if event.entity_kind != EntitySpawnedGameEvent.ENTITY_KIND_PLAYER:
		return "Remote player spawn event had the wrong entity kind."
	if event.source != GameEvent.Source.SERVER_AUTHORITATIVE:
		return "Remote player spawn event was not marked server-authoritative."
	return ""
