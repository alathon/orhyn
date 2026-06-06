@tool
extends Node3D


const PREVIEW_CAMERA_NAME: String = "PreviewFreeLookCamera"
const NAVIGATION_SOURCE_GROUP: StringName = &"navigation_mesh_source_group"
const NAVIGATION_REGION_PREFIX: String = "NavigationRegion3D_Region_"
const DEFAULT_NAVIGATION_REGION_SIZE: float = 512.0
const DEFAULT_NAVIGATION_AABB_HEIGHT: float = 70.0
const DEFAULT_NAVIGATION_AABB_HORIZONTAL_BUFFER: float = 20.0
const TEMPLATE_NAVIGATION_MESH_PATH: String = ""
const LANDLOCKED_DEFAULT_REGION_MIN: Vector2i = Vector2i(0, -2)
const LANDLOCKED_DEFAULT_REGION_COUNT: Vector2i = Vector2i(2, 2)

@export var preview_camera_transform: Transform3D = Transform3D.IDENTITY
@export var navigation_region_size_override: float = DEFAULT_NAVIGATION_REGION_SIZE
@export var navigation_region_aabb_height: float = DEFAULT_NAVIGATION_AABB_HEIGHT
@export var navigation_region_aabb_horizontal_buffer: float = DEFAULT_NAVIGATION_AABB_HORIZONTAL_BUFFER
@export var navigation_region_aabb_y: float = 0.0
@export_tool_button("Capture Editor Camera", "Camera3D")
var capture_editor_camera: Callable:
	get:
		return _capture_editor_camera

@export_tool_button("Create Region Navigation Meshes", "NavigationRegion3D")
var create_region_navigation_meshes: Callable:
	get:
		return _create_region_navigation_meshes

@export_group("Landlocked Border Generator")
@export var landlocked_border_auto_create_regions: bool = true
@export var landlocked_border_region_min: Vector2i = LANDLOCKED_DEFAULT_REGION_MIN
@export var landlocked_border_region_count: Vector2i = LANDLOCKED_DEFAULT_REGION_COUNT
@export var landlocked_border_use_configured_region_bounds: bool = true
@export_range(0.25, 8.0, 0.25, "or_greater") var landlocked_border_sample_spacing: float = 1.0
@export var landlocked_border_base_height_y: float = 16.0
@export var landlocked_border_wall_height_above_base: float = 24.0
@export var landlocked_border_occlusion_margin: float = 18.0
@export var landlocked_border_hill_cap_above_base: float = 6.0
@export var landlocked_border_protected_distance: float = 64.0
@export var landlocked_border_non_playable_distance: float = 24.0
@export var landlocked_border_edge_shoulder_drop: float = 4.0
@export var landlocked_border_raise_border_floor_to_profile: bool = true
@export var landlocked_border_initialize_interior_to_base: bool = false
@export var landlocked_border_disable_navigation_in_border_profile: bool = true
@export var landlocked_border_clip_navigation_bake_to_playable_area: bool = true
@export var landlocked_border_save_after_generate: bool = true
@export_tool_button("Generate Landlocked Border", "Terrain3D")
var generate_landlocked_border: Callable:
	get:
		return _generate_landlocked_border

@export_tool_button("Save Terrain Data", "Terrain3D")
var save_terrain_data: Callable:
	get:
		return _save_terrain_data


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if get_tree().current_scene != self:
		return

	if get_node_or_null(PREVIEW_CAMERA_NAME) != null:
		return

	var camera: FreeLookCamera = FreeLookCamera.new()
	camera.name = PREVIEW_CAMERA_NAME
	camera.current = true
	add_child(camera)
	camera.global_transform = preview_camera_transform


func _capture_editor_camera() -> void:
	if not Engine.is_editor_hint():
		return

	var editor = Engine.get_singleton(&"EditorInterface")
	if editor == null:
		push_warning("EditorInterface is not available; cannot capture editor camera.")
		return

	var viewport = editor.get_editor_viewport_3d(0)
	if viewport == null:
		push_warning("Editor 3D viewport is not available; cannot capture editor camera.")
		return

	var editor_camera: Camera3D = viewport.get_camera_3d()
	if editor_camera == null:
		push_warning("Editor 3D viewport has no active camera; cannot capture editor camera.")
		return

	preview_camera_transform = editor_camera.global_transform
	notify_property_list_changed()

	if editor.has_method("mark_scene_as_unsaved"):
		editor.mark_scene_as_unsaved()


func _create_region_navigation_meshes() -> void:
	if not Engine.is_editor_hint():
		return
	create_region_navigation_meshes_now()


