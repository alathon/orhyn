class_name ClientZoneContainer
extends Node

signal zone_loaded(zone_id: String, zone: Node, entities: Node)

var loaded_zone_id: String = ""
var loaded_zone: Node = null
var loaded_entities: Node = null

func load_zone(zone_id: String) -> void:
	var normalized_zone_id: String = zone_id.strip_edges().to_lower()
	if normalized_zone_id.is_empty():
		push_error("Cannot load client zone with an empty zone id.")
		return

	var scene_path: String = "res://projects/zones/zone_%s/zone_%s.tscn" % [normalized_zone_id, normalized_zone_id]
	var loaded_resource: Resource = ResourceLoader.load(scene_path)
	var zone_scene: PackedScene = loaded_resource as PackedScene
	if zone_scene == null:
		push_error("Failed to load client zone scene for '%s' at %s." % [normalized_zone_id, scene_path])
		return

	_clear_loaded_zone()

	var zone: Node = zone_scene.instantiate()
	zone.name = "Zone_%s" % normalized_zone_id
	add_child(zone)

	var entities: Node = zone.get_node_or_null("Entities") as Node
	if entities == null:
		push_error("Loaded client zone '%s' does not have an Entities node." % normalized_zone_id)
		zone.queue_free()
		return

	loaded_zone_id = normalized_zone_id
	loaded_zone = zone
	loaded_entities = entities
	print("Loaded client zone '%s' from %s" % [loaded_zone_id, scene_path])
	zone_loaded.emit(loaded_zone_id, loaded_zone, loaded_entities)

func _clear_loaded_zone() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	loaded_zone_id = ""
	loaded_zone = null
	loaded_entities = null
