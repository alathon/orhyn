class_name GameEventBus
extends Node

var _subscribers_by_type: Array = []
var _next_local_sequence: int = 1


func _init() -> void:
	_subscribers_by_type.resize(GameEvent.TYPE_COUNT)
	for event_type in GameEvent.TYPE_COUNT:
		_subscribers_by_type[event_type] = []


func subscribe(event_type: int, callback: Callable) -> void:
	if not _is_valid_event_type(event_type) or not callback.is_valid():
		return

	var subscribers: Array = _subscribers_by_type[event_type]
	if subscribers.has(callback):
		return

	subscribers.append(callback)


func unsubscribe(event_type: int, callback: Callable) -> void:
	if not _is_valid_event_type(event_type):
		return

	var subscribers: Array = _subscribers_by_type[event_type]
	subscribers.erase(callback)


func publish(event: GameEvent) -> void:
	if event == null or event.type <= GameEvent.TYPE_NONE or event.type >= GameEvent.TYPE_COUNT:
		return

	var subscribers: Array = _subscribers_by_type[event.type]
	if subscribers.is_empty():
		return

	if event.local_sequence <= 0:
		event.local_sequence = _next_local_sequence
		_next_local_sequence += 1

	for i in subscribers.size():
		var callback: Callable = subscribers[i]
		callback.call(event)


func clear_subscribers() -> void:
	for event_type in GameEvent.TYPE_COUNT:
		var subscribers: Array = _subscribers_by_type[event_type]
		subscribers.clear()


func _is_valid_event_type(event_type: int) -> bool:
	return event_type > GameEvent.TYPE_NONE and event_type < GameEvent.TYPE_COUNT
