class_name ClientApp
extends Node

@export var login_scene: PackedScene
@export var character_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var ingame_scene: PackedScene

@onready var _screen_manager: ScreenManager = %ScreenManager
@onready var _orchestrator_api: OrchestratorAPI = %OrchestratorAPI
@onready var _zone_connection_manager: ZoneConnectionManager = %ZoneConnectionManager

var _zone_transition_in_progress: bool = false

func _ready() -> void:
	_screen_manager.login_scene = login_scene
	_screen_manager.character_select_scene = character_select_scene
	_screen_manager.loading_scene = loading_scene
	_screen_manager.ingame_scene = ingame_scene
	_zone_connection_manager.succeeded.connect(_on_zone_connection_succeeded)
	_zone_connection_manager.failed.connect(_on_zone_connection_failed)
	_show_login()

func _show_login(status: String = "") -> void:
	var screen: LoginScreen = _screen_manager.show_login(status)
	if screen != null:
		screen.play_pressed.connect(_on_login_play_pressed)

func _show_character_select() -> CharacterSelectScreen:
	var screen: CharacterSelectScreen = _screen_manager.transition_to(ScreenManager.Screen.CHARACTER_SELECT_SCREEN) as CharacterSelectScreen
	if screen == null:
		return null
	screen.play_pressed.connect(_on_character_play_pressed)
	screen.back_pressed.connect(_show_login)
	return screen

func _on_login_play_pressed(username: String) -> void:
	print("Client login flow started")
	var login_screen: LoginScreen = _screen_manager.current_screen as LoginScreen
	if login_screen != null:
		login_screen.set_busy(true, "Connecting ...")

	var result: Dictionary = await _orchestrator_api.request_login(username)
	if not bool(result.get("ok", false)):
		if login_screen != null and is_instance_valid(login_screen):
			login_screen.set_busy(false, str(result.get("reason", "Login failed.")))
		return

	var raw_characters: Array = result.get("characters", [])
	var characters: Array[ClientCharacterSummary] = []
	for character: ClientCharacterSummary in raw_characters:
		characters.append(character)

	print("Client login flow complete: characters=%d" % characters.size())
	var character_select_screen: CharacterSelectScreen = _show_character_select()
	if character_select_screen != null:
		character_select_screen.set_login_result(username, characters)

func _on_character_play_pressed(character: ClientCharacterSummary) -> void:
	if _zone_transition_in_progress:
		return

	_zone_transition_in_progress = true
	print("Client character select flow started: character_id=%d" % character.character_id)
	_zone_connection_manager.login_character(character)

func _on_zone_connection_succeeded(_screen: IngameScreen) -> void:
	_zone_transition_in_progress = false

func _on_zone_connection_failed(reason: String) -> void:
	_zone_transition_in_progress = false
	print("Client zone entry failed: %s" % reason)
	_show_login("Could not enter world. Please try again.")
