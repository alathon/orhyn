class_name EquippableStats
extends Resource

@export var max_hp: int = 0
@export var max_mana: int = 0
@export var constitution: int = 0
@export var intelligence: int = 0


func get_all_stats() -> Dictionary[String, int]:
	var stats: Dictionary[String, int] = {}
	_add_stat(stats, StatKeys.CONSTITUTION, constitution)
	_add_stat(stats, StatKeys.INTELLIGENCE, intelligence)
	_add_stat(stats, StatKeys.MAX_HP, max_hp)
	_add_stat(stats, StatKeys.MAX_MANA, max_mana)
	return stats


func _add_stat(stats: Dictionary[String, int], stat_key: StringName, value: int) -> void:
	if value == 0:
		return
	stats[str(stat_key)] = value
