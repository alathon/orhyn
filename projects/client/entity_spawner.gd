class_name ClientEntitySpawner
extends Node

signal entity_spawned(entity: BaseEntity)
signal entity_despawned(entity_id: int)

@onready var api: API = %API
@onready var entities_container: Node = %Entities

@export var player_entity_scene: PackedScene
@export var remote_entity_scene: PackedScene

var _local_player_id = -1
var _local_player: Player
var entities: Dictionary[int, BaseEntity] = {}
var local_entity_id: int:
	get:
		return _local_player_id

func _ready() -> void:
	api.entity_lifecycle_received.connect(_on_entity_lifecycle_received)

func get_local_player() -> Player:
	return _local_player

func get_player(entity_id: int) -> BaseEntity:
	return entities.get(entity_id)

func get_players() -> Dictionary[int, BaseEntity]:
	return entities

func _on_entity_lifecycle_received(lifecycle: EntityLifecycleMsg) -> void:
	if lifecycle.controlled_entity_id != EntityLifecycleMsg.NO_ENTITY_ID:
		_set_local_player_id(lifecycle.controlled_entity_id)

	for despawn in lifecycle.entities_despawned:
		despawn_entity(despawn.entity_id)

	for spawn in lifecycle.entities_spawned:
		spawn_entity(spawn)

func spawn_entity(spawn: EntityLifecycleMsg.SpawnRecord) -> BaseEntity:
	if spawn.entity_kind != EntityLifecycleMsg.EntityKind.Player:
		push_warning("Ignoring unknown entity kind in spawn: %d" % spawn.entity_kind)
		return null

	var entity_id = spawn.entity_id
	if entity_id == _local_player_id:
		return _spawn_local_player(spawn)

	return _spawn_remote_entity(spawn)

func despawn_entity(entity_id: int) -> void:
	var player = entities.get(entity_id) as Node
	if player == null:
		return

	entities.erase(entity_id)
	if player == _local_player:
		_local_player = null
		_local_player_id = -1

	player.queue_free()
	print("Despawned entity=%d" % entity_id)
	entity_despawned.emit(entity_id)

func _set_local_player_id(entity_id: int) -> void:
	if _local_player_id == entity_id:
		return

	if _local_player != null:
		despawn_entity(_local_player_id)

	_local_player_id = entity_id

func _spawn_local_player(spawn: EntityLifecycleMsg.SpawnRecord) -> Player:
	if _local_player != null:
		_apply_spawn_transform(_local_player, spawn)
		return _local_player

	var stale_remote = entities.get(_local_player_id) as Node
	if stale_remote != null:
		entities.erase(_local_player_id)
		stale_remote.queue_free()

	var player: Player = player_entity_scene.instantiate()
	player.name = "PlayerEntity"
	player.entity_id = _local_player_id

	entities_container.add_child(player)
	_apply_spawn_transform(player, spawn)

	_local_player = player
	entities[_local_player_id] = player

	print("Spawned local player entity=%d" % _local_player_id)
	entity_spawned.emit(player)
	return player

func _spawn_remote_entity(spawn: EntityLifecycleMsg.SpawnRecord) -> RemoteEntity:
	var entity_id = spawn.entity_id
	var existing = entities.get(entity_id) as RemoteEntity
	if existing != null:
		_apply_spawn_transform(existing, spawn)
		return existing

	var remote: RemoteEntity = remote_entity_scene.instantiate()
	remote.name = "Remote_%d" % entity_id
	remote.entity_id = entity_id

	entities_container.add_child(remote)
	_apply_spawn_transform(remote, spawn)
	entities[entity_id] = remote

	print("Spawned remote player entity=%d" % entity_id)
	entity_spawned.emit(remote)
	return remote

func _apply_spawn_transform(entity: BaseEntity, spawn: EntityLifecycleMsg.SpawnRecord) -> void:
	var position = spawn.position
	var rotation = spawn.rotation
	var body: Node3D = entity.get_body()
	body.global_transform = Transform3D(Basis(rotation), position)

	if entity is RemoteEntity:
		(entity as RemoteEntity).apply_remote_transform(position, rotation)
