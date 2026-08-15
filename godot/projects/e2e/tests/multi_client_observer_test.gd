extends E2ETestCase

const MIN_MOVEMENT_DISTANCE: float = 0.25
const AUTHORITATIVE_POSITION_EPSILON: float = 0.002
const REMOTE_CONVERGENCE_DISTANCE: float = 0.10
const SWORD_INSTANCE_ID: String = "e2e_multi_client_sword"

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	if coordination_dir.is_empty():
		return failed("configure", "Multi-client observer requires a coordination directory.")

	var observer_ready_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_READY_FILE
	)
	var write_error: Error = E2ECoordination.write_json(observer_ready_path, {
		"entity_id": session.loaded_character.entity_id,
	})
	if write_error != OK:
		return failed("publish_observer_ready", "Could not publish observer readiness.", {
			"path": observer_ready_path,
			"error": error_string(write_error),
		})

	var actor_ready_path: String = coordination_dir.path_join(E2ECoordination.ACTOR_READY_FILE)
	var actor_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actor_ready_path,
		timeout_seconds
	)
	if not bool(actor_ready.get("ok", false)):
		return failed("wait_for_actor", str(actor_ready.get("reason", "Actor did not start.")), {
			"path": actor_ready_path,
		})
	var actor_payload: Dictionary = actor_ready.get("payload", {})
	var actor_entity_id: int = int(actor_payload.get("entity_id", 0))
	if actor_entity_id <= 0:
		return failed("read_actor_identity", "Actor published an invalid entity id.", {
			"path": actor_ready_path,
			"entity_id": actor_entity_id,
		})

	var remote: BaseEntity = await session.wait_for_entity(actor_entity_id, timeout_seconds)
	if not (remote is RemoteEntity):
		return failed("observe_remote_spawn", "Observer did not spawn the actor as a remote entity.", {
			"actor_entity_id": actor_entity_id,
		})

	var origin: Vector3 = session.get_entity_position(actor_entity_id)
	session.clear_movement_snapshots()
	var sees_actor_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_SEES_ACTOR_FILE
	)
	write_error = E2ECoordination.write_json(sees_actor_path, {
		"actor_entity_id": actor_entity_id,
		"origin": str(origin),
	})
	if write_error != OK:
		return failed("publish_remote_spawn", "Could not publish remote-spawn observation.", {
			"path": sees_actor_path,
			"error": error_string(write_error),
		})

	var authoritative_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_AUTHORITATIVE_MOVEMENT_FILE
	)
	var authoritative_result: Dictionary = await E2ECoordination.wait_for_json(
		self,
		authoritative_path,
		timeout_seconds
	)
	if not bool(authoritative_result.get("ok", false)):
		return failed("wait_for_authoritative_movement", str(
			authoritative_result.get("reason", "Actor did not publish authoritative movement.")
		), {
			"actor_entity_id": actor_entity_id,
			"path": authoritative_path,
		})
	var authoritative_payload: Dictionary = authoritative_result.get("payload", {})
	var server_tick: int = int(authoritative_payload.get("server_tick", -1))
	var authoritative_position: Vector3 = E2ECoordination.vector3_from_dictionary(
		authoritative_payload.get("position", {})
	)
	if server_tick < 0 or authoritative_position.distance_to(origin) < MIN_MOVEMENT_DISTANCE:
		return failed("read_authoritative_movement", "Actor published invalid authoritative movement.", {
			"actor_entity_id": actor_entity_id,
			"origin": str(origin),
			"authoritative_position": str(authoritative_position),
			"server_tick": server_tick,
		})

	var snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_movement_snapshot_at_tick(
		actor_entity_id,
		server_tick,
		timeout_seconds
	)
	if snapshot == null:
		return failed("compare_authoritative_movement", "Observer did not receive the actor's target server tick.", {
			"actor_entity_id": actor_entity_id,
			"server_tick": server_tick,
		})
	var authoritative_difference: float = snapshot.position.distance_to(authoritative_position)
	if authoritative_difference > AUTHORITATIVE_POSITION_EPSILON:
		return failed("compare_authoritative_movement", "Actor and observer decoded different authoritative positions.", {
			"actor_entity_id": actor_entity_id,
			"actor_authoritative_position": str(authoritative_position),
			"observer_authoritative_position": str(snapshot.position),
			"difference": authoritative_difference,
			"max_distance": AUTHORITATIVE_POSITION_EPSILON,
			"server_tick": server_tick,
		})
	if not await session.wait_for_entity_position_near(
		actor_entity_id,
		authoritative_position,
		REMOTE_CONVERGENCE_DISTANCE,
		timeout_seconds
	):
		return failed("converge_remote_position", "Observer's remote actor did not converge to the authoritative position.", {
			"actor_entity_id": actor_entity_id,
			"authoritative_position": str(authoritative_position),
			"remote_position": str(session.get_entity_position(actor_entity_id)),
			"max_distance": REMOTE_CONVERGENCE_DISTANCE,
			"server_tick": server_tick,
		})
	var remote_converged_position: Vector3 = session.get_entity_position(actor_entity_id)
	var rendered_difference: float = remote_converged_position.distance_to(authoritative_position)

	var equipped: EquippableItem = await session.wait_for_entity_equipped(
		actor_entity_id,
		Equippable.SlotId.Right_Hand,
		SWORD_INSTANCE_ID,
		timeout_seconds
	)
	if equipped == null:
		return failed("observe_remote_equipment", "Observer did not receive the actor's equipment change.", {
			"actor_entity_id": actor_entity_id,
			"item_instance_id": SWORD_INSTANCE_ID,
		})

	var actions_observed_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_ACTIONS_OBSERVED_FILE
	)
	write_error = E2ECoordination.write_json(actions_observed_path, {
		"actor_entity_id": actor_entity_id,
		"position": E2ECoordination.vector3_to_dictionary(remote_converged_position),
		"authoritative_position": E2ECoordination.vector3_to_dictionary(authoritative_position),
		"server_tick": server_tick,
		"equipment_item": equipped.instance_id,
	})
	if write_error != OK:
		return failed("publish_observations", "Could not publish observer assertions.", {
			"path": actions_observed_path,
			"error": error_string(write_error),
		})

	if not await session.wait_for_entity_despawned(actor_entity_id, timeout_seconds):
		return failed("observe_remote_despawn", "Observer did not receive the actor's despawn.", {
			"actor_entity_id": actor_entity_id,
		})

	return passed({
		"actor_entity_id": actor_entity_id,
		"origin": str(origin),
		"authoritative_position": str(authoritative_position),
		"remote_position": str(remote_converged_position),
		"authoritative_difference": authoritative_difference,
		"rendered_difference": rendered_difference,
		"server_tick": server_tick,
		"last_processed_seq": snapshot.last_processed_movement_seq,
		"equipment_item": equipped.instance_id,
		"despawn_observed": true,
	})
