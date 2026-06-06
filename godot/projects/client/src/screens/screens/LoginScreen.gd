class_name LoginScreen
extends Control

const CHARACTER_SELECT_SCENE: String = "res://projects/client/src/screens/CharacterSelectScreen.tscn"

@onready var _username_input: LineEdit = %UsernameInput
@onready var _login_button: Button = %LoginButton
@onready var _status_label: Label = %StatusLabel
@onready var _build_label: Label = %BuildLabel
@onready var _login_client: LoginClient = %LoginClient
@onready var _flow_state: ClientFlowState = get_node("/root/ClientFlow") as ClientFlowState
@onready var _orchestrator_client: OrchestratorClient = get_node("/root/Orchestrator") as OrchestratorClient
@onready var _backend_api: BackendAPI = get_node("/root/Backend") as BackendAPI


func _ready() -> void:
	var entry_status: String = _flow_state.consume_login_status_message()
	_orchestrator_client.set_enabled(false)
	_backend_api.set_enabled(false)
	_flow_state.reset()
	_login_client.login_succeeded.connect(_on_login_succeeded)
	_login_client.login_failed.connect(_on_login_failed)
	_login_button.pressed.connect(_submit_login)
	_username_input.text_submitted.connect(func(_text: String) -> void: _submit_login())
	_set_loading(false)
	_status_label.text = entry_status
	_build_label.text = "build: %d" % AppVersion.get_build_version()
	if BotRuntime.is_bot():
		_username_input.text = BotRuntime.get_bot_username()
		call_deferred("_submit_login")
	else:
		if _username_input.text.strip_edges().is_empty():
			_username_input.text = "player"
		_username_input.grab_focus()


func _exit_tree() -> void:
	if _login_client != null:
		_login_client.close()


func _submit_login() -> void:
	if _login_client == null:
		return
	var username: String = _username_input.text.strip_edges()
	if username.is_empty():
		_status_label.text = "Enter a username."
		return
	_set_loading(true)
	_status_label.text = "Signing in..."
	_login_client.login(username)


func _on_login_succeeded(characters: Array[ClientCharacterSummary]) -> void:
	_flow_state.set_login_result(_username_input.text.strip_edges(), characters)
	var error: Error = get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	if error != OK:
		_on_login_failed("Could not open character select.")


func _on_login_failed(reason: String) -> void:
	_set_loading(false)
	_status_label.text = reason


func _set_loading(loading: bool) -> void:
	_username_input.editable = not loading
	_login_button.disabled = loading
