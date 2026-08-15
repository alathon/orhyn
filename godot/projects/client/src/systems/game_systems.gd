class_name ClientGameSystems
extends Node

@onready var api: GameServerAPI = $API
@onready var entity_spawner: ClientEntitySpawner = $EntitySpawner
@onready var network_metrics: ClientNetworkMetricsCollector = $ClientNetworkMetricsCollector

@export var screen_manager_group: StringName = ScreenManager.GROUP

var _last_tick_delta: float = Ticker.DEFAULT_TICK_SECONDS
var _player_frozen_for_loading: bool = false

func _ready() -> void:
	GlobalTicker.tick.connect(_on_tick)
	api.movement_snapshot_received.connect(_on_movement_snapshot_received)
	var screen_manager: ScreenManager = _find_screen_manager()
	if screen_manager != null:
		connect_loading_screen_signals(screen_manager)

func connect_loading_screen_signals(screen_manager: ScreenManager) -> void:
	if not screen_manager.LoadingScreenShown.is_connected(_on_loading_screen_shown):
		screen_manager.LoadingScreenShown.connect(_on_loading_screen_shown)
	if not screen_manager.LoadingScreenHidden.is_connected(_on_loading_screen_hidden):
		screen_manager.LoadingScreenHidden.connect(_on_loading_screen_hidden)
	_set_player_frozen_for_loading(screen_manager.is_loading_overlay_visible())

func _on_tick(_n: int, delta: float) -> void:
	_last_tick_delta = delta
	if _player_frozen_for_loading:
		_freeze_current_player()
		return

	var player: Player = entity_spawner.get_local_player()
	if player == null:
		return

	var player_input: PlayerInput = player.get_player_input()
	player_input.record()
	player.simulate(player_input.current_input, delta)
	player_input.record_predicted_state()
	api.send_player_input(
		player_input.current_input,
		player_input.get_previous_inputs_for_resend()
	)

func _on_movement_snapshot_received(msg: MovementSnapshotMsg) -> void:
	if _player_frozen_for_loading:
		return

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

	var result: PlayerMovementReconciliation.Result = reconciliation.reconcile(
		snapshot,
		_last_tick_delta
	)
	network_metrics.record_reconciliation(result)

func _on_loading_screen_shown(_screen: LoadingScreen) -> void:
	_set_player_frozen_for_loading(true)

func _on_loading_screen_hidden() -> void:
	_set_player_frozen_for_loading(false)

func _set_player_frozen_for_loading(is_frozen: bool) -> void:
	_player_frozen_for_loading = is_frozen
	_freeze_current_player()

func _freeze_current_player() -> void:
	var player: Player = entity_spawner.get_local_player()
	if player == null:
		return
	player.freeze_for_loading(_player_frozen_for_loading)

func _find_screen_manager() -> ScreenManager:
	return get_tree().get_first_node_in_group(screen_manager_group) as ScreenManager
