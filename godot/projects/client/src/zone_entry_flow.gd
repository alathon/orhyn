class_name ZoneEntryFlow
extends Node

signal succeeded(screen: IngameScreen)
signal failed(reason: String)

enum State {
	IDLE,
	REQUESTING_REDIRECT,
	CONNECTING_ZONE,
	SENDING_ZONE_LOGIN,
	LOADING_ZONE,
	WAITING_CHARACTER,
	READY,
	FAILED,
	CANCELED,
}

const GATE_REQUEST_ZONE_TOKEN: StringName = &"request_zone_token"
const GATE_RECEIVE_ZONE_REDIRECT: StringName = &"receive_zone_redirect"
const GATE_CONNECT_ZONE: StringName = &"connect_zone"
const GATE_LOAD_ZONE: StringName = &"load_zone"
const GATE_LOAD_CHARACTER: StringName = &"load_character"

@export var ingame_scene: PackedScene
@export var zone_connect_timeout_seconds: float = 5.0
@export var character_loaded_timeout_seconds: float = 8.0

@onready var _flow_state: ClientFlowState = %ClientFlowState
@onready var _loading_coordinator: ClientLoadingCoordinator = %ClientLoadingCoordinator
@onready var _orchestrator_client: ClientOrchestratorClient = %ClientOrchestratorClient
@onready var _screen_container: Node = %ScreenContainer

var state: State = State.IDLE
var _active_screen: IngameScreen = null
var _run_id: int = 0

func enter_character(character: ClientCharacterSummary) -> void:
	if state != State.IDLE:
		return

	_run_id += 1
	var current_run_id: int = _run_id
	state = State.REQUESTING_REDIRECT
	_loading_coordinator.begin_zone_transfer(character.zone_id)
	_register_zone_entry_gates()

	var redirect: ClientZoneRedirect = await _request_redirect(character, current_run_id)
	if redirect == null:
		return

	await _enter_redirect(character, redirect, current_run_id)

func _enter_redirect(character: ClientCharacterSummary, redirect: ClientZoneRedirect, current_run_id: int) -> void:
	_flow_state.set_selected_character(character, redirect)

	var screen: IngameScreen = _create_ingame_screen(current_run_id)
	if screen == null:
		return

	var err: Error = await _connect_and_login(screen, character, redirect, current_run_id)
	if err != OK:
		return

	err = _load_zone(screen, redirect.zone_id, current_run_id)
	if err != OK:
		return

	await _wait_for_character(screen, current_run_id)

func cancel(reason: String = "Canceled") -> void:
	if state == State.IDLE:
		return

	_run_id += 1
	state = State.CANCELED
	_cleanup_active_screen()
	_loading_coordinator.cancel_loading(reason)
	state = State.IDLE

func is_running() -> bool:
	return state != State.IDLE and state != State.READY

func _request_redirect(character: ClientCharacterSummary, current_run_id: int) -> ClientZoneRedirect:
	_loading_coordinator.set_gate_progress(GATE_REQUEST_ZONE_TOKEN, 0.25, "Requesting zone token")
	var select_result: Dictionary = await _orchestrator_client.request_character_select(character.character_id)
	if not _is_current_run(current_run_id):
		return null

	if not bool(select_result.get("ok", false)):
		_fail(current_run_id, GATE_REQUEST_ZONE_TOKEN, str(select_result.get("reason", "Character select failed.")))
		return null

	var redirect: ClientZoneRedirect = select_result.get("redirect", null) as ClientZoneRedirect
	var validation_error: String = _validate_redirect(redirect)
	if not validation_error.is_empty():
		_fail(current_run_id, GATE_RECEIVE_ZONE_REDIRECT, validation_error)
		return null

	_loading_coordinator.complete_gate(GATE_REQUEST_ZONE_TOKEN, "Zone token received")
	_loading_coordinator.complete_gate(GATE_RECEIVE_ZONE_REDIRECT, "Zone redirect received")
	return redirect

