extends E2ETestCase

const ROLE_OBSERVER: String = "observer"
const ROLE_JOINER: String = "joiner"
const AUTHORITATIVE_POSITION_EPSILON: float = 0.002
const REMOTE_CONVERGENCE_DISTANCE: float = 0.10

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	var client_role: String = str(config.get("client_role", ""))
	var wait_timeout: float = session.timeout_seconds
	if coordination_dir.is_empty():
		return failed("configure", "Impaired-network peer requires a coordination directory.")
	if client_role != ROLE_OBSERVER and client_role != ROLE_JOINER:
		return failed("configure", "Impaired-network peer requires observer or joiner role.", {
			"client_role": client_role,
		})

	var local_entity_id: int = session.loaded_character.entity_id
	var observer_entity_id: int = 0
	var actor_entity_id: int = 0
	var joiner_entity_id: int = 0
	var write_error: Error = OK

	if client_role == ROLE_OBSERVER:
		observer_entity_id = local_entity_id
		var observer_ready_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_OBSERVER_READY_FILE
		)
		write_error = E2ECoordination.write_json(observer_ready_path, {
			"entity_id": observer_entity_id,
		})
		if write_error != OK:
			return failed("publish_observer_ready", "Could not publish client A identity.", {
				"error": error_string(write_error),
			})

		var actor_ready_result: Dictionary = await _wait_for_identity(
			coordination_dir,
			E2ECoordination.IMPAIRED_ACTOR_READY_FILE,
			wait_timeout
		)
		if not bool(actor_ready_result.get("ok", false)):
			return failed("wait_for_actor", str(actor_ready_result.get("reason", "Client B was not ready.")))
		actor_entity_id = int(actor_ready_result.get("entity_id", 0))

		if not await session.wait_for_entity_spawned_event_count(
			actor_entity_id,
			1,
			wait_timeout
		):
			return failed("observe_actor_spawn", "Timed out waiting for client B's reliable spawn event.")
		var first_two_ids: Array[int] = [observer_entity_id, actor_entity_id]
		var first_two_error: String = await _validate_entities(
			session,
			first_two_ids,
			wait_timeout
		)
		if not first_two_error.is_empty():
			return failed("verify_first_two_clients", first_two_error, {
				"expected_entity_ids": first_two_ids,
				"actual_entity_ids": session.get_entity_ids(),
			})

		var observer_sees_actor_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_OBSERVER_SEES_ACTOR_FILE
		)
		write_error = E2ECoordination.write_json(observer_sees_actor_path, {
			"entity_ids": session.get_entity_ids(),
		})
		if write_error != OK:
			return failed("publish_observer_sees_actor", "Could not publish the A+B observation.")

		var first_two_verified_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_FIRST_TWO_VERIFIED_FILE
		)
		var first_two_verified: Dictionary = await E2ECoordination.wait_for_json(
			self,
			first_two_verified_path,
			wait_timeout
		)
		if not bool(first_two_verified.get("ok", false)):
			return failed("wait_for_first_two_verification", str(
				first_two_verified.get("reason", "Client B did not verify A+B.")
			))

		var joiner_ready_result: Dictionary = await _wait_for_identity(
			coordination_dir,
			E2ECoordination.IMPAIRED_JOINER_READY_FILE,
			wait_timeout
		)
		if not bool(joiner_ready_result.get("ok", false)):
			return failed("wait_for_joiner", str(joiner_ready_result.get("reason", "Client C was not ready.")))
		joiner_entity_id = int(joiner_ready_result.get("entity_id", 0))

		if not await session.wait_for_entity_spawned_event_count(
			joiner_entity_id,
			1,
			wait_timeout
		):
			return failed("observe_joiner_spawn", "Timed out waiting for client C's reliable spawn event.")
		var observer_all_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
		var observer_all_error: String = await _validate_entities(
			session,
			observer_all_ids,
			wait_timeout
		)
		if not observer_all_error.is_empty():
			return failed("converge_observer_entities", observer_all_error, {
				"expected_entity_ids": observer_all_ids,
				"actual_entity_ids": session.get_entity_ids(),
			})

		var observer_sees_all_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_OBSERVER_SEES_ALL_FILE
		)
		write_error = E2ECoordination.write_json(observer_sees_all_path, {
			"entity_ids": session.get_entity_ids(),
		})
		if write_error != OK:
			return failed("publish_observer_sees_all", "Could not publish client A convergence.")
	else:
		joiner_entity_id = local_entity_id
		var observer_ready_result: Dictionary = await _wait_for_identity(
			coordination_dir,
			E2ECoordination.IMPAIRED_OBSERVER_READY_FILE,
			wait_timeout
		)
		if not bool(observer_ready_result.get("ok", false)):
			return failed("wait_for_observer", str(observer_ready_result.get("reason", "Client A was not ready.")))
		observer_entity_id = int(observer_ready_result.get("entity_id", 0))
		var actor_ready_result: Dictionary = await _wait_for_identity(
			coordination_dir,
			E2ECoordination.IMPAIRED_ACTOR_READY_FILE,
			wait_timeout
		)
		if not bool(actor_ready_result.get("ok", false)):
			return failed("wait_for_actor", str(actor_ready_result.get("reason", "Client B was not ready.")))
		actor_entity_id = int(actor_ready_result.get("entity_id", 0))

		var joiner_ready_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_JOINER_READY_FILE
		)
		write_error = E2ECoordination.write_json(joiner_ready_path, {
			"entity_id": joiner_entity_id,
		})
		if write_error != OK:
			return failed("publish_joiner_ready", "Could not publish client C identity.")

		for remote_entity_id: int in [observer_entity_id, actor_entity_id]:
			if not await session.wait_for_entity_spawned_event_count(
				remote_entity_id,
				1,
				wait_timeout
			):
				return failed("observe_existing_player_spawn", "Timed out waiting for a reliable spawn event.", {
					"entity_id": remote_entity_id,
				})
		var joiner_all_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
		var joiner_all_error: String = await _validate_entities(
			session,
			joiner_all_ids,
			wait_timeout
		)
		if not joiner_all_error.is_empty():
			return failed("converge_joiner_entities", joiner_all_error, {
				"expected_entity_ids": joiner_all_ids,
				"actual_entity_ids": session.get_entity_ids(),
			})

		var joiner_sees_all_path: String = coordination_dir.path_join(
			E2ECoordination.IMPAIRED_JOINER_SEES_ALL_FILE
		)
		write_error = E2ECoordination.write_json(joiner_sees_all_path, {
			"entity_ids": session.get_entity_ids(),
		})
		if write_error != OK:
			return failed("publish_joiner_sees_all", "Could not publish client C convergence.")

	if observer_entity_id <= 0 or actor_entity_id <= 0 or joiner_entity_id <= 0:
		return failed("read_client_identities", "One or more clients published an invalid entity id.", {
			"observer_entity_id": observer_entity_id,
			"actor_entity_id": actor_entity_id,
			"joiner_entity_id": joiner_entity_id,
		})

	var all_ready_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_ALL_CLIENTS_READY_FILE
	)
	var all_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		all_ready_path,
		wait_timeout
	)
	if not bool(all_ready.get("ok", false)):
		return failed("wait_for_all_clients", str(
			all_ready.get("reason", "The actor did not complete the spawn convergence barrier.")
		))

	session.clear_movement_snapshots()
	var action_ready_file: String = E2ECoordination.IMPAIRED_OBSERVER_ACTION_READY_FILE \
		if client_role == ROLE_OBSERVER else E2ECoordination.IMPAIRED_JOINER_ACTION_READY_FILE
	var action_ready_path: String = coordination_dir.path_join(action_ready_file)
	write_error = E2ECoordination.write_json(action_ready_path, {
		"entity_id": local_entity_id,
	})
	if write_error != OK:
		return failed("publish_action_ready", "Could not publish the peer action barrier.")

	var actor_state_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_ACTOR_STATE_FILE
	)
	var actor_state_result: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actor_state_path,
		wait_timeout
	)
	if not bool(actor_state_result.get("ok", false)):
		return failed("wait_for_actor_state", str(
			actor_state_result.get("reason", "The actor did not publish authoritative state.")
		))
	var actor_state: Dictionary = actor_state_result.get("payload", {})
	var settled_server_tick: int = int(actor_state.get("settled_server_tick", -1))
	var settled_position_value: Variant = actor_state.get("settled_position", {})
	if settled_server_tick < 0 or typeof(settled_position_value) != TYPE_DICTIONARY:
		return failed("read_actor_state", "The actor published incomplete authoritative movement state.", {
			"settled_server_tick": settled_server_tick,
		})
	var settled_position: Vector3 = E2ECoordination.vector3_from_dictionary(
		settled_position_value
	)

	var final_snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_authoritative_position_near(
		actor_entity_id,
		settled_position,
		settled_server_tick,
		AUTHORITATIVE_POSITION_EPSILON,
		wait_timeout
	)
	if final_snapshot == null:
		return failed("converge_authoritative_position", "Remote authoritative state did not converge on the actor's final position.", {
			"target": str(settled_position),
			"min_server_tick": settled_server_tick,
		})
	if not await session.wait_for_entity_position_near(
		actor_entity_id,
		settled_position,
		REMOTE_CONVERGENCE_DISTANCE,
		wait_timeout
	):
		return failed("converge_rendered_position", "The rendered remote actor did not converge within bounds.", {
			"target": str(settled_position),
			"actual": str(session.get_entity_position(actor_entity_id)),
			"max_distance": REMOTE_CONVERGENCE_DISTANCE,
		})

	for remote_entity_id: int in [observer_entity_id, actor_entity_id, joiner_entity_id]:
		if remote_entity_id == local_entity_id:
			continue
		if session.get_entity_spawned_event_count(remote_entity_id) != 1:
			return failed("count_remote_spawn_events", "The peer observed duplicate remote spawn events.", {
				"entity_id": remote_entity_id,
				"count": session.get_entity_spawned_event_count(remote_entity_id),
			})

	var convergence_file: String = E2ECoordination.IMPAIRED_OBSERVER_CONVERGED_FILE \
		if client_role == ROLE_OBSERVER else E2ECoordination.IMPAIRED_JOINER_CONVERGED_FILE
	var convergence_path: String = coordination_dir.path_join(convergence_file)
	var rendered_position: Vector3 = session.get_entity_position(actor_entity_id)
	write_error = E2ECoordination.write_json(convergence_path, {
		"role": client_role,
		"entity_id": local_entity_id,
		"final_server_tick": final_snapshot.server_tick,
		"authoritative_position": E2ECoordination.vector3_to_dictionary(final_snapshot.position),
		"rendered_position": E2ECoordination.vector3_to_dictionary(rendered_position),
		"rendered_difference": rendered_position.distance_to(settled_position),
	})
	if write_error != OK:
		return failed("publish_convergence", "Could not publish eventual-consistency results.", {
			"error": error_string(write_error),
		})

	var result_entity_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
	return passed({
		"role": client_role,
		"entity_ids": session.get_entity_ids(),
		"final_server_tick": final_snapshot.server_tick,
		"authoritative_position": str(final_snapshot.position),
		"rendered_position": str(rendered_position),
		"rendered_difference": rendered_position.distance_to(settled_position),
		"remote_spawn_event_counts": _remote_spawn_event_counts(
			session,
			result_entity_ids,
			local_entity_id
		),
	})

