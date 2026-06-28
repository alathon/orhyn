class_name ModelManager
extends Node3D

signal base_model_set(container_node: Node3D, scene: PackedScene)

@export var entity_root_node: BaseEntity
@export var equipment: Equipment

var _model: Node3D
var _anchor_points: AnchorPoints

func _ready() -> void:
	if equipment == null:
		push_error("ModelManager requires an Equipment reference.")
		return
	equipment.slot_changed.connect(_on_equipment_slot_changed)

func load_base_model(scene: PackedScene) -> void:
	if _model != null:
		_unload_base_model()

	_model = scene.instantiate()
	self.add_child(_model)
	var animTree: ModelAnimationTree = _model.get_node_or_null("%AnimationTree")
	if animTree:
		animTree.bind_expression_base(entity_root_node)
	_anchor_points = _model.get_node_or_null("%AnchorPoints")
	_apply_equipment_slots()
	base_model_set.emit(self, scene)

func _unload_base_model() -> void:
	_anchor_points = null
	_model.free()
	_model = null

func _on_equipment_slot_changed(
		slot_id: Equippable.SlotId,
		_previous_item: EquippableItem,
		current_item: EquippableItem) -> void:
	if _anchor_points == null:
		return
	_anchor_points.set_equipment_slot(slot_id, _get_equipment_scene(current_item))

func _apply_equipment_slots() -> void:
	if equipment == null or _anchor_points == null:
		return

	var slot_scenes: Dictionary[Equippable.SlotId, PackedScene] = {}
	for equipped_slot_id: int in equipment.get_equipped_slots():
		var slot_id: Equippable.SlotId = equipped_slot_id
		var item: EquippableItem = equipment.get_equipped(slot_id)
		var scene: PackedScene = _get_equipment_scene(item)
		if scene != null:
			slot_scenes.set(slot_id, scene)
	_anchor_points.set_equipment_slots(slot_scenes)

func _get_equipment_scene(item: EquippableItem) -> PackedScene:
	if item == null or item.template == null or item.template.equippable == null:
		return null
	return item.template.equippable.scene
