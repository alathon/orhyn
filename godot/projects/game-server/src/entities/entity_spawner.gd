class_name EntitySpawner
extends Node

signal entity_spawned(entity: BaseEntity)
signal entity_despawned(entity: BaseEntity)

@export var player_entity_scene: PackedScene
@export var npc_entity: PackedScene
@export var entity_tracker: EntityTracker
@export var network: GameServerNetwork
@export var zone_container: ZoneContainer

const SPAWN_POSITION: Vector3 = Vector3(154.0, 18.0, -159.0)
const SPAWN_GROUND_RAY_UP: float = 100.0
const SPAWN_GROUND_RAY_DOWN: float = 300.0
const SPAWN_GROUND_CLEARANCE: float = 0.05
const DEFAULT_MODEL_NAME: String = "Wizard"
const DEFAULT_LEVEL: int = 1

var entities: Node = null

func _ready() -> void:
	zone_container.zone_loaded.connect(_on_zone_loaded)
	if zone_container.loaded_entities != null:
		_on_zone_loaded(zone_container.loaded_zone_id, zone_container.loaded_zone, zone_container.loaded_entities)
	network.zone_login_received.connect(_on_zone_login_received)
	network.player_disconnected.connect(_on_player_disconnected)

func _on_zone_login_received(peer_id: int, login: ZoneLoginRequestMsg) -> void:
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
	var body: PhysicsBody = player.get_body()
	body.global_position = _snap_spawn_to_ground(body, SPAWN_POSITION)
	entity_spawned.emit(player)
	_send_initial_lifecycle(peer_id, player.entity_id)
	_send_character_loaded(peer_id, login.character_id, player.entity_id)
	_broadcast_spawn(player, [peer_id])

	print(
		"Game server spawned logged-in player: peer=%d character_id=%d entity_id=%d" %
		[peer_id, login.character_id, player.entity_id]
	)

func _snap_spawn_to_ground(body: PhysicsBody, requested_position: Vector3) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = requested_position + Vector3.UP * SPAWN_GROUND_RAY_UP
	query.to = requested_position - Vector3.UP * SPAWN_GROUND_RAY_DOWN
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]

	var result: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		push_warning("Spawn ground snap missed: requested=%s" % str(requested_position))
		return requested_position

	var hit_position: Vector3 = result["position"] as Vector3
	var snapped_position: Vector3 = hit_position + Vector3.UP * SPAWN_GROUND_CLEARANCE
	print("Game server snapped spawn to ground: requested=%s snapped=%s" % [
		str(requested_position),
		str(snapped_position),
	])
	return snapped_position

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
	var spawns: Array[EntitySpawnedGameEvent] = []
	for player: ServerPlayerEntity in entity_tracker.get_players().values():
		spawns.append(_make_spawn_event(player))

	var bytes: PackedByteArray = EntityLifecycleCodec.encode(spawns, [], controlled_entity_id)
	network.send_entity_lifecycle(peer_id, bytes)

func _send_character_loaded(peer_id: int, character_id: int, entity_id: int) -> void:
	var zone_id: String = zone_container.loaded_zone_id
	var bytes: PackedByteArray = CharacterLoadedCodec.encode(
		character_id,
		entity_id,
		"Player",
		zone_id,
		DEFAULT_MODEL_NAME,
		DEFAULT_LEVEL
	)
	var err: Error = network.send_character_loaded(peer_id, bytes)
	if err != OK:
		push_warning("Failed to send character_loaded: peer=%d error=%s" % [peer_id, error_string(err)])
		return

	print(
		"Game server sent character_loaded: peer=%d character_id=%d entity_id=%d zone=%s" %
		[peer_id, character_id, entity_id, zone_id]
	)

func _broadcast_spawn(player: ServerPlayerEntity, excluded_peer_ids: Array[int] = []) -> void:
	var spawns: Array[EntitySpawnedGameEvent] = [_make_spawn_event(player)]
	var bytes: PackedByteArray = EntityLifecycleCodec.encode(spawns, [])
	network.broadcast_entity_lifecycle(bytes, excluded_peer_ids)

func _broadcast_despawn(entity_id: int) -> void:
	var despawns: Array[EntityDespawnedGameEvent] = [EntityDespawnedGameEvent.new(entity_id)]
	var bytes: PackedByteArray = EntityLifecycleCodec.encode([], despawns)
	network.broadcast_entity_lifecycle(bytes)

func _make_spawn_event(player: ServerPlayerEntity) -> EntitySpawnedGameEvent:
	var body: PhysicsBody = player.get_body()
	return EntitySpawnedGameEvent.new(
		player.entity_id,
		EntitySpawnedGameEvent.ENTITY_KIND_PLAYER,
		body.global_position,
		body.global_transform.basis.get_rotation_quaternion(),
		player.equipment.revision,
		player.equipment.get_snapshot_entries()
	)

func _on_zone_loaded(_zone_id: String, _zone: Node, zone_entities: Node) -> void:
	entities = zone_entities
