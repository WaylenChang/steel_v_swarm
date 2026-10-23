class_name LocalFireState
extends RefCounted

signal reload_requested(slot: String)
signal empty_heavy

# Source client presentation accounts; BattleUnit resource settlement stays on authority.
var definitions: Dictionary = {}
var weapons: Dictionary = {}
var last_fire: Dictionary = {"light": 0.0, "heavy": 0.0}
var recoil := RecoilState.new()
var power := 0.0
var reload_factor := 1.0
var feedback: LocalCombatFeedback
var hud_timing: Dictionary = {}

func configure(metadata: Dictionary) -> void:
	hud_timing = metadata
	if hud_timing.is_empty():
		push_error("Missing original weapon HUD timing; regenerate source controls")

func hud(slot: String, level: float, now: float) -> Dictionary:
	if not definitions.has(slot) or not weapons.has(slot) or hud_timing.is_empty():
		return {}
	var definition: Dictionary = definitions[slot]
	var state: Dictionary = weapons[slot]
	var duration: Variant = state.get("reload_duration")
	if not ControlPreferences.truthy(duration):
		duration = definition.get("reload", 0)
	return {"name": definition.name, "lvl": level, "ammo": state.ammo, "mag": definition.mag,
		"reload": maxf(0, float(state.reload_end) - now) if float(state.reload_end) > 0 else 0.0,
		"reloadMax": maxf(float(hud_timing.minimumSeconds), float(duration))}

func _notice(id: String, now: float, values: Dictionary = {}) -> void:
	if feedback != null:
		feedback.show_notice(id, now, values)

func set_weapons(resolved: Dictionary, refill: bool = false) -> void:
	definitions = resolved
	for slot: String in definitions:
		if refill or not weapons.has(slot):
			weapons[slot] = {"ammo": float(definitions[slot].mag), "reload_end": 0.0}

func refill() -> void:
	set_weapons(definitions, true)

func tick(now: float) -> void:
	for slot: String in weapons:
		var state: Dictionary = weapons[slot]
		if float(state.reload_end) > 0 and now >= float(state.reload_end):
			state.ammo = float(definitions[slot].mag)
			state.reload_end = 0.0

func reload(slot: String, now: float) -> void:
	if not definitions.has(slot) or not weapons.has(slot):
		return
	var state: Dictionary = weapons[slot]
	var definition: Dictionary = definitions[slot]
	if float(state.reload_end) > 0 or float(state.ammo) >= float(definition.mag):
		return
	state.ammo = 0.0
	state.reload_duration = float(definition.reload) * reload_factor
	state.reload_end = now + float(state.reload_duration)
	reload_requested.emit(slot)
	_notice("reload_heavy" if slot == "heavy" else "reload_light", now, {"name": definition.name})

func attempt(slot: String, now: float, frame: Dictionary) -> bool:
	if frame.get("side", "").is_empty() or frame.get("dead", false) or frame.get("shop", false) or not definitions.has(slot) or not weapons.has(slot):
		return false
	if not frame.get("firing", false) or frame.get("frozen", false):
		return false
	if frame.get("casting", false):
		_notice("fire_casting", now)
		return false
	if frame.get("emp", false):
		_notice("fire_emp", now)
		return false
	var definition: Dictionary = definitions[slot]
	var state: Dictionary = weapons[slot]
	if recoil.rail_at != 0 and definition.type != "rail":
		recoil.rail_at = 0
		recoil.charge_progress = 0
	var elapsed := now - float(last_fire.get(slot, 0))
	var base_rate := float(definition.rate)
	if elapsed < (INF if base_rate == 0 else 1.0 / base_rate):
		return false
	var defense := .5 if frame.get("defending", false) and float(frame.get("shield", 0)) > 0 else 1.0
	var rate := base_rate * defense
	if defense < 1 and elapsed < 1.0 / rate:
		return false
	var weather := float(frame.get("weather_rate", 1))
	if weather < 1 and elapsed < (INF if rate * weather == 0 else 1.0 / (rate * weather)):
		return false
	_fallback(slot, state, frame)
	if float(state.reload_end) > 0:
		return false
	if float(state.ammo) <= 0:
		reload(slot, now)
		return false
	var cost := float(definition.heavyMp) if slot == "heavy" else 0.0
	if cost > 0 and power < cost:
		_notice("fire_power", now, {"name": definition.name, "cost": str(int(cost))})
		return false
	if float(recoil.settle_until.get(slot, 0)) > now:
		return false
	var profile: Dictionary = definition.get("recoil", {})
	var moving: bool = frame.get("moving", false)
	if float(profile.get("steady", 0)) > 0:
		if moving:
			_notice("steady_move", now, {"name": definition.name})
		elif definition.type != "rail" and recoil.steady_at == 0:
			_notice("steady_start", now, {"name": definition.name})
	if definition.type == "rail" and float(definition.get("charge", 0)) != 0 and recoil.rail_at == 0 and not (float(profile.get("steady", 0)) > 0 and moving):
		_notice("rail_start", now, {"name": definition.name})
	if not recoil.gate(definition, slot, now, frame.get("moving", false)):
		return false
	last_fire[slot] = now
	state.ammo = float(state.ammo) - 1
	if cost > 0:
		power = maxf(0, power - cost)
	recoil.accepted_cadence(definition, slot, now)
	if float(state.ammo) <= 0:
		reload(slot, now)
		_fallback(slot, state, frame)
	return true

func _fallback(slot: String, state: Dictionary, frame: Dictionary) -> void:
	if slot == "heavy" and frame.get("aiming", false) and float(state.ammo) <= 0:
		empty_heavy.emit()
