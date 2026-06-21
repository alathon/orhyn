class_name ClientGameplayProtocolRouter
extends RefCounted


static func route(message_type: int, bytes: PackedByteArray, game_events: GameEventBus) -> Error:
	match message_type:
		MessageHeaders.EntityLifecycleMsgHeader:
			var lifecycle: EntityLifecycleMsg = EntityLifecycleMsg.decode(bytes)
			EntityLifecycleEventSource.publish(lifecycle, game_events)
			return OK
		_:
			push_error("Unhandled gameplay protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA
