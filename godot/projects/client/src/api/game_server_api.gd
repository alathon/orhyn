class_name GameServerAPI
extends Node

signal server_connected
signal server_connection_failed(reason: String)
signal movement_snapshot_received(snapshot: MovementSnapshotMsg)
signal entity_lifecycle_received(lifecycle: EntityLifecycleMsg)
signal character_loaded_received(message: CharacterLoadedMsg)

const DEFAULT_SERVER_HOST: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 4242
const CHANNEL_MOVEMENT: int = 0
const CHANNEL_MOVEMENT_SNAPSHOT: int = 1
const CHANNEL_ENTITY_LIFECYCLE: int = 2
const CHANNEL_ZONE_SESSION: int = 3
const CHANNEL_COUNT: int = 4

@export var auto_connect: bool = true

var _connection: ENetConnection
var _server_peer: ENetPacketPeer

func _ready() -> void:
	if auto_connect:
		connect_to_server()

func _process(_delta: float) -> void:
	poll()

func _exit_tree() -> void:
	disconnect_from_server()

func connect_to_server(host: String = DEFAULT_SERVER_HOST, port: int = DEFAULT_SERVER_PORT) -> Error:
	if _server_peer != null and _server_peer.get_state() != ENetPacketPeer.STATE_DISCONNECTED:
		return OK

	_connection = ENetConnection.new()
	var err: Error = _connection.create_host(1, CHANNEL_COUNT)
	if err != OK:
		push_error("Client ENet host creation failed: %s" % error_string(err))
		_connection = null
		return err

	_server_peer = _connection.connect_to_host(host, port, CHANNEL_COUNT)
	if _server_peer == null:
		push_error("Client ENet connect failed for %s:%d" % [host, port])
		_connection = null
		return ERR_CANT_CONNECT

	return OK

func connect_and_wait(host: String, port: int, timeout_seconds: float = 5.0) -> Error:
	var err: Error = connect_to_server(host, port)
	if err != OK:
		server_connection_failed.emit(error_string(err))
		return err

	var started_msec: int = Time.get_ticks_msec()
	while _server_peer != null:
		poll()
		var state: int = _server_peer.get_state()
		if state == ENetPacketPeer.STATE_CONNECTED:
			print("Client zone connection ready: %s:%d" % [host, port])
			return OK
		if state == ENetPacketPeer.STATE_DISCONNECTED:
			server_connection_failed.emit("Disconnected before connect completed.")
			return ERR_CONNECTION_ERROR
		if float(Time.get_ticks_msec() - started_msec) / 1000.0 >= timeout_seconds:
			server_connection_failed.emit("Timed out connecting to zone.")
			return ERR_TIMEOUT
		await get_tree().process_frame

	server_connection_failed.emit("Zone connection was closed.")
	return ERR_CONNECTION_ERROR

func send_zone_login(character_id: int, transfer_token: String) -> Error:
	if _server_peer == null or _server_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_CONNECTION_ERROR

	var bytes: PackedByteArray = ZoneLoginRequestMsg.encode(character_id, transfer_token)
	var err: Error = _server_peer.send(CHANNEL_ZONE_SESSION, bytes, ENetPacketPeer.FLAG_RELIABLE)
	if err == OK:
		print("Client sent zone login: character_id=%d token_len=%d" % [character_id, transfer_token.length()])
	return err

func send_player_input(input: MovementInputFrame, previous_inputs: Array = []) -> Error:
	var err: Error = connect_to_server()
	if err != OK:
		return err

	poll()
	if _server_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_BUSY

	var bytes: PackedByteArray = MovementInputMsg.encode(input, previous_inputs)
	return _server_peer.send(CHANNEL_MOVEMENT, bytes, 0)

func disconnect_from_server() -> void:
	if _server_peer != null and _server_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_server_peer.peer_disconnect()
		if _connection != null:
			_connection.flush()

	_disconnect()

func poll() -> void:
	if _connection == null:
		return

	while true:
		var event: Array = _connection.service(0)
		var event_type: int = event[0]

		if event_type == ENetConnection.EVENT_NONE:
			return

		if event_type == ENetConnection.EVENT_ERROR:
			push_error("Client ENet service error")
			_disconnect()
			return

		match event_type:
			ENetConnection.EVENT_CONNECT:
				print("Client connected to zone server")
				server_connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				_disconnect()
				return
			ENetConnection.EVENT_RECEIVE:
				var peer: ENetPacketPeer = event[1]
				var channel: int = event[3]
				if channel == CHANNEL_MOVEMENT_SNAPSHOT:
					_receive_movement_snapshot(peer.get_packet())
				elif channel == CHANNEL_ENTITY_LIFECYCLE:
					_receive_entity_lifecycle(peer.get_packet())
				elif channel == CHANNEL_ZONE_SESSION:
					_receive_character_loaded(peer.get_packet())
				else:
					peer.get_packet()

func _disconnect() -> void:
	if _connection != null:
		_connection.destroy()
	_connection = null
	_server_peer = null

func _receive_movement_snapshot(bytes: PackedByteArray) -> void:
	var snapshot: MovementSnapshotMsg = MovementSnapshotMsg.decode(bytes)
	if snapshot.entities.is_empty():
		return

	movement_snapshot_received.emit(snapshot)

func _receive_entity_lifecycle(bytes: PackedByteArray) -> void:
	var lifecycle: EntityLifecycleMsg = EntityLifecycleMsg.decode(bytes)

	if (
		lifecycle.entities_spawned.is_empty()
		and lifecycle.entities_despawned.is_empty()
		and lifecycle.controlled_entity_id == EntityLifecycleMsg.NO_ENTITY_ID
	):
		return

	entity_lifecycle_received.emit(lifecycle)

func _receive_character_loaded(bytes: PackedByteArray) -> void:
	var message: CharacterLoadedMsg = CharacterLoadedMsg.decode(bytes)
	if message.character_id <= 0 or message.entity_id <= 0:
		push_warning("Dropped malformed character_loaded packet")
		return

	print(
		"Client received character_loaded: character_id=%d entity_id=%d zone=%s" %
		[message.character_id, message.entity_id, message.zone_id]
	)
	character_loaded_received.emit(message)
