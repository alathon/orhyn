class_name ControlledEntityAssignedGameEvent
extends GameEvent

var entity_id: int = 0


func _init(
		new_entity_id: int = 0,
		new_source: int = GameEvent.Source.UNKNOWN,
		new_server_tick: int = -1) -> void:
	super(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, new_source, new_server_tick)
	entity_id = new_entity_id
