class_name ClientGameplayProtocolRouter
extends RefCounted


static func route(
		message_type: int,
		bytes: PackedByteArray,
		api: GameServerAPI,
		game_events: GameEventBus) -> Error:
	match message_type:
		MessageHeaders.EntityLifecycleMsgHeader:
			var lifecycle: EntityLifecycleMsg = EntityLifecycleMsg.decode(bytes)
			EntityLifecycleEventSource.publish(lifecycle, game_events)
			return OK
		MessageHeaders.EntityEquipmentChangedMsgHeader:
			var equipment_changed: EntityEquipmentChangedMsg = EntityEquipmentChangedMsg.decode(bytes)
			EntityEquipmentEventSource.publish(equipment_changed, game_events)
			return OK
		MessageHeaders.EntityEquipmentActionResultMsgHeader:
			var result: EntityEquipmentActionResultMsg = EntityEquipmentActionResultMsg.decode(bytes)
			api.publish_equipment_action_result(result)
			return OK
		_:
			push_error("Unhandled gameplay protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA
