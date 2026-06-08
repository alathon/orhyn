class_name ZoneConnectionManager
extends Node

signal succeeded(screen: IngameScreen)
signal failed(reason: String)

enum State {
	IDLE,
	REQUESTING_TOKEN,
	CONNECTING_ZONE,
	SENDING_ZONE_LOGIN,
	LOADING_ZONE,
	WAITING_CHARACTER,
	READY,
	FAILED,
	CANCELED,
}

const GATE_REQUEST_ZONE_TOKEN: StringName = &"request_zone_token"
const GATE_CONNECT_ZONE: StringName = &"connect_zone"
const GATE_LOAD_ZONE: StringName = &"load_zone"
const GATE_LOAD_CHARACTER: StringName = &"load_character"

@export var zone_connect_timeout_seconds: float = 5.0
@export var character_loaded_timeout_seconds: float = 8.0

@onready var _screen_manager: ScreenManager = %ScreenManager
@onready var _orchestrator_api: OrchestratorAPI = %OrchestratorAPI

var state: State = State.IDLE
var _active_screen: IngameScreen = null
var _loading_screen: LoadingScreen = null
var _gates: Dictionary = {}
var _run_id: int = 0

func login_character(character: ClientCharacterSummary) -> void:
	if state != State.IDLE:
		return

	_run_id += 1
	var current_run_id: int = _run_id
	_begin_loading(character.zone_id, "Requesting character login")

	state = State.REQUESTING_TOKEN
	var token_result: Dictionary = await _orchestrator_api.request_character_login(character.character_id)
	if not _is_current_run(current_run_id):
		return
	var redirect: ClientZoneRedirect = _read_redirect(token_result, current_run_id)
	if redirect == null:
		return

	await _enter_zone(character, redirect, current_run_id)

func transfer_to_zone(target_zone_id: String, zone_change_details: Dictionary = {}) -> void:
	if state != State.IDLE:
		return

	var current_screen: IngameScreen = _screen_manager.current_screen as IngameScreen
	if current_screen == null:
		failed.emit("Cannot change zones before entering the world.")
		return

	var loaded_character: ClientLoadedCharacter = current_screen.get_loaded_character()
	if loaded_character == null:
		failed.emit("Cannot change zones before the character is loaded.")
		return

	_run_id += 1
	var current_run_id: int = _run_id
	_begin_loading(target_zone_id, "Requesting zone change")

	state = State.REQUESTING_TOKEN
	var token_result: Dictionary = await _orchestrator_api.request_zone_change(target_zone_id, zone_change_details)
	if not _is_current_run(current_run_id):
		return
	var redirect: ClientZoneRedirect = _read_redirect(token_result, current_run_id)
	if redirect == null:
		return

	var character: ClientCharacterSummary = ClientCharacterSummary.create(
		loaded_character.character_id,
		loaded_character.display_name,
		redirect.zone_id,
		loaded_character.model_name,
		loaded_character.level
	)
	await _enter_zone(character, redirect, current_run_id)

func cancel(reason: String = "Canceled") -> void:
	if state == State.IDLE:
		return

	_run_id += 1
	state = State.CANCELED
	_cleanup_active_screen()
	if _loading_screen != null:
		_loading_screen.cancel_loading()
	_screen_manager.hide_loading_overlay()
	state = State.IDLE
	print("Client zone connection canceled: %s" % reason)

func is_running() -> bool:
	return state != State.IDLE and state != State.READY

func _begin_loading(target_zone_id: String, status: String) -> void:
	_gates.clear()
	_add_gate(GATE_REQUEST_ZONE_TOKEN, "Requesting zone token", 0.25)
	_add_gate(GATE_CONNECT_ZONE, "Connecting zone server", 0.25)
	_add_gate(GATE_LOAD_ZONE, "Loading zone world", 0.25)
	_add_gate(GATE_LOAD_CHARACTER, "Loading character", 0.25)
	_loading_screen = _screen_manager.show_loading_overlay()
	if _loading_screen != null:
		_loading_screen.start_loading("%s: %s" % [status, target_zone_id.to_upper()])
		_update_loading_screen()

