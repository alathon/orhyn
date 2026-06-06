class_name IngameScreen
extends Node3D

signal zone_loaded(zone_id: String)
signal zone_connection_ready(address: String, port: int)
signal zone_connection_failed(reason: String)
signal character_loaded(character: ClientLoadedCharacter)
signal ingame_loaded(zone_id: String, character: ClientLoadedCharacter)

@export var api: API
@export var zone_container: ClientZoneContainer
@export var character_load_controller: CharacterLoadController

var flow_state: ClientFlowState = null
var _loaded_zone_id: String = ""
var _loaded_character: ClientLoadedCharacter = null
var _ingame_loaded: bool = false

func _ready() -> void:
	var zone_id: String = "mvp"
	if flow_state != null and flow_state.pending_zone_redirect != null:
		zone_id = flow_state.pending_zone_redirect.zone_id

	zone_container.zone_loaded.connect(_on_zone_loaded)
	character_load_controller.api = api
	character_load_controller.flow_state = flow_state
	character_load_controller.character_loaded.connect(_on_character_loaded)
	if flow_state != null and flow_state.pending_zone_redirect != null:
		_connect_to_zone(flow_state.pending_zone_redirect)
	zone_container.load_zone(zone_id)

func _on_zone_loaded(zone_id: String, _zone: Node, _entities: Node) -> void:
	_loaded_zone_id = zone_id
	print("Client zone scene loaded: %s" % zone_id)
	zone_loaded.emit(zone_id)
	character_load_controller.begin_character_load()
	_emit_ingame_loaded_if_ready()

func _on_character_loaded(character: ClientLoadedCharacter) -> void:
	_loaded_character = character
	character_loaded.emit(character)
	_emit_ingame_loaded_if_ready()

func _emit_ingame_loaded_if_ready() -> void:
	if _ingame_loaded or _loaded_zone_id.is_empty() or _loaded_character == null:
		return
	_ingame_loaded = true
	ingame_loaded.emit(_loaded_zone_id, _loaded_character)

func is_ingame_loaded() -> bool:
	return _ingame_loaded

func get_loaded_zone_id() -> String:
	return _loaded_zone_id

func get_loaded_character() -> ClientLoadedCharacter:
	return _loaded_character

func _connect_to_zone(redirect: ClientZoneRedirect) -> void:
	print(
		"Client connecting to zone: zone=%s address=%s port=%d" %
		[redirect.zone_id, redirect.address, redirect.port]
	)
	var err: Error = await api.connect_and_wait(redirect.address, redirect.port)
	if err != OK:
		var reason: String = "Zone connection failed: %s" % error_string(err)
		push_warning(reason)
		zone_connection_failed.emit(reason)
		return

	var character_id: int = 0
	if flow_state != null and flow_state.selected_character != null:
		character_id = flow_state.selected_character.character_id
	err = api.send_zone_login(character_id, redirect.transfer_token)
	if err != OK:
		var login_reason: String = "Zone login send failed: %s" % error_string(err)
		push_warning(login_reason)
		zone_connection_failed.emit(login_reason)
		return

	print("Client zone login sent: character_id=%d zone=%s" % [character_id, redirect.zone_id])
	zone_connection_ready.emit(redirect.address, redirect.port)
