class_name GameEvent
extends RefCounted

const TYPE_NONE: int = 0
const TYPE_CONTROLLED_ENTITY_ASSIGNED: int = 1
const TYPE_ENTITY_SPAWNED: int = 2
const TYPE_ENTITY_DESPAWNED: int = 3
const TYPE_CHARACTER_LOADED: int = 4
const TYPE_ENTITY_EQUIPMENT_CHANGED: int = 5
const TYPE_COUNT: int = 6

enum Source {
	UNKNOWN,
	SERVER_AUTHORITATIVE,
	CLIENT_PREDICTED,
	CLIENT_LOCAL,
}

var type: int = TYPE_NONE
var source: int = Source.UNKNOWN
var local_sequence: int = 0
var server_tick: int = -1


func _init(new_type: int = TYPE_NONE, new_source: int = Source.UNKNOWN, new_server_tick: int = -1) -> void:
	type = new_type
	source = new_source
	server_tick = new_server_tick


func toString() -> String:
	var fields: PackedStringArray = PackedStringArray([
		"sequence=%d" % local_sequence,
		"source=%s" % _source_name(source),
		"server_tick=%s" % (str(server_tick) if server_tick >= 0 else "unset"),
	])

	for property: Dictionary in get_property_list():
		var usage: int = int(property.get("usage", 0))
		if not bool(usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue

		var property_name: StringName = property.get("name", &"")
		if property_name == &"type" \
				or property_name == &"source" \
				or property_name == &"local_sequence" \
				or property_name == &"server_tick":
			continue
		fields.append("%s=%s" % [property_name, _format_value(get(property_name))])

	return "%s{%s}" % [_event_class_name(), ", ".join(fields)]


func _to_string() -> String:
	return toString()


func _event_class_name() -> String:
	var event_script: Script = get_script()
	if event_script == null:
		return "GameEvent"
	var global_name: String = event_script.get_global_name()
	return global_name if not global_name.is_empty() else "GameEvent"


static func _source_name(event_source: int) -> String:
	match event_source:
		Source.UNKNOWN:
			return "UNKNOWN"
		Source.SERVER_AUTHORITATIVE:
			return "SERVER_AUTHORITATIVE"
		Source.CLIENT_PREDICTED:
			return "CLIENT_PREDICTED"
		Source.CLIENT_LOCAL:
			return "CLIENT_LOCAL"
		_:
			return "INVALID(%d)" % event_source


static func _format_value(value: Variant) -> String:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		return "\"%s\"" % str(value).c_escape()
	return str(value)
