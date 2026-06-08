class_name ScreenManager
extends Node

const GROUP: StringName = &"screen_manager"

signal ScreenChange(from_screen: int, to_screen: int)
signal LoadingScreenShown(screen: LoadingScreen)
signal LoadingScreenHidden

enum Screen {
	NONE,
	LOGIN_SCREEN,
	CHARACTER_SELECT_SCREEN,
	INGAME_SCREEN,
}

@export var login_scene: PackedScene
@export var character_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var ingame_scene: PackedScene

@onready var _screen_container: Node = %ScreenContainer
@onready var _overlay_container: Node = %OverlayContainer

var current_screen_id: Screen = Screen.NONE
var current_screen: Node = null
var loading_overlay: LoadingScreen = null
var _prepared_ingame_screen: IngameScreen = null
var _loading_overlay_visible: bool = false

func _ready() -> void:
	add_to_group(GROUP)

func transition_to(screen_id: Screen, prepared_screen: Node = null) -> Node:
	match screen_id:
		Screen.LOGIN_SCREEN:
			return _transition_to_scene(screen_id, login_scene)
		Screen.CHARACTER_SELECT_SCREEN:
			var screen: CharacterSelectScreen = _transition_to_scene(screen_id, character_select_scene) as CharacterSelectScreen
			return screen
		Screen.INGAME_SCREEN:
			var ingame_screen: Node = prepared_screen
			if ingame_screen == null:
				ingame_screen = _create_ingame_screen()
			return _transition_to_existing_screen(screen_id, ingame_screen)
		_:
			return null

func show_login(status: String = "") -> LoginScreen:
	var screen: LoginScreen = transition_to(Screen.LOGIN_SCREEN) as LoginScreen
	if screen != null and not status.is_empty():
		screen.set_status(status)
	return screen

func show_loading_overlay() -> LoadingScreen:
	if loading_overlay != null and is_instance_valid(loading_overlay):
		_set_loading_overlay_visible(true)
		return loading_overlay

	if loading_scene == null:
		return null

	var screen: LoadingScreen = loading_scene.instantiate() as LoadingScreen
	if screen == null:
		return null

	_overlay_container.add_child(screen)
	loading_overlay = screen
	_set_loading_overlay_visible(true)
	return screen

func hide_loading_overlay() -> void:
	if loading_overlay == null:
		_set_loading_overlay_visible(false)
		return
	_set_loading_overlay_visible(false)
	if is_instance_valid(loading_overlay):
		_overlay_container.remove_child(loading_overlay)
		loading_overlay.queue_free()
	loading_overlay = null

func is_loading_overlay_visible() -> bool:
	return _loading_overlay_visible

func prepare_ingame_screen() -> IngameScreen:
	discard_prepared_ingame_screen()
	var screen: IngameScreen = _create_ingame_screen()
	if screen != null:
		_screen_container.add_child(screen)
		_screen_container.move_child(screen, 0)
	_prepared_ingame_screen = screen
	return screen

func complete_ingame_transition(screen: IngameScreen) -> void:
	transition_to(Screen.INGAME_SCREEN, screen)
	hide_loading_overlay()

func discard_prepared_ingame_screen(screen: IngameScreen = null) -> void:
	var target_screen: IngameScreen = screen
	if target_screen == null:
		target_screen = _prepared_ingame_screen
	if target_screen == null:
		return
	if is_instance_valid(target_screen):
		if target_screen.get_parent() == _screen_container:
			_screen_container.remove_child(target_screen)
		target_screen.queue_free()
	if target_screen == _prepared_ingame_screen:
		_prepared_ingame_screen = null

func _transition_to_scene(screen_id: int, scene: PackedScene) -> Node:
	if scene == null:
		push_error("Screen scene is not configured: %s" % screen_id)
		return null

	var screen: Node = scene.instantiate()
	if screen == null:
		push_error("Screen scene could not be created: %s" % screen_id)
		return null

	var from_screen: int = current_screen_id
	_clear_screens()
	_screen_container.add_child(screen)
	current_screen = screen
	current_screen_id = screen_id
	_emit_screen_change(from_screen, screen_id)
	return screen

func _transition_to_existing_screen(screen_id: int, screen: Node) -> Node:
	if screen == null or not is_instance_valid(screen):
		push_error("Screen scene could not be created: %s" % screen_id)
		return null

	var from_screen: int = current_screen_id
	for child: Node in _screen_container.get_children():
		if child == screen:
			continue
		_screen_container.remove_child(child)
		child.queue_free()

	if screen.get_parent() != _screen_container:
		_screen_container.add_child(screen)
	_screen_container.move_child(screen, 0)
	current_screen = screen
	current_screen_id = screen_id
	_prepared_ingame_screen = null
	_emit_screen_change(from_screen, screen_id)
	return screen

func _create_ingame_screen() -> IngameScreen:
	if ingame_scene == null:
		return null

	var screen: IngameScreen = ingame_scene.instantiate() as IngameScreen
	if screen == null:
		return null

	return screen

func _clear_screens() -> void:
	for child: Node in _screen_container.get_children():
		_screen_container.remove_child(child)
		child.queue_free()
	current_screen = null
	_prepared_ingame_screen = null

func _emit_screen_change(from_screen: int, to_screen: int) -> void:
	if from_screen == to_screen:
		return
	ScreenChange.emit(from_screen, to_screen)

func _set_loading_overlay_visible(is_visible: bool) -> void:
	if _loading_overlay_visible == is_visible:
		return

	_loading_overlay_visible = is_visible
	if loading_overlay != null and is_instance_valid(loading_overlay):
		loading_overlay.visible = is_visible

	get_viewport().set_disable_input(is_visible)
	if is_visible:
		LoadingScreenShown.emit(loading_overlay)
	else:
		LoadingScreenHidden.emit()