func create_region_navigation_meshes_now() -> void:

	var terrain: Terrain3D = _find_terrain()
	if terrain == null:
		push_warning("No Terrain3D node found; cannot create navigation regions.")
		return
	if terrain.data == null:
		push_warning("Terrain3D has no data resource; cannot create navigation regions.")
		return

	var active_region_locations: Array[Vector2i] = terrain.data.get_region_locations()
	if active_region_locations.is_empty():
		push_warning("Terrain3D has no active regions; cannot create navigation regions.")
		return
	var region_locations: Array[Vector2i] = _get_navigation_region_locations(active_region_locations)
	region_locations.sort_custom(_compare_region_locations)

	var region_size: float = _get_terrain_region_world_size(terrain)
	if region_size <= 0.0:
		push_warning("Terrain3D region size resolved to 0; cannot create navigation regions.")
		return

	terrain.add_to_group(NAVIGATION_SOURCE_GROUP, true)

	var template_mesh: NavigationMesh = _load_template_navigation_mesh()
	var navigation_clip_bounds: Rect2 = _get_navigation_clip_bounds(region_locations, region_size)
	var should_clip_navigation: bool = _is_landlocked_navigation_clip_enabled()
	if should_clip_navigation and _is_rect_empty(navigation_clip_bounds):
		push_warning("Landlocked navigation clip bounds are empty; using full region bake AABBs.")
		should_clip_navigation = false

	var created_count: int = 0
	var updated_count: int = 0

	for region_location in region_locations:
		var nav_region_name: String = _get_navigation_region_name(region_location)
		var nav_region: NavigationRegion3D = get_node_or_null(nav_region_name) as NavigationRegion3D
		if nav_region == null:
			nav_region = NavigationRegion3D.new()
			nav_region.name = nav_region_name
			add_child(nav_region, true)
			nav_region.owner = self
			created_count += 1
		else:
			updated_count += 1

		var nav_mesh: NavigationMesh = _create_navigation_mesh_from_template(template_mesh)
		var source_bounds: Rect2 = _get_region_navigation_source_bounds(
			region_location,
			region_size,
			navigation_clip_bounds,
			should_clip_navigation
		)
		nav_mesh.set_filter_baking_aabb(_get_region_baking_aabb(source_bounds))
		nav_mesh.set_filter_baking_aabb_offset(_get_region_baking_aabb_offset(source_bounds))
		nav_region.navigation_mesh = nav_mesh

	print("ZoneTemplate: Created %d and updated %d region NavigationRegion3D node(s)." % [created_count, updated_count])
	_mark_scene_unsaved()


func _generate_landlocked_border() -> void:
	if not Engine.is_editor_hint():
		return
	generate_landlocked_border_now()


func generate_landlocked_border_now() -> void:

	var terrain: Terrain3D = _find_terrain()
	if terrain == null:
		push_warning("No Terrain3D node found; cannot generate landlocked border.")
		return
	if terrain.data == null:
		push_warning("Terrain3D has no data resource; cannot generate landlocked border.")
		return

	_ensure_terrain_data_directory(terrain)
	_ensure_landlocked_regions(terrain)

	var region_locations: Array[Vector2i] = terrain.data.get_region_locations()
	if region_locations.is_empty():
		push_warning("Terrain3D has no active regions; cannot generate landlocked border.")
		return

	var region_size: float = _get_terrain_region_world_size(terrain)
	if region_size <= 0.0:
		push_warning("Terrain3D region size resolved to 0; cannot generate landlocked border.")
		return

	var bounds: Rect2 = _get_landlocked_border_bounds(region_locations, region_size)

	var sample_spacing: float = maxf(landlocked_border_sample_spacing, terrain.get_vertex_spacing())
	var changed_height_count: int = 0
	var changed_navigation_count: int = 0

	var x: float = bounds.position.x
	while x < bounds.end.x:
		var z: float = bounds.position.y
		while z < bounds.end.y:
			var position: Vector3 = Vector3(x, 0.0, z)
			var current_height: float = terrain.data.get_height(position)
			var distance_to_edge: float = _get_distance_to_bounds_edge(x, z, bounds)
			var target_height: float = _get_landlocked_border_height(current_height, distance_to_edge)
			if not is_equal_approx(current_height, target_height):
				terrain.data.set_height(position, target_height)
				changed_height_count += 1

			if landlocked_border_disable_navigation_in_border_profile and distance_to_edge <= landlocked_border_protected_distance:
				terrain.data.set_control_navigation(position, false)
				changed_navigation_count += 1

			z += sample_spacing
		x += sample_spacing

	terrain.data.calc_height_range(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true, false)
	if landlocked_border_disable_navigation_in_border_profile:
		terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL, true, false)

	if landlocked_border_save_after_generate:
		_save_terrain_data()

	print("ZoneTemplate: Generated landlocked border. Height samples changed: %d. Navigation samples disabled: %d." % [
		changed_height_count,
		changed_navigation_count
	])
	_mark_scene_unsaved()


