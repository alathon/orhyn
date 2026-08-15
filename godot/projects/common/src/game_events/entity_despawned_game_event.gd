class_name EntityDespawnedGameEvent
extends GameEvent

const REASON_UNKNOWN: int = 0

var entity_id: int = 0
var reason: int = 0


func _init(
		new_entity_id: int = 0,
		new_reason: int = REASON_UNKNOWN,
		new_source: int = GameEvent.Source.UNKNOWN,
		new_server_tick: int = -1) -> void:
	super(GameEvent.TYPE_ENTITY_DESPAWNED, new_source, new_server_tick)
	entity_id = new_entity_id
	reason = new_reason
