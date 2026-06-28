class_name EntityEquipmentChangedGameEvent
extends GameEvent

var entity_id: int = 0
var equipment_revision: int = 0
var changes: Array[Dictionary] = []


func _init(
		new_entity_id: int = 0,
		new_equipment_revision: int = 0,
		new_changes: Array[Dictionary] = [],
		new_source: int = GameEvent.Source.UNKNOWN,
		new_server_tick: int = -1) -> void:
	super(GameEvent.TYPE_ENTITY_EQUIPMENT_CHANGED, new_source, new_server_tick)
	entity_id = new_entity_id
	equipment_revision = new_equipment_revision
	changes = new_changes
