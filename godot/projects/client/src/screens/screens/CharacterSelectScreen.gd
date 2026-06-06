class_name CharacterSelectScreen
extends Control

const LOGIN_SCENE: String = "res://projects/client/src/screens/LoginScreen.tscn"
const IN_GAME_SCENE: String = "res://projects/client/src/screens/InGameScreen.tscn"

@onready var _character_name: Label = %CharacterName
@onready var _character_details: Label = %CharacterDetails
@onready var _enter_button: Button = %EnterButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel
@onready var _flow_state: ClientFlowState = get_node("/root/ClientFlow") as ClientFlowState
@onready var _orchestrator_client: OrchestratorClient = get_node("/root/Orchestrator") as OrchestratorClient
@onready var _backend_api: BackendAPI = get_node("/root/Backend") as BackendAPI

var _selected_character: ClientCharacterSummary = null


func _ready() -> void:
	_backend_api.set_enabled(false)
	_orchestrator_client.set_enabled(true)
	_orchestrator_client.character_selected.connect(_on_character_selected)
	_orchestrator_client.character_select_failed.connect(_on_character_select_failed)
	_enter_button.pressed.connect(_submit_character_selection)
	_back_button.pressed.connect(_return_to_login)
	_status_label.text = ""
	_render_characters()
	_set_loading(false)
	if BotRuntime.is_bot():
		call_deferred("_submit_character_selection")


func _exit_tree() -> void:
	if _orchestrator_client != null:
		_orchestrator_client.close()


func _render_characters() -> void:
	if _flow_state.characters.is_empty():
		_status_label.text = "No characters are available."
		_enter_button.disabled = true
		return

	_selected_character = _flow_state.characters[0]
	_character_name.text = _selected_character.display_name
	_character_details.text = "Level %d %s - %s" % [
		_selected_character.level,
		_selected_character.model_name,
		_selected_character.zone_id.capitalize()
	]


func _submit_character_selection() -> void:
	if _selected_character == null:
		_status_label.text = "Select a character."
		return
	_set_loading(true)
	_status_label.text = "Entering world..."
	_orchestrator_client.select_character(_flow_state.username, _selected_character.character_id)


func _on_character_selected(redirect: ZoneRedirectInfo) -> void:
	if redirect == null:
		_on_character_select_failed("No zone redirect was returned.")
		return
	_flow_state.set_selected_character(_selected_character, redirect)
	_orchestrator_client.set_enabled(false)
	var error: Error = get_tree().change_scene_to_file(IN_GAME_SCENE)
	if error != OK:
		_on_character_select_failed("Could not open the game scene.")


func _on_character_select_failed(reason: String) -> void:
	_set_loading(false)
	_status_label.text = reason


func _return_to_login() -> void:
	_orchestrator_client.set_enabled(false)
	_flow_state.reset()
	get_tree().change_scene_to_file(LOGIN_SCENE)


func _set_loading(loading: bool) -> void:
	_enter_button.disabled = loading or _selected_character == null
	_back_button.disabled = loading
