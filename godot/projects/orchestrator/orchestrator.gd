extends Node

## Central orchestrator that manages zone server registration and player
## zone transfers. Runs as a headless Godot instance with a raw WebSocket server.
## Game servers connect on startup and send OrchestratorPacket protobuf messages.

const Proto = preload("res://projects/common/src/proto/packets.gd")

@export var PORT: int = 9000

## Port that game clients connect to for login.
@export var CLIENT_PORT: int = 9001

## HTTP health/readiness probe port.
@export var HEALTH_PORT: int = 9100

## Transfer tokens expire after this many seconds.
const TOKEN_TIMEOUT := 30.0

## Registered zone servers: zone_id -> { peer_id, address, port, max_players, current_players }
var _zones: Dictionary[String, Dictionary] = {}

## peer_id -> zone_id (reverse lookup)
var _peer_zones: Dictionary[int, String] = {}

## Pending transfers: transfer_token -> { from_zone_id, to_zone_id, peer_id, player_state,
##   entry_x, entry_y, entry_z, entry_rot_y, origin_peer, dest_peer, created_at,
##   is_login (bool), client_peer_id (int, only for initial entry) }
var _pending_transfers: Dictionary[String, Dictionary] = {}

## Connected game server WebSocket peers: peer_id -> WebSocketPeer
var _peers: Dictionary[int, WebSocketPeer] = {}

## Connected client WebSocket peers: peer_id -> WebSocketPeer
var _client_peers: Dictionary[int, WebSocketPeer] = {}
var _client_display_names: Dictionary[int, String] = {}
var _disconnected_characters: Dictionary[int, Dictionary] = {}

## Character selections waiting for a zone to become available:
##   Array of { client_peer_id, character_id, zone_id, retry_at }
var _pending_character_select_queue: Array[Dictionary] = []

const LOGIN_RETRY_INTERVAL := 3.0
const PLACEHOLDER_CHARACTER_ID := 1
const PLACEHOLDER_MODEL_NAME := "Wizard"

## peer_id -> last time we received a HeartbeatAck (unix timestamp)
var _last_heartbeat_ack: Dictionary[int, float] = {}

var _tcp_server: TCPServer = null
var _client_tcp_server: TCPServer = null
var _next_peer_id: int = 1
var _next_client_peer_id: int = 10000
var _next_ping_id: int = 0
var _heartbeat_timer: float = 0.0
var _health_server: HealthHttpServer = null

## Send a heartbeat ping every this many seconds.
const HEARTBEAT_INTERVAL := 5.0
## Consider a peer dead if no ack received within this many seconds.
const HEARTBEAT_TIMEOUT := 15.0

func _ready() -> void:
	Log.info("area=Boot message=%s values=%s" % [str("Logging configured"), str({ "runtime": "orchestrator" })])
	_parse_cmdline_args()
	_tcp_server = TCPServer.new()
	var error := _tcp_server.listen(PORT)
	if error != OK:
		Log.error("area=Networking message=%s values=%s" % [str("Failed to listen for game servers"), str({ "port": PORT, "error": error })])
		return
	Log.info("area=Networking message=%s values=%s" % [str("Listening for game servers"), str({ "port": PORT })])

	_client_tcp_server = TCPServer.new()
	error = _client_tcp_server.listen(CLIENT_PORT)
	if error != OK:
		Log.error("area=Networking message=%s values=%s" % [str("Failed to listen for clients"), str({ "port": CLIENT_PORT, "error": error })])
		return
	Log.info("area=Networking message=%s values=%s" % [str("Listening for clients"), str({ "port": CLIENT_PORT })])

	_start_health_server()

func _parse_cmdline_args() -> void:
	_apply_cmdline_args(OS.get_cmdline_args())
	_apply_cmdline_args(OS.get_cmdline_user_args())


func _apply_cmdline_args(args: PackedStringArray) -> void:
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			PORT = int(args[i + 1])
		elif args[i] == "--client-port" and i + 1 < args.size():
			CLIENT_PORT = int(args[i + 1])
		elif args[i] == "--health-port" and i + 1 < args.size():
			HEALTH_PORT = int(args[i + 1])

