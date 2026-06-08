class_name ModelManager
extends Node3D

signal base_model_set(container_node: Node3D, scene: PackedScene)

@export var entity_root_node: BaseEntity

var _model: Node3D

func _ready():
	# TODO: Connect to item equip/unequip events, so we can update the model accordingly.
	pass

func load_base_model(scene: PackedScene):
	if _model != null:
		_unload_base_model()

	_model = scene.instantiate()
	self.add_child(_model)
	var animTree: ModelAnimationTree = _model.get_node_or_null("%AnimationTree")
	if animTree:
		animTree.bind_expression_base(entity_root_node)
	base_model_set.emit(self, scene)
	pass

func _unload_base_model():
	_model.free()

func _on_item_equipped():
	pass

func _on_item_unequipped():
	pass
