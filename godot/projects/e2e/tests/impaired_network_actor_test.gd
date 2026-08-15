extends E2ETestCase

const MOVE_ACTION: StringName = &"move_forward"
const MIN_MOVEMENT_DISTANCE: float = 0.25
const MAX_SETTLED_HORIZONTAL_SPEED: float = 0.01
const LOCAL_CONVERGENCE_DISTANCE: float = 0.05
const EXACTLY_ONCE_OBSERVATION_SECONDS: float = 1.0
const SWORD_TEMPLATE_PATH: String = "res://projects/e2e/fixtures/equipment/e2e_sword.tres"
const SWORD_INSTANCE_ID: String = "e2e_impaired_network_sword"

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var coordination_dir: String = str(config.get("coordination_dir", ""))
	var wait_timeout: float = session.timeout_seconds
	if coordination_dir.is_empty():
		return failed("configure", "Impaired-network actor requires a coordination directory.")

	var actor_entity_id: int = session.loaded_character.entity_id
	var actor_ready_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_ACTOR_READY_FILE
	)
	var write_error: Error = E2ECoordination.write_json(actor_ready_path, {
		"entity_id": actor_entity_id,
	})
	if write_error != OK:
		return failed("publish_actor_ready", "Could not publish the actor identity.", {
			"path": actor_ready_path,
			"error": error_string(write_error),
		})

	var observer_ready_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_OBSERVER_READY_FILE
	)
	var observer_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		observer_ready_path,
		wait_timeout
	)
	if not bool(observer_ready.get("ok", false)):
		return failed("wait_for_observer", str(observer_ready.get("reason", "Client A was not ready.")), {
			"path": observer_ready_path,
		})
	var observer_payload: Dictionary = observer_ready.get("payload", {})
	var observer_entity_id: int = int(observer_payload.get("entity_id", 0))
	if observer_entity_id <= 0:
		return failed("read_observer_identity", "Client A published an invalid entity id.", {
			"entity_id": observer_entity_id,
		})

	if not await session.wait_for_entity_spawned_event_count(
		observer_entity_id,
		1,
		wait_timeout
	):
		return failed("observe_client_a_spawn", "Timed out waiting for client A's reliable spawn event.")
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
	var observer_sees_actor: Dictionary = await E2ECoordination.wait_for_json(
		self,
		observer_sees_actor_path,
		wait_timeout
	)
	if not bool(observer_sees_actor.get("ok", false)):
		return failed("wait_for_observer_verification", str(
			observer_sees_actor.get("reason", "Client A did not verify client B.")
		))

	var first_two_verified_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_FIRST_TWO_VERIFIED_FILE
	)
	write_error = E2ECoordination.write_json(first_two_verified_path, {
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_first_two_verified", "Could not publish the A+B barrier.", {
			"error": error_string(write_error),
		})

	var joiner_ready_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_JOINER_READY_FILE
	)
	var joiner_ready: Dictionary = await E2ECoordination.wait_for_json(
		self,
		joiner_ready_path,
		wait_timeout
	)
	if not bool(joiner_ready.get("ok", false)):
		return failed("wait_for_joiner", str(joiner_ready.get("reason", "Client C was not ready.")))
	var joiner_payload: Dictionary = joiner_ready.get("payload", {})
	var joiner_entity_id: int = int(joiner_payload.get("entity_id", 0))
	if joiner_entity_id <= 0:
		return failed("read_joiner_identity", "Client C published an invalid entity id.")

	if not await session.wait_for_entity_spawned_event_count(
		joiner_entity_id,
		1,
		wait_timeout
	):
		return failed("observe_client_c_spawn", "Timed out waiting for client C's reliable spawn event.")
	var all_entity_ids: Array[int] = [observer_entity_id, actor_entity_id, joiner_entity_id]
	var all_entities_error: String = await _validate_entities(
		session,
		all_entity_ids,
		wait_timeout
	)
	if not all_entities_error.is_empty():
		return failed("verify_all_clients", all_entities_error, {
			"expected_entity_ids": all_entity_ids,
			"actual_entity_ids": session.get_entity_ids(),
		})

	for peer_file: String in [
		E2ECoordination.IMPAIRED_OBSERVER_SEES_ALL_FILE,
		E2ECoordination.IMPAIRED_JOINER_SEES_ALL_FILE,
	]:
		var peer_path: String = coordination_dir.path_join(peer_file)
		var peer_result: Dictionary = await E2ECoordination.wait_for_json(
			self,
			peer_path,
			wait_timeout
		)
		if not bool(peer_result.get("ok", false)):
			return failed("wait_for_peer_spawn_convergence", str(
				peer_result.get("reason", "A peer did not converge on A+B+C.")
			), {
				"path": peer_path,
			})

	var all_ready_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_ALL_CLIENTS_READY_FILE
	)
	write_error = E2ECoordination.write_json(all_ready_path, {
		"entity_ids": session.get_entity_ids(),
	})
	if write_error != OK:
		return failed("publish_all_clients_ready", "Could not publish the action barrier.", {
			"error": error_string(write_error),
		})

	for action_ready_file: String in [
		E2ECoordination.IMPAIRED_OBSERVER_ACTION_READY_FILE,
		E2ECoordination.IMPAIRED_JOINER_ACTION_READY_FILE,
	]:
		var action_ready_path: String = coordination_dir.path_join(action_ready_file)
		var action_ready: Dictionary = await E2ECoordination.wait_for_json(
			self,
			action_ready_path,
			wait_timeout
		)
		if not bool(action_ready.get("ok", false)):
			return failed("wait_for_peer_action_barrier", str(
				action_ready.get("reason", "A peer did not prepare its observation buffers.")
			), {
				"path": action_ready_path,
			})

	var origin: Vector3 = session.get_local_position()
	session.clear_movement_snapshots()
	session.clear_equipment_changed_events()
	Input.action_press(MOVE_ACTION)
	var moved_snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_authoritative_position_changed(
		actor_entity_id,
		origin,
		MIN_MOVEMENT_DISTANCE,
		wait_timeout
	)
	Input.action_release(MOVE_ACTION)
	if moved_snapshot == null:
		return failed("move_actor", "Timed out waiting for authoritative movement under impairment.", {
			"origin": str(origin),
		})

	var settled_snapshot: MovementSnapshotMsg.EntitySnapshot = await session.wait_for_entity_movement_settled(
		actor_entity_id,
		moved_snapshot.last_processed_movement_seq + 1,
		MAX_SETTLED_HORIZONTAL_SPEED,
		wait_timeout
	)
	if settled_snapshot == null:
		return failed("settle_actor", "Timed out waiting for the server-authoritative stop.", {
			"last_processed_seq": moved_snapshot.last_processed_movement_seq,
		})
	if settled_snapshot.position.distance_to(origin) < MIN_MOVEMENT_DISTANCE:
		return failed("settle_actor", "The settled authoritative position did not move far enough.")
	if not await session.wait_for_entity_position_near(
		actor_entity_id,
		settled_snapshot.position,
		LOCAL_CONVERGENCE_DISTANCE,
		wait_timeout
	):
		return failed("reconcile_actor", "The local actor did not converge on its authoritative position.", {
			"authoritative_position": str(settled_snapshot.position),
			"local_position": str(session.get_local_position()),
		})

	var request_id: int = session.try_equip_item(
		_make_item(SWORD_TEMPLATE_PATH, SWORD_INSTANCE_ID),
		Equippable.SlotId.Right_Hand
	)
	if request_id <= 0:
		return failed("equip_actor", "The actor could not send its equipment request.")
	var result_code: int = await session.wait_for_action_result(request_id, wait_timeout)
	if result_code != EntityEquipmentActionResultMsg.RESULT_OK:
		return failed("equip_actor", "The server did not accept the actor equipment request.", {
			"request_id": request_id,
			"result_code": result_code,
		})
	if not await session.wait_for_entity_equipment_changed_event_count(
		actor_entity_id,
		1,
		wait_timeout
	):
		return failed("observe_actor_equipment_event", "The actor did not receive its reliable equipment event.")
	var equipped: EquippableItem = await session.wait_for_equipped(
		Equippable.SlotId.Right_Hand,
		SWORD_INSTANCE_ID,
		wait_timeout
	)
	if equipped == null:
		return failed("converge_actor_equipment", "The actor did not apply its replicated equipment state.")
	await get_tree().create_timer(EXACTLY_ONCE_OBSERVATION_SECONDS).timeout
	if session.get_entity_equipment_changed_event_count(actor_entity_id) != 1:
		return failed("count_actor_equipment_events", "The actor observed duplicate equipment events.", {
			"count": session.get_entity_equipment_changed_event_count(actor_entity_id),
		})

	var actor_state_path: String = coordination_dir.path_join(
		E2ECoordination.IMPAIRED_ACTOR_STATE_FILE
	)
	write_error = E2ECoordination.write_json(actor_state_path, {
		"entity_id": actor_entity_id,
		"settled_server_tick": settled_snapshot.server_tick,
		"settled_position": E2ECoordination.vector3_to_dictionary(settled_snapshot.position),
		"equipment_item": equipped.instance_id,
	})
	if write_error != OK:
		return failed("publish_actor_state", "Could not publish authoritative actor state.", {
			"error": error_string(write_error),
		})

	var peer_convergence: Array[Dictionary] = []
	for convergence_file: String in [
		E2ECoordination.IMPAIRED_OBSERVER_CONVERGED_FILE,
		E2ECoordination.IMPAIRED_JOINER_CONVERGED_FILE,
	]:
		var convergence_path: String = coordination_dir.path_join(convergence_file)
		var convergence: Dictionary = await E2ECoordination.wait_for_json(
			self,
			convergence_path,
			wait_timeout
		)
		if not bool(convergence.get("ok", false)):
			return failed("wait_for_peer_convergence", str(
				convergence.get("reason", "A peer did not reach eventual consistency.")
			), {
				"path": convergence_path,
			})
		peer_convergence.append(convergence.get("payload", {}))

	if session.get_entity_spawned_event_count(observer_entity_id) != 1 \
			or session.get_entity_spawned_event_count(joiner_entity_id) != 1:
		return failed("count_remote_spawn_events", "The actor observed duplicate remote spawn events.", {
			"client_a_count": session.get_entity_spawned_event_count(observer_entity_id),
			"client_c_count": session.get_entity_spawned_event_count(joiner_entity_id),
		})

	return passed({
		"entity_ids": all_entity_ids,
		"origin": str(origin),
		"authoritative_position": str(settled_snapshot.position),
		"local_position": str(session.get_local_position()),
		"server_tick": settled_snapshot.server_tick,
		"remote_spawn_event_counts": {
			str(observer_entity_id): session.get_entity_spawned_event_count(observer_entity_id),
			str(joiner_entity_id): session.get_entity_spawned_event_count(joiner_entity_id),
		},
		"equipment_event_count": session.get_entity_equipment_changed_event_count(actor_entity_id),
		"equipment_item": equipped.instance_id,
		"peer_convergence": peer_convergence,
	})

func _validate_entities(
	session: E2ESession,
	entity_ids: Array[int],
	wait_timeout: float
) -> String:
	if not await session.wait_for_exact_entity_ids(entity_ids, wait_timeout):
		return "The entity registry did not converge on the exact expected ids."
	return ""

func _make_item(template_path: String, item_instance_id: String) -> EquippableItem:
	var template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
	return EquippableItem.create(template, 1, item_instance_id)
