class_name ClientZoneSessionProtocolRouter
extends RefCounted


static func route(message_type: int, bytes: PackedByteArray, game_events: GameEventBus) -> Error:
	match message_type:
		MessageHeaders.CharacterLoadedMsgHeader:
			var events: Array[GameEvent] = CharacterLoadedCodec.decode(bytes)
			if events.is_empty():
				push_warning("Dropped malformed character_loaded packet")
				return ERR_INVALID_DATA
			var event: CharacterLoadedGameEvent = events[0] as CharacterLoadedGameEvent

			print(
				"Client received character_loaded: character_id=%d entity_id=%d zone=%s" %
					[event.character_id, event.entity_id, event.zone_id]
			)
			return _publish_game_events(events, game_events)
		_:
			push_error("Unhandled zone session protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA


static func _publish_game_events(events: Array[GameEvent], game_events: GameEventBus) -> Error:
	if game_events == null:
		push_warning("Dropped zone-session events because no GameEventBus is assigned.")
		return OK

	for event: GameEvent in events:
		event.source = GameEvent.Source.SERVER_AUTHORITATIVE
		game_events.publish(event)
	return OK
