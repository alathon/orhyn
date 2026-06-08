class_name ModelAnimationTree
extends AnimationTree

signal death_animation_finished

const KEY_CLIP := "clip"
const KEY_REQUEST_PATH := "request_path"
const KEY_TIME_SCALE_PATH := "time_scale_path"
const KEY_REQUIRED := "required"
const KEY_FADE_OUT_ON_CANCEL := "fade_out_on_cancel"
const KEY_DIRECT := "direct"

var _animation_player: AnimationPlayer
var _active_actions_by_request: Dictionary = {}
var _death_clip: StringName = &""
var _death_length: float = 0.0
var _is_playing_death: bool = false
var _direct_action_clip: StringName = &""


func bind_expression_base(base_node: Node) -> void:
	if base_node == null:
		push_error("Cannot bind expression base to null")
		return

	if _animation_player != null and _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.disconnect(_on_animation_finished)

	advance_expression_base_node = get_path_to(base_node)
	_animation_player = _resolve_animation_player()
	if _animation_player == null:
		push_error("AnimationTree.anim_player path is null - it must be set.")
		return
	
	active = true
	if _animation_player != null and not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)

	var death_action: Dictionary = _get_action(ModelAnimationActions.LIFECYCLE_DEATH)
	_death_clip = death_action.get(KEY_CLIP, &"")
	_death_length = _get_animation_length(_death_clip)

