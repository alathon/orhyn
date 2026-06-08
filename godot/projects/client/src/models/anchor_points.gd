class_name AnchorPoints
extends Node

@export var anchor_paths: Dictionary[String, Node] = {}

func get_anchor(anchor_id: String) -> Node3D:
	var anchor = anchor_paths.get(anchor_id, null)
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
	var anchor = get_anchor(anchor_id)
	if anchor == null:
		return null
	return anchor.get_node_or_null("ItemContainer") as Node3D

func set_item(anchor_id: String, item: Node3D) -> bool:
	if item.get_parent() != null:
		push_error("Cannot do AnchorPoints.set_item on a node that already has a parent")
		return false

	var anchor = get_anchor(anchor_id)
	if anchor == null:
		push_error("No anchor with the id %s" % anchor_id)
		return false
	
	if anchor.has_node("ItemContainer"):
		if not unset_item(anchor_id):
			push_error("Unable to unset existing ItemContainer for anchor %s" % anchor_id)
			return false

	var itemContainer: Node3D = Node3D.new()
	itemContainer.name = "ItemContainer"
	
	itemContainer.add_child(item)
	anchor.add_child(itemContainer)
	itemContainer.position = Vector3.ZERO
	itemContainer.rotation_degrees = Vector3.ZERO
	return true

func unset_item(anchor_id: String) -> bool:
	var anchor = get_anchor(anchor_id)
	if anchor == null:
		push_error("No anchor with the id %s" % anchor_id)
		return false

	var container: Node3D = anchor.get_node_or_null("ItemContainer") as Node3D
	if container == null:
		push_error("No item to unset for anchor_id %s" % anchor_id)
		return false

	container.free()
	return true

func move_item(from_anchor_id: String, to_anchor_id: String) -> bool:
	var to_anchor = get_anchor(to_anchor_id)
	if to_anchor == null:
		return false
	
	if to_anchor.has_node("ItemContainer"):
		return false
	
	var from_anchor = get_anchor(from_anchor_id)
	if from_anchor == null:
		return false
	
	var item_container: Node3D = from_anchor.get_node_or_null("ItemContainer") as Node3D
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