func _process(delta: float) -> void:
	if _health_server != null:
		_health_server.poll()
	_accept_new_connections()
	_accept_client_connections()
	_poll_peers()
	_poll_client_peers()
	_retry_pending_character_selects()
	_expire_tokens()
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_send_heartbeats()
		_check_heartbeat_timeouts()

func _start_health_server() -> void:
	_health_server = HealthHttpServer.new()
	var err: Error = _health_server.start(
			HEALTH_PORT,
			"orchestrator",
			Callable(self, "_is_ready"),
			Callable(self, "_health_details"))
	if err != OK:
		Log.error("area=Networking message=%s values=%s" % [str("Failed to listen for health checks"), str({ "port": HEALTH_PORT, "error": err })])
		_health_server = null
	else:
		Log.info("area=Networking message=%s values=%s" % [str("Listening for health checks"), str({ "port": HEALTH_PORT })])


func _is_ready() -> bool:
	return _tcp_server != null and _client_tcp_server != null


func _health_details() -> Dictionary:
	return {
		"game_server_port": PORT,
		"client_port": CLIENT_PORT,
		"registered_zones": _zones.size(),
		"game_server_peers": _peers.size(),
		"client_peers": _client_peers.size(),
	}

func _accept_new_connections() -> void:
	while _tcp_server.is_connection_available():
		var tcp := _tcp_server.take_connection()
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp)
		var peer_id := _next_peer_id
		_next_peer_id += 1
		_peers[peer_id] = ws
		_last_heartbeat_ack[peer_id] = Time.get_unix_time_from_system()
		Log.info("area=Networking message=%s values=%s" % [str("Game server connecting"), str({ "peer": peer_id })])

func _accept_client_connections() -> void:
	if _client_tcp_server == null:
		return
	while _client_tcp_server.is_connection_available():
		var tcp := _client_tcp_server.take_connection()
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp)
		var peer_id := _next_client_peer_id
		_next_client_peer_id += 1
		_client_peers[peer_id] = ws
		Log.info("area=Networking message=%s values=%s" % [str("Client connecting"), str({ "peer": peer_id })])

func _poll_peers() -> void:
	for peer_id in _peers.keys():
		var ws: WebSocketPeer = _peers[peer_id]
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				_on_packet(peer_id, ws.get_packet())
		elif state == WebSocketPeer.STATE_CLOSED:
			Log.info("area=Networking message=%s values=%s" % [str("Game server disconnected"), str({ "peer": peer_id })])
			_on_peer_disconnected(peer_id)
			_peers.erase(peer_id)

func _poll_client_peers() -> void:
	for peer_id in _client_peers.keys():
		var ws: WebSocketPeer = _client_peers[peer_id]
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				_on_client_packet(peer_id, ws.get_packet())
		elif state == WebSocketPeer.STATE_CLOSED:
			Log.info("area=Networking message=%s values=%s" % [str("Client disconnected"), str({ "peer": peer_id })])
			_client_display_names.erase(peer_id)
			_client_peers.erase(peer_id)

func _expire_tokens() -> void:
	var now := Time.get_unix_time_from_system()
	for token in _pending_transfers.keys():
		var transfer: Dictionary = _pending_transfers[token]
		if now - transfer["created_at"] > TOKEN_TIMEOUT:
			Log.warn("area=Orchestrator message=%s values=%s" % [str("Transfer token expired"), str({ "token": token })])
			_pending_transfers.erase(token)

func _on_peer_disconnected(peer_id: int) -> void:
	_last_heartbeat_ack.erase(peer_id)
	if _peer_zones.has(peer_id):
		var zone_id: String = _peer_zones[peer_id]
		_zones.erase(zone_id)
		_peer_zones.erase(peer_id)
		Log.info("area=Orchestrator message=%s values=%s" % [str("Unregistered zone"), str({ "zone": zone_id })])

