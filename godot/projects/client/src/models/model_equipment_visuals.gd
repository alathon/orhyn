# This node is meant to be added to an AnchorPoints node. This node ensures that equipment
# is attached and detached from the model anchor points when itemEquipped() is called. It is
# up to something else to know when to call that method.

# TODO: Merge into AnchorPoints. If its always there as a child, then no reason to split functionality
# over two nodes tbh.

class_name EquipmentVisuals
extends Node

@onready var _model_anchor_points: AnchorPoints = get_parent()

func itemEquipped(slot: Equippable.SlotId, template: ItemTemplate):
	_unset_slot_visual(slot)
	if template != null:
		_set_slot_visual(slot, template)
	pass

func _set_slot_visual(slot_id: Equippable.SlotId, template: ItemTemplate) -> void:
	if _model_anchor_points == null:
		push_error("Missing model or anchor points for EntityEquipmentVisuals")
		return
	if template == null or template.equippable == null:
		return
	var scene: PackedScene = template.equippable.scene
	if scene == null:
		return
	var anchor_id: String = _anchor_id_for_slot(slot_id)
	if anchor_id.is_empty():
		return
	var node: Node3D = scene.instantiate() as Node3D
	if node == null:
		push_error("Equipment scene did not instantiate a Node3D for template %s" % template.template_id)
		return
	if not _model_anchor_points.set_item(anchor_id, node):
		node.free()


func _unset_slot_visual(slot_id: Equippable.SlotId) -> void:
	if _model_anchor_points == null:
		return
	var anchor_id: String = _anchor_id_for_slot(slot_id)
	if anchor_id.is_empty():
		return
	if _model_anchor_points.has_item_container(anchor_id):
		_model_anchor_points.unset_item(anchor_id)


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
