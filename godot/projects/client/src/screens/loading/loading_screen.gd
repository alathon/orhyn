class_name LoadingScreen
extends Control

@export var background_texture: Texture2D:
	get:
		return _background_texture
	set(value):
		_background_texture = value
		_apply_background_texture()
@export var loading_tip_text: String = "TIP: DON'T TRUST PIERCE.":
	get:
		return _loading_tip_text
	set(value):
		_loading_tip_text = value
		_apply_loading_text()
@export var loading_status_text: String = "LOADING ...":
	get:
		return _loading_status_text
	set(value):
		_loading_status_text = value
		_apply_loading_text()
@export var progress_minimum_visible_seconds: float = 0.0

@onready var _background_texture_rect: TextureRect = %BackgroundTexture
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _tip_label: Label = %TipLabel
@onready var _status_label: Label = %StatusLabel

var _background_texture: Texture2D = null
var _loading_tip_text: String = "TIP: DON'T TRUST PIERCE."
var _loading_status_text: String = "LOADING ..."
var _shown_msec: int = 0
var _pending_hide: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_apply_background_texture()
	_apply_loading_text()
	set_process(false)

func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()

func _gui_input(_event: InputEvent) -> void:
	if visible:
		accept_event()

func _process(_delta: float) -> void:
	if _pending_hide and _can_hide_now():
		_hide()

func start_loading(status: String = "") -> void:
	_pending_hide = false
	_shown_msec = Time.get_ticks_msec()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	set_process(false)
	grab_focus()
	if is_node_ready():
		_progress_bar.value = 0.0
		_status_label.text = status.to_upper() if not status.is_empty() else loading_status_text

func set_loading_progress(progress: float, status: String = "") -> void:
	if not is_node_ready():
		return

	_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	if not status.is_empty():
		_status_label.text = status.to_upper()

func finish_loading() -> void:
	set_loading_progress(1.0, "Ready")
	_request_hide()

func cancel_loading() -> void:
	_request_hide()

func fail_loading(reason: String) -> void:
	if not is_node_ready():
		return
	_status_label.text = reason.to_upper()

func _request_hide() -> void:
	if _can_hide_now():
		_hide()
		return
	_pending_hide = true
	set_process(true)

func _can_hide_now() -> bool:
	if progress_minimum_visible_seconds <= 0.0:
		return true

	var visible_seconds: float = float(Time.get_ticks_msec() - _shown_msec) / 1000.0
	return visible_seconds >= progress_minimum_visible_seconds

func _hide() -> void:
	visible = false
	_pending_hide = false
	set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	release_focus()

func _apply_background_texture() -> void:
	if not is_inside_tree() or _background_texture_rect == null:
		return
	_background_texture_rect.texture = _background_texture
	_background_texture_rect.visible = _background_texture != null

func _apply_loading_text() -> void:
	if not is_inside_tree() or _tip_label == null or _status_label == null:
		return
	_tip_label.text = _loading_tip_text
	_status_label.text = _loading_status_text
