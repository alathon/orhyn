class_name ClientCharacterSummary
extends RefCounted

var character_id: int = 0
var display_name: String = ""
var zone_id: String = ""
var model_name: String = ""
var level: int = 1

static func create(
	new_character_id: int,
	new_display_name: String,
	new_zone_id: String,
	new_model_name: String,
	new_level: int
) -> ClientCharacterSummary:
	var summary: ClientCharacterSummary = ClientCharacterSummary.new()
	summary.character_id = new_character_id
	summary.display_name = new_display_name
	summary.zone_id = new_zone_id
	summary.model_name = new_model_name
	summary.level = new_level
	return summary
