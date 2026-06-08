class_name ItemTemplate
extends Resource

@export var template_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export_range(1, 9999, 1) var max_stack: int = 1

@export var equippable: Equippable

# TODO: @export var consumable: Consumable etc

func is_stackable() -> bool:
	return max_stack > 1

func get_template_id() -> StringName:
	if not template_id.is_empty():
		return template_id
	if resource_path.is_empty():
		return &""
	return StringName(resource_path.get_file().get_basename())