func _save_terrain_data() -> void:
	if not Engine.is_editor_hint():
		return
	save_terrain_data_now()


func save_terrain_data_now() -> void:

	var terrain: Terrain3D = _find_terrain()
	if terrain == null:
		push_warning("No Terrain3D node found; cannot save terrain data.")
		return
	if terrain.data == null:
		push_warning("Terrain3D has no data resource; cannot save terrain data.")
		return

	var data_directory: String = _ensure_terrain_data_directory(terrain)
	if data_directory.is_empty():
		push_warning("Terrain3D data directory is empty; cannot save terrain data.")
		return

	var absolute_directory: String = ProjectSettings.globalize_path(data_directory)
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if err != OK:
		push_warning("Could not create terrain data directory %s: %s" % [data_directory, error_string(err)])
		return

	terrain.data.save_directory(data_directory)
	print("ZoneTemplate: Saved Terrain3D data to %s." % data_directory)


func _find_terrain() -> Terrain3D:
	for node in find_children("", "Terrain3D", true, false):
		var terrain: Terrain3D = node as Terrain3D
		if terrain != null:
			return terrain
	return null


func _get_terrain_region_world_size(terrain: Terrain3D) -> float:
	var terrain_region_size: float = float(terrain.get_region_size()) * terrain.get_vertex_spacing()
	if terrain_region_size > 0.0:
		return terrain_region_size
	return navigation_region_size_override if navigation_region_size_override > 0.0 else DEFAULT_NAVIGATION_REGION_SIZE


func _get_navigation_region_locations(active_region_locations: Array[Vector2i]) -> Array[Vector2i]:
	if not landlocked_border_use_configured_region_bounds:
		return active_region_locations.duplicate()

	_ensure_configured_region_bounds_cover_regions(active_region_locations)
	var region_locations: Array[Vector2i] = []
	var region_count: Vector2i = Vector2i(
		maxi(landlocked_border_region_count.x, 1),
		maxi(landlocked_border_region_count.y, 1)
	)
	for region_x in range(landlocked_border_region_min.x, landlocked_border_region_min.x + region_count.x):
		for region_y in range(landlocked_border_region_min.y, landlocked_border_region_min.y + region_count.y):
			region_locations.append(Vector2i(region_x, region_y))
	return region_locations


func _ensure_terrain_data_directory(terrain: Terrain3D) -> String:
	var data_directory: String = terrain.data_directory
	if not data_directory.is_empty():
		return data_directory

	var current_scene_path: String = scene_file_path
	if current_scene_path.is_empty():
		push_warning("Scene has not been saved; cannot derive a Terrain3D data directory.")
		return ""

	data_directory = current_scene_path.get_base_dir().path_join("terrain")
	terrain.data_directory = data_directory
	_mark_scene_unsaved()
	return data_directory


func _ensure_landlocked_regions(terrain: Terrain3D) -> void:
	if not landlocked_border_auto_create_regions:
		return
	if not terrain.data.get_region_locations().is_empty():
		return

	var region_count: Vector2i = Vector2i(
		maxi(landlocked_border_region_count.x, 1),
		maxi(landlocked_border_region_count.y, 1)
	)
	for region_x in range(landlocked_border_region_min.x, landlocked_border_region_min.x + region_count.x):
		for region_y in range(landlocked_border_region_min.y, landlocked_border_region_min.y + region_count.y):
			terrain.data.add_region_blank(Vector2i(region_x, region_y), false)

	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)


func _get_region_bounds(region_locations: Array[Vector2i], region_size: float) -> Rect2:
	var region_rect: Rect2i = _get_region_rect(region_locations)
	var position: Vector2 = Vector2(float(region_rect.position.x) * region_size, float(region_rect.position.y) * region_size)
	var end_region: Vector2i = region_rect.position + region_rect.size
	var end: Vector2 = Vector2(float(end_region.x) * region_size, float(end_region.y) * region_size)
	return Rect2(position, end - position)


func _get_configured_region_bounds(region_size: float) -> Rect2:
	var region_count: Vector2i = Vector2i(
		maxi(landlocked_border_region_count.x, 1),
		maxi(landlocked_border_region_count.y, 1)
	)
	var position: Vector2 = Vector2(
		float(landlocked_border_region_min.x) * region_size,
		float(landlocked_border_region_min.y) * region_size
	)
	var size: Vector2 = Vector2(float(region_count.x) * region_size, float(region_count.y) * region_size)
	return Rect2(position, size)


