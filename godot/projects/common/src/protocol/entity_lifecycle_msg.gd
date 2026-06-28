class_name EntityLifecycleMsg
extends RefCounted

const MAGIC: int = MessageHeaders.EntityLifecycleMsgHeader
const HEADER_SIZE := 10
const SPAWN_FIXED_RECORD_SIZE := 40
const DESPAWN_RECORD_SIZE := 8
const EQUIPMENT_ENTRY_FIXED_SIZE := 6

const FLAG_HAS_CONTROLLED_ENTITY_ID := 1

const NO_ENTITY_ID := 0xFFFFFFFF
const DESPAWN_REASON_UNKNOWN := 0

enum EntityKind {
	Player,
	NPC
}

var controlled_entity_id = NO_ENTITY_ID
var entities_spawned: Array[SpawnRecord] = []
var entities_despawned: Array[DespawnRecord] = []

class SpawnRecord:
	var entity_id = 0
	var entity_kind: EntityKind = EntityKind.Player
	var position = Vector3.ZERO
	var rotation = Quaternion.IDENTITY
	var equipment_revision: int = 0
	var equipment_entries: Array[Dictionary] = []

class DespawnRecord:
	var entity_id = 0
	var reason = 0

static func encode(
	entities_spawned_: Array,
	entities_despawned_: Array,
	controlled_entity_id_: int = NO_ENTITY_ID
) -> PackedByteArray:
	var spawned_count = mini(entities_spawned_.size(), 0xFFFF)
	var despawned_count = mini(entities_despawned_.size(), 0xFFFF)
	var flags = FLAG_HAS_CONTROLLED_ENTITY_ID if controlled_entity_id_ != NO_ENTITY_ID else 0

	var bytes = PackedByteArray()
	bytes.resize(_encoded_size(entities_spawned_, spawned_count, despawned_count))

	var offset = 0
	offset = ProtocolUtils.write_u8(bytes, offset, MAGIC)
	offset = ProtocolUtils.write_u8(bytes, offset, flags)
	offset = ProtocolUtils.write_u16(bytes, offset, spawned_count)
	offset = ProtocolUtils.write_u16(bytes, offset, despawned_count)
	offset = ProtocolUtils.write_u32(bytes, offset, controlled_entity_id_)

	for i in spawned_count:
		offset = _write_spawn_record(bytes, offset, entities_spawned_[i])

	for i in despawned_count:
		offset = _write_despawn_record(bytes, offset, entities_despawned_[i])

	return bytes

static func decode(bytes: PackedByteArray) -> EntityLifecycleMsg:
	if bytes.size() < HEADER_SIZE:
		return empty()

	var offset = 0
	var magic = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	if magic != MAGIC:
		return empty()

	var flags = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	var spawned_count = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var despawned_count = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	var controlled_eid = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	if not bool(flags & FLAG_HAS_CONTROLLED_ENTITY_ID):
		controlled_eid = NO_ENTITY_ID

	var msg = EntityLifecycleMsg.new()
	msg.controlled_entity_id = controlled_eid
	msg.entities_spawned.resize(spawned_count)
	for i in spawned_count:
		var result = _read_spawn_record(bytes, offset)
		if result.is_empty():
			return empty()
		msg.entities_spawned[i] = result.record
		offset = result.offset

	msg.entities_despawned.resize(despawned_count)
	for i in despawned_count:
		if bytes.size() < offset + DESPAWN_RECORD_SIZE:
			return empty()
		var result = _read_despawn_record(bytes, offset)
		msg.entities_despawned[i] = result.record
		offset = result.offset

	return msg

static func encode_packet(
	entities_spawned_: Array,
	entities_despawned_: Array,
	controlled_entity_id_: int = NO_ENTITY_ID
) -> PackedByteArray:
	return encode(entities_spawned_, entities_despawned_, controlled_entity_id_)

static func decode_packet(bytes: PackedByteArray) -> EntityLifecycleMsg:
	return decode(bytes)

static func empty() -> EntityLifecycleMsg:
	return EntityLifecycleMsg.new()

static func _encoded_size(entities_spawned_: Array, spawned_count: int, despawned_count: int) -> int:
	var size: int = HEADER_SIZE + despawned_count * DESPAWN_RECORD_SIZE
	for i in spawned_count:
		size += SPAWN_FIXED_RECORD_SIZE + _equipment_entries_encoded_size(
			ProtocolUtils.get_value(entities_spawned_[i], "equipment_entries", [])
		)
	return size

