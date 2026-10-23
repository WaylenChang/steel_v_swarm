class_name BodyPresentation
extends RefCounted

var body: BodyRig
var entity: Dictionary = {}
var accepted_event := -1
var presented_shot := -1
var pending_snap := true
var accumulated := 0.0
var previous := Vector3.ZERO
var previous_yaw := 0.0
var sampled := false
var carrier_motion := CarrierBodyMotion.new()
var view_motion := BodyViewMotion.new()
var report: Dictionary = {}

static func time_now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0

func configure(rig: BodyRig, source_id: String) -> void:
	body = rig
	entity = {"id": source_id}
	pending_snap = not bool(rig.profile["static"])
	body.begin_motion(source_id)

func capture_snapshot(state: Dictionary, now: float) -> void:
	var point: Variant = state.get("position")
	if not point is Vector3 or not point.is_finite() or not is_finite(now):
		push_error("Body presentation requires a finite authority snapshot")
		return
	var status: Dictionary = state.get("status", {})
	report = {"position": point, "yaw": float(state.yaw), "altitude": float(state.get("hero_y", NAN)),
		"shield": float(state.shield), "dead": bool(state.get("dead", float(state.hp) <= 0)), "defending": bool(state.get("defending", false)),
		"expanded": bool(state.get("shield_expanded", float(status.get("shield_expand_until", 0)) > now))}

func accept(event: Dictionary, received_at: float, caster: Vector3, is_self: bool, authoritative_echo: bool = false) -> bool:
	if event.get("hero_report", false):
		return false
	if not authoritative_echo and not event.get("public_pose", true):
		return false
	if body == null or not is_finite(received_at) or event.get("type") not in ["weapon_fire", "body_echo", "shot", "cast", "cast_start", "heavy_charge"]:
		return false
	var serial: Variant = event.get("body_serial")
	if not (serial is int or serial is float) or not is_finite(float(serial)) or float(serial) != floorf(serial) or int(serial) <= accepted_event:
		return false
	if event.type in ["cast", "cast_start"] and (not event.get("point") is Vector3 or not event.get("fx") is String or not event.get("slot") is String):
		return false
	if event.type == "shot" and not event.get("end") is Vector3:
		return false
	accepted_event = int(serial)
	if event.type == "body_echo" and is_self and not authoritative_echo:
		return true
	match event.type:
		"shot":
			var point: Vector3 = event.end
			entity._aimAt = {"x": point.x, "y": point.y, "z": point.z,
				"until": received_at + float(Content.balance.bodyRules.presentation.aimHold)}
			var shot_style: Dictionary = NpcShotMotion.report_style(event, body.profile.kind).style
			entity.fireFx = {"t0": received_at, "slot": "light" if shot_style.mode in ["gun", "beam"] else "heavy"}
			var gun := int(event.get("gun", 0))
			if body.profile.kind == "base":
				if not entity.has("_gunAim"):
					entity._gunAim = {}
				entity._gunAim[gun] = {"x": point.x, "y": point.y, "z": point.z,
					"until": received_at + float(Content.balance.bodyRules.presentation.baseAimHold)}
			var muzzle := body.fire_npc(received_at, gun)
			var fallback := Vector3(caster.x, body.source_root.global_position.y, caster.z)
			entity.npcMuzzle = muzzle.global_position if muzzle != null else BodyMountAim.fallback_muzzle(fallback,
				float(event.get("muzzle_ground", caster.y)), float(body.profile.dimensions.height), point,
				event.get("garrison", false), event.get("muzzle_y"))
			if not entity.has("npcShots"):
				entity.npcShots = {}
			for id: int in entity.npcShots.keys():
				if received_at - float(entity.npcShots[id].at) > float(Content.balance.bodyRules.presentation.aimHold):
					entity.npcShots.erase(id)
			entity.npcShots[int(serial)] = {"origin": entity.npcMuzzle, "at": received_at}
		"weapon_fire", "body_echo":
			var slot := "heavy" if event.get("slot") == "heavy" else "light"
			if event.type == "weapon_fire" and event.has("serial"):
				cache_hero_port(int(event.serial), slot, received_at)
			fire_local(slot, received_at)
		"heavy_charge":
			entity.heavyFx = {"phase": "charge", "t0": received_at} if event.get("on", false) else null
		"cast", "cast_start":
			if not is_self:
				var point: Vector3 = event.point
				var remote := Vector2(point.x - caster.x, point.z - caster.z).length() > float(Content.balance.bodyRules.presentation.castRemote)
				entity.castFx = {"t0": received_at, "slot": event.slot, "dir": cast_direction(event.fx, remote)}
	return true

