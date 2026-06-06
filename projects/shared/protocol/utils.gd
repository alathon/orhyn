class_name ProtocolUtils
extends RefCounted

static func write_u8(bytes: PackedByteArray, offset: int, value: int) -> int:
	bytes[offset] = value & 0xFF
	return offset + 1

static func write_u16(bytes: PackedByteArray, offset: int, value: int) -> int:
	bytes[offset] = value & 0xFF
	bytes[offset + 1] = (value >> 8) & 0xFF
	return offset + 2

static func write_i16(bytes: PackedByteArray, offset: int, value: int) -> int:
	return write_u16(bytes, offset, value & 0xFFFF)

static func write_u32(bytes: PackedByteArray, offset: int, value: int) -> int:
	bytes[offset] = value & 0xFF
	bytes[offset + 1] = (value >> 8) & 0xFF
	bytes[offset + 2] = (value >> 16) & 0xFF
	bytes[offset + 3] = (value >> 24) & 0xFF
	return offset + 4

static func write_i32(bytes: PackedByteArray, offset: int, value: int) -> int:
	return write_u32(bytes, offset, value & 0xFFFFFFFF)

static func write_float(bytes: PackedByteArray, offset: int, value: float) -> int:
	bytes.encode_float(offset, value)
	return offset + 4

static func read_u8(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset]

static func read_u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)

static func read_i16(bytes: PackedByteArray, offset: int) -> int:
	var value = read_u16(bytes, offset)
	return value - 0x10000 if value >= 0x8000 else value

static func read_u32(bytes: PackedByteArray, offset: int) -> int:
	return (
		bytes[offset]
		| (bytes[offset + 1] << 8)
		| (bytes[offset + 2] << 16)
		| (bytes[offset + 3] << 24)
	)

static func read_i32(bytes: PackedByteArray, offset: int) -> int:
	var value = read_u32(bytes, offset)
	return value - 0x100000000 if value >= 0x80000000 else value

static func read_float(bytes: PackedByteArray, offset: int) -> float:
	return bytes.decode_float(offset)

static func quantize_vector3(value: Vector3, scale: float, min_value: int, max_value: int) -> Vector3i:
	return Vector3i(
		clampi(roundi(value.x * scale), min_value, max_value),
		clampi(roundi(value.y * scale), min_value, max_value),
		clampi(roundi(value.z * scale), min_value, max_value)
	)

static func dequantize_vector3(value: Vector3i, scale: float) -> Vector3:
	return Vector3(value) / scale

static func quantize_vector3_i16(value: Vector3, scale: float) -> Vector3i:
	return quantize_vector3(value, scale, -0x8000, 0x7FFF)

static func quantize_vector3_i32(value: Vector3, scale: float) -> Vector3i:
	return quantize_vector3(value, scale, -0x80000000, 0x7FFFFFFF)

static func quantize_unit_float(value: float, scale: float) -> int:
	return clampi(roundi(clampf(value, -1.0, 1.0) * scale), -0x7FFF, 0x7FFF)

static func dequantize_float(value: int, scale: float) -> float:
	return float(value) / scale

static func clamp_i16(value: int) -> int:
	return clampi(value, -0x8000, 0x7FFF)

static func clamp_i32(value: int) -> int:
	return clampi(value, -0x80000000, 0x7FFFFFFF)

static func get_value(input: Variant, property: String, default_value: Variant) -> Variant:
	if input is Dictionary:
		return input.get(property, default_value)
	if input == null:
		return default_value
	var value: Variant = input.get(property)
	return default_value if value == null else value

static func get_int(input: Variant, property: String, default_value: int) -> int:
	return int(get_value(input, property, default_value))

static func get_float(input: Variant, property: String, default_value: float) -> float:
	return float(get_value(input, property, default_value))

static func get_bool(input: Variant, property: String, default_value: bool) -> bool:
	return bool(get_value(input, property, default_value))

static func get_vector3(input: Variant, property: String, default_value: Vector3) -> Vector3:
	var value: Variant = get_value(input, property, default_value)
	return value if value is Vector3 else default_value

static func get_quaternion(value: Variant) -> Quaternion:
	if value is Quaternion:
		return (value as Quaternion).normalized()
	if value is Basis:
		return (value as Basis).get_rotation_quaternion().normalized()
	return Quaternion.IDENTITY
