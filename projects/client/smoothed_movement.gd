extends Node

@export var model: Node3D
@export var body: PhysicsBody

var _base_model_transform := Transform3D.IDENTITY
var _from_transform := Transform3D.IDENTITY
var _to_transform := Transform3D.IDENTITY
var _tick_elapsed := 0.0
var _tick_duration := 0.05
var _has_tick := false

func _ready() -> void:
	if model == null:
		return

	_base_model_transform = model.transform
	_from_transform = model.global_transform
	_to_transform = model.global_transform
	
	GlobalTicker.before_tick.connect(_on_before_tick)
	GlobalTicker.after_tick.connect(_on_after_tick)

func set_model(m: Node3D):
	model = m
	_base_model_transform = model.transform
	_from_transform = model.global_transform
	_to_transform = model.global_transform

func set_body(b: PhysicsBody):
	body = b

func _on_before_tick(_n: int, _delta: float) -> void:
	if model == null:
		return

	_from_transform = model.global_transform

func _on_after_tick(_n: int, tick_delta: float) -> void:
	if model == null or body == null:
		return

	_to_transform = body.global_transform * _base_model_transform
	_tick_elapsed = 0.0
	_tick_duration = maxf(tick_delta, 0.001)
	_has_tick = true

func _process(delta: float) -> void:
	if not _has_tick or model == null:
		return

	_tick_elapsed += delta
	var weight := clampf(_tick_elapsed / _tick_duration, 0.0, 1.0)
	model.global_transform = _from_transform.interpolate_with(_to_transform, weight)

	if weight >= 1.0:
		_has_tick = false
