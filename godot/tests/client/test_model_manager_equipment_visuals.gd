extends GutTest


func test_applies_existing_equipment_when_base_model_loads() -> void:
	var equipment: Equipment = autofree(Equipment.new())
	var manager: ModelManager = ModelManager.new()
	manager.equipment = equipment
	add_child_autoqfree(manager)

	equipment.set_equipped(
		_make_equippable_item(_make_visual_scene("SwordVisual")),
		Equippable.SlotId.Right_Hand
	)
	manager.load_base_model(_make_model_scene())

	var anchor: Node3D = _get_right_hand_anchor(manager)
	assert_true(anchor.has_node("ItemContainer"))


func test_updates_equipment_visual_when_slot_changes() -> void:
	var equipment: Equipment = autofree(Equipment.new())
	var manager: ModelManager = ModelManager.new()
	manager.equipment = equipment
	add_child_autoqfree(manager)
	manager.load_base_model(_make_model_scene())

	equipment.set_equipped(
		_make_equippable_item(_make_visual_scene("SwordVisual")),
		Equippable.SlotId.Right_Hand
	)

	var anchor: Node3D = _get_right_hand_anchor(manager)
	var container: Node3D = anchor.get_node_or_null("ItemContainer")
	assert_true(container != null)
	assert_eq(container.get_child(0).name, "SwordVisual")

	equipment.unset_equipped(Equippable.SlotId.Right_Hand)

	assert_false(anchor.has_node("ItemContainer"))


func _make_model_scene() -> PackedScene:
	var root: Node3D = Node3D.new()
	root.name = "ModelRoot"

	var right_hand: Node3D = Node3D.new()
	right_hand.name = "RightHand"
	root.add_child(right_hand)
	right_hand.owner = root

	var anchor_points: AnchorPoints = AnchorPoints.new()
	anchor_points.name = "AnchorPoints"
	anchor_points.unique_name_in_owner = true
	anchor_points.anchor_paths = {
		"right_hand": right_hand,
	}
	root.add_child(anchor_points)
	anchor_points.owner = root

	var scene: PackedScene = PackedScene.new()
	var err: Error = scene.pack(root)
	assert_eq(err, OK)
	root.free()
	return scene


func _make_visual_scene(node_name: String) -> PackedScene:
	var visual: Node3D = Node3D.new()
	visual.name = node_name
	var scene: PackedScene = PackedScene.new()
	var err: Error = scene.pack(visual)
	assert_eq(err, OK)
	visual.free()
	return scene


func _make_equippable_item(scene: PackedScene) -> EquippableItem:
	var equippable: Equippable = Equippable.new()
	equippable.slots = [Equippable.SlotId.Right_Hand]
	equippable.scene = scene

	var template: ItemTemplate = ItemTemplate.new()
	template.equippable = equippable
	return EquippableItem.create(template, 1, "weapon_instance")


func _get_right_hand_anchor(manager: ModelManager) -> Node3D:
	return manager.get_node("ModelRoot/RightHand")
