class_name MarineRippleState
extends RefCounted

var packets := PackedVector4Array()
var index := 0
var cooldown := 0.0
var amplitude := 0.0

func configure(rules: Dictionary) -> bool:
	var count := int(rules.get("SWAMP_RIPPLE_N", 0))
	var strength := float(rules.get("SWAMP_RIPPLE_AMP", 0))
	if count <= 0 or not is_finite(strength):
		push_error("Missing original swamp ripple declarations")
		return false
	if not packets.is_empty():
		if packets.size() != count or amplitude != strength:
			push_error("Original shared swamp ripple declarations changed within this runtime")
			return false
		return true
	packets.resize(count)
	packets.fill(Vector4(0, 0, -999, 0))
	amplitude = strength
	return true

static func hash_value(value: int) -> float:
	var word := ((value & 0xffffffff) ^ 0x5bd1e995) & 0xffffffff
	word = (((word * 0x5bd1e995) & 0xffffffff) ^ (word >> 15)) & 0xffffffff
	return float(word) / 4294967296.0

func advance(cells: Array, delta: float, now: float) -> void:
	if cells.is_empty():
		return
	# JS dt || 0 discards NaN, while positive infinity still consumes the capped frame.
	cooldown -= clampf(delta, 0, 0.25) if not is_nan(delta) else 0.0
	if cooldown > 0:
		return
	var seed_value := int(floor(now * 7.31)) & 0xffffffff
	cooldown = 2 + hash_value(seed_value ^ 0xa7c3) * 3
	var selected := int(floor(hash_value(seed_value ^ 0x3e91) * cells.size())) % cells.size()
	var cell: Dictionary = cells[selected]
	var x := (hash_value(seed_value ^ 0x17b5) - 0.5) * 10
	var z := (hash_value(seed_value ^ 0x92d4) - 0.5) * 10
	packets[index % packets.size()] = Vector4(float(cell.x) + x, float(cell.z) + z, now, amplitude)
	index += 1
