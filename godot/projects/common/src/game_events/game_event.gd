class_name GameEvent
extends RefCounted

const TYPE_NONE: int = 0
const TYPE_CONTROLLED_ENTITY_ASSIGNED: int = 1
const TYPE_ENTITY_SPAWNED: int = 2
const TYPE_ENTITY_DESPAWNED: int = 3
const TYPE_CHARACTER_LOADED: int = 4
const TYPE_COUNT: int = 5

enum Source {
	UNKNOWN,
	SERVER_AUTHORITATIVE,
	CLIENT_PREDICTED,
	CLIENT_LOCAL,
}

var type: int = TYPE_NONE
var source: int = Source.UNKNOWN
var local_sequence: int = 0
var server_tick: int = -1


func _init(new_type: int = TYPE_NONE, new_source: int = Source.UNKNOWN, new_server_tick: int = -1) -> void:
	type = new_type
	source = new_source
	server_tick = new_server_tick
