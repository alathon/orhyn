class_name Item
extends RefCounted

@export var template: ItemTemplate
var quantity: int = 1
var instance_id: String = ""


static func create(new_template: ItemTemplate, new_quantity: int = 1, new_instance_id: String = "") -> Item:
	var item: Item = Item.new()
	item.template = new_template
	item.quantity = new_quantity
	item.instance_id = new_instance_id
	return item


func duplicate_item() -> Item:
	return Item.create(template, quantity, instance_id)


func is_empty() -> bool:
	return template == null or instance_id.is_empty() or quantity <= 0


func get_template_resource_path() -> String:
	if template == null:
		return ""
	return template.resource_path
