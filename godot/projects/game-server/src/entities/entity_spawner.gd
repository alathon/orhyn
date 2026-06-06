class_name EntitySpawner
extends Node

signal entity_spawned(entity: BaseEntity)
signal entity_despawned(entity: BaseEntity)

@export var player_entity_scene: PackedScene
@export var npc_entity: PackedScene
@export var entity_tracker: EntityTracker
@export var network: GameServerAPI
@export var zone_container: ZoneContainer

const SPAWN_POSITION: Vector3 = Vector3(-39.976143, 0.7148186, -40.79889)

var entities: Node = null

func _ready() -> void:
	zone_container.zone_loaded.connect(_on_zone_loaded)
	if zone_container.loaded_entities != null:
		_on_zone_loaded(zone_container.loaded_zone_id, zone_container.loaded_zone, zone_container.loaded_entities)
	network.player_connected.connect(_on_player_connected)
	network.player_disconnected.connect(_on_player_disconnected)

func _on_player_connected(peer_id: int) -> void:
	if entities == null:
		push_error("Cannot spawn player before the zone Entities node is available.")
		return

	if entity_tracker.has_player(peer_id):
		return

	var player: ServerPlayerEntity = player_entity_scene.instantiate() as ServerPlayerEntity
	if player == null:
		push_error("Configured player entity scene did not instantiate a ServerPlayerEntity.")
		return

	player.name = "Player_%d" % peer_id
	player.peer_id = peer_id
	player.entity_id = entity_tracker.allocate_entity_id()

	entities.add_child(player)
	player.get_body().global_position = SPAWN_POSITION
	entity_spawned.emit(player)
	_send_initial_lifecycle(peer_id, player.entity_id)
	_broadcast_spawn(player, [peer_id])

	print("Spawned server player entity=%d for peer %d" % [player.entity_id, peer_id])

func _on_player_disconnected(peer_id: int) -> void:
	var player: ServerPlayerEntity = entity_tracker.get_player(peer_id)
	if player == null:
		return

	var entity_id: int = player.entity_id
	entity_despawned.emit(player)
	player.queue_free()
	_broadcast_despawn(entity_id)

	print("Removed server player entity=%d for peer %d" % [entity_id, peer_id])

func _send_initial_lifecycle(peer_id: int, controlled_entity_id: int) -> void:
	var spawns: Array[EntityLifecycleMsg.SpawnRecord] = []
	for player: ServerPlayerEntity in entity_tracker.get_players().values():
		spawns.append(_make_spawn_record(player))

	var bytes: PackedByteArray = EntityLifecycleMsg.encode(spawns, [], controlled_entity_id)
	network.send_entity_lifecycle(peer_id, bytes)

func _broadcast_spawn(player: ServerPlayerEntity, excluded_peer_ids: Array[int] = []) -> void:
	var spawns: Array[EntityLifecycleMsg.SpawnRecord] = [_make_spawn_record(player)]
	var bytes: PackedByteArray = EntityLifecycleMsg.encode(spawns, [])
	network.broadcast_entity_lifecycle(bytes, excluded_peer_ids)

func _broadcast_despawn(entity_id: int) -> void:
	var despawn: EntityLifecycleMsg.DespawnRecord = EntityLifecycleMsg.DespawnRecord.new()
	despawn.entity_id = entity_id
	var despawns: Array[EntityLifecycleMsg.DespawnRecord] = [despawn]
	var bytes: PackedByteArray = EntityLifecycleMsg.encode([], despawns)
	network.broadcast_entity_lifecycle(bytes)

func _make_spawn_record(player: ServerPlayerEntity) -> EntityLifecycleMsg.SpawnRecord:
	var body: PhysicsBody = player.get_body()
	var spawn: EntityLifecycleMsg.SpawnRecord = EntityLifecycleMsg.SpawnRecord.new()
	spawn.entity_id = player.entity_id
	spawn.entity_kind = EntityLifecycleMsg.EntityKind.Player
	spawn.position = body.global_position
	spawn.rotation = body.global_transform.basis.get_rotation_quaternion()
	return spawn

func _on_zone_loaded(_zone_id: String, _zone: Node, zone_entities: Node) -> void:
	entities = zone_entities
