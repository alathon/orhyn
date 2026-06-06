class_name OrchestratorClient
extends Node

const RECONNECT_INTERVAL: float = 3.0

@export var _config: GameServerConfig
@export var _network: GameServerAPI

var _socket: WebSocketPeer = WebSocketPeer.new()
var _reconnect_timer: float = 0.0
var _was_open: bool = false

func _ready() -> void:
	_connect_to_orchestrator()

func _process(delta: float) -> void:
	_socket.poll()
	var state: int = _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open and _network.is_listening():
			_was_open = true
			_register_zone()
		_poll_packets()
		return

	if state == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			print("Orchestrator disconnected")
		_was_open = false
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_INTERVAL:
			_connect_to_orchestrator()

func _connect_to_orchestrator() -> void:
	_reconnect_timer = 0.0
	_socket = WebSocketPeer.new()
	var err: Error = _socket.connect_to_url(_config.orchestrator_url)
	if err != OK:
		push_warning("Orchestrator connect failed for %s: %s" % [_config.orchestrator_url, error_string(err)])
		return
	print("Connecting to orchestrator at %s" % _config.orchestrator_url)

func _poll_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _socket.get_packet()
		var text: String = packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Dropped malformed orchestrator message: %s" % text)
			continue

		var message: Dictionary = parsed
		var message_type: String = str(message.get("type", ""))
		match message_type:
			"heartbeat":
				_send({
					"type": "heartbeat_ack",
					"ping_id": int(message.get("ping_id", 0)),
				})
			_:
				print("Unhandled orchestrator message: %s" % text)

func _register_zone() -> void:
	var message: Dictionary = {
		"type": "zone_register",
		"zone_id": _config.zone_name,
		"address": _config.advertise_address,
		"port": _config.port,
		"max_players": _config.max_peers,
		"current_players": _network.get_peer_count(),
	}
	_send(message)
	print("Registered zone with orchestrator: %s" % str(message))

func _send(message: Dictionary) -> Error:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var text: String = JSON.stringify(message)
	return _socket.send_text(text)
