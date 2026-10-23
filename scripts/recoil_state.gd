class_name RecoilState
extends RefCounted

var pitch := 0.0
var yaw := 0.0
var trauma := 0.0
var move_factor := 1.0
var view_pitch := 0.0
var view_yaw := 0.0
var shake := Vector3.ZERO
var burst_count: Dictionary = {}
var settle_until: Dictionary = {}
var rail_at := 0.0
var steady_at := 0.0
var charge_progress := 0.0
var echoes := BurstPresentationQueue.new()

func basis(base_yaw: float, base_pitch: float, roll: float = 0.0) -> Basis:
	return Basis(Vector3.UP, base_yaw + view_yaw) * Basis(Vector3.RIGHT, base_pitch + view_pitch) * Basis(Vector3.BACK, roll + shake.z)

func third_person_basis(base_yaw: float, base_pitch: float, roll: float = 0.0) -> Basis:
	# TPS applies recoil around the already pitched camera's local axes.
	return Basis(Vector3.UP, base_yaw) * Basis(Vector3.RIGHT, base_pitch) * Basis(Vector3.UP, view_yaw) * Basis(Vector3.RIGHT, view_pitch) * Basis(Vector3.BACK, roll + shake.z)

func active() -> bool:
	return absf(pitch) > float(Content.constants.RECOIL.END_RAD)

func movement_factor(flying: bool) -> float:
	if not active():
		return 1.0
	return 1 - (1 - move_factor) * float(Content.constants.RECOIL.AIR_F) if flying and move_factor < 1 else move_factor

func advance(delta: float, random: Callable) -> void:
	var decay := exp(-delta * float(Content.constants.RECOIL.DECAY))
	pitch *= decay
	yaw *= decay
	var rules: Dictionary = Content.balance.controls.recoil
	trauma = maxf(0, trauma - delta * float(rules.traumaDecay))
	var strength := trauma * trauma
	shake = Vector3((float(random.call()) * 2 - 1) * strength * float(rules.shakeAngle),
		(float(random.call()) * 2 - 1) * strength * float(rules.shakeAngle),
		(float(random.call()) * 2 - 1) * strength * float(rules.shakeRoll))
	view_pitch = pitch + shake.x
	view_yaw = yaw + shake.y

func gate(definition: Dictionary, slot: String, now: float, moving: bool) -> bool:
	var profile: Dictionary = definition.get("recoil", {})
	if rail_at != 0 and definition.type != "rail":
		rail_at = 0
		charge_progress = 0
	if float(settle_until.get(slot, 0)) > now:
		return false
	if float(profile.get("steady", 0)) > 0:
		if moving:
			rail_at = 0
			steady_at = 0
			charge_progress = 0
			return false
		if definition.type != "rail":
			if steady_at == 0:
				steady_at = now
			charge_progress = (now - steady_at) / float(profile.steady)
			if charge_progress < 1:
				return false
			steady_at = 0
			charge_progress = 0
	if definition.type == "rail" and float(definition.get("charge", 0)) != 0:
		if rail_at == 0:
			rail_at = now
		charge_progress = (now - rail_at) / float(definition.charge)
		if charge_progress < 1:
			return false
		rail_at = 0
		charge_progress = 0
	return true

func accepted(definition: Dictionary, slot: String, now: float, flying: bool, random: Callable, echo: bool = false) -> float:
	var profile: Dictionary = definition.get("recoil", {})
	var air := float(Content.constants.RECOIL.AIR_RECOIL_MUL) if flying else 1.0
	var climb := float(profile.get("climb", 0.011 if echo or slot == "light" else 0.033)) * air
	if not echo:
		var factor := maxf(0, 1 - pow(minf(1, maxf(0, climb) / float(Content.constants.RECOIL_CLIMB_MAX)), float(Content.constants.RECOIL.MOVE_K)))
		move_factor = minf(move_factor, factor) if active() else factor
		accepted_cadence(definition, slot, now)
		echoes.schedule(definition, now, {"slot": slot, "definition": definition})
	pitch += climb
	yaw += (float(random.call()) - 0.5) * float(Content.balance.controls.recoil.yawSpread) * float(profile.get("kick", 1)) * air
	var shake_rules: Dictionary = Content.constants.SHAKE
	trauma = minf(1, trauma + float(shake_rules.FIRE) * float(profile.get("kick", 1)) * air * (float(shake_rules.HEAVY_F) if not echo and slot == "heavy" else 1.0))
	return float(profile.get("back", 0)) * air

func accepted_cadence(definition: Dictionary, slot: String, now: float) -> void:
	var profile: Dictionary = definition.get("recoil", {})
	if float(profile.get("burst", 0)) != 0 and not definition.get("fan", false):
		burst_count[slot] = float(burst_count.get(slot, 0)) + float(definition.burst.count)
		if float(burst_count[slot]) >= float(profile.burst):
			burst_count[slot] = 0
			var duration := float(profile.get("settle", 0))
			settle_until[slot] = now + (duration if duration != 0 else 0.4)

func release_fire() -> void:
	rail_at = 0
	steady_at = 0
	charge_progress = 0
	burst_count.clear()

func clear_active() -> void:
	pitch = 0
	yaw = 0
	move_factor = 1
	view_pitch = 0
	view_yaw = 0
	shake = Vector3.ZERO
	echoes.pending.clear()

func snapshot() -> Dictionary:
	return {"pitch": pitch, "yaw": yaw, "trauma": trauma, "move_factor": move_factor,
		"view_pitch": view_pitch, "view_yaw": view_yaw, "shake": shake,
		"burst_count": burst_count.duplicate(), "settle_until": settle_until.duplicate(),
		"rail_at": rail_at, "steady_at": steady_at, "charge_progress": charge_progress}

func apply_snapshot(state: Dictionary) -> void:
	for key: String in ["pitch", "yaw", "trauma", "move_factor", "view_pitch", "view_yaw", "rail_at", "steady_at", "charge_progress"]:
		set(key, float(state.get(key, get(key))))
	shake = state.get("shake", Vector3.ZERO)
	burst_count = state.get("burst_count", {}).duplicate()
	settle_until = state.get("settle_until", {}).duplicate()
