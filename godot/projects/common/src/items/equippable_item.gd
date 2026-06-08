class_name EquippableItem
extends Item


static func create(
		new_template: ItemTemplate,
		new_quantity: int = 1,
		new_instance_id: String = "") -> EquippableItem:
	var item: EquippableItem = EquippableItem.new()
	item.template = new_template
	item.quantity = new_quantity
	item.instance_id = new_instance_id
	return item


func duplicate_item() -> Item:
	return EquippableItem.create(template, quantity, instance_id)
