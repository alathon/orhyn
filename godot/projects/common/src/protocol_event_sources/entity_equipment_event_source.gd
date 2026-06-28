class_name EntityEquipmentEventSource
extends RefCounted


static func publish(message: EntityEquipmentChangedMsg, game_events: GameEventBus) -> void:
	if message.changes.is_empty():
		return

	if game_events == null:
		push_warning("Dropped entity equipment changed event because no GameEventBus is assigned.")
		return

	game_events.publish(EntityEquipmentChangedGameEvent.new(
		message.entity_id,
		message.equipment_revision,
		message.changes,
		GameEvent.Source.SERVER_AUTHORITATIVE
	))
