extends GutTest

const SWORD_PATH: String = "user://test_equipment_sword.tres"
const HELMET_PATH: String = "user://test_equipment_helmet.tres"

func test_can_equip_allows_matching_slot() -> void:
	var equipment: Equipment = autofree(Equipment.new())
	var template_path: String = _save_equippable_template(
		SWORD_PATH,
		[Equippable.SlotId.Right_Hand]
	)
	var item: EquippableItem = _load_item(template_path, "weapon_1")

	assert_true(equipment.can_equip(item, Equippable.SlotId.Right_Hand))

func test_can_equip_rejects_wrong_slot() -> void:
	var equipment: Equipment = autofree(Equipment.new())
	var template_path: String = _save_equippable_template(
		HELMET_PATH,
		[Equippable.SlotId.Head]
	)
	var item: EquippableItem = _load_item(template_path, "helmet_1")

	assert_false(equipment.can_equip(item, Equippable.SlotId.Right_Hand))

func _save_equippable_template(path: String, slots: Array[Equippable.SlotId]) -> String:
	var equippable: Equippable = Equippable.new()
	equippable.slots = slots
	var template: ItemTemplate = ItemTemplate.new()
	template.equippable = equippable
	assert_eq(ResourceSaver.save(template, path), OK)
	return path

func _load_item(template_path: String, item_instance_id: String) -> EquippableItem:
	var template: ItemTemplate = ResourceLoader.load(template_path) as ItemTemplate
	return EquippableItem.create(template, 1, item_instance_id)