func _get_landlocked_border_bounds(region_locations: Array[Vector2i], region_size: float) -> Rect2:
	if landlocked_border_use_configured_region_bounds:
		_ensure_configured_region_bounds_cover_regions(region_locations)
		return _get_configured_region_bounds(region_size)
	return _get_region_bounds(region_locations, region_size)


func _ensure_configured_region_bounds_cover_regions(region_locations: Array[Vector2i]) -> void:
	var active_rect: Rect2i = _get_region_rect(region_locations)
	var configured_rect: Rect2i = Rect2i(landlocked_border_region_min, Vector2i(
		maxi(landlocked_border_region_count.x, 1),
		maxi(landlocked_border_region_count.y, 1)
	))

	if _region_rect_contains(configured_rect, active_rect):
		return

	push_warning("Configured landlocked border region bounds did not cover active Terrain3D regions; using active region bounds.")
	landlocked_border_region_min = active_rect.position
	landlocked_border_region_count = active_rect.size
	notify_property_list_changed()
	_mark_scene_unsaved()


func _get_region_rect(region_locations: Array[Vector2i]) -> Rect2i:
	var min_region: Vector2i = region_locations[0]
	var max_region: Vector2i = region_locations[0]
	for location in region_locations:
		min_region.x = mini(min_region.x, location.x)
		min_region.y = mini(min_region.y, location.y)
		max_region.x = maxi(max_region.x, location.x)
		max_region.y = maxi(max_region.y, location.y)

	return Rect2i(min_region, max_region - min_region + Vector2i.ONE)


func _region_rect_contains(outer: Rect2i, inner: Rect2i) -> bool:
	var outer_end: Vector2i = outer.position + outer.size
	var inner_end: Vector2i = inner.position + inner.size
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner_end.x <= outer_end.x
		and inner_end.y <= outer_end.y
	)


func _get_distance_to_bounds_edge(x: float, z: float, bounds: Rect2) -> float:
	var distance_left: float = x - bounds.position.x
	var distance_right: float = bounds.end.x - x
	var distance_top: float = z - bounds.position.y
	var distance_bottom: float = bounds.end.y - z
	return minf(minf(distance_left, distance_right), minf(distance_top, distance_bottom))


func _get_landlocked_border_height(current_height: float, distance_to_edge: float) -> float:
	var wall_peak_height: float = landlocked_border_base_height_y + landlocked_border_wall_height_above_base
	var safe_cap_height: float = minf(
		wall_peak_height - landlocked_border_occlusion_margin,
		landlocked_border_base_height_y + landlocked_border_hill_cap_above_base
	)
	var non_playable_distance: float = maxf(landlocked_border_non_playable_distance, 0.0)
	var protected_distance: float = maxf(landlocked_border_protected_distance, non_playable_distance)

	if distance_to_edge <= non_playable_distance:
		return _get_landlocked_ridge_height(distance_to_edge, non_playable_distance, wall_peak_height, safe_cap_height)

	if distance_to_edge <= protected_distance:
		var blend: float = inverse_lerp(non_playable_distance, protected_distance, distance_to_edge)
		var profile_height: float = lerpf(safe_cap_height, landlocked_border_base_height_y, _smoothstep01(blend))
		if current_height > profile_height:
			return profile_height
		if landlocked_border_raise_border_floor_to_profile:
			return maxf(current_height, profile_height)
		return current_height

	if landlocked_border_initialize_interior_to_base:
		return landlocked_border_base_height_y
	return current_height


func _get_landlocked_ridge_height(
		distance_to_edge: float,
		non_playable_distance: float,
		wall_peak_height: float,
		safe_cap_height: float) -> float:
	if non_playable_distance <= 0.0:
		return wall_peak_height

	var shoulder_height: float = maxf(
		landlocked_border_base_height_y,
		wall_peak_height - maxf(landlocked_border_edge_shoulder_drop, 0.0)
	)
	var blend: float = clampf(distance_to_edge / non_playable_distance, 0.0, 1.0)
	var crest_blend: float = 0.35
	if blend <= crest_blend:
		return lerpf(shoulder_height, wall_peak_height, _smoothstep01(blend / crest_blend))

	var inner_blend: float = (blend - crest_blend) / (1.0 - crest_blend)
	return lerpf(wall_peak_height, safe_cap_height, _smoothstep01(inner_blend))


