class_name SourceRng
extends RefCounted

# Preserve the source's uint32 overflow for imported recipes and reference fixtures.
var state: int

func _init(seed_value: int = 0) -> void:
	state = seed_value & 0xffffffff

func next() -> float:
	state = (state + 0x6d2b79f5) & 0xffffffff
	var value := ((state ^ (state >> 15)) * (1 | state)) & 0xffffffff
	value = ((value + (((value ^ (value >> 7)) * (61 | value)) & 0xffffffff)) & 0xffffffff) ^ value
	return float((value ^ (value >> 14)) & 0xffffffff) / 4294967296.0