func _wait_for_identity(
	coordination_dir: String,
	file_name: String,
	wait_timeout: float
) -> Dictionary:
	var path: String = coordination_dir.path_join(file_name)
	var result: Dictionary = await E2ECoordination.wait_for_json(self, path, wait_timeout)
	if not bool(result.get("ok", false)):
		return result
	var payload: Dictionary = result.get("payload", {})
	var entity_id: int = int(payload.get("entity_id", 0))
	if entity_id <= 0:
		return {
			"ok": false,
			"reason": "Coordination file contained an invalid entity id.",
			"path": path,
		}
	return {
		"ok": true,
		"entity_id": entity_id,
	}

func _validate_entities(
	session: E2ESession,
	entity_ids: Array[int],
	wait_timeout: float
) -> String:
	if not await session.wait_for_exact_entity_ids(entity_ids, wait_timeout):
		return "The entity registry did not converge on the exact expected ids."
	return ""

func _remote_spawn_event_counts(
	session: E2ESession,
	entity_ids: Array[int],
	local_entity_id: int
) -> Dictionary:
	var counts: Dictionary = {}
	for entity_id: int in entity_ids:
		if entity_id != local_entity_id:
			counts[str(entity_id)] = session.get_entity_spawned_event_count(entity_id)
	return counts
