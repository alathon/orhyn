@tool
class_name PlayerViewPreviewRig
extends Node3D

@export var walk_speed: float = 6.0
@export var run_speed: float = 14.0
@export var ground_clearance: float = 0.05
@export var mouse_sensitivity: float = 0.01
@export var player_capsule_height: float = 1.5
@export var player_capsule_radius: float = 0.35
@export var camera_offset: Vector3 = Vector3(0.0, 2.0, 0.0)
@export_range(-89.0, 89.0, 0.1, "degrees") var camera_default_pitch_degrees: float = -32.0
@export_range(0.0, 40.0, 0.1) var camera_default_distance: float = 0.0
@export_range(0.0, 40.0, 0.1) var camera_distance_min: float = 0.0
@export_range(0.25, 80.0, 0.1) var camera_distance_max: float = 14.0
@export_range(0.05, 5.0, 0.05) var camera_zoom_step: float = 0.2
@export_range(1.0, 179.0, 0.1, "degrees") var camera_fov_degrees: float = 75.0


func _ready() -> void:
	apply_camera_settings()


func apply_camera_settings() -> void:
	_apply_player_marker_settings()

	var pivot: Node3D = _get_camera_pivot()
	if pivot != null:
		pivot.position = camera_offset
		pivot.rotation.x = clampf(
				deg_to_rad(camera_default_pitch_degrees),
				deg_to_rad(-89.0),
				deg_to_rad(89.0))

	var spring_arm: SpringArm3D = _get_spring_arm()
	if spring_arm != null:
		spring_arm.spring_length = clampf(
				camera_default_distance,
				camera_distance_min,
				camera_distance_max)

	var preview_camera: Camera3D = get_preview_camera()
	if preview_camera != null:
		preview_camera.fov = camera_fov_degrees


func get_preview_camera() -> Camera3D:
	return get_node_or_null("CameraPivot/SpringArm3D/Camera") as Camera3D


func _apply_player_marker_settings() -> void:
	var marker: MeshInstance3D = get_node_or_null("Marker") as MeshInstance3D
	if marker == null:
		return

	var marker_height: float = maxf(player_capsule_height, player_capsule_radius * 2.0)
	marker.position = Vector3(0.0, marker_height * 0.5, 0.0)

	var capsule_mesh: CapsuleMesh = marker.mesh as CapsuleMesh
	if capsule_mesh == null:
		return
	capsule_mesh.radius = maxf(player_capsule_radius, 0.01)
	capsule_mesh.height = marker_height


func align_preview_camera_to(target_transform: Transform3D) -> void:
	apply_camera_settings()

	var target_basis: Basis = target_transform.basis.orthonormalized()
	var target_forward: Vector3 = -target_basis.z
	var flat_forward: Vector3 = Vector3(target_forward.x, 0.0, target_forward.z)
	if flat_forward.length_squared() <= 0.000001:
		flat_forward = Vector3.FORWARD

	global_position = Vector3.ZERO
	look_at(global_position + flat_forward.normalized(), Vector3.UP)

	var pivot: Node3D = _get_camera_pivot()
	if pivot != null:
		pivot.rotation.x = asin(clampf(target_forward.normalized().y, -1.0, 1.0))

	var preview_camera: Camera3D = get_preview_camera()
	if preview_camera == null:
		global_position = target_transform.origin
		return

	var camera_origin_from_zero: Vector3 = preview_camera.global_position
	global_position = target_transform.origin - camera_origin_from_zero


func rotate_view(screen_relative: Vector2) -> void:
	var pivot: Node3D = _get_camera_pivot()
	if pivot == null:
		return
	rotation.y -= screen_relative.x * mouse_sensitivity
	pivot.rotation.x -= screen_relative.y * mouse_sensitivity
	pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func apply_zoom_steps(steps: float) -> void:
	var spring_arm: SpringArm3D = _get_spring_arm()
	if spring_arm == null:
		return
	spring_arm.spring_length = clampf(
			spring_arm.spring_length + steps * camera_zoom_step,
			camera_distance_min,
			camera_distance_max)


func move_flat(input_vector: Vector3, distance: float) -> void:
	var movement: Vector3 = get_flat_right() * input_vector.x
	movement += get_flat_forward() * input_vector.z
	if movement.length_squared() <= 0.0:
		return
	global_position += movement.normalized() * distance


func move_fly(input_vector: Vector3, distance: float) -> void:
	var preview_camera: Camera3D = get_preview_camera()
	if preview_camera == null:
		move_flat(input_vector, distance)
		return

	var camera_basis: Basis = preview_camera.global_transform.basis
	var movement: Vector3 = camera_basis.x * input_vector.x
	movement += -camera_basis.z * input_vector.z
	movement += Vector3.UP * input_vector.y
	if movement.length_squared() <= 0.0:
		return
	global_position += movement.normalized() * distance


func snap_to_terrain(terrain: Node) -> bool:
	if terrain == null:
		return false
	var data: Variant = terrain.get("data")
	if data == null or not data.has_method("get_height"):
		return false
	var height_value: Variant = data.call("get_height", global_position)
	if typeof(height_value) != TYPE_FLOAT and typeof(height_value) != TYPE_INT:
		return false
	var height: float = float(height_value)
	if is_nan(height):
		return false
	global_position.y = height + ground_clearance
	return true


func get_flat_forward() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return forward.normalized()


func get_flat_right() -> Vector3:
	var right: Vector3 = global_transform.basis.x
	right.y = 0.0
	if right.length_squared() <= 0.000001:
		return Vector3.RIGHT
	return right.normalized()


func _get_camera_pivot() -> Node3D:
	return get_node_or_null("CameraPivot") as Node3D


func _get_spring_arm() -> SpringArm3D:
	return get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
