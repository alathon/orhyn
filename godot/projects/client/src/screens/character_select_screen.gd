class_name CharacterSelectScreen
extends Control

signal play_pressed(character: ClientCharacterSummary)
signal back_pressed

const MAX_VISIBLE_CHARACTERS: int = 5
const ICON_ROOT: String = "res://projects/client/assets/ui/images/screens/char_select/icons/"
const CLASS_ICON_PATHS: Dictionary = {
	"knight": ICON_ROOT + "class_knight.png",
	"ranger": ICON_ROOT + "class_ranger.png",
	"mage": ICON_ROOT + "class_mage.png",
	"rogue": ICON_ROOT + "class_rogue.png",
	"druid": ICON_ROOT + "class_druid.png",
	"enchanter": ICON_ROOT + "class_enchanter.png",
}
const ZONE_ICON_PATHS: Dictionary = {
	"stormreach": ICON_ROOT + "zone_stormreach.png",
	"silverwood": ICON_ROOT + "zone_silverwood.png",
	"aurelia": ICON_ROOT + "zone_aurelia.png",
	"umbralis": ICON_ROOT + "zone_umbralis.png",
	"greenhollow": ICON_ROOT + "zone_greenhollow.png",
}

@export var character_row_background: Texture2D

@onready var _character_rows: VBoxContainer = $CharacterPanel/RowsMargin/CharacterRows
@onready var _play_button: TextureButton = $PlayButton
@onready var _back_button: TextureButton = $BackButton
@onready var _delete_button: TextureButton = get_node_or_null("DeleteButton") as TextureButton
@onready var _status_label: Label = $StatusLabel
@onready var _body_font: Font = $StatusLabel.get_theme_font("font")
@onready var _heading_font: Font = _get_heading_font()

var flow_state: ClientFlowState = null
var _selected_character: ClientCharacterSummary = null
var _selected_character_index: int = 0
var _row_buttons: Array[Button] = []
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_play_button.pressed.connect(_submit)
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	if _delete_button != null:
		_delete_button.disabled = true
	render()

func render() -> void:
	if not is_node_ready():
		return

	_clear_character_rows()

	if flow_state == null or flow_state.characters.is_empty():
		_selected_character = null
		_status_label.text = "No characters are available."
		_play_button.disabled = true
		return

	_selected_character_index = clampi(_selected_character_index, 0, flow_state.characters.size() - 1)
	var visible_count: int = mini(flow_state.characters.size(), MAX_VISIBLE_CHARACTERS)
	for index: int in visible_count:
		var character: ClientCharacterSummary = flow_state.characters[index]
		var row_button: Button = _create_character_row(character, index)
		_character_rows.add_child(row_button)
		_row_buttons.append(row_button)

	_select_character(_selected_character_index)
	_status_label.text = ""
	_play_button.disabled = false

func _submit() -> void:
	if _selected_character == null:
		_status_label.text = "Select a character."
		return

	play_pressed.emit(_selected_character)

func _select_character(index: int) -> void:
	if flow_state == null or index < 0 or index >= flow_state.characters.size():
		return

	_selected_character_index = index
	_selected_character = flow_state.characters[index]
	for row_index: int in _row_buttons.size():
		var row_button: Button = _row_buttons[row_index]
		var selection_overlay: Panel = row_button.get_node("SelectionOverlay") as Panel
		var glow_overlay: Panel = row_button.get_node("GlowOverlay") as Panel
		var is_selected: bool = row_index == _selected_character_index
		selection_overlay.visible = is_selected
		glow_overlay.visible = is_selected

func _clear_character_rows() -> void:
	_row_buttons.clear()
	for child: Node in _character_rows.get_children():
		_character_rows.remove_child(child)
		child.queue_free()