func _on_packet(peer_id: int, bytes: PackedByteArray) -> void:
	var pkt := Proto.OrchestratorPacket.new()
	pkt.from_bytes(bytes)
	if pkt.has_zone_register():
		_handle_zone_register(peer_id, pkt.get_zone_register())
	elif pkt.has_zone_transfer_request():
		_handle_zone_transfer_request(peer_id, pkt.get_zone_transfer_request())
	elif pkt.has_prepare_player_ack():
		_handle_prepare_player_ack(peer_id, pkt.get_prepare_player_ack())
	elif pkt.has_heartbeat_ack():
		_last_heartbeat_ack[peer_id] = Time.get_unix_time_from_system()
		var zone_name: String = _peer_zones.get(peer_id, "unknown")
		Log.debug("area=Networking message=%s values=%s" % [str("Heartbeat ack"), str({ "peer": peer_id, "zone": zone_name })])
	elif pkt.has_character_disconnected_reserve():
		_handle_character_disconnected_reserve(pkt.get_character_disconnected_reserve())
	elif pkt.has_character_disconnected_clear():
		_handle_character_disconnected_clear(pkt.get_character_disconnected_clear())

# ── Zone Registration ─────────────────────────────────────────────────────────

func _handle_zone_register(peer_id: int, msg: Proto.ZoneRegister) -> void:
	var version: Proto.VersionInfo = msg.get_version() if msg.has_version() else null
	if not AppVersion.matches_current(version):
		Log.warn("area=Orchestrator message=%s values=%s" % [str("Zone registration rejected; version mismatch"), str(AppVersion.describe_mismatch(version).merged({ "peer": peer_id, "zone": msg.get_zone_id() }))])
		if _peers.has(peer_id):
			_peers[peer_id].close()
		_on_peer_disconnected(peer_id)
		_peers.erase(peer_id)
		return

	var zone_id: String = msg.get_zone_id()
	_zones[zone_id] = {
		"peer_id": peer_id,
		"address": msg.get_address(),
		"port": msg.get_port(),
		"max_players": msg.get_max_players(),
		"current_players": msg.get_current_players(),
	}
	_peer_zones[peer_id] = zone_id
	Log.info("area=Orchestrator message=%s values=%s" % [str("Registered zone"), str({
		"zone": zone_id,
		"address": msg.get_address(),
		"port": msg.get_port(),
		"peer": peer_id,
	})])

# ── Client Login ──────────────────────────────────────────────────────────────

func _on_client_packet(client_peer_id: int, bytes: PackedByteArray) -> void:
	var pkt: Proto.Packet = Proto.Packet.new()
	pkt.from_bytes(bytes)
	if pkt.has_login_request():
		_handle_login_request(client_peer_id, pkt.get_login_request())
	elif pkt.has_character_select_request():
		_handle_character_select_request(client_peer_id, pkt.get_character_select_request())

func _handle_login_request(client_peer_id: int, msg: Proto.LoginRequest) -> void:
	var version: Proto.VersionInfo = msg.get_version() if msg.has_version() else null
	if not AppVersion.matches_current(version):
		Log.warn("area=Orchestrator message=%s values=%s" % [str("Login rejected; version mismatch"), str(AppVersion.describe_mismatch(version).merged({ "client_peer": client_peer_id, "username": msg.get_username() }))])
		_send_login_failure(client_peer_id, "Client version does not match the server.")
		return

	var username: String = msg.get_username()
	_client_display_names[client_peer_id] = _placeholder_display_name(username)
	# TODO: authenticate username. For now, accept all.
	_send_login_response(client_peer_id, username)

func _send_login_response(client_peer_id: int, username: String) -> void:
	var pkt: Proto.Packet = Proto.Packet.new()
	var response: Proto.LoginResponse = pkt.new_login_response()
	var character: Proto.CharacterSummary = response.add_characters()
	var display_name: String = _client_display_names.get(client_peer_id, _placeholder_display_name(username))
	character.set_character_id(PLACEHOLDER_CHARACTER_ID)
	character.set_display_name(display_name)
	character.set_zone_id(ZoneCatalog.get_default_login_zone_id())
	character.set_model_name(PLACEHOLDER_MODEL_NAME)
	character.set_level(1)
	if _client_peers.has(client_peer_id):
		_client_peers[client_peer_id].send(pkt.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)
	Log.info("area=Orchestrator message=%s values=%s" % [str("Login response sent"), str({ "client_peer": client_peer_id, "username": username })])

