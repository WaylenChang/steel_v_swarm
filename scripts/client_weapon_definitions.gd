class_name ClientWeaponDefinitions
extends RefCounted

var character := ""
var levels: Array = []
var own: Dictionary = {}
var others: Dictionary = {}
var profile: BalanceDefinitions

func _resolve(pilot: String, slot: String, level: float = 1) -> Dictionary:
	return profile.weapon(pilot, slot, level) if profile != null else Content.weapon(pilot, slot, level)

func own_weapon(pilot: String, slot: String, light_level: float, heavy_level: float) -> Dictionary:
	var incoming := [light_level, heavy_level]
	if character != pilot or levels != incoming:
		character = pilot
		levels = incoming
		own = {"light": _resolve(pilot, "light", light_level), "heavy": _resolve(pilot, "heavy", heavy_level)}
	return own[slot]

func other_weapon(pilot: String, slot: String) -> Dictionary:
	var key := pilot + ":" + slot
	if not others.has(key):
		others[key] = _resolve(pilot, slot)
	return others[key]
