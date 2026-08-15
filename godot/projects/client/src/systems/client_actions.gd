class_name ClientActions
extends Node

signal action_submitted(action_name: StringName, request_id: int)
signal action_rejected(action_name: StringName, reason: StringName)
signal action_resolved(action_name: StringName, request_id: int, result_code: int)

@export var api: GameServerAPI
@export var entity_spawner: ClientEntitySpawner

var _local_player: Player = null
var _pending_action_names: Dictionary[int, StringName] = {}

func _ready() -> void:
	if api == null:
		push_error("ClientActions has no GameServerAPI assigned.")
		return
	if entity_spawner == null:
		push_error("ClientActions has no ClientEntitySpawner assigned.")
		return

	api.action_result_received.connect(_on_action_result_received)
	entity_spawner.local_player_spawned.connect(_on_local_player_spawned)
	entity_spawner.local_player_despawned.connect(_on_local_player_despawned)

func try_equip_item(item: EquippableItem, slot_id: Equippable.SlotId) -> int:
	if api == null:
		push_warning("Cannot equip item because no GameServerAPI is assigned.")
		return -1

	if _local_player == null:
		action_rejected.emit(&"equip_item", &"local_player_not_available")
		return -1

	if not _local_player.equipment.can_equip(item, slot_id):
		action_rejected.emit(&"equip_item", &"cannot_equip")
		return -1

	var request_id: int = api.request_equip_item(
		slot_id,
		item.instance_id,
		item.get_template_resource_path()
	)
	if request_id > 0:
		_submit_action(&"equip_item", request_id)
	return request_id

func try_unequip_slot(slot_id: Equippable.SlotId) -> int:
	if api == null:
		push_warning("Cannot unequip slot because no GameServerAPI is assigned.")
		return -1

	if _local_player == null:
		action_rejected.emit(&"unequip_slot", &"local_player_not_available")
		return -1

	var request_id: int = api.request_unequip_slot(slot_id)
	if request_id > 0:
		_submit_action(&"unequip_slot", request_id)
	return request_id

func _submit_action(action_name: StringName, request_id: int) -> void:
	_pending_action_names[request_id] = action_name
	action_submitted.emit(action_name, request_id)

func _on_action_result_received(request_id: int, result_code: int) -> void:
	if not _pending_action_names.has(request_id):
		return

	var action_name: StringName = _pending_action_names.get(request_id)
	_pending_action_names.erase(request_id)
	action_resolved.emit(action_name, request_id, result_code)

func _on_local_player_spawned(player: Player) -> void:
	_local_player = player

func _on_local_player_despawned(entity_id: int) -> void:
	if _local_player != null and _local_player.entity_id == entity_id:
		_local_player = null
