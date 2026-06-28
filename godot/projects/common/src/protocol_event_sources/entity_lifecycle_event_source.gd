class_name EntityLifecycleEventSource
extends RefCounted


static func publish(lifecycle: EntityLifecycleMsg, game_events: GameEventBus) -> void:
	if (
		lifecycle.entities_spawned.is_empty()
		and lifecycle.entities_despawned.is_empty()
		and lifecycle.controlled_entity_id == EntityLifecycleMsg.NO_ENTITY_ID
	):
		return

	if game_events == null:
		push_warning("Dropped entity lifecycle events because no GameEventBus is assigned.")
		return

	if lifecycle.controlled_entity_id != EntityLifecycleMsg.NO_ENTITY_ID:
		game_events.publish(ControlledEntityAssignedGameEvent.new(
			lifecycle.controlled_entity_id,
			GameEvent.Source.SERVER_AUTHORITATIVE
		))

	for despawn: EntityLifecycleMsg.DespawnRecord in lifecycle.entities_despawned:
		game_events.publish(EntityDespawnedGameEvent.new(
			despawn.entity_id,
			despawn.reason,
			GameEvent.Source.SERVER_AUTHORITATIVE
		))

	for spawn: EntityLifecycleMsg.SpawnRecord in lifecycle.entities_spawned:
		game_events.publish(EntitySpawnedGameEvent.new(
			spawn.entity_id,
			_to_game_event_entity_kind(spawn.entity_kind),
			spawn.position,
			spawn.rotation,
			spawn.equipment_revision,
			spawn.equipment_entries,
			GameEvent.Source.SERVER_AUTHORITATIVE
		))


static func _to_game_event_entity_kind(entity_kind: int) -> int:
	match entity_kind:
		EntityLifecycleMsg.EntityKind.Player:
			return EntitySpawnedGameEvent.ENTITY_KIND_PLAYER
		EntityLifecycleMsg.EntityKind.NPC:
			return EntitySpawnedGameEvent.ENTITY_KIND_NPC
		_:
			return entity_kind
