class_name CharacterSelectScreen
extends Control

signal play_pressed(character: ClientCharacterSummary)
signal back_pressed

const MAX_VISIBLE_CHARACTERS: int = 5
const ICON_ROOT: String = "res://projects/client/assets/ui/images/screens/char_select/icons/"
const CLASS_ICON_PATHS: Dictionary = {
	"knight": ICON_ROOT + "class_1.png",
	"ranger": ICON_ROOT + "class_2.png",
	"mage": ICON_ROOT + "class_3.png",
	"wizard": ICON_ROOT + "class_3.png",
	"rogue": ICON_ROOT + "class_4.png",
	"druid": ICON_ROOT + "class_5.png",
	"enchanter": ICON_ROOT + "class_6.png",
}

@export var character_row_background: Texture2D

@onready var _character_rows: VBoxContainer = $CharacterPanel/RowsMargin/CharacterRows
@onready var _play_button: TextureButton = $PlayButton
@onready var _back_button: TextureButton = $BackButton
@onready var _status_label: Label = $StatusLabel

var flow_state: ClientFlowState = null
var _selected_character: ClientCharacterSummary = null
var _selected_character_index: int = 0
var _row_slots: Array[CharacterRow] = []
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_cache_row_slots()
	_play_button.pressed.connect(_submit)
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	render()

func render() -> void:
	if not is_node_ready():
		return

	if _row_slots.is_empty():
		_cache_row_slots()

	if flow_state == null or flow_state.characters.is_empty():
		_selected_character = null
		_status_label.text = "No characters are available."
		_play_button.disabled = true
		_clear_row_slots()
		return

	var visible_count: int = mini(flow_state.characters.size(), mini(MAX_VISIBLE_CHARACTERS, _row_slots.size()))
	_selected_character_index = clampi(_selected_character_index, 0, visible_count - 1)

	for index: int in range(_row_slots.size()):
		var row: CharacterRow = _row_slots[index]
		if index < visible_count:
			var character: ClientCharacterSummary = flow_state.characters[index]
			row.set_character(character, _get_class_icon(character))
			row.set_selected(false)
		else:
			row.set_character(null, null)
			row.set_selected(false)

	_select_character(_selected_character_index)
	_status_label.text = ""
	_play_button.disabled = false

func _submit() -> void:
	if _selected_character == null:
		_status_label.text = "Select a character."
		return

	play_pressed.emit(_selected_character)

func _cache_row_slots() -> void:
	_row_slots.clear()
	for child: Node in _character_rows.get_children():
		var row: CharacterRow = child as CharacterRow
		if row == null:
			continue
		_row_slots.append(row)
		if not row.selected.is_connected(_on_row_selected):
			row.selected.connect(_on_row_selected)

func _clear_row_slots() -> void:
	for row: CharacterRow in _row_slots:
		row.set_character(null, null)
		row.set_selected(false)

func _on_row_selected(row: CharacterRow) -> void:
	var index: int = _row_slots.find(row)
	if index < 0:
		return
	_select_character(index)

func _select_character(index: int) -> void:
	if flow_state == null or index < 0 or index >= flow_state.characters.size() or index >= _row_slots.size():
		return

	var row: CharacterRow = _row_slots[index]
	if row.character == null:
		return

	_selected_character_index = index
	_selected_character = flow_state.characters[index]
	for row_index: int in range(_row_slots.size()):
		_row_slots[row_index].set_selected(row_index == _selected_character_index)

func _get_class_icon(character: ClientCharacterSummary) -> Texture2D:
	var model_name: String = character.model_name.strip_edges().to_lower()
	for keyword: String in CLASS_ICON_PATHS.keys():
		if model_name.contains(keyword):
			return _load_icon(str(CLASS_ICON_PATHS[keyword]))
	return null

func _load_icon(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D

	var texture: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = texture
	return texture
