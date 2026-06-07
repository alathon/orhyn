extends Panel

@onready var class_icon_texture: TextureRect = %ClassIcon
@onready var character_name_label: RichTextLabel = %CharacterName
@onready var character_race_class_level_label: RichTextLabel = %CharacterRaceClassLevel
@onready var zone_info_label: RichTextLabel = %ZoneInfo

var character_name: String:
	set(v):
		character_name_label.text = v

var character_race: String:
	set(v):
		character_race = v
		_recompute_character_race_class_level_text()

var character_class: String:
	set(v):
		character_class = v
		_recompute_character_race_class_level_text()

var character_level: String:
	set(v):
		character_level = v
		_recompute_character_race_class_level_text()

var character_class_icon: Texture2D:
	set(v):
		class_icon_texture.texture = v

var character_entity_id: int = -1

func _recompute_character_race_class_level_text():
	character_race_class_level_label.text = "%s %s\nLevel %s" % [character_race, character_class, character_level]