func _create_character_row(character: ClientCharacterSummary, index: int) -> Button:
	var row_button: Button = Button.new()
	row_button.custom_minimum_size = Vector2(0, 98)
	row_button.focus_mode = Control.FOCUS_NONE
	row_button.text = ""
	row_button.add_theme_stylebox_override("normal", _create_empty_style())
	row_button.add_theme_stylebox_override("hover", _create_empty_style())
	row_button.add_theme_stylebox_override("pressed", _create_empty_style())
	row_button.pressed.connect(func() -> void: _select_character(index))

	var background: TextureRect = TextureRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.texture = character_row_background
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	row_button.add_child(background)

	var glow_overlay: Panel = Panel.new()
	glow_overlay.name = "GlowOverlay"
	glow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_overlay.visible = false
	glow_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_overlay.offset_left = 2
	glow_overlay.offset_top = 2
	glow_overlay.offset_right = -2
	glow_overlay.offset_bottom = -2
	glow_overlay.add_theme_stylebox_override("panel", _create_glow_style())
	row_button.add_child(glow_overlay)

	var selection_overlay: Panel = Panel.new()
	selection_overlay.name = "SelectionOverlay"
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.visible = false
	selection_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_overlay.offset_left = 3
	selection_overlay.offset_top = 3
	selection_overlay.offset_right = -3
	selection_overlay.offset_bottom = -3
	selection_overlay.add_theme_stylebox_override("panel", _create_selection_style())
	row_button.add_child(selection_overlay)

	var content: HBoxContainer = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 22
	content.offset_top = 10
	content.offset_right = -18
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 14)
	row_button.add_child(content)

	var class_icon: TextureRect = TextureRect.new()
	class_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_icon.custom_minimum_size = Vector2(76, 76)
	class_icon.texture = _get_class_icon(character)
	class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(class_icon)

	var details: VBoxContainer = VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	content.add_child(details)

	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = character.display_name
	name_label.add_theme_font_override("font", _heading_font)
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.9, 1.0))
	details.add_child(name_label)

	var model_label: Label = Label.new()
	model_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model_label.text = character.model_name
	model_label.add_theme_font_override("font", _body_font)
	model_label.add_theme_font_size_override("font_size", 15)
	model_label.add_theme_color_override("font_color", Color(0.66, 0.63, 0.7, 1.0))
	details.add_child(model_label)

	var level_label: Label = Label.new()
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.text = "Level %d" % character.level
	level_label.add_theme_font_override("font", _body_font)
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.add_theme_color_override("font_color", Color(0.72, 0.69, 0.76, 1.0))
	details.add_child(level_label)

	var zone_box: VBoxContainer = VBoxContainer.new()
	zone_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_box.custom_minimum_size = Vector2(118, 0)
	zone_box.add_theme_constant_override("separation", 4)
	content.add_child(zone_box)

	var zone_label: Label = Label.new()
	zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_label.text = character.zone_id.capitalize()
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zone_label.add_theme_font_override("font", _body_font)
	zone_label.add_theme_font_size_override("font_size", 15)
	zone_label.add_theme_color_override("font_color", Color(0.57, 0.54, 0.62, 1.0))
	zone_box.add_child(zone_label)

	var zone_icon: TextureRect = TextureRect.new()
	zone_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_icon.custom_minimum_size = Vector2(30, 30)
	zone_icon.size_flags_horizontal = Control.SIZE_SHRINK_END
	zone_icon.texture = _get_zone_icon(character)
	zone_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zone_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	zone_box.add_child(zone_icon)

	return row_button

func _create_empty_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	return style

func _create_selection_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.09, 0.42, 0.34)
	style.border_color = Color(0.64, 0.27, 1.0, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.shadow_color = Color(0.5, 0.16, 1.0, 0.32)
	style.shadow_size = 10
	return style

func _create_glow_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.41, 0.13, 0.86, 0.1)
	style.border_color = Color(0.72, 0.29, 1.0, 0.72)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.shadow_color = Color(0.57, 0.16, 1.0, 0.62)
	style.shadow_size = 18
	return style

func _get_class_icon(character: ClientCharacterSummary) -> Texture2D:
	var model_name: String = character.model_name.strip_edges().to_lower()
	for keyword: String in CLASS_ICON_PATHS.keys():
		if model_name.contains(keyword):
			return _load_icon(str(CLASS_ICON_PATHS[keyword]))
	return null

func _get_zone_icon(character: ClientCharacterSummary) -> Texture2D:
	var zone_id: String = character.zone_id.strip_edges().to_lower()
	if ZONE_ICON_PATHS.has(zone_id):
		return _load_icon(str(ZONE_ICON_PATHS[zone_id]))
	return null

func _load_icon(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D

	var texture: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = texture
	return texture

func _get_heading_font() -> Font:
	var select_label: Label = get_node_or_null("SelectLabel") as Label
	if select_label != null:
		return select_label.get_theme_font("font")
	return _body_font
