class_name IngameScreen
extends Node3D

signal zone_loaded(zone_id: String)
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
	zone_container.zone_loaded.connect(_on_zone_loaded)
	character_load_controller.api = api
	character_load_controller.flow_state = flow_state
	character_load_controller.character_loaded.connect(_on_character_loaded)

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

func begin_character_load() -> void:
	character_load_controller.begin_character_load()
