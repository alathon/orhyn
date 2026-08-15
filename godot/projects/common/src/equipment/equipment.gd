class_name Equipment
extends Node

signal slot_changed(slot_id: Equippable.SlotId, previous_item: EquippableItem, current_item: EquippableItem)
signal changed()

var _equipment: Dictionary[Equippable.SlotId, EquippableItem]
var revision: int = 0

func can_equip(item: EquippableItem, slot_id: Equippable.SlotId) -> bool:
	# For now, we just check that slot_id is legal for the item.
	return item != null \
			and item.template != null \
			and item.template.equippable != null \
			and item.template.equippable.slots.has(slot_id)

func get_equipped(slot_id: Equippable.SlotId) -> EquippableItem:
	return _equipment.get(slot_id, null) as EquippableItem


func has_equipped_slot(slot_id: Equippable.SlotId) -> bool:
	return _equipment.has(slot_id)


func get_equipped_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot_id in _equipment.keys():
		slots.append(int(slot_id))
	slots.sort()
	return slots


# Returns the item that was already equipped, if replacing an existing item.
func set_equipped(item: EquippableItem, slot_id: Equippable.SlotId) -> EquippableItem:
	var existing: EquippableItem = get_equipped(slot_id)
	_equipment.set(slot_id, item)
	revision += 1
	slot_changed.emit(slot_id, existing, item)
	changed.emit()
	return existing


# Returns the unequipped item
func unset_equipped(slot_id: Equippable.SlotId) -> EquippableItem:
	var existing: EquippableItem = get_equipped(slot_id)
	if existing == null:
		return null
	_equipment.erase(slot_id)
	revision += 1
	slot_changed.emit(slot_id, existing, null)
	changed.emit()
	return existing


func clear() -> void:
	if _equipment.is_empty():
		return
	var previous_slots: Array[int] = get_equipped_slots()
	for slot_id in previous_slots:
		var previous_item: EquippableItem = get_equipped(slot_id)
		_equipment.erase(slot_id)
		slot_changed.emit(slot_id, previous_item, null)
	revision += 1
	changed.emit()


func get_snapshot_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot_id in get_equipped_slots():
		var item: EquippableItem = get_equipped(slot_id)
		if item == null or item.template == null:
			continue
		entries.append({
			"slot_id": slot_id,
			"item_instance_id": item.instance_id,
			"template_resource_path": item.get_template_resource_path(),
		})
	return entries


func apply_snapshot_entries(entries: Array[Dictionary], snapshot_revision: int = -1) -> void:
	var desired_equipment: Dictionary[Equippable.SlotId, EquippableItem] = {}
	for entry in entries:
		var template_path: String = str(entry.get("template_resource_path", ""))
		var template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
		if template == null:
			push_warning("Equipment item template could not be loaded: %s" % template_path)
			continue
		var item: EquippableItem = EquippableItem.create(
				template,
				1,
				str(entry.get("item_instance_id", "")))
		var slot_id: Equippable.SlotId = int(entry.get("slot_id", 0))
		desired_equipment.set(slot_id, item)

	for equipped_slot_id: int in get_equipped_slots():
		var slot_id: Equippable.SlotId = equipped_slot_id
		if not desired_equipment.has(slot_id):
			unset_equipped(slot_id)

	var desired_slots: Array[int] = []
	for slot_id in desired_equipment.keys():
		desired_slots.append(int(slot_id))
	desired_slots.sort()
	for desired_slot_id: int in desired_slots:
		var slot_id: Equippable.SlotId = desired_slot_id
		var desired_item: EquippableItem = desired_equipment.get(slot_id) as EquippableItem
		if _matches_equipped_snapshot(get_equipped(slot_id), desired_item):
			continue
		set_equipped(desired_item, slot_id)

	if snapshot_revision >= 0:
		revision = snapshot_revision


func _matches_equipped_snapshot(current_item: EquippableItem, desired_item: EquippableItem) -> bool:
	if current_item == null or desired_item == null:
		return current_item == desired_item
	return current_item.instance_id == desired_item.instance_id \
			and current_item.get_template_resource_path() == desired_item.get_template_resource_path()
