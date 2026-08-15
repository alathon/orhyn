extends E2ETestCase

func run(session: E2ESession, config: Dictionary = {}) -> Dictionary:
	if session.loaded_character == null:
		return failed("observe_character", "Session did not expose a loaded character.")
	if session.local_player() == null:
		return failed("observe_local_player", "Session did not expose a local player.")

	var expected_zone_id: String = str(
		config.get("zone_id", E2ESession.DEFAULT_ZONE_ID)
	).strip_edges().to_lower()
	if session.loaded_character.zone_id != expected_zone_id:
		return failed("observe_zone", "Session entered an unexpected zone.", {
			"expected_zone_id": expected_zone_id,
			"actual_zone_id": session.loaded_character.zone_id,
		})

	return passed({
		"zone_id": session.loaded_character.zone_id,
		"character_id": session.loaded_character.character_id,
		"entity_id": session.loaded_character.entity_id,
	})
