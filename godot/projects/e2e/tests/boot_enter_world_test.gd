extends E2ETestCase

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	var ok: bool = await session.start(config)
	if not ok:
		return failed(session.failure_step, session.failure_reason, session.failure_details)

	return passed({
		"zone_id": session.loaded_character.zone_id,
		"character_id": session.loaded_character.character_id,
		"entity_id": session.loaded_character.entity_id,
	})
