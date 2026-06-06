class_name Network
extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_input_received(peer_id: int, input: MovementInputFrame)

const BIND_ADDRESS := "0.0.0.0"
const PORT := 4242
const CHANNEL_MOVEMENT := 0
const CHANNEL_MOVEMENT_SNAPSHOT := 1
const CHANNEL_ENTITY_LIFECYCLE := 2
const MAX_PEERS := 32
const CHANNEL_COUNT := 3

var _connection = ENetConnection.new()
var _peer_ids: Dictionary = {}
var _peer_ids_by_instance_id: Dictionary = {}
var _peer_keys_by_id: Dictionary = {}
var _peer_addresses_by_id: Dictionary = {}
var _peer_ports_by_id: Dictionary = {}
var _peers_by_id: Dictionary = {}
var _next_peer_id = 1
var _is_listening = false

func _ready() -> void:
	var err = _connection.create_host_bound(BIND_ADDRESS, PORT, MAX_PEERS, CHANNEL_COUNT)
	if err != OK:
		push_error("Server ENet bind failed on %s:%d: %s" % [BIND_ADDRESS, PORT, error_string(err)])
		return

	_is_listening = true
	print("Server listening on %s:%d" % [BIND_ADDRESS, PORT])

func _process(_delta: float) -> void:
	if not _is_listening:
		return

	_poll_network()
	_cleanup_disconnected_peers()

func _poll_network() -> void:
	while true:
		var event = _connection.service(0)
		var event_type: int = event[0]

		if event_type == ENetConnection.EVENT_NONE:
			return

		if event_type == ENetConnection.EVENT_ERROR:
			push_error("Server ENet service error")
			return

		var peer: ENetPacketPeer = event[1]
		match event_type:
			ENetConnection.EVENT_CONNECT:
				var peer_id = _assign_peer_id(peer)
				print("Client connected: peer=%d %s:%d" % [peer_id, peer.get_remote_address(), peer.get_remote_port()])
				player_connected.emit(peer_id)
			ENetConnection.EVENT_DISCONNECT:
				_disconnect_peer(peer)
			ENetConnection.EVENT_RECEIVE:
				if event[3] == CHANNEL_MOVEMENT:
					_receive_movement_input(peer)

func _receive_movement_input(peer: ENetPacketPeer) -> void:
	var msg = MovementInputMsg.decode(peer.get_packet())
	if msg.inputs.is_empty():
		push_warning("Dropped malformed movement input packet")
		return

	var peer_id = _get_peer_id(peer)
	for input in msg.inputs:
		_receive_movement_input_frame(peer_id, input)

func _receive_movement_input_frame(peer_id: int, input: MovementInputFrame) -> void:
	player_input_received.emit(peer_id, input)

	# print(
	# 	"input peer=%d seq=%d x=%.3f z=%.3f jump=%s down=%s" %
	# 	[
	# 		peer_id,
	# 		input.seq,
	# 		input.input_x,
	# 		input.input_z,
	# 		input.jump_pressed,
	# 		input.jump_down,
	# 	]
	# )

func _cleanup_disconnected_peers() -> void:
	var peer_ids = _peers_by_id.keys()
	for peer_id in peer_ids:
		var peer = _peers_by_id.get(peer_id) as ENetPacketPeer
		if peer == null or peer.get_state() == ENetPacketPeer.STATE_DISCONNECTED:
			_disconnect_peer(peer, int(peer_id))

func _disconnect_peer(peer: ENetPacketPeer, known_peer_id := -1) -> void:
	var peer_id = known_peer_id
	if peer_id == -1 and peer != null:
		peer_id = _get_peer_id(peer)

	var address = "<unknown>"
	var port = -1
	var peer_key = ""
	if peer_id != -1:
		address = str(_peer_addresses_by_id.get(peer_id, address))
		port = int(_peer_ports_by_id.get(peer_id, port))
		peer_key = str(_peer_keys_by_id.get(peer_id, ""))

	if peer != null:
		_peer_ids_by_instance_id.erase(peer.get_instance_id())
	if not peer_key.is_empty():
		_peer_ids.erase(peer_key)

	if peer_id == -1:
		push_warning("Disconnected unknown client %s:%d" % [address, port])
		return

	_peers_by_id.erase(peer_id)
	_peer_keys_by_id.erase(peer_id)
	_peer_addresses_by_id.erase(peer_id)
	_peer_ports_by_id.erase(peer_id)
	player_disconnected.emit(peer_id)
	print("Client disconnected: peer=%d %s:%d" % [peer_id, address, port])

func _assign_peer_id(peer: ENetPacketPeer) -> int:
	var key = _peer_key(peer)
	var peer_id = _next_peer_id
	_next_peer_id += 1
	_peer_ids[key] = peer_id
	_peer_ids_by_instance_id[peer.get_instance_id()] = peer_id
	_peer_keys_by_id[peer_id] = key
	_peer_addresses_by_id[peer_id] = peer.get_remote_address()
	_peer_ports_by_id[peer_id] = peer.get_remote_port()
	_peers_by_id[peer_id] = peer
	return peer_id

func broadcast_movement_snapshot(bytes: PackedByteArray) -> void:
	for peer in _peers_by_id.values():
		var packet_peer = peer as ENetPacketPeer
		if packet_peer == null:
			continue
		if packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		packet_peer.send(CHANNEL_MOVEMENT_SNAPSHOT, bytes, ENetPacketPeer.FLAG_UNSEQUENCED)

func send_entity_lifecycle(peer_id: int, bytes: PackedByteArray) -> Error:
	var peer = _peers_by_id.get(peer_id) as ENetPacketPeer
	if peer == null:
		return ERR_DOES_NOT_EXIST
	if peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_CONNECTION_ERROR

	return peer.send(CHANNEL_ENTITY_LIFECYCLE, bytes, ENetPacketPeer.FLAG_RELIABLE)

func broadcast_entity_lifecycle(bytes: PackedByteArray, excluded_peer_ids: Array[int] = []) -> void:
	for peer_id in _peers_by_id:
		if excluded_peer_ids.has(int(peer_id)):
			continue
		send_entity_lifecycle(int(peer_id), bytes)

func _get_peer_id(peer: ENetPacketPeer) -> int:
	var instance_id = peer.get_instance_id()
	if _peer_ids_by_instance_id.has(instance_id):
		return int(_peer_ids_by_instance_id[instance_id])

	for peer_id in _peers_by_id:
		if _peers_by_id[peer_id] == peer:
			return int(peer_id)

	return -1

func _peer_key(peer: ENetPacketPeer) -> String:
	return "%s:%d" % [peer.get_remote_address(), peer.get_remote_port()]
