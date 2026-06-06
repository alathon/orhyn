class_name Ticker
extends Node

const DEFAULT_TICK_SECONDS := 0.05

signal tick(n: int, delta: float)
signal before_tick(n: int, delta: float)
signal after_tick(n: int, delta: float)

@export var tick_seconds := DEFAULT_TICK_SECONDS

var _accumulator := 0.0
var _tick_n := 0

func _physics_process(delta: float) -> void:
	_accumulator += delta

	while _accumulator >= tick_seconds:
		_accumulator -= tick_seconds
		_tick_n += 1
		before_tick.emit(_tick_n, tick_seconds)
		tick.emit(_tick_n, tick_seconds)
		after_tick.emit(_tick_n, tick_seconds)
