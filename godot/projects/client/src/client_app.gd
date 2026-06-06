class_name ClientApp
extends Node

const GATE_REQUEST_ZONE_TOKEN: StringName = &"request_zone_token"
const GATE_RECEIVE_ZONE_REDIRECT: StringName = &"receive_zone_redirect"
const GATE_DISCONNECT_OLD_ZONE: StringName = &"disconnect_old_zone"
const GATE_CONNECT_ZONE: StringName = &"connect_zone"
const GATE_LOAD_ZONE: StringName = &"load_zone"
const GATE_LOAD_CHARACTER: StringName = &"load_character"

@export var login_scene: PackedScene
@export var character_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var ingame_scene: PackedScene

@onready var _flow_state: ClientFlowState = %ClientFlowState
@onready var _loading_coordinator: ClientLoadingCoordinator = %ClientLoadingCoordinator
@onready var _orchestrator_client: ClientOrchestratorClient = %ClientOrchestratorClient
@onready var _screen_container: Node = %ScreenContainer

var _current_screen: Node = null
var _loading_screen: LoadingScreen = null
var _zone_transition_in_progress: bool = false

func _ready() -> void:
	_show_login()

func _show_login() -> void:
	_flow_state.reset()
	var screen: LoginScreen = _show_screen(login_scene) as LoginScreen
	screen.play_pressed.connect(_on_login_play_pressed)

func _show_character_select() -> void:
	_clear_screen()
	var screen: CharacterSelectScreen = character_select_scene.instantiate() as CharacterSelectScreen
	screen.flow_state = _flow_state
	_screen_container.add_child(screen)
	_current_screen = screen
	screen.play_pressed.connect(_on_character_play_pressed)
	screen.back_pressed.connect(_show_login)
	screen.render()

func _show_ingame() -> void:
	_clear_screen()
	_instantiate_ingame_screen()

func _show_loading() -> LoadingScreen:
	_clear_screen()
	var screen: LoadingScreen = loading_scene.instantiate() as LoadingScreen
	screen.loading_coordinator = _loading_coordinator
	_screen_container.add_child(screen)
	_current_screen = screen
	_loading_screen = screen
	return screen

func _instantiate_ingame_screen() -> IngameScreen:
	var screen: IngameScreen = ingame_scene.instantiate() as IngameScreen
	screen.flow_state = _flow_state
	_screen_container.add_child(screen)
	_current_screen = screen
	return screen

func _show_screen(scene: PackedScene) -> Node:
	_clear_screen()
	var screen: Node = scene.instantiate()
	_screen_container.add_child(screen)
	_current_screen = screen
	return screen

func _clear_screen() -> void:
	for child: Node in _screen_container.get_children():
		_screen_container.remove_child(child)
		child.queue_free()
	_current_screen = null
	_loading_screen = null

func _on_login_play_pressed(username: String) -> void:
	print("Client login flow started")
	var login_screen: LoginScreen = _current_screen as LoginScreen
	if login_screen != null:
		login_screen.set_busy(true, "Connecting ...")

	var result: Dictionary = await _orchestrator_client.request_login(username)
	if not bool(result.get("ok", false)):
		if login_screen != null and is_instance_valid(login_screen):
			login_screen.set_busy(false, str(result.get("reason", "Login failed.")))
		return

	var raw_characters: Array = result.get("characters", [])
	var characters: Array[ClientCharacterSummary] = []
	for character: ClientCharacterSummary in raw_characters:
		characters.append(character)

	_flow_state.set_login_result(username, characters)
	print("Client login flow complete: characters=%d" % characters.size())
	_show_character_select()

func _on_character_play_pressed(character: ClientCharacterSummary) -> void:
	if _zone_transition_in_progress:
		return

	_zone_transition_in_progress = true
	print("Client character select flow started: character_id=%d" % character.character_id)
	_show_loading()
	await _load_character_zone(character)
	_zone_transition_in_progress = false

