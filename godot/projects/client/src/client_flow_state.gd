class_name ClientFlowState
extends Node

var username: String = ""
var characters: Array[ClientCharacterSummary] = []
var selected_character: ClientCharacterSummary = null
var pending_zone_redirect: ClientZoneRedirect = null

func reset() -> void:
	username = ""
	characters.clear()
	selected_character = null
	pending_zone_redirect = null

func set_login_result(new_username: String, new_characters: Array[ClientCharacterSummary]) -> void:
	username = new_username
	characters = new_characters.duplicate()
	selected_character = null
	pending_zone_redirect = null

func set_selected_character(character: ClientCharacterSummary, redirect: ClientZoneRedirect) -> void:
	selected_character = character
	pending_zone_redirect = redirect

func has_selected_session() -> bool:
	return selected_character != null and pending_zone_redirect != null