func play_action(
		action_key: StringName,
		request_id: int = 0,
		duration: float = 0.0,
		context: Dictionary = {}) -> bool:
	var action: Dictionary = _resolve_action(action_key, context)
	if action.is_empty():
		return false
	if request_id >= 0:
		_active_actions_by_request[request_id] = action

	if bool(action.get(KEY_DIRECT, false)):
		return _play_direct_action(action)
	return _request_tree_action(action, duration, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func cancel_action(request_id: int = -1) -> void:
	if request_id >= 0:
		var action: Dictionary = _active_actions_by_request.get(request_id, {})
		_cancel_action(action)
		_active_actions_by_request.erase(request_id)
		return
	for action in _active_actions_by_request.values():
		_cancel_action(action)
	_active_actions_by_request.clear()


func play_death() -> void:
	if _animation_player == null or _death_clip == &"":
		snap_death_pose()
		return
	_is_playing_death = true
	active = false
	_animation_player.stop()
	_animation_player.play(_death_clip)


func snap_death_pose() -> void:
	_is_playing_death = false
	active = false
	if _animation_player == null or _death_clip == &"":
		return
	_animation_player.play(_death_clip)
	if _death_length > 0.0:
		_animation_player.seek(maxf(_death_length - 0.001, 0.0), true)
	_animation_player.pause()


func restore_living() -> void:
	_is_playing_death = false
	_direct_action_clip = &""
	if _animation_player != null and not _animation_player.current_animation.is_empty():
		_animation_player.stop()
	active = true


func is_playing_death_animation() -> bool:
	return _is_playing_death


func get_bound_animation_player() -> AnimationPlayer:
	if _animation_player == null:
		push_error("Missing _animation_player")
		return

	return _animation_player


func supports_action(action_key: StringName) -> bool:
	return not _get_action(action_key).is_empty()


func validate_model(model_id: StringName) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var player: AnimationPlayer = _resolve_animation_player()
	if player == null:
		errors.append(_error(model_id, &"", "animation_player", "AnimationPlayer", "missing"))
	if tree_root == null:
		errors.append(_error(model_id, &"", "tree_root", "AnimationTree.tree_root", "missing"))
	if player == null:
		return errors

	var parameters: Dictionary = _collect_tree_parameters()
	for action_key in _get_actions().keys():
		var action: Dictionary = _get_action(action_key)
		if not bool(action.get(KEY_REQUIRED, false)):
			continue
		var clip_name: StringName = action.get(KEY_CLIP, &"")
		if clip_name == &"":
			errors.append(_error(model_id, action_key, "clip", "", "empty"))
		elif not player.has_animation(clip_name):
			errors.append(_error(model_id, action_key, "clip", str(clip_name), "missing"))
		for parameter_path in [str(action.get(KEY_REQUEST_PATH, "")), str(action.get(KEY_TIME_SCALE_PATH, ""))]:
			if parameter_path.is_empty():
				continue
			if not parameters.has(parameter_path):
				errors.append(_error(model_id, action_key, "tree_parameter", parameter_path, "missing"))
	return errors


func _get_actions() -> Dictionary:
	return {}


func _resolve_action(action_key: StringName, _context: Dictionary) -> Dictionary:
	return _get_action(action_key)


func _get_action(action_key: StringName) -> Dictionary:
	return _get_actions().get(action_key, {})


func _action(
		clip_name: StringName,
		request_path: String = "",
		time_scale_path: String = "",
		required: bool = true,
		fade_out_on_cancel: bool = true,
		direct: bool = false) -> Dictionary:
	return {
		KEY_CLIP: clip_name,
		KEY_REQUEST_PATH: request_path,
		KEY_TIME_SCALE_PATH: time_scale_path,
		KEY_REQUIRED: required,
		KEY_FADE_OUT_ON_CANCEL: fade_out_on_cancel,
		KEY_DIRECT: direct,
	}


func _direct_action(clip_name: StringName, required: bool = true) -> Dictionary:
	return _action(clip_name, "", "", required, false, true)


func _validation_clip(clip_name: StringName, required: bool = true) -> Dictionary:
	return _action(clip_name, "", "", required, false, false)


func _request_tree_action(action: Dictionary, duration: float, request: int) -> bool:
	var request_path: String = str(action.get(KEY_REQUEST_PATH, ""))
	if request_path.is_empty() or not _has_tree_parameter(request_path):
		return false
	var clip_name: StringName = action.get(KEY_CLIP, &"")
	var clip_length: float = _get_animation_length(clip_name)
	_set_time_scale(str(action.get(KEY_TIME_SCALE_PATH, "")), clip_length, duration)
	set(request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
	set(request_path, request)
	return true


func _play_direct_action(action: Dictionary) -> bool:
	if _animation_player == null:
		return false
	var clip_name: StringName = action.get(KEY_CLIP, &"")
	if clip_name == &"" or not _animation_player.has_animation(clip_name):
		return false
	_direct_action_clip = clip_name
	active = false
	_animation_player.stop()
	_animation_player.play(clip_name)
	return true


func _cancel_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	if bool(action.get(KEY_DIRECT, false)):
		_direct_action_clip = &""
		if _animation_player != null and not _animation_player.current_animation.is_empty():
			_animation_player.stop()
		active = true
		return
	if not bool(action.get(KEY_FADE_OUT_ON_CANCEL, false)):
		return
	_request_tree_action(action, 0.0, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _set_time_scale(parameter_path: String, clip_length: float, duration: float) -> void:
	if parameter_path.is_empty() or not _has_tree_parameter(parameter_path):
		return
	if clip_length <= 0.0 or duration <= 0.0:
		set(parameter_path, 1.0)
		return
	set(parameter_path, clip_length / duration)


func _get_animation_length(animation_name: StringName) -> float:
	if _animation_player == null or animation_name == &"" or not _animation_player.has_animation(animation_name):
		return 0.0
	return _animation_player.get_animation(animation_name).length


func _resolve_animation_player() -> AnimationPlayer:
	if anim_player == NodePath(""):
		return null
	return get_node_or_null(anim_player) as AnimationPlayer


func _collect_tree_parameters() -> Dictionary:
	var parameters: Dictionary = {}
	for property in get_property_list():
		parameters[str(property.name)] = true
	return parameters


func _has_tree_parameter(parameter_name: String) -> bool:
	for property in get_property_list():
		if property.name == parameter_name:
			return true
	return false


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == _death_clip and _is_playing_death:
		_is_playing_death = false
		death_animation_finished.emit()
		return
	if animation_name == _direct_action_clip:
		_direct_action_clip = &""
		active = true


func _error(
		model_id: StringName,
		action_key: StringName,
		field: String,
		expected: String,
		reason: String) -> Dictionary:
	return {
		"model_id": str(model_id),
		"tree": get_script().resource_path,
		"key": str(action_key),
		"field": field,
		"expected": expected,
		"reason": reason,
	}