func _enter_zone(character: ClientCharacterSummary, redirect: ClientZoneRedirect, current_run_id: int) -> void:
	var screen: IngameScreen = _screen_manager.prepare_ingame_screen()
	if screen == null:
		_fail(current_run_id, GATE_LOAD_ZONE, "In-game scene could not be created.")
		return

	_active_screen = screen
	var err: Error = await _connect_and_login(screen, character, redirect, current_run_id)
	if err != OK:
		return

	err = _load_zone(screen, redirect.zone_id, current_run_id)
	if err != OK:
		return

	await _wait_for_character(screen, current_run_id)

func _read_redirect(result: Dictionary, current_run_id: int) -> ClientZoneRedirect:
	if not bool(result.get("ok", false)):
		_fail(current_run_id, GATE_REQUEST_ZONE_TOKEN, str(result.get("reason", "Zone token request failed.")))
		return null

	var redirect: ClientZoneRedirect = result.get("redirect", null) as ClientZoneRedirect
	var validation_error: String = _validate_redirect(redirect)
	if not validation_error.is_empty():
		_fail(current_run_id, GATE_REQUEST_ZONE_TOKEN, validation_error)
		return null

	_complete_gate(GATE_REQUEST_ZONE_TOKEN, "Zone token received")
	return redirect

func _connect_and_login(
	screen: IngameScreen,
	character: ClientCharacterSummary,
	redirect: ClientZoneRedirect,
	current_run_id: int
) -> Error:
	state = State.CONNECTING_ZONE
	_set_gate_progress(GATE_CONNECT_ZONE, 0.15, "Connecting to %s" % redirect.zone_id.to_upper())
	screen.begin_character_load(character, redirect)

	var err: Error = await screen.api.connect_and_wait(
		redirect.address,
		redirect.port,
		zone_connect_timeout_seconds
	)
	if not _is_current_run(current_run_id):
		return ERR_BUSY
	if err != OK:
		_fail(current_run_id, GATE_CONNECT_ZONE, "Could not connect to zone.")
		return err

	state = State.SENDING_ZONE_LOGIN
	_set_gate_progress(GATE_CONNECT_ZONE, 0.70, "Entering zone")
	err = screen.api.send_zone_login(character.character_id, redirect.transfer_token)
	if err != OK:
		_fail(current_run_id, GATE_CONNECT_ZONE, "Could not enter zone.")
		return err

	_complete_gate(GATE_CONNECT_ZONE, "Zone login sent")
	return OK

func _load_zone(screen: IngameScreen, zone_id: String, current_run_id: int) -> Error:
	state = State.LOADING_ZONE
	_set_gate_progress(GATE_LOAD_ZONE, 0.15, "Loading %s" % zone_id.to_upper())
	var err: Error = screen.load_zone(zone_id)
	if not _is_current_run(current_run_id):
		return ERR_BUSY
	if err != OK:
		_fail(current_run_id, GATE_LOAD_ZONE, "Could not load zone.")
		return err

	_complete_gate(GATE_LOAD_ZONE, "Loaded %s" % zone_id.to_upper())
	_set_gate_progress(GATE_LOAD_CHARACTER, 0.35, "Loading character")
	return OK