func _load_character_zone(character: ClientCharacterSummary) -> void:
	_loading_coordinator.begin_zone_transfer(character.zone_id)
	_register_zone_transfer_gates()

	_loading_coordinator.set_gate_progress(GATE_REQUEST_ZONE_TOKEN, 0.25, "Requesting zone token")
	var select_result: Dictionary = await _orchestrator_client.request_character_select(character.character_id)
	if not bool(select_result.get("ok", false)):
		_loading_coordinator.fail_gate(GATE_REQUEST_ZONE_TOKEN, str(select_result.get("reason", "Character select failed.")))
		return

	var redirect: ClientZoneRedirect = select_result.get("redirect", null) as ClientZoneRedirect
	if redirect == null:
		_loading_coordinator.fail_gate(GATE_RECEIVE_ZONE_REDIRECT, "Orchestrator did not return a zone redirect.")
		return

	_loading_coordinator.complete_gate(GATE_REQUEST_ZONE_TOKEN, "Zone token received")
	_loading_coordinator.complete_gate(GATE_RECEIVE_ZONE_REDIRECT, "Zone redirect received")
	_flow_state.set_selected_character(character, redirect)
	print(
		"Client stored zone redirect: character_id=%d zone=%s address=%s port=%d" %
		[character.character_id, redirect.zone_id, redirect.address, redirect.port]
	)

	await _advance_loading_gate(GATE_DISCONNECT_OLD_ZONE, 0.18, "Disconnecting previous zone")
	await _load_ingame_world_behind_loading(redirect.zone_id)

func _register_zone_transfer_gates() -> void:
	_loading_coordinator.add_gate(GATE_REQUEST_ZONE_TOKEN, "Requesting zone token", 0.20)
	_loading_coordinator.add_gate(GATE_RECEIVE_ZONE_REDIRECT, "Receiving zone redirect", 0.20)
	_loading_coordinator.add_gate(GATE_DISCONNECT_OLD_ZONE, "Disconnecting previous zone", 0.10)
	_loading_coordinator.add_gate(GATE_CONNECT_ZONE, "Connecting zone server", 0.20)
	_loading_coordinator.add_gate(GATE_LOAD_ZONE, "Loading zone world", 0.20)
	_loading_coordinator.add_gate(GATE_LOAD_CHARACTER, "Loading character", 0.20)

func _advance_loading_gate(gate_id: StringName, duration_seconds: float, detail: String) -> void:
	_loading_coordinator.set_gate_progress(gate_id, 0.20, detail)
	await get_tree().create_timer(duration_seconds * 0.40).timeout
	_loading_coordinator.set_gate_progress(gate_id, 0.65, detail)
	await get_tree().create_timer(duration_seconds * 0.60).timeout
	_loading_coordinator.complete_gate(gate_id, detail)
	await get_tree().process_frame

func _load_ingame_world_behind_loading(zone_id: String) -> void:
	_loading_coordinator.set_gate_progress(GATE_CONNECT_ZONE, 0.10, "Connecting to %s" % zone_id.to_upper())
	_loading_coordinator.set_gate_progress(GATE_LOAD_ZONE, 0.15, "Loading %s" % zone_id.to_upper())
	_loading_coordinator.set_gate_progress(GATE_LOAD_CHARACTER, 0.05, "Waiting for character")

	var screen: IngameScreen = ingame_scene.instantiate() as IngameScreen
	screen.flow_state = _flow_state
	screen.zone_connection_ready.connect(func(_address: String, _port: int) -> void:
		_loading_coordinator.complete_gate(GATE_CONNECT_ZONE, "Zone login sent")
	)
	screen.zone_connection_failed.connect(func(reason: String) -> void:
		_loading_coordinator.fail_gate(GATE_CONNECT_ZONE, reason)
	)
	screen.zone_loaded.connect(func(new_zone_id: String) -> void:
		_loading_coordinator.complete_gate(GATE_LOAD_ZONE, "Loaded %s" % new_zone_id.to_upper())
		_loading_coordinator.set_gate_progress(GATE_LOAD_CHARACTER, 0.35, "Loading character")
	)
	screen.character_loaded.connect(func(character: ClientLoadedCharacter) -> void:
		_loading_coordinator.set_gate_progress(GATE_LOAD_CHARACTER, 0.85, "Loaded %s" % character.display_name)
	)
	_screen_container.add_child(screen)
	_current_screen = screen
	if _loading_screen != null:
		_loading_screen.move_to_front()

	while not screen.is_ingame_loaded() and _loading_coordinator.is_loading():
		await get_tree().process_frame

	if not screen.is_ingame_loaded():
		return

	await get_tree().process_frame
	await get_tree().process_frame
	_loading_coordinator.complete_gate(GATE_LOAD_CHARACTER, "Ready")

	if _loading_screen != null:
		var completed_loading_screen: LoadingScreen = _loading_screen
		_loading_screen = null
		_screen_container.remove_child(completed_loading_screen)
		completed_loading_screen.queue_free()
