class_name RemoteBody
extends Node3D

var server_tick: int = -1
var velocity: Vector3 = Vector3.ZERO
var is_on_floor: bool = false

func apply_authoritative_snapshot(snapshot: MovementSnapshotMsg.EntitySnapshot) -> void:
	server_tick = snapshot.server_tick
	velocity = snapshot.velocity
	is_on_floor = snapshot.is_on_floor
	global_transform = Transform3D(
		Basis(snapshot.rotation.normalized()),
		snapshot.position
	)

func get_rid() -> RID:
	return RID()