func npc_origin(serial: int, fallback: Vector3) -> Vector3:
	var shots: Dictionary = entity.get("npcShots", {})
	if not shots.has(serial):
		return fallback
	var origin: Vector3 = shots[serial].origin
	shots.erase(serial)
	return origin if origin.is_finite() else fallback

func cache_hero_port(serial: int, slot: String, now: float) -> void:
	if not entity.has("heroPorts"):
		entity.heroPorts = {}
	for id: int in entity.heroPorts.keys():
		if now - float(entity.heroPorts[id].at) > float(Content.balance.bodyRules.presentation.aimHold):
			entity.heroPorts.erase(id)
	entity.heroPorts[serial] = {"origin": body.next_muzzle(slot), "at": now}

func hero_origin(serial: int, fallback: Vector3) -> Vector3:
	var ports: Dictionary = entity.get("heroPorts", {})
	if not ports.has(serial):
		return fallback
	var point: Vector3 = ports[serial].origin
	ports.erase(serial)
	return point if point.is_finite() else fallback

func fire_local(slot: String, now: float) -> void:
	var shot := {"t0": now, "slot": slot}
	entity.fireFx = shot
	body.fire(shot)
	if slot == "heavy":
		entity.heavyFx = {"phase": "fire", "t0": now}

func request_snap() -> void:
	pending_snap = true

func frame(delta: float, now: float, number: int, position: Vector3, yaw: float, camera: Vector3, state: Dictionary, first_person: bool, low_power: bool = false, before_pose: Callable = Callable(), view_plan: Dictionary = {}) -> bool:
	if body == null or body.source_root == null or not is_finite(delta) or delta < 0 or not is_finite(now):
		return false
	if not is_same(entity, state):
		entity.merge(state, true)
	# Native physics owns the actor transform; this explicit frame is presentation only.
	if state.get("isSelf", false) and first_person:
		previous = position
		previous_yaw = yaw
		sampled = true
		accumulated = 0
		return false
	if pending_snap:
		for key: String in ["loco", "cfx", "fireFx", "heavyFx", "castFx"]:
			entity.erase(key)
		body.begin_motion(str(entity.id))
		accumulated = 0
		sampled = false
	var stride := update_stride(Vector2(position.x - camera.x, position.z - camera.z).length_squared(), low_power)
	accumulated += delta
	var due: bool = view_plan.get("due", update_due(number, str(entity.id), stride))
	if not pending_snap and not state.get("isSelf", false) and not due:
		return false
	var step := accumulated if accumulated != 0 else delta
	accumulated = 0
	if before_pose.is_valid():
		before_pose.call(step, now)
	body.step_combat(entity, now, step)
	body.step_locomotion(entity, step, now, previous if sampled else view_plan.get("previous", position),
		previous_yaw if sampled else float(view_plan.get("previous_yaw", yaw)), {"position": position, "yaw": yaw})
	previous = position
	previous_yaw = yaw
	sampled = true
	pending_snap = false
	return true

static func update_stride(distance_squared: float, low_power: bool = false) -> int:
	var rules: Dictionary = Content.balance.bodyRules.presentation.lod
	var stride: int
	if distance_squared < float(rules.NEAR_M) * float(rules.NEAR_M):
		stride = int(rules.STRIDE_NEAR)
	elif distance_squared < float(rules.MID_M) * float(rules.MID_M):
		stride = int(rules.STRIDE_MID)
	elif distance_squared < float(rules.FAR_M) * float(rules.FAR_M):
		stride = int(rules.STRIDE_FAR)
	else:
		stride = int(rules.STRIDE_VERYFAR)
	return mini(int(rules.STRIDE_MAX_LOWPOWER), stride * 2) if low_power and stride > 1 else stride

static func update_due(number: int, source_id: String, stride: int) -> bool:
	return stride <= 1 or (number + BodyMotionState.hash_of(source_id)) % stride == 0

static func cast_direction(effect: String, remote: bool) -> int:
	var rules: Dictionary = Content.balance.bodyRules.presentation
	return int(rules.castDirection[effect][1 if remote else 0]) if rules.castDirection.has(effect) else int(rules.castDefault)
