class_name AnchorPoints
extends Node

const ITEM_CONTAINER_NAME: String = "ItemContainer"
const EQUIPMENT_SLOT_META: StringName = &"equipment_slot_id"

@export var anchor_paths: Dictionary[String, Node] = {}

var _equipment_visual_scenes: Dictionary[Equippable.SlotId, PackedScene] = {}

func get_anchor(anchor_id: String) -> Node3D:
	var anchor: Variant = anchor_paths.get(anchor_id, null)
	if anchor == null:
		return null
	if anchor is NodePath:
		return get_node_or_null(anchor) as Node3D
	return anchor as Node3D

func has_anchor(anchor_id: String) -> bool:
	return get_anchor(anchor_id) != null

func has_item_container(anchor_id: String) -> bool:
	return get_item_container(anchor_id) != null

func get_item_container(anchor_id: String) -> Node3D:
	var anchor: Node3D = get_anchor(anchor_id)
	if anchor == null:
		return null
	return anchor.get_node_or_null(ITEM_CONTAINER_NAME) as Node3D

func set_equipment_slots(slot_equipment_scenes: Dictionary[Equippable.SlotId, PackedScene]) -> void:
	for previous_slot_id in _equipment_visual_scenes.keys():
		var slot_id: Equippable.SlotId = previous_slot_id
		if not slot_equipment_scenes.has(slot_id):
			unset_equipment_visual(slot_id)

	for desired_slot_id in slot_equipment_scenes.keys():
		var slot_id: Equippable.SlotId = desired_slot_id
		var scene: PackedScene = slot_equipment_scenes.get(slot_id, null)
		set_equipment_slot(slot_id, scene)

func set_equipment_slot(slot_id: Equippable.SlotId, scene: PackedScene) -> bool:
	if scene == null:
		return unset_equipment_visual(slot_id)

	var existing_scene: PackedScene = _equipment_visual_scenes.get(slot_id, null)
	if existing_scene == scene and _find_equipment_slot_container(slot_id) != null:
		return true

	unset_equipment_visual(slot_id)

	var anchor_id: String = _anchor_id_for_slot(slot_id)
	if anchor_id.is_empty() or not has_anchor(anchor_id):
		return false

	var instance: Node = scene.instantiate()
	var node: Node3D = instance as Node3D
	if node == null:
		instance.free()
		push_error("Equipment scene did not instantiate a Node3D for slot %s" % slot_id)
		return false
	if not _set_anchor_visual(anchor_id, node):
		node.free()
		return false

	var container: Node3D = get_item_container(anchor_id)
	if container != null:
		container.set_meta(EQUIPMENT_SLOT_META, int(slot_id))
	_equipment_visual_scenes.set(slot_id, scene)
	return true

func unset_equipment_visual(slot_id: Equippable.SlotId) -> bool:
	_equipment_visual_scenes.erase(slot_id)

	var container: Node3D = _find_equipment_slot_container(slot_id)
	if container == null:
		return true

	container.free()
	return true

func _set_anchor_visual(anchor_id: String, visual: Node3D) -> bool:
	if visual.get_parent() != null:
		push_error("Cannot attach an equipment visual that already has a parent")
		return false

	var anchor: Node3D = get_anchor(anchor_id)
	if anchor == null:
		push_error("No anchor with the id %s" % anchor_id)
		return false
	
	if anchor.has_node(ITEM_CONTAINER_NAME):
		if not _unset_anchor_visual(anchor_id):
			push_error("Unable to unset existing ItemContainer for anchor %s" % anchor_id)
			return false

	var item_container: Node3D = Node3D.new()
	item_container.name = ITEM_CONTAINER_NAME
	
	item_container.add_child(visual)
	anchor.add_child(item_container)
	item_container.position = Vector3.ZERO
	item_container.rotation_degrees = Vector3.ZERO
	return true

func _unset_anchor_visual(anchor_id: String) -> bool:
	var anchor: Node3D = get_anchor(anchor_id)
	if anchor == null:
		push_error("No anchor with the id %s" % anchor_id)
		return false

	var container: Node3D = anchor.get_node_or_null(ITEM_CONTAINER_NAME) as Node3D
	if container == null:
		push_error("No item to unset for anchor_id %s" % anchor_id)
		return false

	if container.has_meta(EQUIPMENT_SLOT_META):
		var slot_id: Equippable.SlotId = int(container.get_meta(EQUIPMENT_SLOT_META))
		_equipment_visual_scenes.erase(slot_id)
	container.free()
	return true

func move_item(from_anchor_id: String, to_anchor_id: String) -> bool:
	var to_anchor: Node3D = get_anchor(to_anchor_id)
	if to_anchor == null:
		return false
	
	if to_anchor.has_node(ITEM_CONTAINER_NAME):
		return false
	
	var from_anchor: Node3D = get_anchor(from_anchor_id)
	if from_anchor == null:
		return false
	
	var item_container: Node3D = from_anchor.get_node_or_null(ITEM_CONTAINER_NAME) as Node3D
	if item_container == null:
		return false
	
	from_anchor.remove_child(item_container)
	to_anchor.add_child(item_container)
	item_container.position = Vector3.ZERO
	item_container.rotation_degrees = Vector3.ZERO
	return true

# Utility methods for easier keyframing of common needs here.
func move_left_hand_to_hip() -> void:
	move_item("left_hand", "hip_left")

func move_hip_to_left_hand() -> void:
	move_item("hip_left", "left_hand")

func move_right_hand_to_hip_r() -> void:
	move_item("right_hand", "hip_right")

func move_hip_r_to_right_hand() -> void:
	move_item("hip_right", "right_hand")

func _find_equipment_slot_container(slot_id: Equippable.SlotId) -> Node3D:
	for anchor_id in anchor_paths.keys():
		var container: Node3D = get_item_container(anchor_id)
		if container == null:
			continue
		if not container.has_meta(EQUIPMENT_SLOT_META):
			continue
		if int(container.get_meta(EQUIPMENT_SLOT_META)) == int(slot_id):
			return container
	return null

func _anchor_id_for_slot(slot_id: Equippable.SlotId) -> String:
	match slot_id:
		Equippable.SlotId.Head:
			return "head"
		Equippable.SlotId.Shoulders:
			return "shoulders"
		Equippable.SlotId.Chest:
			return "chest"
		Equippable.SlotId.Hands:
			return "hands"
		Equippable.SlotId.Legs:
			return "legs"
		Equippable.SlotId.Feet:
			return "feet"
		Equippable.SlotId.Left_Hand:
			return "left_hand"
		Equippable.SlotId.Right_Hand:
			return "right_hand"
		Equippable.SlotId.Earrings:
			return "earrings"
		Equippable.SlotId.Bracelets:
			return "bracelets"
		Equippable.SlotId.Necklace:
			return "necklace"
		Equippable.SlotId.Ring1:
			return "ring1"
		Equippable.SlotId.Ring2:
			return "ring2"
		Equippable.SlotId.Charm:
			return "charm"
	return ""
