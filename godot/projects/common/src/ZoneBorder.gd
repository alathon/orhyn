class_name ZoneBorder
extends Area3D

## The zone_id of the destination zone.
@export var target_zone_id: String = ""

## Path to the spawn point Node3D in the destination zone's world scene,
## relative to the world scene root. e.g. "ZoneBorders/FromForestSpawn"
@export var target_spawn_path: String = ""

func _ready() -> void:
	add_to_group("zone_borders")
