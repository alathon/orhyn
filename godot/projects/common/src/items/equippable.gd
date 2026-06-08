class_name Equippable
extends Resource

enum SlotId { 
	Head,
	Shoulders,
	Chest,
	Hands,
	Legs,
	Feet,
	Earrings,
	Bracelets,
	Necklace,
	Ring1,
	Ring2,
	Charm,
	Left_Hand,
	Right_Hand
}

@export var slots: Array[SlotId]
@export var scene: PackedScene
@export var unique: bool = false
@export var stats: EquippableStats
@export var weapon_profile: WeaponProfile
