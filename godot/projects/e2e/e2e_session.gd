class_name E2ESession
extends Node

const DEFAULT_USERNAME: String = "e2e"
const DEFAULT_ZONE_ID: String = "mvp"
const DEFAULT_ORCHESTRATOR_URL: String = OrchestratorAPI.DEFAULT_ORCHESTRATOR_URL
const DEFAULT_TIMEOUT_SECONDS: float = 10.0
const ACTION_RESULT_TIMEOUT: int = -1

@export var orchestrator_api: OrchestratorAPI
@export var ingame_scene: PackedScene

var username: String = DEFAULT_USERNAME
var target_zone_id: String = DEFAULT_ZONE_ID
var orchestrator_url: String = DEFAULT_ORCHESTRATOR_URL
var timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS

var character: ClientCharacterSummary = null
var redirect: ClientZoneRedirect = null
var loaded_character: ClientLoadedCharacter = null

var failure_step: String = ""
var failure_reason: String = ""
var failure_details: Dictionary = {}

var _ingame_screen: IngameScreen = null
var _game_server_api: GameServerAPI = null
var _entity_spawner: ClientEntitySpawner = null
var _client_actions: ClientActions = null
var _action_result_codes: Dictionary[int, int] = {}
var _movement_snapshots: Array[MovementSnapshotMsg] = []

func start(config: Dictionary = {}) -> bool:
	username = str(config.get("username", DEFAULT_USERNAME))
	target_zone_id = str(config.get("zone_id", DEFAULT_ZONE_ID)).strip_edges().to_lower()
	orchestrator_url = str(config.get("orchestrator_url", DEFAULT_ORCHESTRATOR_URL))
	timeout_seconds = float(config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))

	if target_zone_id.is_empty():
		return _fail("configure", "Zone id cannot be empty.")
	if username.strip_edges().is_empty():
		return _fail("configure", "Username cannot be empty.")

	if not _configure_orchestrator_api():
		return false

	var login_result: Dictionary = await _login()
	if not bool(login_result.get("ok", false)):
		return false

	character = _select_character(login_result)
	if character == null:
		return false

	var redirect_result: Dictionary = await _request_redirect(character)
	if not bool(redirect_result.get("ok", false)):
		return false

	if not _load_ingame_screen():
		return false

	var entered_zone: bool = await _connect_and_enter_zone()
	if not entered_zone:
		return false

	var load_zone_error: Error = _ingame_screen.load_zone(target_zone_id)
	if load_zone_error != OK:
		return _fail("load_zone", "Client zone scene could not be loaded.", {
			"zone_id": target_zone_id,
			"error": error_string(load_zone_error),
		})

	var entered_world: bool = await _wait_for_entered_world()
	return entered_world

func close() -> void:
	if _game_server_api != null:
		_game_server_api.disconnect_from_server()
	if orchestrator_api != null:
		orchestrator_api.close()

func local_player() -> Player:
	if _entity_spawner == null:
		return null
	return _entity_spawner.get_local_player()

func try_equip_item(item: EquippableItem, slot_id: Equippable.SlotId) -> int:
	if _client_actions == null:
		return -1
	return _client_actions.try_equip_item(item, slot_id)

func try_unequip_slot(slot_id: Equippable.SlotId) -> int:
	if _client_actions == null:
		return -1
	return _client_actions.try_unequip_slot(slot_id)

