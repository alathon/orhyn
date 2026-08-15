class_name EntityLifecycleCodec
extends RefCounted

const MAGIC: int = MessageHeaders.EntityLifecycleMsgHeader
const HEADER_SIZE: int = 10
const SPAWN_FIXED_RECORD_SIZE: int = 40
const DESPAWN_RECORD_SIZE: int = 8
const EQUIPMENT_ENTRY_FIXED_SIZE: int = 6

const FLAG_HAS_CONTROLLED_ENTITY_ID: int = 1
const NO_ENTITY_ID: int = 0xFFFFFFFF


static func encode(
		entities_spawned: Array,
		entities_despawned: Array,
		controlled_entity_id: int = NO_ENTITY_ID) -> PackedByteArray:
	var spawned_count: int = mini(entities_spawned.size(), 0xFFFF)
	var despawned_count: int = mini(entities_despawned.size(), 0xFFFF)
	var flags: int = FLAG_HAS_CONTROLLED_ENTITY_ID \
			if controlled_entity_id != NO_ENTITY_ID else 0

	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_encoded_size(entities_spawned, spawned_count, despawned_count))

	var offset: int = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, flags)
	offset = ProtocolUtils.write_u16(bytes, offset, spawned_count)
	offset = ProtocolUtils.write_u16(bytes, offset, despawned_count)
	offset = ProtocolUtils.write_u32(bytes, offset, controlled_entity_id)

	for i in spawned_count:
		var spawn: EntitySpawnedGameEvent = entities_spawned[i]
		offset = _write_spawn_event(bytes, offset, spawn)

	for i in despawned_count:
		var despawn: EntityDespawnedGameEvent = entities_despawned[i]
		offset = _write_despawn_event(bytes, offset, despawn)

	return bytes


static func decode(bytes: PackedByteArray) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if bytes.size() < HEADER_SIZE:
		return events

	var offset: int = 0
	var magic: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return events

	var flags: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	var spawned_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var despawned_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var controlled_entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	if bool(flags & FLAG_HAS_CONTROLLED_ENTITY_ID):
		events.append(ControlledEntityAssignedGameEvent.new(controlled_entity_id))

	var spawned_events: Array[GameEvent] = []
	for i in spawned_count:
		var result: Dictionary = _read_spawn_event(bytes, offset)
		if result.is_empty():
			return []
		spawned_events.append(result.event)
		offset = result.offset

	for i in despawned_count:
		if bytes.size() < offset + DESPAWN_RECORD_SIZE:
			return []
		var result: Dictionary = _read_despawn_event(bytes, offset)
		events.append(result.event)
		offset = result.offset

	events.append_array(spawned_events)
	return events


static func _encoded_size(
		entities_spawned: Array,
		spawned_count: int,
		despawned_count: int) -> int:
	var size: int = HEADER_SIZE + despawned_count * DESPAWN_RECORD_SIZE
	for i in spawned_count:
		var spawn: EntitySpawnedGameEvent = entities_spawned[i]
		size += SPAWN_FIXED_RECORD_SIZE + _equipment_entries_encoded_size(
			spawn.equipment_entries
		)
	return size


static func _write_spawn_event(
		bytes: PackedByteArray,
		offset: int,
		event: EntitySpawnedGameEvent) -> int:
	var equipment_count: int = mini(event.equipment_entries.size(), 0xFFFF)

	offset = ProtocolUtils.write_u32(bytes, offset, event.entity_id)
	offset = ProtocolUtils.write_u8(bytes, offset, event.entity_kind)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, equipment_count)
	offset = ProtocolUtils.write_u32(bytes, offset, event.equipment_revision)
	offset = ProtocolUtils.write_float(bytes, offset, event.position.x)
	offset = ProtocolUtils.write_float(bytes, offset, event.position.y)
	offset = ProtocolUtils.write_float(bytes, offset, event.position.z)
	offset = ProtocolUtils.write_float(bytes, offset, event.rotation.x)
	offset = ProtocolUtils.write_float(bytes, offset, event.rotation.y)
	offset = ProtocolUtils.write_float(bytes, offset, event.rotation.z)
	offset = ProtocolUtils.write_float(bytes, offset, event.rotation.w)
	for i in equipment_count:
		offset = _write_equipment_entry(bytes, offset, event.equipment_entries[i])
	return offset


