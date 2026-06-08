class_name MovementSnapshotSystem
extends BaseSystem

@export var player_input_buffers: PlayerInputBuffers
@export var network: GameServerNetwork
@export var systems: TickSystems

func _on_tick(tick: int, _delta: float):
	var entities: Array[MovementSnapshotMsg.EntitySnapshot] = []

	for entity: BaseEntity in systems.tick_context.entities_moved:
		if entity is ServerPlayerEntity:
			var player: ServerPlayerEntity = entity
			var body: PhysicsBody = player.get_body()
			var snapshot = MovementSnapshotMsg.EntitySnapshot.new()
			snapshot.entity_id = player.entity_id
			snapshot.last_processed_movement_seq = player.input_buffer.get_last_processed_seq()
			snapshot.position = body.global_position
			snapshot.velocity = body.velocity
			snapshot.rotation = body.global_transform.basis.get_rotation_quaternion()
			snapshot.is_on_floor = body.is_on_floor()
			entities.append(snapshot)

	if entities.is_empty():
		return

	network.broadcast_movement_snapshot(MovementSnapshotMsg.encode(entities, tick))
