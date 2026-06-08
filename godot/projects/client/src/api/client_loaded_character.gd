class_name ClientLoadedCharacter
extends RefCounted

var character_id: int = 0
var entity_id: int = 0
var display_name: String = ""
var zone_id: String = ""
var model_name: String = ""
var level: int = 1

static func create(
	new_character_id: int,
	new_entity_id: int,
	new_display_name: String,
	new_zone_id: String,
	new_model_name: String,
	new_level: int
) -> ClientLoadedCharacter:
	var loaded_character: ClientLoadedCharacter = ClientLoadedCharacter.new()
	loaded_character.character_id = new_character_id
	loaded_character.entity_id = new_entity_id
	loaded_character.display_name = new_display_name
	loaded_character.zone_id = new_zone_id
	loaded_character.model_name = new_model_name
	loaded_character.level = new_level
	return loaded_character
