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

var loading_coordinator: ClientLoadingCoordinator = null:
	get:
		return _loading_coordinator
	set(value):
		_set_loading_coordinator(value)

var _background_texture: Texture2D = null
var _loading_tip_text: String = "TIP: DON'T TRUST PIERCE."
var _loading_status_text: String = "LOADING ..."
var _loading_coordinator: ClientLoadingCoordinator = null
var _active_session_id: int = 0
var _shown_msec: int = 0
var _pending_hide: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_apply_background_texture()
	_apply_loading_text()
	if _loading_coordinator != null and _loading_coordinator.is_loading():
		_on_loading_started(_loading_coordinator.get_session_id(), _loading_coordinator.get_context())
		_on_loading_progress_changed(
			_loading_coordinator.get_session_id(),
			_loading_coordinator.get_progress(),
			_loading_coordinator.get_gate_snapshot()
		)
	set_process(false)

func _exit_tree() -> void:
	_disconnect_loading_coordinator()

func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()

func _gui_input(_event: InputEvent) -> void:
	if visible:
		accept_event()

func _process(_delta: float) -> void:
	if _pending_hide and _can_hide_now():
		_hide()

func _set_loading_coordinator(value: ClientLoadingCoordinator) -> void:
	if _loading_coordinator == value:
		return

	_disconnect_loading_coordinator()
	_loading_coordinator = value
	if _loading_coordinator != null:
		_loading_coordinator.loading_started.connect(_on_loading_started)
		_loading_coordinator.loading_progress_changed.connect(_on_loading_progress_changed)
		_loading_coordinator.loading_failed.connect(_on_loading_failed)
		_loading_coordinator.loading_completed.connect(_on_loading_completed)
		_loading_coordinator.loading_canceled.connect(_on_loading_canceled)

func _disconnect_loading_coordinator() -> void:
	if _loading_coordinator == null:
		return
	if _loading_coordinator.loading_started.is_connected(_on_loading_started):
		_loading_coordinator.loading_started.disconnect(_on_loading_started)
	if _loading_coordinator.loading_progress_changed.is_connected(_on_loading_progress_changed):
		_loading_coordinator.loading_progress_changed.disconnect(_on_loading_progress_changed)
	if _loading_coordinator.loading_failed.is_connected(_on_loading_failed):
		_loading_coordinator.loading_failed.disconnect(_on_loading_failed)
	if _loading_coordinator.loading_completed.is_connected(_on_loading_completed):
		_loading_coordinator.loading_completed.disconnect(_on_loading_completed)
	if _loading_coordinator.loading_canceled.is_connected(_on_loading_canceled):
		_loading_coordinator.loading_canceled.disconnect(_on_loading_canceled)
	_loading_coordinator = null

func _on_loading_started(session_id: int, _context: Dictionary) -> void:
	_active_session_id = session_id
	_pending_hide = false
	_shown_msec = Time.get_ticks_msec()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	set_process(false)
	grab_focus()
	if is_node_ready():
		_progress_bar.value = 0.0
		_status_label.text = loading_status_text

func _on_loading_progress_changed(session_id: int, progress: float, gates: Dictionary) -> void:
	if session_id != _active_session_id or not is_node_ready():
		return

	_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	_status_label.text = _get_status_from_gates(gates)

func _on_loading_completed(session_id: int, _context: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_request_hide()

func _on_loading_canceled(session_id: int, _reason: String) -> void:
	if session_id != _active_session_id:
		return
	_request_hide()

func _on_loading_failed(session_id: int, reason: String) -> void:
	if session_id != _active_session_id:
		return
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

func _get_status_from_gates(gates: Dictionary) -> String:
	var fallback: String = _loading_status_text
	for gate_id: StringName in gates.keys():
		var gate: Dictionary = gates[gate_id]
		if bool(gate.get("complete", false)):
			continue

		var detail: String = str(gate.get("detail", ""))
		if not detail.is_empty():
			return detail.to_upper()

		var label: String = str(gate.get("label", ""))
		if not label.is_empty():
			return label.to_upper()

	return fallback
