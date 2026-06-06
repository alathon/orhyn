class_name ClientOrchestratorClient
extends Node

const DEFAULT_ORCHESTRATOR_URL: String = "ws://127.0.0.1:9001/ws"
const TYPE_LOGIN_RESPONSE: String = "login_response"
const TYPE_LOGIN_FAILURE: String = "login_failure"
const TYPE_CHARACTER_SELECT_FAILURE: String = "character_select_failure"
const TYPE_ZONE_REDIRECT: String = "zone_redirect"

@export var orchestrator_url: String = DEFAULT_ORCHESTRATOR_URL
@export var connect_timeout_seconds: float = 3.0
@export var response_timeout_seconds: float = 12.0

var _socket: WebSocketPeer = WebSocketPeer.new()
var _active_request_type: String = ""
var _active_request_result: Dictionary = {}

func request_login(username: String) -> Dictionary:
	print("Client requesting orchestrator login: username=%s" % username)
	var err: Error = await _ensure_connected()
	if err != OK:
		return _failure("Could not connect to orchestrator: %s" % error_string(err))

	if not _begin_request("login"):
		return _failure("Orchestrator request already in progress.")

	err = _send({
		"type": "login_request",
		"username": username,
	})
	if err != OK:
		_clear_request()
		return _failure("Could not send login request: %s" % error_string(err))

	return await _wait_for_request("login")

func request_character_select(character_id: int) -> Dictionary:
	print("Client requesting character zone redirect: character_id=%d" % character_id)
	var err: Error = await _ensure_connected()
	if err != OK:
		return _failure("Could not connect to orchestrator: %s" % error_string(err))

	if not _begin_request("character_select"):
		return _failure("Orchestrator request already in progress.")

	err = _send({
		"type": "character_select_request",
		"character_id": character_id,
	})
	if err != OK:
		_clear_request()
		return _failure("Could not send character select request: %s" % error_string(err))

	return await _wait_for_request("character_select")

func close() -> void:
	_socket.close()

func _process(_delta: float) -> void:
	_poll_socket()

func _ensure_connected() -> Error:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return OK

	if _socket.get_ready_state() != WebSocketPeer.STATE_CONNECTING:
		_socket = WebSocketPeer.new()
		print("Client connecting to orchestrator: %s" % orchestrator_url)
		var err: Error = _socket.connect_to_url(orchestrator_url)
		if err != OK:
			return err

	var started_msec: int = Time.get_ticks_msec()
	while _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_poll_socket()
		if _elapsed_seconds(started_msec) >= connect_timeout_seconds:
			_socket.close()
			return ERR_TIMEOUT
		await get_tree().process_frame

	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		print("Client connected to orchestrator")
		return OK
	return ERR_CANT_CONNECT

func _begin_request(request_type: String) -> bool:
	if not _active_request_type.is_empty():
		return false
	_active_request_type = request_type
	_active_request_result = {}
	return true

func _clear_request() -> void:
	_active_request_type = ""
	_active_request_result = {}

func _wait_for_request(request_type: String) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	while _active_request_type == request_type:
		_poll_socket()
		if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_clear_request()
			return _failure("Orchestrator connection closed.")
		if _elapsed_seconds(started_msec) >= response_timeout_seconds:
			_clear_request()
			return _failure("Timed out waiting for orchestrator.")
		await get_tree().process_frame

	var result: Dictionary = _active_request_result.duplicate(true)
	_clear_request()
	return result

func _poll_socket() -> void:
	_socket.poll()
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	while _socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _socket.get_packet()
		var text: String = packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Dropped malformed orchestrator message: %s" % text)
			continue
		var message: Dictionary = parsed
		_handle_message(message)

func _handle_message(message: Dictionary) -> void:
	var message_type: String = str(message.get("type", ""))
	match message_type:
		TYPE_LOGIN_RESPONSE:
			_handle_login_response(message)
		TYPE_LOGIN_FAILURE:
			_finish_request("login", _failure(str(message.get("reason", "Login failed."))))
		TYPE_CHARACTER_SELECT_FAILURE:
			_finish_request("character_select", _failure(str(message.get("reason", "Character select failed."))))
		TYPE_ZONE_REDIRECT:
			_handle_zone_redirect(message)
		_:
			print("Unhandled client orchestrator message: %s" % str(message))

func _handle_login_response(message: Dictionary) -> void:
	var characters: Array[ClientCharacterSummary] = []
	var raw_characters: Array = message.get("characters", [])
	for raw_character: Variant in raw_characters:
		if typeof(raw_character) != TYPE_DICTIONARY:
			continue
		var character_data: Dictionary = raw_character
		characters.append(ClientCharacterSummary.create(
			int(character_data.get("character_id", 0)),
			str(character_data.get("display_name", "")),
			str(character_data.get("zone_id", "")),
			str(character_data.get("model_name", "")),
			int(character_data.get("level", 1))
		))

	_finish_request("login", {
		"ok": true,
		"characters": characters,
	})
	print("Client received login_response: characters=%d" % characters.size())

func _handle_zone_redirect(message: Dictionary) -> void:
	var redirect: ClientZoneRedirect = ClientZoneRedirect.create(
		str(message.get("zone_id", "")),
		str(message.get("address", "")),
		int(message.get("port", 0)),
		str(message.get("transfer_token", ""))
	)
	_finish_request("character_select", {
		"ok": true,
		"redirect": redirect,
	})
	print(
		"Client received zone_redirect: zone=%s address=%s port=%d token_len=%d" %
		[redirect.zone_id, redirect.address, redirect.port, redirect.transfer_token.length()]
	)

func _finish_request(request_type: String, result: Dictionary) -> void:
	if _active_request_type != request_type:
		return
	_active_request_type = ""
	_active_request_result = result

func _send(message: Dictionary) -> Error:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var text: String = JSON.stringify(message)
	return _socket.send_text(text)

func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}

func _elapsed_seconds(started_msec: int) -> float:
	return float(Time.get_ticks_msec() - started_msec) / 1000.0
