class_name ClientApp
extends Node

@export var login_scene: PackedScene
@export var character_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var ingame_scene: PackedScene

@onready var _flow_state: ClientFlowState = %ClientFlowState
@onready var _loading_coordinator: ClientLoadingCoordinator = %ClientLoadingCoordinator
@onready var _orchestrator_client: ClientOrchestratorClient = %ClientOrchestratorClient
@onready var _zone_entry_flow: ZoneEntryFlow = %ZoneEntryFlow
@onready var _screen_container: Node = %ScreenContainer

var _current_screen: Node = null
var _loading_screen: LoadingScreen = null
var _zone_transition_in_progress: bool = false

func _ready() -> void:
	_zone_entry_flow.ingame_scene = ingame_scene
	_zone_entry_flow.succeeded.connect(_on_zone_entry_succeeded)
	_zone_entry_flow.failed.connect(_on_zone_entry_failed)
	_show_login()

func _show_login(status: String = "") -> void:
	_flow_state.reset()
	var screen: LoginScreen = _show_screen(login_scene) as LoginScreen
	screen.play_pressed.connect(_on_login_play_pressed)
	if not status.is_empty():
		screen.set_status(status)

func _show_character_select() -> void:
	_clear_screen()
	var screen: CharacterSelectScreen = character_select_scene.instantiate() as CharacterSelectScreen
	screen.flow_state = _flow_state
	_screen_container.add_child(screen)
	_current_screen = screen
	screen.play_pressed.connect(_on_character_play_pressed)
	screen.back_pressed.connect(_show_login)
	screen.render()

func _show_loading() -> LoadingScreen:
	_clear_screen()
	var screen: LoadingScreen = loading_scene.instantiate() as LoadingScreen
	screen.loading_coordinator = _loading_coordinator
	_screen_container.add_child(screen)
	_current_screen = screen
	_loading_screen = screen
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
	_zone_entry_flow.enter_character(character)

func _on_zone_entry_succeeded(screen: IngameScreen) -> void:
	_zone_transition_in_progress = false
	_current_screen = screen

	if _loading_screen != null:
		var completed_loading_screen: LoadingScreen = _loading_screen
		_loading_screen = null
		_screen_container.remove_child(completed_loading_screen)
		completed_loading_screen.queue_free()

func _on_zone_entry_failed(reason: String) -> void:
	_zone_transition_in_progress = false
	print("Client zone entry failed: %s" % reason)
	_show_login("Could not enter world. Please try again.")