func wait_for_action_result(
		request_id: int,
		wait_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> int:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < wait_timeout_seconds:
		if _action_result_codes.has(request_id):
			var result_code: int = int(_action_result_codes.get(request_id))
			_action_result_codes.erase(request_id)
			return result_code
		if _game_server_api != null:
			_game_server_api.poll()
		await get_tree().process_frame
	return ACTION_RESULT_TIMEOUT

func wait_for_equipped(
		slot_id: Equippable.SlotId,
		item_instance_id: String,
		wait_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> EquippableItem:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < wait_timeout_seconds:
		var player: Player = local_player()
		if player != null:
			var item: EquippableItem = player.equipment.get_equipped(slot_id)
			if item != null and item.instance_id == item_instance_id:
				return item
		if _game_server_api != null:
			_game_server_api.poll()
		await get_tree().process_frame
	return null

func wait_for_unequipped(
		slot_id: Equippable.SlotId,
		wait_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> bool:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < wait_timeout_seconds:
		var player: Player = local_player()
		if player != null and not player.equipment.has_equipped_slot(slot_id):
			return true
		if _game_server_api != null:
			_game_server_api.poll()
		await get_tree().process_frame
	return false

func get_local_position() -> Vector3:
	var player: Player = local_player()
	if player == null:
		return Vector3.ZERO
	return player.get_body().global_position

func wait_for_local_position_changed(
		origin: Vector3,
		min_distance: float,
		wait_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> bool:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < wait_timeout_seconds:
		if get_local_position().distance_to(origin) >= min_distance:
			return true
		if _game_server_api != null:
			_game_server_api.poll()
		await get_tree().process_frame
	return false

func wait_for_local_movement_snapshot(
		min_processed_seq: int,
		wait_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> MovementSnapshotMsg.EntitySnapshot:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < wait_timeout_seconds:
		for snapshot: MovementSnapshotMsg in _movement_snapshots:
			var entity_snapshot: MovementSnapshotMsg.EntitySnapshot = _find_local_snapshot(snapshot)
			if entity_snapshot == null:
				continue
			if entity_snapshot.last_processed_movement_seq >= min_processed_seq:
				return entity_snapshot
		if _game_server_api != null:
			_game_server_api.poll()
		await get_tree().process_frame
	return null

func clear_movement_snapshots() -> void:
	_movement_snapshots.clear()

func to_result(ok: bool) -> Dictionary:
	var loaded_character_id: int = 0
	var loaded_entity_id: int = 0
	var loaded_zone_id: String = ""

	if loaded_character != null:
		loaded_character_id = loaded_character.character_id
		loaded_entity_id = loaded_character.entity_id
		loaded_zone_id = loaded_character.zone_id

	return {
		"ok": ok,
		"suite": "boot_enter_world",
		"username": username,
		"zone_id": target_zone_id,
		"loaded_zone_id": loaded_zone_id,
		"character_id": loaded_character_id,
		"entity_id": loaded_entity_id,
		"failure_step": failure_step,
		"failure_reason": failure_reason,
		"failure_details": failure_details,
	}

func _configure_orchestrator_api() -> bool:
	if orchestrator_api == null:
		return _fail("configure", "E2ESession requires an OrchestratorAPI node.")

	orchestrator_api.orchestrator_url = orchestrator_url
	orchestrator_api.connect_timeout_seconds = timeout_seconds
	orchestrator_api.response_timeout_seconds = timeout_seconds
	return true

func _login() -> Dictionary:
	var result: Dictionary = await orchestrator_api.request_login(username)
	if not bool(result.get("ok", false)):
		_fail("orchestrator_login", str(result.get("reason", "Login failed.")), {
			"orchestrator_url": orchestrator_url,
		})
	return result

func _select_character(login_result: Dictionary) -> ClientCharacterSummary:
	var characters: Array = login_result.get("characters", [])
	for value: Variant in characters:
		var candidate: ClientCharacterSummary = value as ClientCharacterSummary
		if candidate == null:
			continue
		if candidate.zone_id.strip_edges().to_lower() == target_zone_id:
			return candidate

	_fail("select_character", "No character is available in the target zone.", {
		"zone_id": target_zone_id,
		"characters": characters.size(),
	})
	return null

func _request_redirect(selected_character: ClientCharacterSummary) -> Dictionary:
	var result: Dictionary = await orchestrator_api.request_character_login(selected_character.character_id)
	if not bool(result.get("ok", false)):
		_fail("character_select", str(result.get("reason", "Character select failed.")), {
			"character_id": selected_character.character_id,
		})
		return result

	redirect = result.get("redirect", null) as ClientZoneRedirect
	if redirect == null:
		_fail("character_select", "Orchestrator did not return a zone redirect.")
		return {"ok": false}
	if redirect.zone_id.strip_edges().to_lower() != target_zone_id:
		_fail("character_select", "Orchestrator returned an unexpected zone.", {
			"expected_zone_id": target_zone_id,
			"actual_zone_id": redirect.zone_id,
		})
		return {"ok": false}
	if redirect.address.strip_edges().is_empty() or redirect.port <= 0 or redirect.transfer_token.is_empty():
		_fail("character_select", "Orchestrator returned an incomplete zone redirect.", {
			"zone_id": redirect.zone_id,
			"address": redirect.address,
			"port": redirect.port,
			"token_length": redirect.transfer_token.length(),
		})
		return {"ok": false}

	return result

func _load_ingame_screen() -> bool:
	if ingame_scene == null:
		return _fail("load_ingame_screen", "E2ESession requires an in-game screen scene.")

	_ingame_screen = ingame_scene.instantiate() as IngameScreen
	if _ingame_screen == null:
		return _fail("load_ingame_screen", "In-game scene did not instantiate an IngameScreen.", {
			"scene_path": ingame_scene.resource_path,
		})
	add_child(_ingame_screen)

	_game_server_api = _ingame_screen.api
	if _game_server_api == null:
		return _fail("load_ingame_screen", "In-game screen has no GameServerAPI.")
	_game_server_api.movement_snapshot_received.connect(_on_movement_snapshot_received)

	_entity_spawner = _ingame_screen.entity_spawner
	if _entity_spawner == null:
		return _fail("load_ingame_screen", "In-game screen has no ClientEntitySpawner.")

	_client_actions = _ingame_screen.client_actions
	if _client_actions == null:
		return _fail("load_ingame_screen", "In-game screen has no ClientActions.")
	_client_actions.action_resolved.connect(_on_action_resolved)

	return true

func _connect_and_enter_zone() -> bool:
	_ingame_screen.begin_character_load(character, redirect)

	var connect_error: Error = await _game_server_api.connect_and_wait(
		redirect.address,
		redirect.port,
		timeout_seconds
	)
	if connect_error != OK:
		return _fail("connect_zone", "Could not connect to zone server.", {
			"address": redirect.address,
			"port": redirect.port,
			"error": error_string(connect_error),
		})

	var login_error: Error = _game_server_api.send_zone_login(
		character.character_id,
		redirect.transfer_token
	)
	if login_error != OK:
		return _fail("zone_login", "Could not send zone login.", {
			"character_id": character.character_id,
			"error": error_string(login_error),
		})

	return true

func _wait_for_entered_world() -> bool:
	var started_msec: int = Time.get_ticks_msec()
	while _elapsed_seconds(started_msec) < timeout_seconds:
		if _game_server_api != null:
			_game_server_api.poll()

		loaded_character = _ingame_screen.get_loaded_character()
		if (
				_ingame_screen.is_ingame_loaded()
				and loaded_character != null
				and _entity_spawner.local_entity_id > 0
				and _entity_spawner.get_local_player() != null
		):
			return true

		await get_tree().process_frame

	return _fail("enter_world", "Timed out waiting for loaded character and local player.", {
		"zone_loaded": _ingame_screen.get_loaded_zone_id(),
		"has_loaded_character": loaded_character != null,
		"local_entity_id": _entity_spawner.local_entity_id,
	})

func _on_action_resolved(
		_action_name: StringName,
		request_id: int,
		result_code: int) -> void:
	_action_result_codes[request_id] = result_code

func _on_movement_snapshot_received(snapshot: MovementSnapshotMsg) -> void:
	_movement_snapshots.append(snapshot)
	if _movement_snapshots.size() > 64:
		_movement_snapshots.pop_front()

func _find_local_snapshot(snapshot: MovementSnapshotMsg) -> MovementSnapshotMsg.EntitySnapshot:
	if _entity_spawner == null:
		return null
	for entity_snapshot: MovementSnapshotMsg.EntitySnapshot in snapshot.entities:
		if entity_snapshot.entity_id == _entity_spawner.local_entity_id:
			return entity_snapshot
	return null

func _fail(step: String, reason: String, details: Dictionary = {}) -> bool:
	failure_step = step
	failure_reason = reason
	failure_details = details
	push_error("E2E failed at %s: %s details=%s" % [step, reason, str(details)])
	return false

func _elapsed_seconds(started_msec: int) -> float:
	return float(Time.get_ticks_msec() - started_msec) / 1000.0
