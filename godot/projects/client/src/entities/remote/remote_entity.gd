class_name RemoteEntity
extends BaseEntity

@onready var body: RemoteBody = %Body
@onready var interpolation_buffer: RemoteInterpolationBuffer = %RemoteInterpolationBuffer

func get_rid() -> RID:
	return body.get_rid()

func is_alive():
	return true

func get_body():
	return body

func push_movement_snapshot(snapshot: MovementSnapshotMsg.EntitySnapshot) -> void:
	interpolation_buffer.push_movement_snapshot(snapshot)

func apply_remote_transform(position: Vector3, rotation: Quaternion) -> void:
	var remote_transform = Transform3D(Basis(rotation), position)
	body.global_transform = remote_transform
	%Model.global_transform = remote_transform
