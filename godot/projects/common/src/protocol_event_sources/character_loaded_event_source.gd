class_name CharacterLoadedEventSource
extends RefCounted


static func publish(message: CharacterLoadedMsg, game_events: GameEventBus) -> void:
	if game_events == null:
		push_warning("Dropped character loaded event because no GameEventBus is assigned.")
		return

	game_events.publish(CharacterLoadedGameEvent.new(
		message.character_id,
		message.entity_id,
		message.display_name,
		message.zone_id,
		message.model_name,
		message.level,
		GameEvent.Source.SERVER_AUTHORITATIVE
	))
