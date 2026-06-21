class_name ClientMovementProtocolRouter
extends RefCounted


static func route(message_type: int, bytes: PackedByteArray, api: GameServerAPI) -> Error:
	match message_type:
		MessageHeaders.MovementSnapshotMsgHeader:
			var snapshot: MovementSnapshotMsg = MovementSnapshotMsg.decode(bytes)
			if snapshot.entities.is_empty():
				return ERR_INVALID_DATA
			api.publish_movement_snapshot(snapshot)
			return OK
		_:
			push_error("Unhandled movement protocol message_type=%d" % message_type)
			return ERR_INVALID_DATA