static func _write_spawn_record(bytes: PackedByteArray, offset: int, entity: Variant) -> int:
	var position = ProtocolUtils.get_vector3(entity, "position", Vector3.ZERO)
	var rotation = ProtocolUtils.get_quaternion(
		ProtocolUtils.get_value(entity, "rotation", Quaternion.IDENTITY)
	)
	var equipment_entries: Array = ProtocolUtils.get_value(entity, "equipment_entries", [])
	var equipment_count: int = mini(equipment_entries.size(), 0xFFFF)

	offset = ProtocolUtils.write_u32(bytes, offset, ProtocolUtils.get_int(entity, "entity_id", 0))
	offset = ProtocolUtils.write_u8(
		bytes,
		offset,
		ProtocolUtils.get_int(entity, "entity_kind", EntityKind.Player)
	)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, equipment_count)
	offset = ProtocolUtils.write_u32(bytes, offset, ProtocolUtils.get_int(entity, "equipment_revision", 0))
	offset = ProtocolUtils.write_float(bytes, offset, position.x)
	offset = ProtocolUtils.write_float(bytes, offset, position.y)
	offset = ProtocolUtils.write_float(bytes, offset, position.z)
	offset = ProtocolUtils.write_float(bytes, offset, rotation.x)
	offset = ProtocolUtils.write_float(bytes, offset, rotation.y)
	offset = ProtocolUtils.write_float(bytes, offset, rotation.z)
	offset = ProtocolUtils.write_float(bytes, offset, rotation.w)
	for i in equipment_count:
		offset = _write_equipment_entry(bytes, offset, equipment_entries[i])
	return offset

static func _read_spawn_record(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() < offset + SPAWN_FIXED_RECORD_SIZE:
		return {}

	var record = SpawnRecord.new()
	record.entity_id = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	record.entity_kind = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	offset += 1 # record flags
	var equipment_count: int = ProtocolUtils.read_u16(bytes, offset)
	offset += 2
	record.equipment_revision = ProtocolUtils.read_u32(bytes, offset)
	offset += 4

	record.position = Vector3(
		ProtocolUtils.read_float(bytes, offset),
		ProtocolUtils.read_float(bytes, offset + 4),
		ProtocolUtils.read_float(bytes, offset + 8)
	)
	offset += 12

	record.rotation = Quaternion(
		ProtocolUtils.read_float(bytes, offset),
		ProtocolUtils.read_float(bytes, offset + 4),
		ProtocolUtils.read_float(bytes, offset + 8),
		ProtocolUtils.read_float(bytes, offset + 12)
	).normalized()
	offset += 16

	record.equipment_entries.resize(equipment_count)
	for i in equipment_count:
		var result: Dictionary = _read_equipment_entry(bytes, offset)
		if result.is_empty():
			return {}
		record.equipment_entries[i] = result.entry
		offset = result.offset

	return {
		"record": record,
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

	var item_instance_id: String = bytes.slice(offset, offset + item_instance_size).get_string_from_utf8()
	offset += item_instance_size
	var template_resource_path: String = bytes.slice(offset, offset + template_size).get_string_from_utf8()
	offset += template_size

	return {
		"entry": {
			"slot_id": slot_id,
			"item_instance_id": item_instance_id,
			"template_resource_path": template_resource_path,
		},
		"offset": offset,
	}

static func _write_bytes(
		target: PackedByteArray,
		offset: int,
		source: PackedByteArray,
		source_size: int) -> int:
	for index: int in range(source_size):
		target[offset + index] = source[index]
	return offset + source_size

static func _write_despawn_record(bytes: PackedByteArray, offset: int, entity: Variant) -> int:
	offset = ProtocolUtils.write_u32(bytes, offset, ProtocolUtils.get_int(entity, "entity_id", 0))
	offset = ProtocolUtils.write_u8(
		bytes,
		offset,
		ProtocolUtils.get_int(entity, "reason", DESPAWN_REASON_UNKNOWN)
	)
	offset = ProtocolUtils.write_u8(bytes, offset, 0)
	offset = ProtocolUtils.write_u16(bytes, offset, 0)
	return offset

static func _read_despawn_record(bytes: PackedByteArray, offset: int) -> Dictionary:
	var record = DespawnRecord.new()
	record.entity_id = ProtocolUtils.read_u32(bytes, offset)
	offset += 4
	record.reason = ProtocolUtils.read_u8(bytes, offset)
	offset += 1
	offset += 1 # record flags
	offset += 2 # reserved

	return {
		"record": record,
		"offset": offset,
	}
