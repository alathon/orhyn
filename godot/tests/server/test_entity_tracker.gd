extends GutTest

func test_tracks_player_by_peer_and_entity_id() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	player.entity_id = tracker.allocate_entity_id()

	tracker.track_player(42, player)

	assert_same(tracker.get_player(42), player, "Peer lookup should return the player")
	assert_same(tracker.get_player_by_entity_id(player.entity_id), player, "Entity lookup should return the player")
	assert_same(tracker.get_entity(player.entity_id), player, "Generic entity lookup should return the player")
	assert_eq(tracker.get_peer_id_for_entity(player.entity_id), 42)
	assert_true(tracker.has_player(42))
	assert_true(tracker.has_entity(player.entity_id))

func test_untrack_player_removes_player_and_entity_indexes() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	player.entity_id = tracker.allocate_entity_id()
	tracker.track_player(7, player)

	var removed: ServerPlayerEntity = tracker.untrack_player(7)

	assert_same(removed, player)
	assert_eq(tracker.get_player(7), null)
	assert_eq(tracker.get_player_by_entity_id(player.entity_id), null)
	assert_eq(tracker.get_entity(player.entity_id), null)
	assert_eq(tracker.get_peer_id_for_entity(player.entity_id), -1)

func test_untrack_entity_removes_player_indexes() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	player.entity_id = tracker.allocate_entity_id()
	tracker.track_player(7, player)

	var removed: BaseEntity = tracker.untrack_entity(player.entity_id)

	assert_same(removed, player)
	assert_eq(tracker.get_player(7), null)
	assert_eq(tracker.get_player_by_entity_id(player.entity_id), null)
	assert_eq(tracker.get_entity(player.entity_id), null)

func test_tracking_same_entity_replaces_old_peer_mapping() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var old_player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	var new_player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	old_player.entity_id = tracker.allocate_entity_id()
	new_player.entity_id = old_player.entity_id
	tracker.track_player(1, old_player)

	tracker.track_player(2, new_player)

	assert_eq(tracker.get_player(1), null)
	assert_same(tracker.get_player(2), new_player)
	assert_same(tracker.get_entity(new_player.entity_id), new_player)
	assert_eq(tracker.get_peer_id_for_entity(new_player.entity_id), 2)

func test_entity_spawn_signal_handler_tracks_server_player() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	player.peer_id = 13
	player.entity_id = tracker.allocate_entity_id()

	tracker._on_entity_spawned(player)

	assert_same(tracker.get_player(13), player)
	assert_same(tracker.get_entity(player.entity_id), player)
	assert_eq(tracker.get_peer_id_for_entity(player.entity_id), 13)

func test_entity_despawn_signal_handler_untracks_entity() -> void:
	var tracker: EntityTracker = autofree(EntityTracker.new()) as EntityTracker
	var player: ServerPlayerEntity = autofree(ServerPlayerEntity.new()) as ServerPlayerEntity
	player.peer_id = 13
	player.entity_id = tracker.allocate_entity_id()
	tracker._on_entity_spawned(player)

	tracker._on_entity_despawned(player)

	assert_eq(tracker.get_player(13), null)
	assert_eq(tracker.get_entity(player.entity_id), null)
	assert_eq(tracker.get_peer_id_for_entity(player.entity_id), -1)
