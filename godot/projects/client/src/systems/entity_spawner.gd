class_name ClientEntitySpawner
extends Node

signal entity_spawned(entity: BaseEntity)
signal entity_despawned(entity_id: int)

@export var zone_container: ClientZoneContainer
@export var game_events: GameEventBus
@export var player_entity_scene: PackedScene
@export var remote_entity_scene: PackedScene

var entities_container: Node = null
var _local_player_id: int = -1
var _local_player: Player
var entities: Dictionary[int, BaseEntity] = {}
var local_entity_id: int:
	get:
		return _local_player_id

func _ready() -> void:
	if game_events != null:
		game_events.subscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _on_controlled_entity_assigned)
		game_events.subscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _on_entity_despawned)
		game_events.subscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_entity_spawned)
	else:
		push_warning("ClientEntitySpawner has no GameEventBus assigned.")

	if zone_container == null:
		push_warning("ClientEntitySpawner has no zone_container assigned.")
		return

	zone_container.zone_loaded.connect(_on_zone_loaded)
	if zone_container.loaded_entities != null:
		_set_entities_container(zone_container.loaded_entities)

func _exit_tree() -> void:
	if game_events == null:
		return
	game_events.unsubscribe(GameEvent.TYPE_CONTROLLED_ENTITY_ASSIGNED, _on_controlled_entity_assigned)
	game_events.unsubscribe(GameEvent.TYPE_ENTITY_DESPAWNED, _on_entity_despawned)
	game_events.unsubscribe(GameEvent.TYPE_ENTITY_SPAWNED, _on_entity_spawned)

func get_local_player() -> Player:
	return _local_player

func get_player(entity_id: int) -> BaseEntity:
	return entities.get(entity_id)

func get_players() -> Dictionary[int, BaseEntity]:
	return entities

func _on_controlled_entity_assigned(event: ControlledEntityAssignedGameEvent) -> void:
	_set_local_player_id(event.entity_id)

func _on_entity_despawned(event: EntityDespawnedGameEvent) -> void:
	despawn_entity(event.entity_id)

func _on_entity_spawned(event: EntitySpawnedGameEvent) -> void:
	spawn_entity(event)

func spawn_entity(spawn: EntitySpawnedGameEvent) -> BaseEntity:
	if entities_container == null:
		push_warning("Cannot spawn entity before a zone Entities node is loaded.")
		return null

	if spawn.entity_kind != EntitySpawnedGameEvent.ENTITY_KIND_PLAYER:
		push_warning("Ignoring unknown entity kind in spawn: %d" % spawn.entity_kind)
		return null

	var entity_id: int = spawn.entity_id
	if entity_id == _local_player_id:
		return _spawn_local_player(spawn)

	return _spawn_remote_entity(spawn)

func despawn_entity(entity_id: int) -> void:
	var player: Node = entities.get(entity_id) as Node
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

func _spawn_local_player(spawn: EntitySpawnedGameEvent) -> Player:
	if _local_player != null:
		_apply_spawn_transform(_local_player, spawn)
		return _local_player

	var stale_remote: Node = entities.get(_local_player_id) as Node
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

func _spawn_remote_entity(spawn: EntitySpawnedGameEvent) -> RemoteEntity:
	var entity_id: int = spawn.entity_id
	var existing: RemoteEntity = entities.get(entity_id) as RemoteEntity
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

func _apply_spawn_transform(entity: BaseEntity, spawn: EntitySpawnedGameEvent) -> void:
	var position: Vector3 = spawn.position
	var rotation: Quaternion = spawn.rotation
	var body: Node3D = entity.get_body()
	body.global_transform = Transform3D(Basis(rotation), position)

	if entity is RemoteEntity:
		(entity as RemoteEntity).apply_remote_transform(position, rotation)

func _on_zone_loaded(_zone_id: String, _zone: Node, entities_node: Node) -> void:
	_reset_spawned_entities()
	_set_entities_container(entities_node)

func _set_entities_container(entities_node: Node) -> void:
	entities_container = entities_node

func _reset_spawned_entities() -> void:
	for entity: BaseEntity in entities.values():
		if entity != null:
			entity.queue_free()
	entities.clear()
	_local_player = null
	_local_player_id = -1