func _send_login_failure(client_peer_id: int, reason: String) -> void:
	var pkt: Proto.Packet = Proto.Packet.new()
	var failure: Proto.LoginFailure = pkt.new_login_failure()
	failure.set_reason(reason)
	if _client_peers.has(client_peer_id):
		_client_peers[client_peer_id].send(pkt.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)

func _handle_character_select_request(client_peer_id: int, msg: Proto.CharacterSelectRequest) -> void:
	var character_id: int = int(msg.get_character_id())
	if character_id != PLACEHOLDER_CHARACTER_ID:
		_send_character_select_failure(client_peer_id, "Selected character is not available.")
		return
	if _is_character_disconnect_reserved(character_id):
		_send_character_select_failure(client_peer_id, "That character is still disconnecting. Try again shortly.")
		return

	var initial_zone_id: String = ZoneCatalog.get_default_login_zone_id()
	if not _zones.has(initial_zone_id):
		Log.warn("area=Orchestrator message=%s values=%s" % [str("Initial zone not ready; character selection queued"), str({
			"zone": initial_zone_id,
			"character_id": character_id,
			"retry_seconds": LOGIN_RETRY_INTERVAL,
		})])
		_pending_character_select_queue.append({
			"client_peer_id": client_peer_id,
			"character_id": character_id,
			"zone_id": initial_zone_id,
			"retry_at": Time.get_unix_time_from_system() + LOGIN_RETRY_INTERVAL,
		})
		return

	_prepare_initial_zone(client_peer_id, character_id, initial_zone_id)

func _send_character_select_failure(client_peer_id: int, reason: String) -> void:
	var pkt: Proto.Packet = Proto.Packet.new()
	var failure: Proto.CharacterSelectFailure = pkt.new_character_select_failure()
	failure.set_reason(reason)
	if _client_peers.has(client_peer_id):
		_client_peers[client_peer_id].send(pkt.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)

func _prepare_initial_zone(client_peer_id: int, character_id: int, zone_id: String) -> void:
	var spawn: Dictionary = ZoneCatalog.get_login_spawn(zone_id)
	if spawn.is_empty():
		Log.error("area=Orchestrator message=%s values=%s" % [str("Character selection rejected; no spawn defined"), str({ "character_id": character_id, "zone": zone_id })])
		_send_character_select_failure(client_peer_id, "Selected character has no spawn point.")
		return

	var dest: Dictionary = _zones[zone_id]
	var token: String = _generate_token()

	_pending_transfers[token] = {
		"is_login": true,
		"client_peer_id": client_peer_id,
		"to_zone_id": zone_id,
		"dest_peer": dest["peer_id"],
		"created_at": Time.get_unix_time_from_system(),
	}

	Log.info("area=Orchestrator message=%s values=%s" % [str("Initial zone prepared"), str({ "character_id": character_id, "zone": zone_id, "token": token })])

	var spawn_pos: Vector3 = spawn["pos"]
	var display_name: String = _client_display_names.get(client_peer_id, "Player")
	var pkt: Proto.OrchestratorPacket = Proto.OrchestratorPacket.new()
	var prepare: Proto.PreparePlayer = pkt.new_prepare_player()
	prepare.set_transfer_token(token)
	prepare.set_entry_spawn_path("")  # position supplied directly in player_state
	var state: Proto.PlayerState = prepare.new_player_state()
	state.set_pos_x(spawn_pos.x)
	state.set_pos_y(spawn_pos.y)
	state.set_pos_z(spawn_pos.z)
	state.set_vel_x(0.0)
	state.set_vel_y(0.0)
	state.set_vel_z(0.0)
	state.set_rot_y(spawn["rot_y"])
	state.set_hp(100)
	state.set_max_hp(100)
	state.set_mana(100)
	state.set_max_mana(100)
	state.set_stamina(100)
	state.set_max_stamina(100)
	state.set_condition(Proto.EntityCondition.LIVING)
	state.set_display_name(display_name)
	state.set_visual_model_id(PLACEHOLDER_MODEL_NAME)
	state.set_character_id(character_id)
	_send_to_peer(dest["peer_id"], pkt)


func _handle_character_disconnected_reserve(msg: Proto.CharacterDisconnectedReserve) -> void:
	var character_id: int = int(msg.get_character_id())
	if character_id <= 0:
		return
	_disconnected_characters[character_id] = {
		"zone_id": msg.get_zone_id(),
		"expires_unix": msg.get_expires_unix(),
	}


