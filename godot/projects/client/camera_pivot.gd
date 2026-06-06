extends Node3D

const CLICK_DRAG_THRESHOLD_PX := 6.0

@export_range(0.0, 1.0) var mouse_sensitivity = 0.01
@export var tilt_limit = deg_to_rad(75)
@export var offset: Vector3 = Vector3(0, 2.0, 0)
@export_range(-75.0, 75.0, 0.1, "degrees") var camera_default_pitch_degrees := -32.0

@export var body: PhysicsBody
@export var model: Node3D

# ZOOM
@export_group("Camera Zoom")
## Default distance to set the camera from the player.
@export var camera_default_distance := 7.0
## Maximum distance the camera can zoom out to.
@export var camera_distance_max := 14
## Mininum distance the camera can zoom in to.
@export var camera_distance_min := 1.0
## How far the camera will move per zoom input.
@export var camera_zoom_step := 0.2
## How quickly the camera zoom interpolates.
@export var camera_lerp_speed := 5.0
# Variable for handling smooth zooming.
var _spring_arm_target_length := camera_default_distance

@onready var _spring_arm: SpringArm3D = $SpringArm3D

var _mouse_position_when_hidden = Vector2.ZERO
var _left_click_position: Vector2 = Vector2.ZERO
var _left_drag_delta: Vector2 = Vector2.ZERO
var _left_pressed: bool = false
var _left_dragging: bool = false
var _right_click_position: Vector2 = Vector2.ZERO
var _right_drag_delta: Vector2 = Vector2.ZERO
var _right_pressed: bool = false
var _right_dragging: bool = false



func _ready() -> void:
	var start_transform := global_transform
	top_level = true
	global_transform = start_transform

	rotation.x = clampf(deg_to_rad(camera_default_pitch_degrees), -tilt_limit, tilt_limit)
	_spring_arm_target_length = clampf(camera_default_distance, camera_distance_min, camera_distance_max)
	_spring_arm.spring_length = _spring_arm_target_length
	_spring_arm.add_excluded_object(body)
	
	if model != null:
		rotation.y = model.global_rotation.y
	if model != null:
		var pos: Vector3 = model.global_position
		global_position.x = pos.x + offset.x
		global_position.y = pos.y + offset.y
		global_position.z = pos.z + offset.z

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var motion_event: InputEventMouseMotion = event
	if _left_pressed and motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_click_or_drag(motion_event)
		get_viewport().set_input_as_handled()
	elif _right_pressed and motion_event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_update_click_or_drag(motion_event)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_begin_click_or_drag(event)
			else:
				_end_click_or_drag(event)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_spring_arm_target_length -= camera_zoom_step
			_spring_arm_target_length = clamp(_spring_arm_target_length, camera_distance_min, camera_distance_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_spring_arm_target_length += camera_zoom_step
			_spring_arm_target_length = clamp(_spring_arm_target_length, camera_distance_min, camera_distance_max)

func _process(delta: float):
	if model != null:
		# Follow visual_position (smoothed) when available, so the camera
		# isn't affected by tick-rate jitter from clock stretching.
		var pos: Vector3 = model.global_position
		global_position.x = pos.x + offset.x
		global_position.y = pos.y + offset.y
		global_position.z = pos.z + offset.z

	# Handle smooth camera zooming.
	if _spring_arm_target_length != _spring_arm.spring_length:
		var zoom_weight: float = clampf(camera_lerp_speed * delta, 0.0, 1.0)
		_spring_arm.spring_length = lerp(_spring_arm.spring_length, _spring_arm_target_length, zoom_weight)

func _request_mouse_restore():
	get_viewport().warp_mouse(_mouse_position_when_hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _begin_click_or_drag(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_left_pressed = true
		_left_dragging = false
		_left_drag_delta = Vector2.ZERO
		_left_click_position = event.position
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_right_pressed = true
		_right_dragging = false
		_right_drag_delta = Vector2.ZERO
		_right_click_position = event.position
	else:
		return

	_capture_mouse_for_drag(event.position)


func _end_click_or_drag(event: InputEvent) -> void:
	var is_left: bool = event.button_index == MOUSE_BUTTON_LEFT
	if is_left:
		if not _left_pressed:
			return
		_left_pressed = false
		_left_dragging = false
		_left_drag_delta = Vector2.ZERO
	else:
		if not _right_pressed:
			return
		_right_pressed = false
		_right_dragging = false
		_right_drag_delta = Vector2.ZERO

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		call_deferred("_request_mouse_restore")

func _update_click_or_drag(event: InputEventMouseMotion) -> void:
	var relative: Vector2 = event.relative
	var is_left: bool = bool(event.button_mask & MOUSE_BUTTON_MASK_LEFT)
	if is_left:
		_left_drag_delta += relative
		if not _left_dragging and _left_drag_delta.length() >= CLICK_DRAG_THRESHOLD_PX:
			_left_dragging = true
		if _left_dragging:
			_rotate_from_mouse_motion(relative)
	else:
		_right_drag_delta += relative
		if not _right_dragging and _right_drag_delta.length() >= CLICK_DRAG_THRESHOLD_PX:
			_right_dragging = true
		if _right_dragging:
			_rotate_from_mouse_motion(relative)

func _capture_mouse_for_drag(restore_position: Vector2) -> void:
	_mouse_position_when_hidden = restore_position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _rotate_from_mouse_motion(relative: Vector2) -> void:
	rotation.x -= relative.y * mouse_sensitivity
	# Prevent camera from rotating too far up/down
	rotation.x = clampf(rotation.x, -tilt_limit, tilt_limit)
	rotation.y += -relative.x * mouse_sensitivity
