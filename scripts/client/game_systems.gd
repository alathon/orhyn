extends Node

@onready var api: API = $API
@onready var entity_spawner: ClientEntitySpawner = $EntitySpawner

var _last_tick_delta: float = Ticker.DEFAULT_TICK_SECONDS

func _ready() -> void:
	GlobalTicker.tick.connect(_on_tick)
	api.movement_snapshot_received.connect(_on_movement_snapshot_received)

func _on_tick(_n: int, delta: float) -> void:
	_last_tick_delta = delta
	var player: Player = entity_spawner.get_local_player()
	if player == null:
		return

	var player_input: PlayerInput = player.get_player_input()
	player_input.record()
	player.simulate(player_input.current_input, delta)
	player_input.record_predicted_state()
	api.send_player_input(
		player_input.current_input,
		player_input.get_previous_input_for_resend()
	)

func _on_movement_snapshot_received(msg: MovementSnapshotMsg) -> void:
	var local_snapshot: MovementSnapshotMsg.EntitySnapshot = null
	for snapshot in msg.entities:
		var entity_id = snapshot.entity_id

		if entity_id != entity_spawner.local_entity_id:
			var remote: RemoteEntity = entity_spawner.get_player(entity_id) as RemoteEntity
			if remote != null:
				remote.push_movement_snapshot(snapshot)
			continue

		local_snapshot = snapshot

	if local_snapshot == null:
		return

	_reconcile_local_player(local_snapshot)

func _reconcile_local_player(snapshot: MovementSnapshotMsg.EntitySnapshot) -> void:
	if snapshot.last_processed_movement_seq == MovementSnapshotMsg.NO_PROCESSED_SEQ:
		return

	var player: Player = entity_spawner.get_local_player()
	if player == null:
		return

	var reconciliation: PlayerMovementReconciliation = player.get_movement_reconciliation()
	if reconciliation == null:
		return

	reconciliation.reconcile(snapshot, _last_tick_delta)
