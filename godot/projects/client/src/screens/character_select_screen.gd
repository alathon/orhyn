class_name CharacterSelectScreen
extends Control

signal play_pressed(character: ClientCharacterSummary)
signal back_pressed

@onready var _character_name: Label = %CharacterName
@onready var _character_details: Label = %CharacterDetails
@onready var _play_button: Button = %PlayButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel

var flow_state: ClientFlowState = null
var _selected_character: ClientCharacterSummary = null

func _ready() -> void:
	_play_button.pressed.connect(_submit)
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	render()

func render() -> void:
	if not is_node_ready():
		return

	if flow_state == null or flow_state.characters.is_empty():
		_selected_character = null
		_character_name.text = "No Character"
		_character_details.text = ""
		_status_label.text = "No characters are available."
		_play_button.disabled = true
		return

	_selected_character = flow_state.characters[0]
	_character_name.text = _selected_character.display_name
	_character_details.text = "Level %d %s - %s" % [
		_selected_character.level,
		_selected_character.model_name,
		_selected_character.zone_id.capitalize(),
	]
	_status_label.text = ""
	_play_button.disabled = false

func _submit() -> void:
	if _selected_character == null:
		_status_label.text = "Select a character."
		return

	play_pressed.emit(_selected_character)