func _smoothstep01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _load_template_navigation_mesh() -> NavigationMesh:
	if TEMPLATE_NAVIGATION_MESH_PATH.is_empty():
		return null
	var resource: Resource = load(TEMPLATE_NAVIGATION_MESH_PATH)
	var nav_mesh: NavigationMesh = resource as NavigationMesh
	if nav_mesh == null:
		push_warning("Could not load template NavigationMesh at %s; using default settings." % TEMPLATE_NAVIGATION_MESH_PATH)
	return nav_mesh


func _create_navigation_mesh_from_template(template_mesh: NavigationMesh) -> NavigationMesh:
	var nav_mesh: NavigationMesh
	if template_mesh != null:
		nav_mesh = template_mesh.duplicate(false) as NavigationMesh
		nav_mesh.clear()
	else:
		nav_mesh = NavigationMesh.new()

	nav_mesh.set_source_geometry_mode(NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN)
	nav_mesh.set_source_group_name(NAVIGATION_SOURCE_GROUP)
	return nav_mesh


func _is_landlocked_navigation_clip_enabled() -> bool:
	return landlocked_border_clip_navigation_bake_to_playable_area != false


func _get_navigation_clip_bounds(region_locations: Array[Vector2i], region_size: float) -> Rect2:
	var zone_bounds: Rect2 = _get_landlocked_border_bounds(region_locations, region_size)
	return _shrink_rect(zone_bounds, maxf(landlocked_border_protected_distance, 0.0))


func _get_region_navigation_source_bounds(
		region_location: Vector2i,
		region_size: float,
		navigation_clip_bounds: Rect2,
		should_clip_navigation: bool) -> Rect2:
	var source_bounds: Rect2 = _get_padded_region_bounds(region_location, region_size)
	if not should_clip_navigation:
		return source_bounds
	return _intersect_rects(source_bounds, navigation_clip_bounds)


func _get_padded_region_bounds(region_location: Vector2i, region_size: float) -> Rect2:
	var horizontal_padding: float = maxf(navigation_region_aabb_horizontal_buffer, 0.0) * 0.5
	var position: Vector2 = Vector2(
		float(region_location.x) * region_size - horizontal_padding,
		float(region_location.y) * region_size - horizontal_padding
	)
	var size: Vector2 = Vector2(
		region_size + horizontal_padding * 2.0,
		region_size + horizontal_padding * 2.0
	)
	return Rect2(position, size)


func _get_region_baking_aabb(source_bounds: Rect2) -> AABB:
	var pos: Vector3 = Vector3(
		0.0,
		navigation_region_aabb_y,
		0.0
	)
	var size: Vector3 = Vector3(
		maxf(source_bounds.size.x, 0.0),
		navigation_region_aabb_height if navigation_region_aabb_height > 0.0 else DEFAULT_NAVIGATION_AABB_HEIGHT,
		maxf(source_bounds.size.y, 0.0)
	)
	return AABB(pos, size)


func _get_region_baking_aabb_offset(source_bounds: Rect2) -> Vector3:
	return Vector3(
		source_bounds.position.x,
		0.0,
		source_bounds.position.y
	)


func _shrink_rect(rect: Rect2, inset: float) -> Rect2:
	var shrink_amount: float = maxf(inset, 0.0)
	var size: Vector2 = rect.size - Vector2(shrink_amount * 2.0, shrink_amount * 2.0)
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(rect.get_center(), Vector2.ZERO)
	return Rect2(rect.position + Vector2(shrink_amount, shrink_amount), size)


func _intersect_rects(a: Rect2, b: Rect2) -> Rect2:
	var start: Vector2 = Vector2(maxf(a.position.x, b.position.x), maxf(a.position.y, b.position.y))
	var end: Vector2 = Vector2(minf(a.end.x, b.end.x), minf(a.end.y, b.end.y))
	var size: Vector2 = end - start
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(start, Vector2.ZERO)
	return Rect2(start, size)


func _is_rect_empty(rect: Rect2) -> bool:
	return rect.size.x <= 0.0 or rect.size.y <= 0.0


func _get_navigation_region_name(region_location: Vector2i) -> String:
	return NAVIGATION_REGION_PREFIX + _format_region_component(region_location.x) + "_" + _format_region_component(region_location.y)


func _format_region_component(value: int) -> String:
	if value < 0:
		return "m%02d" % abs(value)
	return "%02d" % value


func _compare_region_locations(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


func _mark_scene_unsaved() -> void:
	var editor = Engine.get_singleton(&"EditorInterface")
	if editor != null and editor.has_method("mark_scene_as_unsaved"):
		editor.mark_scene_as_unsaved()
