class_name CharacterLoadedGameEvent
extends GameEvent

var character_id: int = 0
var entity_id: int = 0
var display_name: String = ""
var zone_id: String = ""
var model_name: String = ""
var level: int = 1


func _init(
		new_character_id: int = 0,
		new_entity_id: int = 0,
		new_display_name: String = "",
		new_zone_id: String = "",
		new_model_name: String = "",
		new_level: int = 1,
		new_source: int = GameEvent.Source.UNKNOWN,
		new_server_tick: int = -1) -> void:
	super(GameEvent.TYPE_CHARACTER_LOADED, new_source, new_server_tick)
	character_id = new_character_id
	entity_id = new_entity_id
	display_name = new_display_name
	zone_id = new_zone_id
	model_name = new_model_name
	level = new_level
