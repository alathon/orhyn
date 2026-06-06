class_name LoginScreen
extends Control

signal play_pressed(username: String)

@onready var _username_input: LineEdit = %UsernameInput
@onready var _play_button: Button = %PlayButton
@onready var _status_label: Label = %StatusLabel

func _ready() -> void:
	_play_button.pressed.connect(_submit)
	_username_input.text_submitted.connect(func(_text: String) -> void: _submit())
	if _username_input.text.strip_edges().is_empty():
		_username_input.text = "player"
	_username_input.grab_focus()

func _submit() -> void:
	var username: String = _username_input.text.strip_edges()
	if username.is_empty():
		_status_label.text = "Enter a username."
		return

	_status_label.text = ""
	play_pressed.emit(username)

func set_busy(is_busy: bool, status: String = "") -> void:
	_play_button.disabled = is_busy
	_username_input.editable = not is_busy
	_status_label.text = status

func set_status(status: String) -> void:
	_status_label.text = status
