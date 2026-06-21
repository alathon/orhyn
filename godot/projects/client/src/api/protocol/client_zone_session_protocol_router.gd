class_name ClientZoneSessionProtocolRouter
extends RefCounted


static func route(message_type: int, bytes: PackedByteArray, game_events: GameEventBus) -> Error:
	match message_type:
		MessageHeaders.CharacterLoadedMsgHeader:
			var message: CharacterLoadedMsg = CharacterLoadedMsg.decode(bytes)
			if message.character_id <= 0 or message.entity_id <= 0:
				push_warning("Dropped malformed character_loaded packet")
				return ERR_INVALID_DATA

			print(
				"Client received character_loaded: character_id=%d entity_id=%d zone=%s" %
				[message.character_id, message.entity_id, message.zone_id]
			)
			CharacterLoadedEventSource.publish(message, game_events)
			return OK
		_:
			push_error("Unhandled zone session protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA
