class_name CharacterRow
extends Panel

signal selected(row: CharacterRow)

@onready var class_icon_texture: TextureRect = %ClassIcon
@onready var character_name_label: RichTextLabel = %CharacterName
@onready var character_race_class_level_label: RichTextLabel = %CharacterRaceClassLevel
@onready var zone_info_label: RichTextLabel = %ZoneInfo
@onready var selected_glow: ColorRect = %SelectionGlow

@export var selected_glow_shader: Shader

var character_id: int = -1
var character: ClientCharacterSummary = null

var _glow_material: ShaderMaterial = null
var _is_selected: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_on_gui_input)
	_glow_material = _create_glow_material()
	selected_glow.material = _glow_material
	set_selected(false)

func set_character(summary: ClientCharacterSummary, class_icon: Texture2D) -> void:
	character = summary
	if summary == null:
		visible = true
		character_id = -1
		character_name_label.text = ""
		character_race_class_level_label.text = ""
		zone_info_label.text = ""
		class_icon_texture.texture = null
		return

	visible = true
	character_id = summary.character_id
	character_name_label.text = summary.display_name
	character_race_class_level_label.text = "%s\nLevel %d" % [summary.model_name, summary.level]
	zone_info_label.text = summary.zone_id.capitalize()
	class_icon_texture.texture = class_icon

func set_selected(is_selected: bool) -> void:
	_is_selected = is_selected
	selected_glow.visible = _is_selected
	if _is_selected and _glow_material != null:
		_glow_material.set_shader_parameter("glow_color", Color(0.76, 0.24, 1.0, 0.95))
		_glow_material.set_shader_parameter("border_strength", 0.85)
		_glow_material.set_shader_parameter("fill_strength", 0.06)

func _on_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	accept_event()
	selected.emit(self)

func _create_glow_material() -> ShaderMaterial:
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = selected_glow_shader
	return shader_material
