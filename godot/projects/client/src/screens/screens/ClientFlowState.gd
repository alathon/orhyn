class_name ClientFlowState
extends Node

const LOGIN_SCENE: String = "res://projects/client/src/screens/LoginScreen.tscn"
const CHARACTER_SELECT_SCENE: String = "res://projects/client/src/screens/CharacterSelectScreen.tscn"
const LOGOUT_REFRESH_SCENE: String = "res://projects/client/src/screens/LogoutRefreshScreen.tscn"

enum GameplayDisconnectIntent {
	NONE,
	CLEAN_LOGOUT,
	ZONE_TRANSFER,
}

var username: String = ""
var characters: Array[ClientCharacterSummary] = []
var selected_character: ClientCharacterSummary = null
var pending_zone_redirect: ZoneRedirectInfo = null
var gameplay_disconnect_intent: int = GameplayDisconnectIntent.NONE
var login_status_message: String = ""

var _background_refresh_active: bool = false


func reset() -> void:
	username = ""
	characters.clear()
	selected_character = null
	pending_zone_redirect = null
	gameplay_disconnect_intent = GameplayDisconnectIntent.NONE


func set_login_result(new_username: String, character_list: Array[ClientCharacterSummary]) -> void:
	username = new_username
	characters = character_list.duplicate()
	selected_character = null
	pending_zone_redirect = null
	gameplay_disconnect_intent = GameplayDisconnectIntent.NONE


func set_selected_character(character: ClientCharacterSummary, redirect: ZoneRedirectInfo) -> void:
	selected_character = character
	pending_zone_redirect = redirect


func get_selected_session() -> SelectedSessionState:
	if selected_character == null or pending_zone_redirect == null:
		return null
	return SelectedSessionState.create(username, selected_character, pending_zone_redirect)


func consume_zone_redirect() -> ZoneRedirectInfo:
	var redirect: ZoneRedirectInfo = pending_zone_redirect
	pending_zone_redirect = null
	return redirect


func begin_zone_transfer_transition() -> void:
	gameplay_disconnect_intent = GameplayDisconnectIntent.ZONE_TRANSFER


func finish_zone_transfer_transition() -> void:
	if gameplay_disconnect_intent == GameplayDisconnectIntent.ZONE_TRANSFER:
		gameplay_disconnect_intent = GameplayDisconnectIntent.NONE


func begin_clean_logout_transition() -> void:
	gameplay_disconnect_intent = GameplayDisconnectIntent.CLEAN_LOGOUT


func is_intentional_gameplay_disconnect() -> bool:
	return gameplay_disconnect_intent != GameplayDisconnectIntent.NONE


func start_clean_logout_refresh() -> void:
	begin_clean_logout_transition()
	selected_character = null
	pending_zone_redirect = null
	characters.clear()
	var backend: BackendAPI = get_node_or_null("/root/Backend") as BackendAPI
	if backend != null:
		backend.set_enabled(false)
	var error: Error = get_tree().change_scene_to_file(LOGOUT_REFRESH_SCENE)
	if error != OK:
		transition_to_login("Could not leave the game cleanly.")


func submit_background_login_refresh(login_client: LoginClient) -> void:
	if _background_refresh_active:
		return
	if username.strip_edges().is_empty():
		transition_to_login("Session expired. Log in again.")
		return
	if login_client == null:
		transition_to_login("Login refresh is not available.")
		return
	_disconnect_background_login_client(login_client)
	login_client.login_succeeded.connect(_on_background_login_succeeded)
	login_client.login_failed.connect(_on_background_login_failed)
	_background_refresh_active = true
	login_client.login(username)


func handle_unexpected_gameplay_disconnect(reason: String = "Connection to the game server was lost.") -> void:
	if is_intentional_gameplay_disconnect():
		return
	var backend: BackendAPI = get_node_or_null("/root/Backend") as BackendAPI
	if backend != null:
		backend.set_enabled(false)
	selected_character = null
	pending_zone_redirect = null
	transition_to_login(reason)


func transition_to_login(reason: String) -> void:
	var preserved_reason: String = reason
	reset()
	login_status_message = preserved_reason
	var error: Error = get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		Log.error("area=Client message=%s values=%s" % [str("Failed to transition to login"), str({ "error": error, "reason": reason })])


func consume_login_status_message() -> String:
	var message: String = login_status_message
	login_status_message = ""
	return message


func _on_background_login_succeeded(character_list: Array[ClientCharacterSummary]) -> void:
	var current_username: String = username
	_background_refresh_active = false
	set_login_result(current_username, character_list)
	var error: Error = get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	if error != OK:
		transition_to_login("Could not open character select.")


func _on_background_login_failed(reason: String) -> void:
	_background_refresh_active = false
	transition_to_login(reason if not reason.is_empty() else "Login refresh failed.")


func _disconnect_background_login_client(login_client: LoginClient) -> void:
	if login_client.login_succeeded.is_connected(_on_background_login_succeeded):
		login_client.login_succeeded.disconnect(_on_background_login_succeeded)
	if login_client.login_failed.is_connected(_on_background_login_failed):
		login_client.login_failed.disconnect(_on_background_login_failed)