func _create_ingame_screen(current_run_id: int) -> IngameScreen:
	if ingame_scene == null:
		_fail(current_run_id, GATE_LOAD_ZONE, "In-game scene is not configured.")
		return null

	var screen: IngameScreen = ingame_scene.instantiate() as IngameScreen
	if screen == null:
		_fail(current_run_id, GATE_LOAD_ZONE, "In-game scene could not be created.")
		return null

	screen.flow_state = _flow_state
	_screen_container.add_child(screen)
	_screen_container.move_child(screen, 0)
	_active_screen = screen
	return screen

func _connect_and_login(
	screen: IngameScreen,
	character: ClientCharacterSummary,
	redirect: ClientZoneRedirect,
	current_run_id: int
) -> Error:
	state = State.CONNECTING_ZONE
	_loading_coordinator.set_gate_progress(GATE_CONNECT_ZONE, 0.15, "Connecting to %s" % redirect.zone_id.to_upper())
	screen.begin_character_load()

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
	_loading_coordinator.set_gate_progress(GATE_CONNECT_ZONE, 0.70, "Entering zone")
	err = screen.api.send_zone_login(character.character_id, redirect.transfer_token)
	if err != OK:
		_fail(current_run_id, GATE_CONNECT_ZONE, "Could not enter zone.")
		return err

	_loading_coordinator.complete_gate(GATE_CONNECT_ZONE, "Zone login sent")
	return OK

func _load_zone(screen: IngameScreen, zone_id: String, current_run_id: int) -> Error:
	state = State.LOADING_ZONE
	_loading_coordinator.set_gate_progress(GATE_LOAD_ZONE, 0.15, "Loading %s" % zone_id.to_upper())
	var err: Error = screen.load_zone(zone_id)
	if not _is_current_run(current_run_id):
		return ERR_BUSY
	if err != OK:
		_fail(current_run_id, GATE_LOAD_ZONE, "Could not load zone.")
		return err

	_loading_coordinator.complete_gate(GATE_LOAD_ZONE, "Loaded %s" % zone_id.to_upper())
	_loading_coordinator.set_gate_progress(GATE_LOAD_CHARACTER, 0.35, "Loading character")
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
		_loading_coordinator.set_gate_progress(GATE_LOAD_CHARACTER, 0.85, "Loaded %s" % loaded_character.display_name)
	_loading_coordinator.complete_gate(GATE_LOAD_CHARACTER, "Ready")
	state = State.READY
	_active_screen = null
	succeeded.emit(screen)
	state = State.IDLE

func _register_zone_entry_gates() -> void:
	_loading_coordinator.add_gate(GATE_REQUEST_ZONE_TOKEN, "Requesting zone token", 0.20)
	_loading_coordinator.add_gate(GATE_RECEIVE_ZONE_REDIRECT, "Receiving zone redirect", 0.20)
	_loading_coordinator.add_gate(GATE_CONNECT_ZONE, "Connecting zone server", 0.25)
	_loading_coordinator.add_gate(GATE_LOAD_ZONE, "Loading zone world", 0.20)
	_loading_coordinator.add_gate(GATE_LOAD_CHARACTER, "Loading character", 0.25)

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
	_loading_coordinator.fail_gate(gate_id, reason)
	failed.emit(reason)
	state = State.IDLE

func _cleanup_active_screen() -> void:
	if _active_screen == null:
		return
	if is_instance_valid(_active_screen):
		if _active_screen.api != null:
			_active_screen.api.disconnect_from_server()
		_screen_container.remove_child(_active_screen)
		_active_screen.queue_free()
	_active_screen = null

func _is_current_run(current_run_id: int) -> bool:
	return current_run_id == _run_id and state != State.CANCELED

func _elapsed_seconds(started_msec: int) -> float:
	return float(Time.get_ticks_msec() - started_msec) / 1000.0
