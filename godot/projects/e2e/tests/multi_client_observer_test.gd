extends E2ETestCase

const MIN_MOVEMENT_DISTANCE: float = 0.25
const AUTHORITATIVE_POSITION_EPSILON: float = 0.002
const REMOTE_CONVERGENCE_DISTANCE: float = 0.10
const SPAWN_POSITION_TOLERANCE: float = 0.002
const SWORD_TEMPLATE_PATH: String = "res://projects/e2e/fixtures/equipment/e2e_sword.tres"
const SWORD_INSTANCE_ID: String = "e2e_multi_client_sword"

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	if coordination_dir.is_empty():
		return failed("configure", "Multi-client observer requires a coordination directory.")

	var observer_entity_id: int = session.loaded_character.entity_id
	var observer_ready_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_READY_FILE
	)
	var write_error: Error = E2ECoordination.write_json(observer_ready_path, {
		"entity_id": observer_entity_id,
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

	var actor_spawn: EntitySpawnedGameEvent = await session.wait_for_entity_spawned_event(
		actor_entity_id,
		timeout_seconds
	)
	var actor_spawn_error: String = _validate_remote_player_spawn(actor_spawn, actor_entity_id)
	if not actor_spawn_error.is_empty():
		return failed("observe_client_b_spawn", actor_spawn_error, {
			"actor_entity_id": actor_entity_id,
		})
	var first_two_ids: Array[int] = [observer_entity_id, actor_entity_id]
	if not await session.wait_for_exact_entity_ids(first_two_ids, timeout_seconds):
		return failed("verify_first_two_entities", "Client A did not have exactly clients A and B.", {
			"expected_entity_ids": first_two_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})
	if not (session.get_entity(observer_entity_id) is Player):
		return failed("verify_client_a_local", "Client A did not represent itself as the local player.", {
			"client_a_entity_id": observer_entity_id,
		})
	var remote: BaseEntity = session.get_entity(actor_entity_id)
	if not (remote is RemoteEntity):
		return failed("verify_client_b_remote", "Client A did not represent client B as a remote entity.", {
			"actor_entity_id": actor_entity_id,
		})
	if not await session.wait_for_entities_near_spawn_positions(
		first_two_ids,
		SPAWN_POSITION_TOLERANCE,
		timeout_seconds
	):
		return failed("verify_first_two_spawn_positions", "Client A placed A or B away from its spawn event position.", {
			"max_distance": SPAWN_POSITION_TOLERANCE,
			"positions": session.get_entity_spawn_position_details(first_two_ids),
		})
	var first_two_spawn_positions: Array[Dictionary] = session.get_entity_spawn_position_details(
		first_two_ids
	)

	var sees_actor_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_SEES_ACTOR_FILE
	)
	write_error = E2ECoordination.write_json(sees_actor_path, {
		"client_a_entity_id": observer_entity_id,
		"actor_entity_id": actor_entity_id,
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_client_a_sees_b", "Client A could not publish its A+B verification.", {
			"path": sees_actor_path,
			"error": error_string(write_error),
		})

	var actor_sees_observer_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_SEES_OBSERVER_FILE
	)
	var actor_sees_observer: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actor_sees_observer_path,
		timeout_seconds
	)
	if not bool(actor_sees_observer.get("ok", false)):
		return failed("wait_for_client_b_verification", str(
			actor_sees_observer.get("reason", "Client B did not verify client A.")
		), {
			"path": actor_sees_observer_path,
		})

	var first_two_verified_path: String = coordination_dir.path_join(
		E2ECoordination.FIRST_TWO_CLIENTS_VERIFIED_FILE
	)
	write_error = E2ECoordination.write_json(first_two_verified_path, {
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_first_two_clients", "Could not publish the A+B verification barrier.", {
			"path": first_two_verified_path,
			"error": error_string(write_error),
		})

	var joiner_ready_path: String = coordination_dir.path_join(E2ECoordination.JOINER_READY_FILE)
	var joiner_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		joiner_ready_path,
		timeout_seconds
	)
	if not bool(joiner_ready.get("ok", false)):
		return failed("wait_for_client_c", str(joiner_ready.get("reason", "Client C was not ready.")), {
			"path": joiner_ready_path,
		})
	var joiner_payload: Dictionary = joiner_ready.get("payload", {})
	var joiner_entity_id: int = int(joiner_payload.get("entity_id", 0))
	if joiner_entity_id <= 0:
		return failed("read_client_c_identity", "Client C published an invalid entity id.", {
			"path": joiner_ready_path,
			"entity_id": joiner_entity_id,
		})

	var joiner_spawn: EntitySpawnedGameEvent = await session.wait_for_entity_spawned_event(
		joiner_entity_id,
		timeout_seconds
	)
	var joiner_spawn_error: String = _validate_remote_player_spawn(joiner_spawn, joiner_entity_id)
	if not joiner_spawn_error.is_empty():
		return failed("observe_client_c_spawn", joiner_spawn_error, {
			"client_c_entity_id": joiner_entity_id,
		})
	var three_client_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
	if not await session.wait_for_exact_entity_ids(three_client_ids, timeout_seconds):
		return failed("verify_three_entities", "Client A did not have exactly clients A, B, and C.", {
			"expected_entity_ids": three_client_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})
	if not (session.get_entity(joiner_entity_id) is RemoteEntity):
		return failed("verify_client_c_remote", "Client A did not represent client C as a remote entity.", {
			"client_c_entity_id": joiner_entity_id,
		})
	if not await session.wait_for_entities_near_spawn_positions(
		three_client_ids,
		SPAWN_POSITION_TOLERANCE,
		timeout_seconds
	):
		return failed("verify_three_spawn_positions", "Client A placed a client away from its spawn event position.", {
			"max_distance": SPAWN_POSITION_TOLERANCE,
			"positions": session.get_entity_spawn_position_details(three_client_ids),
		})
	var three_client_spawn_positions: Array[Dictionary] = session.get_entity_spawn_position_details(
		three_client_ids
	)

	var observer_sees_joiner_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_SEES_JOINER_FILE
	)
	write_error = E2ECoordination.write_json(observer_sees_joiner_path, {
		"client_c_entity_id": joiner_entity_id,
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_client_a_sees_c", "Client A could not publish its A+B+C verification.", {
			"path": observer_sees_joiner_path,
			"error": error_string(write_error),
		})

	var actor_sees_joiner_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_SEES_JOINER_FILE
	)
	var actor_sees_joiner: Dictionary = await E2ECoordination.wait_for_json(
		self,
		actor_sees_joiner_path,
		timeout_seconds
	)
	if not bool(actor_sees_joiner.get("ok", false)):
		return failed("wait_for_client_b_sees_c", str(
			actor_sees_joiner.get("reason", "Client B did not verify client C.")
		), {
			"path": actor_sees_joiner_path,
		})
	var joiner_verified_path: String = coordination_dir.path_join(
		E2ECoordination.JOINER_SEES_EXISTING_CLIENTS_FILE
	)
	var joiner_verified: Dictionary = await E2ECoordination.wait_for_json(
		self,
		joiner_verified_path,
		timeout_seconds
	)
	if not bool(joiner_verified.get("ok", false)):
		return failed("wait_for_client_c_verification", str(
			joiner_verified.get("reason", "Client C did not verify clients A and B.")
		), {
			"path": joiner_verified_path,
		})

	var three_clients_ready_path: String = coordination_dir.path_join(
		E2ECoordination.THREE_CLIENTS_READY_FILE
	)
	write_error = E2ECoordination.write_json(three_clients_ready_path, {
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_three_clients", "Could not publish the A+B+C verification barrier.", {
			"path": three_clients_ready_path,
			"error": error_string(write_error),
		})

	var origin: Vector3 = session.get_entity_position(actor_entity_id)
	session.clear_movement_snapshots()
	session.clear_equipment_changed_events()

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

	var equipment_event: EntityEquipmentChangedGameEvent = await session.wait_for_entity_equipment_changed_event(
		actor_entity_id,
		1,
		timeout_seconds
	)
	if equipment_event == null:
		return failed("observe_remote_equipment_event", "Observer did not receive the actor's equipment game event.", {
			"actor_entity_id": actor_entity_id,
			"item_instance_id": SWORD_INSTANCE_ID,
		})
	var event_error: String = _validate_equipment_event(equipment_event, actor_entity_id)
	if not event_error.is_empty():
		return failed("validate_remote_equipment_event", event_error, {
			"actor_entity_id": actor_entity_id,
			"event": equipment_event.toString(),
		})

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
		"equipment_event_revision": equipment_event.equipment_revision,
		"equipment_event_source": equipment_event.source,
		"first_two_entity_ids": first_two_ids,
		"first_two_spawn_positions": first_two_spawn_positions,
		"three_client_entity_ids": three_client_ids,
		"three_client_spawn_positions": three_client_spawn_positions,
		"client_b_spawn_sequence": actor_spawn.local_sequence,
		"client_c_spawn_sequence": joiner_spawn.local_sequence,
		"despawn_observed": true,
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

func _validate_equipment_event(
		event: EntityEquipmentChangedGameEvent,
		actor_entity_id: int
) -> String:
	if event.entity_id != actor_entity_id:
		return "Equipment event targeted the wrong entity."
	if event.source != GameEvent.Source.SERVER_AUTHORITATIVE:
		return "Equipment event was not marked server-authoritative."
	if event.equipment_revision != 1:
		return "Equipment event had an unexpected revision."
	if event.changes.size() != 1:
		return "Equipment event did not contain exactly one change."

	var change: Dictionary = event.changes[0]
	if int(change.get("slot_id", -1)) != Equippable.SlotId.Right_Hand:
		return "Equipment event targeted the wrong slot."
	if int(change.get("operation", -1)) != EntityEquipmentChangedGameEvent.OPERATION_SET:
		return "Equipment event had the wrong operation."
	if str(change.get("item_instance_id", "")) != SWORD_INSTANCE_ID:
		return "Equipment event had the wrong item instance id."
	if str(change.get("template_resource_path", "")) != SWORD_TEMPLATE_PATH:
		return "Equipment event had the wrong template resource path."
	return ""