func _wait_for_character(screen: IngameScreen, current_run_id: int) -> void:
	state = State.WAITING_CHARACTER
	var started_msec: int = Time.get_ticks_msec()
	while _is_current_run(current_run_id) and not screen.is_ingame_loaded():
		if _elapsed_seconds(started_msec) >= character_loaded_timeout_seconds:
			_fail(current_run_id, GATE_LOAD_CHARACTER, "Could not load character.")
			return
		await get_tree().process_frame

	if not _is_current_run(current_run_id):
		return

	var loaded_character: ClientLoadedCharacter = screen.get_loaded_character()
	if loaded_character != null:
		_set_gate_progress(GATE_LOAD_CHARACTER, 0.85, "Loaded %s" % loaded_character.display_name)
	_complete_gate(GATE_LOAD_CHARACTER, "Ready")
	state = State.READY
	_active_screen = null
	if _loading_screen != null:
		_loading_screen.finish_loading()
	_screen_manager.complete_ingame_transition(screen)
	succeeded.emit(screen)
	state = State.IDLE

func _validate_redirect(redirect: ClientZoneRedirect) -> String:
	if redirect == null:
		return "Orchestrator did not return a zone redirect."
	if redirect.zone_id.strip_edges().is_empty():
		return "Zone redirect did not include a zone."
	if redirect.address.strip_edges().is_empty():
		return "Zone redirect did not include an address."
	if redirect.port <= 0 or redirect.port > 65535:
		return "Zone redirect did not include a valid port."
	if redirect.transfer_token.strip_edges().is_empty():
		return "Zone redirect did not include a token."
	return ""

func _fail(current_run_id: int, gate_id: StringName, reason: String) -> void:
	if not _is_current_run(current_run_id):
		return

	state = State.FAILED
	_cleanup_active_screen()
	_fail_gate(gate_id, reason)
	if _loading_screen != null:
		_loading_screen.fail_loading(reason)
	failed.emit(reason)
	_screen_manager.hide_loading_overlay()
	_loading_screen = null
	state = State.IDLE

func _cleanup_active_screen() -> void:
	if _active_screen == null:
		return
	if is_instance_valid(_active_screen):
		if _active_screen.api != null:
			_active_screen.api.disconnect_from_server()
		_screen_manager.discard_prepared_ingame_screen(_active_screen)
	_active_screen = null

func _add_gate(gate_id: StringName, label: String, weight: float = 1.0) -> void:
	_gates[gate_id] = {
		"label": label,
		"weight": maxf(weight, 0.0),
		"progress": 0.0,
		"complete": false,
		"detail": "",
	}

func _set_gate_progress(gate_id: StringName, progress: float, detail: String = "") -> void:
	if not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	if bool(gate.get("complete", false)):
		return

	gate["progress"] = clampf(progress, 0.0, 1.0)
	gate["detail"] = detail
	_gates[gate_id] = gate
	_update_loading_screen()

func _complete_gate(gate_id: StringName, detail: String = "") -> void:
	if not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	gate["progress"] = 1.0
	gate["complete"] = true
	gate["detail"] = detail
	_gates[gate_id] = gate
	_update_loading_screen()

func _fail_gate(gate_id: StringName, reason: String) -> void:
	if not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	gate["progress"] = 1.0
	gate["detail"] = reason
	_gates[gate_id] = gate
	_update_loading_screen()

func _update_loading_screen() -> void:
	if _loading_screen == null:
		return

	var total_weight: float = 0.0
	var weighted_progress: float = 0.0
	var status: String = ""
	for gate_id: StringName in _gates.keys():
		var gate: Dictionary = _gates[gate_id]
		var weight: float = float(gate.get("weight", 1.0))
		total_weight += weight
		weighted_progress += weight * float(gate.get("progress", 0.0))

		if status.is_empty() and not bool(gate.get("complete", false)):
			var detail: String = str(gate.get("detail", ""))
			status = detail if not detail.is_empty() else str(gate.get("label", ""))

	var progress: float = weighted_progress / total_weight if total_weight > 0.0 else 0.0
	_loading_screen.set_loading_progress(progress, status)

func _is_current_run(current_run_id: int) -> bool:
	return current_run_id == _run_id and state != State.CANCELED

func _elapsed_seconds(started_msec: int) -> float:
	return float(Time.get_ticks_msec() - started_msec) / 1000.0