func _handle_character_disconnected_clear(msg: Proto.CharacterDisconnectedClear) -> void:
	_disconnected_characters.erase(int(msg.get_character_id()))


func _is_character_disconnect_reserved(character_id: int) -> bool:
	var state: Dictionary = _disconnected_characters.get(character_id, {})
	if state.is_empty():
		return false
	if Time.get_unix_time_from_system() >= float(state.get("expires_unix", 0.0)):
		_disconnected_characters.erase(character_id)
		return false
	return true

func _retry_pending_character_selects() -> void:
	if _pending_character_select_queue.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	for i in range(_pending_character_select_queue.size() - 1, -1, -1):
		var entry: Dictionary = _pending_character_select_queue[i]
		if now < entry["retry_at"]:
			continue
		# Drop if the client disconnected while waiting.
		if not _client_peers.has(entry["client_peer_id"]):
			Log.info("area=Orchestrator message=%s values=%s" % [str("Character selection retry dropped; client disconnected"), str({ "client_peer": entry["client_peer_id"] })])
			_pending_character_select_queue.remove_at(i)
			continue
		if not _zones.has(entry["zone_id"]):
			Log.debug("area=Orchestrator message=%s values=%s" % [str("Zone still not ready; character selection retry delayed"), str({
				"zone": entry["zone_id"],
				"character_id": entry["character_id"],
				"retry_seconds": LOGIN_RETRY_INTERVAL,
			})])
			entry["retry_at"] = now + LOGIN_RETRY_INTERVAL
			continue
		# Zone is ready - proceed with initial entry.
		_pending_character_select_queue.remove_at(i)
		_prepare_initial_zone(entry["client_peer_id"], int(entry["character_id"]), entry["zone_id"])

# ── Zone Transfer ─────────────────────────────────────────────────────────────

func _handle_zone_transfer_request(origin_peer: int, msg: Proto.ZoneTransferRequest) -> void:
	var to_zone: String = msg.get_to_zone_id()
	var from_zone: String = msg.get_from_zone_id()
	var game_peer_id: int = msg.get_peer_id()

	if not _zones.has(to_zone):
		Log.warn("area=Orchestrator message=%s values=%s" % [str("Transfer rejected; destination zone not registered"), str({ "zone": to_zone, "peer": game_peer_id })])
		# TODO: send rejection back to origin so it can unfreeze the player.
		return

	var dest: Dictionary = _zones[to_zone]
	var token := _generate_token()

	_pending_transfers[token] = {
		"from_zone_id": from_zone,
		"to_zone_id": to_zone,
		"peer_id": game_peer_id,
		"origin_peer": origin_peer,
		"dest_peer": dest["peer_id"],
		"created_at": Time.get_unix_time_from_system(),
	}

	var spawn_path: String = msg.get_entry_spawn_path()
	Log.info("area=Orchestrator message=%s values=%s" % [str("Transfer prepared"), str({
		"peer": game_peer_id,
		"from_zone": from_zone,
		"to_zone": to_zone,
		"token": token,
		"spawn_path": spawn_path,
	})])

	# Send PreparePlayer to destination server.
	var pkt := Proto.OrchestratorPacket.new()
	var prepare := pkt.new_prepare_player()
	prepare.set_transfer_token(token)
	prepare.set_entry_spawn_path(spawn_path)
	var src_state := msg.get_player_state()
	var dst_state := prepare.new_player_state()
	dst_state.set_pos_x(src_state.get_pos_x())
	dst_state.set_pos_y(src_state.get_pos_y())
	dst_state.set_pos_z(src_state.get_pos_z())
	dst_state.set_vel_x(src_state.get_vel_x())
	dst_state.set_vel_y(src_state.get_vel_y())
	dst_state.set_vel_z(src_state.get_vel_z())
	dst_state.set_rot_y(src_state.get_rot_y())
	dst_state.set_hp(src_state.get_hp())
	dst_state.set_max_hp(src_state.get_max_hp())
	dst_state.set_mana(src_state.get_mana())
	dst_state.set_max_mana(src_state.get_max_mana())
	dst_state.set_stamina(src_state.get_stamina())
	dst_state.set_max_stamina(src_state.get_max_stamina())
	dst_state.set_condition(src_state.get_condition())
	dst_state.set_display_name(src_state.get_display_name())
	dst_state.set_visual_model_id(src_state.get_visual_model_id())
	dst_state.set_character_id(src_state.get_character_id())

	_send_to_peer(dest["peer_id"], pkt)

