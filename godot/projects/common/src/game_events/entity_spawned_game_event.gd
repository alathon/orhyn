class_name EntitySpawnedGameEvent
extends GameEvent

const ENTITY_KIND_PLAYER: int = 0
const ENTITY_KIND_NPC: int = 1

var entity_id: int = 0
var entity_kind: int = ENTITY_KIND_PLAYER
var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var equipment_revision: int = 0
var equipment_entries: Array[Dictionary] = []


func _init(
		new_entity_id: int = 0,
		new_entity_kind: int = ENTITY_KIND_PLAYER,
		new_position: Vector3 = Vector3.ZERO,
		new_rotation: Quaternion = Quaternion.IDENTITY,
		new_equipment_revision: int = 0,
		new_equipment_entries: Array[Dictionary] = [],
		new_source: int = GameEvent.Source.UNKNOWN,
		new_server_tick: int = -1) -> void:
	super(GameEvent.TYPE_ENTITY_SPAWNED, new_source, new_server_tick)
	entity_id = new_entity_id
	entity_kind = new_entity_kind
	position = new_position
	rotation = new_rotation
	equipment_revision = new_equipment_revision
	equipment_entries = new_equipment_entries
