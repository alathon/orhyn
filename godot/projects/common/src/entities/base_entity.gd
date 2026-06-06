@abstract
class_name BaseEntity
extends Node

var entity_id: int = -1

@abstract
func get_rid() -> RID

@abstract
func is_alive()

@abstract
func get_body()
