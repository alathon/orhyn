class_name SelectedSessionState
extends RefCounted

var username: String = ""
var selected_character: ClientCharacterSummary = null
var pending_zone_redirect: ZoneRedirectInfo = null


static func create(
		new_username: String,
		new_selected_character: ClientCharacterSummary,
		new_pending_zone_redirect: ZoneRedirectInfo) -> SelectedSessionState:
	var state: SelectedSessionState = SelectedSessionState.new()
	state.username = new_username
	state.selected_character = new_selected_character
	state.pending_zone_redirect = new_pending_zone_redirect
	return state
