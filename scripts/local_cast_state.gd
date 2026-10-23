class_name LocalCastState
extends RefCounted

var timing: Dictionary = {}
var cooldowns: Array = [0.0, 0.0]
var charges: Variant = null
var cast_left := 0.0
var emp_left := 0.0
var until := 0.0
var shield_expand_until := 0.0
var def_jump_until := 0.0
var feedback: LocalCombatFeedback
var rejection: Dictionary = {}

func notify_rejection(now: float) -> void:
	if feedback != null and not rejection.is_empty():
		feedback.show_notice(rejection.id, now, rejection.get("values", {}))

func configure(metadata: Dictionary) -> void:
	timing = metadata
	if timing.is_empty():
		push_error("Missing original local cast timing; regenerate source controls")

func sync(summary: Dictionary, remaining: float, emp_remaining: float = 0) -> void:
	if summary.has("cooldowns"):
		cooldowns = summary.cooldowns.duplicate()
	if summary.has("charges"):
		charges = summary.charges.duplicate(true)
	cast_left = remaining
	emp_left = emp_remaining

func is_casting(now: float) -> bool:
	return cast_left > 0 or now < until

func hud(definition: Dictionary, slot: String, level: float, power: float, snow: float) -> Dictionary:
	var index := 0 if slot == "def" else 1
	var charge: Array = charges[index] if charges is Array and charges.size() > index and charges[index] is Array else [1, 1, 0]
	var cost := floorf(float(definition.mp) + .5)
	var cooldown := float(cooldowns[index])
	var full := float(definition.cd) if ControlPreferences.truthy(definition.cd) else float(timing.cooldownDefaultSeconds)
	return {"name": definition.name, "lvl": level, "cd": cooldown, "mp": cost,
		"cdMax": maxf(float(timing.hudMinimumSeconds), full * snow), "ready": cooldown <= 0 and power >= cost,
		"charges": charge[0] if charge[0] != null else 1,
		"maxCharges": charge[1] if charge[1] != null else definition.charges,
		"nextCd": charge[2] if ControlPreferences.truthy(charge[2]) else 0}

func cancel() -> void:
	until = 0
	cast_left = 0

func started(duration: float, now: float) -> void:
	if timing.is_empty():
		return
	var seconds := duration if duration != 0 else float(timing.startDefaultSeconds)
	until = now + seconds
	cast_left = seconds

func can_request(definition: Dictionary, slot: String, now: float, frame: Dictionary) -> bool:
	rejection = {}
	if timing.is_empty() or definition.is_empty() or slot not in ["def", "atk"] or frame.get("side", "").is_empty() or frame.get("dead", false) or frame.get("shop", false) or frame.get("frozen", false):
		return false
	if is_casting(now):
		rejection = {"id": "cast_busy"}
		return false
	var index := 0 if slot == "def" else 1
	var cooldown := float(cooldowns[index])
	var charge: Variant = charges[index] if charges is Array and charges.size() > index else null
	var ready := float(charge[0]) if charge is Array else 1.0 if cooldown <= 0 else 0.0
	if ready <= 0 and cooldown > 0:
		rejection = {"id": "cast_cooldown", "values": {"name": definition.name, "seconds": str(int(CssDecimal.fixed(cooldown, 0)))}}
		return false
	var cost := floorf(float(definition.mp) + .5)
	if float(frame.get("power", 0)) < cost:
		rejection = {"id": "cast_power", "values": {"name": definition.name, "cost": str(int(cost))}}
		return false
	if frame.get("emp", false):
		rejection = {"id": "cast_emp"}
		return false
	if float(definition.range) > 0 and definition.fx in ["strike", "emp"] and not frame.get("locked", false):
		rejection = {"id": "cast_lock", "values": {"name": definition.name}}
		return false
	return true

func request(definition: Dictionary, slot: String, now: float, frame: Dictionary) -> bool:
	if not can_request(definition, slot, now, frame):
		notify_rejection(now)
		return false
	var index := 0 if slot == "def" else 1
	var charge: Variant = charges[index] if charges is Array and charges.size() > index else null
	var duration := float(definition.dur) if ControlPreferences.truthy(definition.dur) else float(timing.expansionDefaultSeconds)
	if definition.get("shieldExpand", false):
		shield_expand_until = now + duration
	if definition.get("defJump", false):
		def_jump_until = now + duration
	var cooldown_seconds := float(definition.cd) if ControlPreferences.truthy(definition.cd) else float(timing.cooldownDefaultSeconds)
	var deadline := cooldown_seconds * float(frame.get("snow", 1))
	if charge is Array and float(charge[1]) > 1:
		charge[0] = maxf(0, float(charge[0]) - 1)
		cooldowns[index] = deadline if float(charge[0]) <= 0 else 0.0
	else:
		cooldowns[index] = deadline
	var cast_seconds := float(definition.castTime)
	if slot == "atk" and cast_seconds == 0:
		cast_seconds = float(timing.attackDefaultSeconds)
	if cast_seconds > 0:
		until = now + cast_seconds
		cast_left = cast_seconds
	return true
