extends E2ETestCase

const MOVE_ACTION: StringName = &"move_forward"
const MIN_MOVEMENT_DISTANCE: float = 0.25
const MAX_SETTLED_HORIZONTAL_SPEED: float = 0.01
const LOCAL_CONVERGENCE_DISTANCE: float = 0.05
const SPAWN_POSITION_TOLERANCE: float = 0.002
const SWORD_TEMPLATE_PATH: String = "res://projects/e2e/fixtures/equipment/e2e_sword.tres"
const SWORD_INSTANCE_ID: String = "e2e_multi_client_sword"

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	if coordination_dir.is_empty():
		return failed("configure", "Multi-client actor requires a coordination directory.")

	var actor_entity_id: int = session.loaded_character.entity_id
	var actor_ready_path: String = coordination_dir.path_join(E2ECoordination.ACTOR_READY_FILE)
	var write_error: Error = E2ECoordination.write_json(actor_ready_path, {
		"entity_id": actor_entity_id,
	})
	if write_error != OK:
		return failed("publish_actor_ready", "Could not publish actor identity.", {
			"path": actor_ready_path,
			"error": error_string(write_error),
		})

	var observer_ready_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_READY_FILE
	)
	var observer_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		observer_ready_path,
		timeout_seconds
	)
	if not bool(observer_ready.get("ok", false)):
		return failed("wait_for_observer", str(observer_ready.get("reason", "Client A was not ready.")), {
			"actor_entity_id": actor_entity_id,
			"path": observer_ready_path,
		})
	var observer_payload: Dictionary = observer_ready.get("payload", {})
	var observer_entity_id: int = int(observer_payload.get("entity_id", 0))
	if observer_entity_id <= 0:
		return failed("read_observer_identity", "Client A published an invalid entity id.", {
			"path": observer_ready_path,
			"entity_id": observer_entity_id,
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
			"client_b_entity_id": actor_entity_id,
		})
	var first_two_ids: Array[int] = [observer_entity_id, actor_entity_id]
	if not await session.wait_for_exact_entity_ids(first_two_ids, timeout_seconds):
		return failed("verify_first_two_entities", "Client B did not have exactly clients A and B.", {
			"expected_entity_ids": first_two_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})
	if not (session.get_entity(actor_entity_id) is Player):
		return failed("verify_client_b_local", "Client B did not represent itself as the local player.", {
			"client_b_entity_id": actor_entity_id,
		})
	if not (session.get_entity(observer_entity_id) is RemoteEntity):
		return failed("verify_client_a_remote", "Client B did not represent client A as a remote entity.", {
			"client_a_entity_id": observer_entity_id,
		})
	if not await session.wait_for_entities_near_spawn_positions(
		first_two_ids,
		SPAWN_POSITION_TOLERANCE,
		timeout_seconds
	):
		return failed("verify_first_two_spawn_positions", "Client B placed A or B away from its spawn event position.", {
			"max_distance": SPAWN_POSITION_TOLERANCE,
			"positions": session.get_entity_spawn_position_details(first_two_ids),
		})
	var first_two_spawn_positions: Array[Dictionary] = session.get_entity_spawn_position_details(
		first_two_ids
	)

	var actor_sees_observer_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_SEES_OBSERVER_FILE
	)
	write_error = E2ECoordination.write_json(actor_sees_observer_path, {
		"client_a_entity_id": observer_entity_id,
		"client_b_entity_id": actor_entity_id,
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_client_b_sees_a", "Client B could not publish its A+B verification.", {
			"path": actor_sees_observer_path,
			"error": error_string(write_error),
		})

	var first_two_verified_path: String = coordination_dir.path_join(
		E2ECoordination.FIRST_TWO_CLIENTS_VERIFIED_FILE
	)
	var first_two_verified: Dictionary = await E2ECoordination.wait_for_json(
		self,
		first_two_verified_path,
		timeout_seconds
	)
	if not bool(first_two_verified.get("ok", false)):
		return failed("wait_for_first_two_clients", str(
			first_two_verified.get("reason", "Clients A and B were not verified.")
		), {
			"path": first_two_verified_path,
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
		return failed("verify_three_entities", "Client B did not have exactly clients A, B, and C.", {
			"expected_entity_ids": three_client_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})
	if not (session.get_entity(joiner_entity_id) is RemoteEntity):
		return failed("verify_client_c_remote", "Client B did not represent client C as a remote entity.", {
			"client_c_entity_id": joiner_entity_id,
		})
	if not await session.wait_for_entities_near_spawn_positions(
		three_client_ids,
		SPAWN_POSITION_TOLERANCE,
		timeout_seconds
	):
		return failed("verify_three_spawn_positions", "Client B placed a client away from its spawn event position.", {
			"max_distance": SPAWN_POSITION_TOLERANCE,
			"positions": session.get_entity_spawn_position_details(three_client_ids),
		})
	var three_client_spawn_positions: Array[Dictionary] = session.get_entity_spawn_position_details(
		three_client_ids
	)

	var actor_sees_joiner_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_SEES_JOINER_FILE
	)
	write_error = E2ECoordination.write_json(actor_sees_joiner_path, {
		"client_c_entity_id": joiner_entity_id,
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_client_b_sees_c", "Client B could not publish its A+B+C verification.", {
			"path": actor_sees_joiner_path,
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

	var origin: Vector3 = session.get_local_position()
	session.clear_movement_snapshots()
	Input.action_press(MOVE_ACTION)
	var snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_authoritative_position_changed(
		actor_entity_id,
		origin,
		MIN_MOVEMENT_DISTANCE,
		timeout_seconds
	)
	Input.action_release(MOVE_ACTION)
	if snapshot == null:
		return failed("move_actor", "Timed out waiting for the actor's authoritative movement snapshot.", {
			"actor_entity_id": actor_entity_id,
			"origin": str(origin),
		})
	if not await session.wait_for_local_position_changed(origin, MIN_MOVEMENT_DISTANCE, timeout_seconds):
		return failed("move_actor", "Actor did not move after authoritative snapshots.", {
			"actor_entity_id": actor_entity_id,
			"origin": str(origin),
			"current": str(session.get_local_position()),
			"last_processed_seq": snapshot.last_processed_movement_seq,
		})

	var settled_snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_movement_settled(
		actor_entity_id,
		snapshot.last_processed_movement_seq + 1,
		MAX_SETTLED_HORIZONTAL_SPEED,
		timeout_seconds
	)
	if settled_snapshot == null:
		return failed("settle_actor_movement", "Timed out waiting for a post-release authoritative stop snapshot.", {
			"actor_entity_id": actor_entity_id,
			"min_processed_seq": snapshot.last_processed_movement_seq + 1,
			"max_horizontal_speed": MAX_SETTLED_HORIZONTAL_SPEED,
		})
	if settled_snapshot.position.distance_to(origin) < MIN_MOVEMENT_DISTANCE:
		return failed("settle_actor_movement", "Actor's settled authoritative position did not move enough.", {
			"actor_entity_id": actor_entity_id,
			"origin": str(origin),
			"authoritative_position": str(settled_snapshot.position),
			"server_tick": settled_snapshot.server_tick,
		})
	if not await session.wait_for_entity_position_near(
		actor_entity_id,
		settled_snapshot.position,
		LOCAL_CONVERGENCE_DISTANCE,
		timeout_seconds
	):
		return failed("reconcile_actor_position", "Actor did not converge to its authoritative position.", {
			"actor_entity_id": actor_entity_id,
			"authoritative_position": str(settled_snapshot.position),
			"local_position": str(session.get_local_position()),
			"max_distance": LOCAL_CONVERGENCE_DISTANCE,
			"server_tick": settled_snapshot.server_tick,
		})

	var authoritative_path: String = coordination_dir.path_join(
		E2ECoordination.ACTOR_AUTHORITATIVE_MOVEMENT_FILE
	)
	write_error = E2ECoordination.write_json(authoritative_path, {
		"entity_id": actor_entity_id,
		"server_tick": settled_snapshot.server_tick,
		"last_processed_seq": settled_snapshot.last_processed_movement_seq,
		"position": E2ECoordination.vector3_to_dictionary(settled_snapshot.position),
		"velocity": E2ECoordination.vector3_to_dictionary(settled_snapshot.velocity),
		"local_position": E2ECoordination.vector3_to_dictionary(session.get_local_position()),
	})
	if write_error != OK:
		return failed("publish_authoritative_movement", "Could not publish actor movement state.", {
			"path": authoritative_path,
			"error": error_string(write_error),
		})

	var request_id: int = session.try_equip_item(
		_make_item(SWORD_TEMPLATE_PATH, SWORD_INSTANCE_ID),
		Equippable.SlotId.Right_Hand
	)
	if request_id <= 0:
		return failed("equip_actor", "Could not send the actor's equip request.", {
			"actor_entity_id": actor_entity_id,
		})
	var result_code: int = await session.wait_for_action_result(request_id, timeout_seconds)
	if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return failed("equip_actor", "Actor equip request did not succeed.", {
			"actor_entity_id": actor_entity_id,
			"request_id": request_id,
			"result_code": result_code,
		})
	var equipped: EquippableItem = await session.wait_for_equipped(
		Equippable.SlotId.Right_Hand,
		SWORD_INSTANCE_ID,
		timeout_seconds
	)
	if equipped == null:
		return failed("equip_actor", "Actor did not observe its replicated equipment.", {
			"actor_entity_id": actor_entity_id,
			"request_id": request_id,
		})

	var observed_path: String = coordination_dir.path_join(
		E2ECoordination.OBSERVER_ACTIONS_OBSERVED_FILE
	)
	var observed: Dictionary = await E2ECoordination.wait_for_json(
		self,
		observed_path,
		timeout_seconds
	)
	if not bool(observed.get("ok", false)):
		return failed("wait_for_observer_assertions", str(observed.get("reason", "Observer did not finish.")), {
			"actor_entity_id": actor_entity_id,
			"path": observed_path,
		})

	return passed({
		"entity_id": actor_entity_id,
		"origin": str(origin),
		"current": str(session.get_local_position()),
		"authoritative_position": str(settled_snapshot.position),
		"authoritative_drift": session.get_local_position().distance_to(settled_snapshot.position),
		"server_tick": settled_snapshot.server_tick,
		"last_processed_seq": settled_snapshot.last_processed_movement_seq,
		"equipment_item": SWORD_INSTANCE_ID,
		"first_two_entity_ids": first_two_ids,
		"first_two_spawn_positions": first_two_spawn_positions,
		"three_client_entity_ids": three_client_ids,
		"three_client_spawn_positions": three_client_spawn_positions,
		"client_a_spawn_sequence": observer_spawn.local_sequence,
		"client_c_spawn_sequence": joiner_spawn.local_sequence,
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

func _make_item(template_path: String, item_instance_id: String) -> EquippableItem:
	var template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
	return EquippableItem.create(template, 1, item_instance_id)
