class_name MovementSnapshotSystem
extends BaseSystem

@onready var entity_tracker: EntityTracker = %EntityTracker
@onready var player_input_buffers: PlayerInputBuffers = %PlayerInputBuffers
@onready var network: Network = %Network

func _on_tick(server_tick: int, _delta: float):
	var entities: Array[MovementSnapshotMsg.EntitySnapshot] = []

	var players: Dictionary = entity_tracker.get_players()
	for peer_id in players:
		var player: ServerPlayerEntity = players[peer_id]
		var body: PhysicsBody = player.get_body()
		var snapshot = MovementSnapshotMsg.EntitySnapshot.new()
		snapshot.entity_id = player.entity_id
		snapshot.last_processed_movement_seq = player_input_buffers.get_last_processed_seq(peer_id)
		snapshot.position = body.global_position
		snapshot.velocity = body.velocity
		snapshot.rotation = body.global_transform.basis.get_rotation_quaternion()
		snapshot.is_on_floor = body.is_on_floor()
		entities.append(snapshot)

	if entities.is_empty():
		return

	network.broadcast_movement_snapshot(MovementSnapshotMsg.encode(entities, server_tick))
