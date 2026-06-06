class_name EntityTracker
extends Node

@onready var entity_spawner: EntitySpawner = %EntitySpawner

var _next_entity_id: int = 1
var _entities_by_entity_id: Dictionary = {}
var _players_by_peer_id: Dictionary = {}
var _peer_ids_by_entity_id: Dictionary = {}

func _ready() -> void:
	entity_spawner.entity_spawned.connect(_on_entity_spawned)
	entity_spawner.entity_despawned.connect(_on_entity_despawned)

func allocate_entity_id() -> int:
	var entity_id: int = _next_entity_id
	_next_entity_id += 1
	return entity_id

func track_player(peer_id: int, player: ServerPlayerEntity) -> void:
	if player == null:
		return

	_untrack_existing_player(peer_id)
	_untrack_existing_entity(player.entity_id)

	_players_by_peer_id[peer_id] = player
	_peer_ids_by_entity_id[player.entity_id] = peer_id
	_entities_by_entity_id[player.entity_id] = player

func untrack_player(peer_id: int) -> ServerPlayerEntity:
	var player: ServerPlayerEntity = get_player(peer_id)
	if player == null:
		return null

	_players_by_peer_id.erase(peer_id)
	_peer_ids_by_entity_id.erase(player.entity_id)
	_entities_by_entity_id.erase(player.entity_id)
	return player

func track_entity(entity: BaseEntity) -> void:
	if entity == null:
		return

	_untrack_existing_entity(entity.entity_id)
	_entities_by_entity_id[entity.entity_id] = entity

func untrack_entity(entity_id: int) -> BaseEntity:
	var entity: BaseEntity = get_entity(entity_id)
	if entity == null:
		return null

	_untrack_existing_entity(entity_id)
	return entity

func has_player(peer_id: int) -> bool:
	return _players_by_peer_id.has(peer_id)

func has_entity(entity_id: int) -> bool:
	return _entities_by_entity_id.has(entity_id)

func get_player(peer_id: int) -> ServerPlayerEntity:
	return _players_by_peer_id.get(peer_id) as ServerPlayerEntity

func get_player_by_entity_id(entity_id: int) -> ServerPlayerEntity:
	var peer_id: int = get_peer_id_for_entity(entity_id)
	if peer_id == -1:
		return null
	return get_player(peer_id)

func get_peer_id_for_entity(entity_id: int) -> int:
	return int(_peer_ids_by_entity_id.get(entity_id, -1))

func get_entity(entity_id: int) -> BaseEntity:
	return _entities_by_entity_id.get(entity_id) as BaseEntity

func get_players() -> Dictionary:
	return _players_by_peer_id

func get_entities() -> Dictionary:
	return _entities_by_entity_id

func get_peer_ids() -> Array:
	return _players_by_peer_id.keys()

func get_entity_ids() -> Array:
	return _entities_by_entity_id.keys()

func _on_entity_spawned(entity: BaseEntity) -> void:
	if entity is ServerPlayerEntity:
		var player: ServerPlayerEntity = entity as ServerPlayerEntity
		track_player(player.peer_id, player)
		return

	track_entity(entity)

func _on_entity_despawned(entity: BaseEntity) -> void:
	if entity == null:
		return

	untrack_entity(entity.entity_id)

func _untrack_existing_player(peer_id: int) -> void:
	var existing: ServerPlayerEntity = get_player(peer_id)
	if existing == null:
		return

	_players_by_peer_id.erase(peer_id)
	_peer_ids_by_entity_id.erase(existing.entity_id)
	_entities_by_entity_id.erase(existing.entity_id)

func _untrack_existing_entity(entity_id: int) -> void:
	if not _entities_by_entity_id.has(entity_id):
		return

	_entities_by_entity_id.erase(entity_id)

	if not _peer_ids_by_entity_id.has(entity_id):
		return

	var peer_id: int = int(_peer_ids_by_entity_id[entity_id])
	_peer_ids_by_entity_id.erase(entity_id)
	_players_by_peer_id.erase(peer_id)