func _handle_prepare_player_ack(dest_peer: int, msg: Proto.PreparePlayerAck) -> void:
	var token: String = msg.get_transfer_token()
	if not _pending_transfers.has(token):
		Log.warn("area=Orchestrator message=%s values=%s" % [str("PreparePlayerAck for unknown token"), str({ "token": token, "peer": dest_peer })])
		return

	var transfer: Dictionary = _pending_transfers[token]

	if not msg.get_accepted():
		Log.warn("area=Orchestrator message=%s values=%s" % [str("Destination rejected transfer"), str({ "token": token, "peer": dest_peer })])
		_pending_transfers.erase(token)
		# TODO: send rejection back to origin so it can unfreeze the player.
		return

	var dest: Dictionary = _zones[transfer["to_zone_id"]]

	if transfer.get("is_login", false):
		# Login: send ZoneRedirect directly to the client over WebSocket.
		var client_peer_id: int = transfer["client_peer_id"]
		var pkt := Proto.Packet.new()
		var redirect := pkt.new_zone_redirect()
		redirect.set_zone_id(transfer["to_zone_id"])
		redirect.set_address(dest["address"])
		redirect.set_port(dest["port"])
		redirect.set_transfer_token(token)
		if _client_peers.has(client_peer_id):
			_client_peers[client_peer_id].send(pkt.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)
		Log.info("area=Orchestrator message=%s values=%s" % [str("Login redirect sent"), str({ "client_peer": client_peer_id, "token": token })])
	else:
		# Zone transfer: send ZoneTransferResponse to origin server so it can redirect the client.
		var pkt := Proto.OrchestratorPacket.new()
		var resp := pkt.new_zone_transfer_response()
		resp.set_peer_id(transfer["peer_id"])
		resp.set_transfer_token(token)
		resp.set_target_address(dest["address"])
		resp.set_target_port(dest["port"])
		resp.set_zone_id(transfer["to_zone_id"])
		_send_to_peer(transfer["origin_peer"], pkt)
		Log.info("area=Orchestrator message=%s values=%s" % [str("Zone redirect sent to origin"), str({ "peer": transfer["peer_id"], "token": token })])

# ── Heartbeat ─────────────────────────────────────────────────────────────────

func _send_heartbeats() -> void:
	var pkt := Proto.OrchestratorPacket.new()
	var hb := pkt.new_heartbeat()
	_next_ping_id += 1
	hb.set_ping_id(_next_ping_id)
	var bytes := pkt.to_bytes()
	var count := 0
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)
			count += 1
	if count > 0:
		Log.debug("area=Networking message=%s values=%s" % [str("Heartbeat sent"), str({ "peers": count, "ping_id": _next_ping_id })])

func _check_heartbeat_timeouts() -> void:
	var now := Time.get_unix_time_from_system()
	for peer_id in _last_heartbeat_ack.keys():
		if now - _last_heartbeat_ack[peer_id] > HEARTBEAT_TIMEOUT:
			Log.warn("area=Networking message=%s values=%s" % [str("Peer heartbeat timeout; disconnecting"), str({ "peer": peer_id })])
			if _peers.has(peer_id):
				_peers[peer_id].close()
			_on_peer_disconnected(peer_id)
			_peers.erase(peer_id)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _send_to_peer(peer_id: int, pkt: Proto.OrchestratorPacket) -> void:
	if _peers.has(peer_id):
		_peers[peer_id].send(pkt.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)
	else:
		Log.warn("area=Networking message=%s values=%s" % [str("Attempted to send to unknown game server peer"), str({ "peer": peer_id })])

func _generate_token() -> String:
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(randi() % 256)
	return bytes.hex_encode()

func _placeholder_display_name(username: String) -> String:
	var trimmed: String = username.strip_edges()
	if trimmed.is_empty():
		return "Player"
	return trimmed
