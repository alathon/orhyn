extends GutTest


class RecordingGameEventBus:
	extends GameEventBus

	var logged_events: PackedStringArray = []

	func _log_event(event: GameEvent) -> void:
		logged_events.append(event.toString())


func test_event_string_includes_metadata_and_payload_fields() -> void:
	var event: CharacterLoadedGameEvent = CharacterLoadedGameEvent.new(
		11,
		22,
		"Ada \"The Swift\"",
		"zone_forest",
		"Wizard",
		7,
		GameEvent.Source.SERVER_AUTHORITATIVE,
		91
	)
	event.local_sequence = 4

	var representation: String = event.toString()
	assert_true(representation.begins_with("CharacterLoadedGameEvent{"))
	assert_string_contains(representation, "sequence=4")
	assert_string_contains(representation, "source=SERVER_AUTHORITATIVE")
	assert_string_contains(representation, "server_tick=91")
	assert_string_contains(representation, "character_id=11")
	assert_string_contains(representation, "display_name=\"Ada \\\"The Swift\\\"\"")
	assert_eq(str(event), representation)


func test_debug_log_level_logs_published_events_without_subscribers() -> void:
	var bus: RecordingGameEventBus = autofree(RecordingGameEventBus.new()) as RecordingGameEventBus
	bus.log_level = GameEventBus.LogLevel.DEBUG
	var event: ControlledEntityAssignedGameEvent = ControlledEntityAssignedGameEvent.new(17)

	bus.publish(event)

	assert_eq(event.local_sequence, 1)
	assert_eq(bus.logged_events.size(), 1)
	assert_string_contains(bus.logged_events[0], "entity_id=17")


func test_none_log_level_does_not_log_published_events() -> void:
	var bus: RecordingGameEventBus = autofree(RecordingGameEventBus.new()) as RecordingGameEventBus
	bus.log_level = GameEventBus.LogLevel.NONE

	bus.publish(ControlledEntityAssignedGameEvent.new(17))

	assert_true(bus.logged_events.is_empty())