static func _read_spawn_event(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() < offset + SPAWN_FIXED_RECORD_SIZE:
		return {}

	var entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var entity_kind: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	offset += 1 # record flags
	var equipment_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var equipment_revision: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	var position: Vector3 = Vector3(
		ProtocolUtils.read_float(bytes, offset),
		ProtocolUtils.read_float(bytes, offset + 4),
		ProtocolUtils.read_float(bytes, offset + 8)
	)
	offset += 12

	var rotation: Quaternion = Quaternion(
		ProtocolUtils.read_float(bytes, offset),
		ProtocolUtils.read_float(bytes, offset + 4),
		ProtocolUtils.read_float(bytes, offset + 8),
		ProtocolUtils.read_float(bytes, offset + 12)
	).normalized()
	offset += 16

	var equipment_entries: Array[Dictionary] = []
	equipment_entries.resize(equipment_count)
	for i in equipment_count:
		var result: Dictionary = _read_equipment_entry(bytes, offset)
		if result.is_empty():
			return {}
		equipment_entries[i] = result.entry
		offset = result.offset

	return {
		"event": EntitySpawnedGameEvent.new(
			entity_id,
			_to_game_event_entity_kind(entity_kind),
			position,
			rotation,
			equipment_revision,
			equipment_entries
		),
		"offset": offset,
	}


static func _equipment_entries_encoded_size(entries: Variant) -> int:
	if not entries is Array:
		return 0
	var size: int = 0
	var equipment_entries: Array = entries
	var equipment_count: int = mini(equipment_entries.size(), 0xFFFF)
	for i in equipment_count:
		var entry: Variant = equipment_entries[i]
		var item_instance_bytes: PackedByteArray = str(
			ProtocolUtils.get_value(entry, "item_instance_id", "")
		).to_utf8_buffer()
		var template_bytes: PackedByteArray = str(
			ProtocolUtils.get_value(entry, "template_resource_path", "")
		).to_utf8_buffer()
		size += EQUIPMENT_ENTRY_FIXED_SIZE \
				+ mini(item_instance_bytes.size(), 0xFFFF) \
				+ mini(template_bytes.size(), 0xFFFF)
	return size


static func _write_equipment_entry(bytes: PackedByteArray, offset: int, entry: Variant) -> int:
	var item_instance_bytes: PackedByteArray = str(
		ProtocolUtils.get_value(entry, "item_instance_id", "")
	).to_utf8_buffer()
	var template_bytes: PackedByteArray = str(
		ProtocolUtils.get_value(entry, "template_resource_path", "")
	).to_utf8_buffer()
	var item_instance_size: int = mini(item_instance_bytes.size(), 0xFFFF)
	var template_size: int = mini(template_bytes.size(), 0xFFFF)

	offset = ProtocolUtils.write_u8(bytes, offset, ProtocolUtils.get_int(entry, "slot_id", 0))
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, item_instance_size)
	offset = ProtocolUtils.write_u16(bytes, offset, template_size)
	offset = _write_bytes(bytes, offset, item_instance_bytes, item_instance_size)
	return _write_bytes(bytes, offset, template_bytes, template_size)


static func _read_equipment_entry(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() < offset + EQUIPMENT_ENTRY_FIXED_SIZE:
		return {}

	var slot_id: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	offset += 1 # entry flags
	var item_instance_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var template_size: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2

	var expected_size: int = offset + item_instance_size + template_size
	if bytes.size() < expected_size:
		return {}

	var item_instance_id: String = bytes.slice(
		offset,
		offset + item_instance_size
	).get_string_from_utf8()
	offset += item_instance_size
	var template_resource_path: String = bytes.slice(
		offset,
		offset + template_size
	).get_string_from_utf8()
	offset += template_size

	return {
		"entry": {
			"slot_id": slot_id,
			"item_instance_id": item_instance_id,
			"template_resource_path": template_resource_path,
		},
		"offset": offset,
	}


static func _write_despawn_event(
		bytes: PackedByteArray,
		offset: int,
		event: EntityDespawnedGameEvent) -> int:
	offset = ProtocolUtils.write_u32(bytes, offset, event.entity_id)
	offset = ProtocolUtils.write_u8(bytes, offset, event.reason)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, 0)
	return offset


static func _read_despawn_event(bytes: PackedByteArray, offset: int) -> Dictionary:
	var entity_id: int = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	var reason: int = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	offset += 1 # record flags
	offset += 2 # reserved

	return {
		"event": EntityDespawnedGameEvent.new(entity_id, reason),
		"offset": offset,
	}


static func _to_game_event_entity_kind(entity_kind: int) -> int:
	match entity_kind:
		EntitySpawnedGameEvent.ENTITY_KIND_PLAYER:
			return EntitySpawnedGameEvent.ENTITY_KIND_PLAYER
		EntitySpawnedGameEvent.ENTITY_KIND_NPC:
			return EntitySpawnedGameEvent.ENTITY_KIND_NPC
		_:
			return entity_kind


static func _write_bytes(
		target: PackedByteArray,
		offset: int,
		source: PackedByteArray,
		source_size: int) -> int:
	for index: int in range(source_size):
		target[offset + index] = source[index]
	return offset + source_size
