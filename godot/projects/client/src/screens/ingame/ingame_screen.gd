class_name IngameScreen
extends Node3D

signal zone_loaded(zone_id: String)
signal character_loaded(character: ClientLoadedCharacter)
signal ingame_loaded(zone_id: String, character: ClientLoadedCharacter)

@export var api: GameServerAPI
@export var zone_container: ClientZoneContainer
@export var dev_character_load_delay_seconds: float = 0.20
@export var dev_entity_id: int = 1

var selected_character: ClientCharacterSummary = null
var pending_zone_redirect: ClientZoneRedirect = null
var _loaded_zone_id: String = ""
var _loaded_character: ClientLoadedCharacter = null
var _ingame_loaded: bool = false
var _load_in_progress: bool = false
var _waiting_for_server_character: bool = false

func _ready() -> void:
	zone_container.zone_loaded.connect(_on_zone_loaded)
	if api != null:
		api.character_loaded_received.connect(_on_character_loaded_received)

func _on_zone_loaded(zone_id: String, _zone: Node, _entities: Node) -> void:
	_loaded_zone_id = zone_id
	print("Client zone scene loaded: %s" % zone_id)
	zone_loaded.emit(zone_id)
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

func load_zone(zone_id: String) -> Error:
	return zone_container.load_zone(zone_id)

func begin_character_load(character: ClientCharacterSummary = null, redirect: ClientZoneRedirect = null) -> void:
	if _load_in_progress:
		return

	selected_character = character
	pending_zone_redirect = redirect
	_load_in_progress = true
	_loaded_character = null

	if _should_wait_for_server_character():
		_waiting_for_server_character = true
		print("Client waiting for character_loaded from zone server")
		return

	await get_tree().create_timer(dev_character_load_delay_seconds).timeout
	_emit_dev_character_loaded()

func _on_character_loaded_received(message: CharacterLoadedMsg) -> void:
	if not _waiting_for_server_character:
		return

	_loaded_character = ClientLoadedCharacter.create(
		message.character_id,
		message.entity_id,
		message.display_name,
		message.zone_id,
		message.model_name,
		message.level
	)
	_waiting_for_server_character = false
	_load_in_progress = false
	print(
		"Client character load complete: character_id=%d entity_id=%d" %
		[_loaded_character.character_id, _loaded_character.entity_id]
	)
	character_loaded.emit(_loaded_character)
	_emit_ingame_loaded_if_ready()

func _should_wait_for_server_character() -> bool:
	return api != null and pending_zone_redirect != null

func _emit_dev_character_loaded() -> void:
	if selected_character == null:
		selected_character = ClientCharacterSummary.create(
			1,
			"player",
			"mvp",
			"Wizard",
			1
		)

	_loaded_character = ClientLoadedCharacter.create(
		selected_character.character_id,
		dev_entity_id,
		selected_character.display_name,
		selected_character.zone_id,
		selected_character.model_name,
		selected_character.level
	)
	_load_in_progress = false
	print(
		"Client character load complete (dev fallback): character_id=%d entity_id=%d" %
		[_loaded_character.character_id, _loaded_character.entity_id]
	)
	character_loaded.emit(_loaded_character)
	_emit_ingame_loaded_if_ready()
