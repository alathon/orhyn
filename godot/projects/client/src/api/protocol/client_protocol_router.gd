class_name ClientProtocolRouter
extends RefCounted


static func route(
		channel: int,
		bytes: PackedByteArray,
		api: GameServerAPI,
		game_events: GameEventBus) -> Error:
	if bytes.is_empty():
		push_error("Dropped empty client protocol packet on channel=%d" % channel)
		return ERR_INVALID_DATA

	var message_type: int = bytes[0]
	match channel:
		GameServerAPI.CHANNEL_MOVEMENT_SNAPSHOT:
			return ClientMovementProtocolRouter.route(message_type, bytes, api)
		GameServerAPI.CHANNEL_ENTITY_LIFECYCLE:
			return ClientGameplayProtocolRouter.route(message_type, bytes, api, game_events)
		GameServerAPI.CHANNEL_ZONE_SESSION:
			return ClientZoneSessionProtocolRouter.route(message_type, bytes, game_events)
		_:
			push_error(
				"Unhandled client protocol channel=%d message_type=%d" %
				[channel, message_type]
			)
			return ERR_INVALID_DATA
