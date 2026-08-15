class_name ClientGameplayProtocolRouter
extends RefCounted


static func route(
		message_type: int,
		bytes: PackedByteArray,
		api: GameServerAPI,
		game_events: GameEventBus) -> Error:
	match message_type:
		MessageHeaders.EntityLifecycleMsgHeader:
			return _publish_game_events(EntityLifecycleCodec.decode(bytes), game_events)
		MessageHeaders.EntityEquipmentChangedMsgHeader:
			return _publish_game_events(EntityEquipmentChangedCodec.decode(bytes), game_events)
		MessageHeaders.EntityEquipmentActionResultMsgHeader:
			var result: EntityEquipmentActionResultMsg = EntityEquipmentActionResultMsg.decode(bytes)
			api.publish_action_result(result.request_id, result.result_code)
			return OK
		_:
			push_error("Unhandled gameplay protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA


static func _publish_game_events(events: Array[GameEvent], game_events: GameEventBus) -> Error:
	if events.is_empty():
		return OK
	if game_events == null:
		push_warning("Dropped gameplay events because no GameEventBus is assigned.")
		return OK

	for event: GameEvent in events:
		event.source = GameEvent.Source.SERVER_AUTHORITATIVE
		game_events.publish(event)
	return OK
