class_name CharacterLoadController
extends Node

signal character_loaded(character: ClientLoadedCharacter)

@export var dev_character_load_delay_seconds: float = 0.20
@export var dev_entity_id: int = 1
@export var api: API

var flow_state: ClientFlowState = null
var loaded_character: ClientLoadedCharacter = null
var _load_in_progress: bool = false
var _waiting_for_server_character: bool = false

func _ready() -> void:
	if api != null:
		api.character_loaded_received.connect(_on_character_loaded_received)

func begin_character_load() -> void:
	if _load_in_progress:
		return

	_load_in_progress = true
	loaded_character = null
	if _should_wait_for_server_character():
		_waiting_for_server_character = true
		print("Client waiting for character_loaded from zone server")
		return

	await get_tree().create_timer(dev_character_load_delay_seconds).timeout
	_emit_dev_character_loaded()

func _on_character_loaded_received(message: CharacterLoadedMsg) -> void:
	if not _waiting_for_server_character:
		return

	loaded_character = ClientLoadedCharacter.create(
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
		[loaded_character.character_id, loaded_character.entity_id]
	)
	character_loaded.emit(loaded_character)

func _should_wait_for_server_character() -> bool:
	return (
		api != null
		and flow_state != null
		and flow_state.pending_zone_redirect != null
	)

func _emit_dev_character_loaded() -> void:
	var selected_character: ClientCharacterSummary = null
	if flow_state != null:
		selected_character = flow_state.selected_character

	if selected_character == null:
		selected_character = ClientCharacterSummary.create(
			1,
			"player",
			"mvp",
			"Wizard",
			1
		)

	loaded_character = ClientLoadedCharacter.create(
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
		[loaded_character.character_id, loaded_character.entity_id]
	)
	character_loaded.emit(loaded_character)
