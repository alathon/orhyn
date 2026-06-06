class_name ClientZoneContainer
extends Node

signal zone_loaded(zone_id: String, zone: Node, entities: Node)
signal zone_load_failed(reason: String)

var loaded_zone_id: String = ""
var loaded_zone: Node = null
var loaded_entities: Node = null

func load_zone(zone_id: String) -> Error:
	var normalized_zone_id: String = zone_id.strip_edges().to_lower()
	if normalized_zone_id.is_empty():
		var empty_reason: String = "Cannot load client zone with an empty zone id."
		push_error(empty_reason)
		zone_load_failed.emit(empty_reason)
		return ERR_INVALID_PARAMETER

	var scene_path: String = "res://projects/zones/zone_%s/zone_%s.tscn" % [normalized_zone_id, normalized_zone_id]
	var loaded_resource: Resource = ResourceLoader.load(scene_path)
	var zone_scene: PackedScene = loaded_resource as PackedScene
	if zone_scene == null:
		var scene_reason: String = "Failed to load client zone scene for '%s' at %s." % [normalized_zone_id, scene_path]
		push_error(scene_reason)
		zone_load_failed.emit(scene_reason)
		return ERR_FILE_NOT_FOUND

	_clear_loaded_zone()

	var zone: Node = zone_scene.instantiate()
	zone.name = "Zone_%s" % normalized_zone_id
	add_child(zone)

	var entities: Node = zone.get_node_or_null("Entities") as Node
	if entities == null:
		var entities_reason: String = "Loaded client zone '%s' does not have an Entities node." % normalized_zone_id
		push_error(entities_reason)
		zone_load_failed.emit(entities_reason)
		zone.queue_free()
		return ERR_DOES_NOT_EXIST

	loaded_zone_id = normalized_zone_id
	loaded_zone = zone
	loaded_entities = entities
	print("Loaded client zone '%s' from %s" % [loaded_zone_id, scene_path])
	zone_loaded.emit(loaded_zone_id, loaded_zone, loaded_entities)
	return OK

func _clear_loaded_zone() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	loaded_zone_id = ""
	loaded_zone = null
	loaded_entities = null
