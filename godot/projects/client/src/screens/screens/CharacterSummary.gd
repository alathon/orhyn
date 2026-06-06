class_name ClientCharacterSummary
extends RefCounted

const Proto = preload("res://projects/common/src/proto/packets.gd")

var character_id: int = 0
var display_name: String = ""
var zone_id: String = ""
var model_name: String = ""
var level: int = 1


static func create(
		new_character_id: int,
		new_display_name: String,
		new_zone_id: String,
		new_model_name: String,
		new_level: int) -> ClientCharacterSummary:
	var summary: ClientCharacterSummary = ClientCharacterSummary.new()
	summary.character_id = new_character_id
	summary.display_name = new_display_name
	summary.zone_id = new_zone_id
	summary.model_name = new_model_name
	summary.level = new_level
	return summary


static func from_proto(proto: Proto.CharacterSummary) -> ClientCharacterSummary:
	if proto == null:
		return null
	return ClientCharacterSummary.create(
			int(proto.get_character_id()),
			proto.get_display_name(),
			proto.get_zone_id(),
			proto.get_model_name(),
			int(proto.get_level()))


func write_proto(proto: Proto.CharacterSummary) -> void:
	proto.set_character_id(character_id)
	proto.set_display_name(display_name)
	proto.set_zone_id(zone_id)
	proto.set_model_name(model_name)
	proto.set_level(level)
