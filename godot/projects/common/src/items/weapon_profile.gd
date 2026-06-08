class_name WeaponProfile
extends Resource

@export var attack_ability_id: int = 0
@export_range(0.1, 20.0, 0.1, "or_greater") var swing_delay_seconds: float = 2.0
@export_range(0.0, 5.0, 0.05, "or_greater") var lock_lead_time_seconds: float = 0.35


func has_attack_payload() -> bool:
	return attack_ability_id > 0


func get_lock_lead_time_seconds() -> float:
	return minf(lock_lead_time_seconds, swing_delay_seconds)
