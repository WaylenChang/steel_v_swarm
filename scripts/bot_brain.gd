class_name BotBrain
extends RefCounted

var simulation: BattleSimulation
var unit: BattleUnit
var difficulty: Dictionary
var tactics: Dictionary
var role := ""
var role_character := ""
var lane := 0
var state := "PUSH"
var progress := 0.0
var cruise_altitude := 0.0
var jitter := Vector2.ZERO
var op_at: Dictionary = {}
var op_next := 0.0
var target_id := 0
var aim_at := 0.0
var wanted_yaw := NAN
var wanted_pitch := 0.0
var stuck_time := 0.0
var skirt_until := 0.0
var skirt_side := 1.0
var rally_point := Vector2(INF, INF)
var rally_progress := 0.0

func configure(owner: BattleSimulation, pilot: BattleUnit, key: String) -> void:
	simulation = owner
	unit = pilot
	difficulty = Content.constants.BOT_DIFF.get(key, Content.constants.BOT_DIFF[Content.constants.DEFAULT_BOT_DIFF])
	tactics = Content.constants.BOT_TACTIC
	lane = unit.lane % simulation.world.lane_points.size()
	var rules: Dictionary = Content.balance.bot
	cruise_altitude = float(rules.cruise.min) + simulation.rng.next() * (float(rules.cruise.max) - float(rules.cruise.min))
	# Source construction draws north-positive jitter; only the native boundary mirrors Z.
	jitter = Vector2((simulation.rng.next() - 0.5) * float(rules.laneJitter), -(simulation.rng.next() - 0.5) * float(rules.laneJitter))

func op(kind: String) -> bool:
	var now := simulation.clock
	if now < op_next or now < float(op_at.get(kind, 0)):
		return false
	op_at[kind] = now + float(difficulty.gap) * float(Content.constants.BOT_OPS.get(kind, 1))
	op_next = now + float(difficulty.gap)
	return true

func light_weapon() -> Dictionary:
	return simulation.weapon_definition(unit.character, "light", unit.combat_level("light"))

func heavy_weapon() -> Dictionary:
	return simulation.weapon_definition(unit.character, "heavy", unit.combat_level("heavy"))

func heavy_ready(definition: Dictionary = {}) -> bool:
	if not difficulty.heavy:
		return false
	if definition.is_empty():
		definition = heavy_weapon()
	simulation._refill_if_done(unit, "heavy", definition)
	return float(unit.reload_at.get("heavy", 0)) <= simulation.clock and (not unit.ammo.has("heavy") or float(unit.ammo.heavy) > 0 or unit.has_status("no_reload_until", simulation.clock)) and unit.power >= float(definition.heavyMp)

func target_weapon() -> Dictionary:
	var definition := heavy_weapon() if unit.input_state.get("aim", false) else {}
	return definition if not definition.is_empty() and heavy_ready(definition) else light_weapon()

func pulling() -> bool:
	return state in ["RETREAT", "RALLY"]

func in_fight() -> bool:
	return simulation.clock - unit.damaged_at < float(Content.constants.VITALS.OOC_S)

func flying() -> bool:
	return unit.kind == "drone" or unit.kind == "morph" and simulation._missile_target_altitude(unit) > float(Content.constants.FLY_Y)

func enraged() -> bool:
	return unit.special.get("boss", false) and int(unit.special.get("boss_segment", 0)) >= 3

func home() -> Vector2:
	var hold: Dictionary = simulation.bot_holds.get(unit.peer_id, {})
	if not hold.is_empty():
		return Vector2(hold.x, hold.z)
	var point: Vector3 = simulation.world.bases[unit.side]
	return Vector2(point.x, point.z)

func stationary() -> bool:
	return state == "RALLY" and not in_fight() or (state == "RETREAT" or simulation.bot_holds.has(unit.peer_id)) and point().distance_to(home()) < 30

func point() -> Vector2:
	return Vector2(unit.position.x, unit.position.z)

func bearing(target: Vector2) -> float:
	var offset := target - point()
	return BotRules.wrap_pi(atan2(-offset.x, -offset.y) - unit.yaw)

func recent_damage() -> float:
	var amount := 0.0
	for record: Dictionary in unit.threat.values():
		if record.kind not in ["tower", "base"]:
			amount += float(record.value) * BotRules.threat_decay(simulation.clock - float(record.at), tactics)
	return amount

func control_factor() -> float:
	if unit.has_status("freeze_until", simulation.clock) or unit.has_status("stun_until", simulation.clock):
		return 0.0
	var factor := float(unit.status.get("slow_factor", 0.6)) if unit.has_status("slow_until", simulation.clock) else 1.0
	return factor * (0.5 if unit.has_status("confuse_until", simulation.clock) else 1.0)

func speed(direction: Vector2 = Vector2.ZERO) -> float:
	var value := simulation.hero_speed(unit.character, flying())
	value *= control_factor() * (1 - float(Content.constants.HIGH_SUP.SPEED) * simulation._suppression(unit))
	if enraged():
		value *= float(Content.constants.BOSS.ENRAGE_SPD_F)
	if flying():
		if not simulation.weather_dynamics.is_empty():
			value *= WeatherRules.wind_speed(direction.x, direction.y, simulation.weather_dynamics.windDir, simulation.weather_dynamics.wind)
	else:
		value *= WeatherRules.ground_speed(simulation.weather_surface)
	return value

func pull_want(fraction: float, shield_fraction: float) -> String:
	if unit.special.get("boss", false):
		if enraged():
			return ""
		if fraction < float(tactics.BASE_HP) or state == "RETREAT":
			return "RETREAT"
		return "RALLY" if shield_fraction < float(tactics.PULL_SP) and in_fight() and shield_fraction <= 0.15 else ""
	if not difficulty.tactic:
		return "RETREAT" if fraction < float(tactics.PULL_HP) else ""
	if fraction < float(tactics.BASE_HP) or state == "RETREAT":
		return "RETREAT"
	if shield_fraction >= float(tactics.PULL_SP) or not in_fight():
		return ""
	if fraction < float(tactics.PULL_HP) or shield_fraction <= 0.20 or difficulty.elite and recent_damage() >= float(tactics.PULL_SP) * unit.max_shield:
		return "RALLY"
	return ""

func resolve_role() -> void:
	if not difficulty.tactic or role_character == unit.character:
		return
	role_character = unit.character
	var profile := simulation.bot_profile(role_character)
	role = profile.role
	tactics = profile.tactic

func update_aiming() -> void:
	var alert: Dictionary = unit.bot_alert
	var reactive: bool = difficulty.tactic and not alert.is_empty() and simulation.clock - float(alert.at) <= float(Content.constants.BOT_VIEW.ALERT_S) and target_id == 0 and acquire() == null
	var want: bool = stationary() and (float(difficulty.scopeSearchDeg) > 0 or difficulty.tactic) or heavy_ready() or reactive
	if want != bool(unit.input_state.get("aim", false)) and op("weapon"):
		simulation._bot_aim(unit, want)

func missiles_targeting_pilot() -> bool:
	for missile: Dictionary in simulation.missiles:
		var target: BattleUnit = simulation.units.get(int(missile.target))
		if target != null and target.peer_id == unit.peer_id and target.is_hero():
			return true
	return false

func update_defending(target: BattleUnit) -> void:
	if not difficulty.defend or not unit.alive() or unit.shield <= 0 or not unit.cast_state.is_empty():
		if unit.defending:
			simulation._bot_defend(unit, false)
		return
	var want := state == "RETREAT" and in_fight()
	if difficulty.tactic:
		want = pulling() and in_fight() or state == "ENGAGE" and float(unit.reload_at.get("light", 0)) > simulation.clock and not heavy_ready() or in_fight() and (recent_damage() >= unit.max_shield * 0.35 or missiles_targeting_pilot()) or flying() and in_fight()
		if difficulty.elite and target != null and float(unit.reload_at.get("light", 0)) <= simulation.clock and simulation.clock >= aim_at:
			want = false
	if want or unit.defending:
		if target != null:
			face(Vector2(target.position.x, target.position.z))
		elif not unit.bot_alert.is_empty():
			face(unit.bot_alert.point)
	if want != unit.defending and op("defend"):
		simulation._bot_defend(unit, want)

func target() -> BattleUnit:
	var held: BattleUnit = simulation.units.get(target_id)
	if held != null and (not held.alive() or held.side == unit.side or held.special.get("neutral", false) or held.special.get("garrison", false) or held.has_status("stealth_until", simulation.clock) or simulation._planar_distance(unit.position, held.position) > float(target_weapon().range) * 1.15):
		held = null
		target_id = 0
	if not op("scan"):
		return held
	var found := acquire()
	var id := found.entity_id if found != null else 0
	if id != target_id:
		target_id = id
		if found != null:
			aim_at = simulation.clock + float(difficulty.react)
	return found

func acquire() -> BattleUnit:
	var definition := target_weapon()
	var hold: Dictionary = simulation.bot_holds.get(unit.peer_id, {})
	var candidates: Array = []
	for other: BattleUnit in simulation.units.values():
		if other.side == unit.side or other.special.get("neutral", false) or other.special.get("garrison", false) or simulation.siege_locked(other) or not other.alive() or other.has_status("stealth_until", simulation.clock):
			continue
		var offset := Vector2(other.position.x - unit.position.x, other.position.z - unit.position.z)
		var height := simulation._missile_target_altitude(unit) - (simulation._missile_target_altitude(other) if other.is_hero() else 0.0)
		var distance := sqrt(offset.length_squared() + height * height)
		var in_zone := not hold.is_empty() and Vector2(other.position.x - float(hold.x), other.position.z - float(hold.z)).length() <= float(hold.r) * 1.1
		var reach := maxf(float(definition.range) * 1.15, float(hold.r) * 1.1) if in_zone else float(definition.range) * 1.15
		if distance > reach or not in_zone and absf(bearing(Vector2(other.position.x, other.position.z))) > BotRules.fov_half(unit.kind):
			continue
		if unit.input_state.get("aim", false) and not in_zone:
			var altitude := simulation._missile_target_altitude(other) if other.is_hero() or other.kind == "heli" else 8.0 if other.kind in ["tower", "base"] else 0.0
			var target_pitch := atan2(altitude - simulation._missile_target_altitude(unit) - float(Content.constants.LOS.EYE_M), offset.length())
			if absf(BotRules.wrap_pi(target_pitch - unit.pitch)) > BotRules.fov_half(unit.kind, true):
				continue
		if float(simulation.vision_until.get(unit.side, 0)) <= simulation.clock and not simulation.visible_to_side(other, unit.side):
			continue
		distance *= float(tactics.PRIO_HERO) if other.is_hero() else float(tactics.PRIO_STRUCT) if other.kind in ["tower", "base"] else 1.8 if other.side in ["GUER", "MILI"] else 1.0
		distance /= CombatMath.vs_multiplier(definition, other.kind)
		candidates.append({"unit": other, "distance": distance})
	if difficulty.tactic:
		prioritize(candidates, definition)
	var best: BattleUnit
	var best_distance := INF
	for candidate: Dictionary in candidates:
		if float(candidate.distance) < best_distance:
			best = candidate.unit
			best_distance = candidate.distance
	return best

func prioritize(candidates: Array, definition: Dictionary) -> void:
	var maximum_threat := 0.0
	var maximum_output := 0.0
	for candidate: Dictionary in candidates:
		var other: BattleUnit = candidate.unit
		var record: Dictionary = unit.threat.get(BotRules.threat_key(other), {})
		candidate.threat = float(record.value) * BotRules.threat_decay(simulation.clock - float(record.at), tactics) if not record.is_empty() else 0.0
		candidate.output = 0.0 if other.kind in ["tower", "base"] else other.damage_out
		var health := other.hp + other.shield
		candidate.execution = BotRules.execution_weight(health, (other.max_hp if other.max_hp else health) + other.max_shield, BotRules.salvo(definition, other.kind, tactics) if difficulty.elite else 0.0)
		maximum_threat = maxf(maximum_threat, candidate.threat)
		maximum_output = maxf(maximum_output, candidate.output)
	for candidate: Dictionary in candidates:
		candidate.distance /= BotRules.priority(float(candidate.threat) / maximum_threat if maximum_threat > 0 else 0.0,
			float(candidate.output) / maximum_output if maximum_output > 0 else 0.0, candidate.execution, tactics)

func fire(target: BattleUnit, slot: String, mode: String = "direct") -> bool:
	if simulation.clock < aim_at or simulation.rng.next() < float(difficulty.aimErr):
		return false
	return simulation._bot_fire(unit, target, slot, mode)

func ready(slot: String) -> Dictionary:
	if not unit.cast_state.is_empty() or unit.has_status("cast_lock_until", simulation.clock) or float(unit.cooldowns.get(slot, 0)) > simulation.clock:
		return {}
	var definition := simulation.ability_definition(unit.character, slot, unit.combat_level(slot))
	return definition if unit.power >= float(definition.mp) else {}

func cast_support(fraction: float) -> void:
	if not difficulty.ability:
		return
	for slot: String in ["def", "atk"]:
		var definition := ready(slot)
		if definition.is_empty():
			continue
		var hurt := fraction < float(tactics.CAST_HURT)
		var low_shield := unit.max_shield > 0 and unit.shield / unit.max_shield < 0.5 and in_fight()
		var full_charges: bool = difficulty.elite and int(definition.charges) > 1 and in_fight() and simulation._ready_charges(unit, slot, definition) >= int(definition.charges)
		var defensive: bool = definition.fx in ["heal", "reflect", "phaseshift", "fog", "cube"] or definition.spRestore or definition.shieldDefBoost or definition.shieldExpand or definition.spRegenHit
		if defensive and (hurt or low_shield or full_charges) or definition.fx == "buff" and definition.mul is Dictionary and definition.mul.get("dmgTaken", 0) and (hurt or low_shield or full_charges) or definition.fx == "stealth" and pulling():
			if op("ability"):
				simulation.cast(unit, slot)

func face(target: Vector2, altitude: float = NAN) -> void:
	var offset := target - point()
	wanted_yaw = atan2(-offset.x, -offset.y)
	wanted_pitch = atan2(altitude - simulation._missile_target_altitude(unit), offset.length()) if is_finite(altitude) and offset.length() > 0.01 else 0.0

func turn(delta: float) -> void:
	if is_finite(wanted_yaw):
		unit.yaw = BotRules.wrap_pi(unit.yaw + CombatMath.view_lock_step(BotRules.wrap_pi(wanted_yaw - unit.yaw), delta))
	unit.pitch = BotRules.wrap_pi(unit.pitch + CombatMath.view_lock_step(BotRules.wrap_pi(wanted_pitch - unit.pitch), delta))
	unit.rotation.y = unit.yaw
	unit.input_state.yaw = unit.yaw
	unit.input_state.pitch = unit.pitch
	if unit.camera != null:
		unit.camera.rotation.x = unit.pitch
		var stats: Dictionary = Content.constants.UNITS[unit.kind]
		unit.camera.fov = stats.get("zoomFov", 35) if unit.input_state.get("aim", false) else stats.get("fovAir", stats.get("fov", 68)) if unit.flying else stats.get("fov", 68)
	unit.sync_view_camera()

func move(destination: Vector2, delta: float) -> float:
	if unit.has_status("rooted_until", simulation.clock):
		return 0.0
	var hold: Dictionary = simulation.bot_holds.get(unit.peer_id, {})
	if not hold.is_empty() and not enraged():
		var centre := Vector2(hold.x, hold.z)
		var offset := destination - centre
		if offset.length() > float(hold.r):
			destination = centre + offset.normalized() * float(hold.r)
	return simulation._bot_move(unit, destination, delta)

func skirt(destination: Vector2) -> Vector2:
	if simulation.clock >= skirt_until:
		return destination
	var offset := destination - point()
	var distance := offset.length() if offset.length() else 1.0
	# Source north-positive tangent becomes the opposite native Z tangent.
	return destination + Vector2(offset.y, -offset.x) / distance * float(Content.balance.bot.stuck.SKIRT_M) * skirt_side

func stuck(fraction: float, delta: float) -> void:
	var rules: Dictionary = Content.balance.bot.stuck
	stuck_time = stuck_time + delta if fraction < float(rules.F) else 0.0
	if stuck_time < float(rules.S) or simulation.clock < skirt_until:
		return
	stuck_time = 0
	skirt_side = -skirt_side
	skirt_until = simulation.clock + float(rules.SKIRT_S)

func progress_at() -> float:
	var distances: Array = simulation.world.lane_distances[lane]
	var along := BotRules.project_lane(simulation.world.lane_points[lane], distances, unit.position.x, unit.position.z)
	return along if unit.side == "SWARM" else float(distances[-1]) - along

func lane_point(own_progress: float) -> Vector2:
	var distances: Array = simulation.world.lane_distances[lane]
	var sample := WaveRules.point_at(simulation.world.lane_points[lane], distances, own_progress if unit.side == "SWARM" else float(distances[-1]) - own_progress)
	return Vector2(sample.x, sample.z)

func push(delta: float) -> void:
	var total: float = simulation.world.lane_distances[lane][-1]
	var foot := lane_point(progress)
	var look := lane_point(clampf(progress + float(Content.balance.bot.pushLook), 0, total))
	progress = minf(total, progress + speed(look - foot) * 0.85 * delta)
	face(look)
	var destination := skirt(foot + jitter)
	stuck(move(point() + (destination - point()) * minf(1, delta * 2.2 * control_factor()), delta), delta)
	if point().distance_to(foot) > 90:
		progress = maxf(0, progress - speed() * delta * 4)

func pick_rally() -> void:
	if simulation.bot_holds.has(unit.peer_id):
		rally_progress = progress
		rally_point = home()
		return
	var best := INF
	var fraction := NAN
	for site: Dictionary in simulation.bot_tower_sites[lane]:
		if not site.has(unit.side):
			continue
		var anchor: Array = site[unit.side]
		var position := Vector2(anchor[0], anchor[1])
		var alive := false
		for structure: BattleUnit in simulation.units.values():
			if structure.kind == "tower" and structure.side == unit.side and structure.alive() and Vector2(structure.position.x, structure.position.z).distance_to(position) <= float(Content.constants.GAME.TOWER_SIDE_OFF) * 1.5:
				alive = true
				break
		if not alive:
			continue
		var distance := point().distance_to(position)
		if distance < best:
			best = distance
			fraction = site.frac
	if not is_finite(fraction):
		rally_progress = 0
		rally_point = home()
		return
	rally_progress = maxf(0, float(simulation.world.lane_distances[lane][-1]) * fraction - float(tactics.RALLY_BACK_M))
	rally_point = lane_point(rally_progress)

func navigate_to(destination: Vector2, delta: float) -> void:
	var offset := destination - point()
	if offset.length() < (30.0 if destination == home() else 5.0):
		return
	if not unit.defending:
		face(destination)
	var goal := skirt(destination) - point()
	var distance := goal.length() if goal.length() else 1.0
	stuck(move(point() + goal / distance * speed(goal) * delta, delta), delta)

func scope_search(expansion: float = 1.0) -> Vector2:
	var frequency: float = difficulty.get("scopeSearchFreq", Content.constants.BOT_VIEW.SEARCH_FREQ)
	return Vector2(sin(simulation.clock * frequency + lane) * deg_to_rad(float(difficulty.scopeSearchDeg) * expansion),
		sin(simulation.clock * frequency * 2 + lane) * deg_to_rad(float(difficulty.scopeSearchPitchDeg) * expansion))

func face_lane_forward() -> void:
	var look := lane_point(clampf((rally_progress if state == "RALLY" else progress_at()) + float(Content.balance.bot.pushLook), 0, simulation.world.lane_distances[lane][-1]))
	var search := scope_search() if unit.input_state.get("aim", false) and stationary() else Vector2.ZERO
	if search == Vector2.ZERO:
		face(look)
		return
	var offset := look - point()
	var yaw := atan2(-offset.x, -offset.y) + search.x
	var distance := offset.length() if offset.length() else float(Content.balance.bot.pushLook)
	face(point() + Vector2(-sin(yaw), -cos(yaw)) * distance, simulation._missile_target_altitude(unit) + sin(search.y) * distance)

func alert_look() -> void:
	var alert: Dictionary = unit.bot_alert
	if alert.is_empty():
		return
	if simulation.clock - float(alert.at) > float(Content.constants.BOT_VIEW.ALERT_S) or target_id != 0 or acquire() != null:
		unit.bot_alert.clear()
		return
	if not difficulty.tactic:
		if absf(bearing(alert.point)) <= BotRules.fov_half(unit.kind):
			unit.bot_alert.clear()
		else:
			face(alert.point)
		return
	var offset: Vector2 = alert.point - point()
	var altitude := simulation._missile_target_altitude(unit)
	var eye := altitude + float(Content.constants.LOS.EYE_M)
	var yaw: float
	var pitch: float
	var distance := offset.length() if offset.length() else 60.0
	if difficulty.elite:
		var relative_bearing := bearing(alert.point)
		var elevation := BotRules.wrap_pi(atan2(float(alert.get("altitude", altitude)) - eye, offset.length()) - unit.pitch) if offset.length() > 0.01 else 0.0
		var half_h := BotRules.fov_half(unit.kind)
		var half_v := BotRules.fov_half(unit.kind, true)
		var direction := BotRules.blood_direction(BotRules.blood_uv(relative_bearing, elevation, half_h, half_v), half_h, half_v)
		yaw = BotRules.wrap_pi(unit.yaw + direction.x)
		pitch = BotRules.wrap_pi(unit.pitch + direction.y)
		face(point() + Vector2(-sin(yaw), -cos(yaw)) * distance, eye + sin(pitch) * distance)
	else:
		var search := scope_search(float(Content.constants.BOT_VIEW.ALERT_SEARCH_EXPAND))
		yaw = atan2(-offset.x, -offset.y) + search.x
		face(point() + Vector2(-sin(yaw), -cos(yaw)) * distance, float(alert.get("altitude", altitude)) + sin(search.y) * distance)

func engage(enemy: BattleUnit, delta: float) -> void:
	var definition := target_weapon()
	var offset := Vector2(enemy.position.x, enemy.position.z) - point()
	var distance := offset.length() if offset.length() else 1.0
	var structure := enemy.kind in ["tower", "base"]
	var kite: float = tactics.KEEP_F
	if difficulty.elite and not structure:
		kite = tactics.KITE_FAR if float(unit.reload_at.get("light", 0)) > simulation.clock else tactics.KITE_NEAR
	var keep: float = definition.range * (float(tactics.KEEP_STRUCT) if structure else kite)
	var radial := (distance - keep) / maxf(1, distance)
	var strafe := sin(simulation.clock * 0.9 + lane * 2) * 0.6
	var direction := offset / distance * radial + Vector2(offset.y, -offset.x) / distance * strafe
	move(point() + direction * speed(direction) * delta, delta)
	face(Vector2(enemy.position.x, enemy.position.z))
	fire(enemy, "light")
	var heavy := heavy_weapon()
	var packed := 0
	var packed_reach := BotRules.packed_reach(heavy)
	for other: BattleUnit in simulation.units.values():
		if other.side != unit.side and not other.special.get("neutral", false) and simulation._planar_distance(other.position, enemy.position) <= packed_reach:
			packed += 1
	if difficulty.heavy and (packed >= 3 or structure or enemy.is_hero()) and heavy_ready(heavy) and simulation.clock >= aim_at and op("weapon"):
		if not unit.input_state.get("aim", false):
			simulation._bot_aim(unit, true)
		if heavy.type in ["launcher", "missile"]:
			if simulation.rng.next() >= float(difficulty.aimErr) and simulation._bot_clear_shot(unit, enemy):
				simulation._bot_fire(unit, enemy, "heavy", "burst")
		elif heavy.type == "plasma":
			simulation._bot_fire(unit, enemy, "heavy", "fan")
		else:
			fire(enemy, "heavy")
	if not difficulty.ability:
		return
	for slot: String in ["def", "atk"]:
		var ability := ready(slot)
		if ability.is_empty():
			continue
		var aimed := false
		var use := false
		if ability.fx in ["strike", "emp"] and packed >= 3 or ability.fx in ["summon", "vision"]:
			use = true
			aimed = true
		elif ability.fx == "buff" and ability.mul is Dictionary and ability.mul.get("dmg", 0) or ability.fx == "intercept" and missiles_targeting_pilot() or ability.fx == "shield_bash" and (unit.defending or distance <= 35 or packed >= 2):
			use = true
		elif difficulty.elite and int(ability.charges) > 1 and simulation._ready_charges(unit, slot, ability) >= int(ability.charges):
			use = true
			aimed = ability.fx in ["strike", "emp"]
		elif difficulty.elite and enemy.is_hero() and (ability.dmg or ability.get("baseDmg", 0) or ability.fx == "strike") and enemy.hp <= BotRules.salvo(light_weapon(), enemy.kind, tactics):
			use = true
			aimed = true
		if use and op("ability"):
			simulation.cast(unit, slot, enemy.position if aimed else Vector3(INF, INF, INF))

func update(delta: float) -> void:
	if not simulation.authoritative or simulation.over or unit.has_status("freeze_until", simulation.clock):
		return
	if not unit.alive():
		state = "PUSH"
		progress = 0
		return
	resolve_role()
	var fraction := unit.hp / unit.max_hp
	var shield_fraction := unit.shield / unit.max_shield if unit.max_shield > 0 else 1.0
	var wanted := pull_want(fraction, shield_fraction)
	if not wanted.is_empty() and state != wanted and op("state"):
		state = wanted
		if state == "RALLY":
			pick_rally()
	elif (state == "RETREAT" and fraction >= float(tactics.RESUME_HP) or state == "RALLY" and shield_fraction >= float(tactics.RALLY_SP)) and op("state"):
		progress = progress_at() if state == "RALLY" else 0.0
		state = "PUSH"
	update_aiming()
	var enemy := target()
	if not pulling():
		state = "ENGAGE" if enemy != null else "PUSH"
	update_defending(enemy)
	var can_buy := false
	if not unit.special.get("boss", false):
		for item: String in Content.constants.ECON.UPGRADES:
			var level := int(unit.upgrades[item])
			if level < int(Content.constants.ECON.UPGRADES[item].max):
				var step: Dictionary = Content.constants.ECON.UPG_STEPS[level]
				can_buy = can_buy or unit.money >= float(step.price) and unit.score >= float(step.score)
	if (can_buy or not unit.special.get("boss", false) and unit.money >= float(Content.constants.CREEP_UPG.PRICE)) and op("buy"):
		var bought := false
		var order: Array = simulation.bot_profile(unit.character).buy if not role.is_empty() else Content.constants.BOT_BUY_ORDER
		for item: String in order:
			if not difficulty.ability and item in ["def", "atk"]:
				continue
			if simulation.buy(unit, item):
				bought = true
				break
		if not bought:
			simulation.buy_creep(unit, lane)
	cast_support(fraction)
	if state == "RETREAT":
		navigate_to(home(), delta)
	elif state == "RALLY":
		if in_fight():
			navigate_to(rally_point if rally_point.is_finite() else home(), delta)
		if enemy != null:
			face(Vector2(enemy.position.x, enemy.position.z))
			if in_fight():
				fire(enemy, "light")
		else:
			face_lane_forward()
	elif state == "ENGAGE":
		engage(enemy, delta)
	elif simulation.bot_holds.has(unit.peer_id) and not enraged():
		navigate_to(home(), delta)
		face_lane_forward()
	else:
		push(delta)
	if unit.defending:
		if enemy != null:
			face(Vector2(enemy.position.x, enemy.position.z), simulation._missile_target_altitude(enemy))
		elif not unit.bot_alert.is_empty():
			face(unit.bot_alert.point, unit.bot_alert.get("altitude", NAN))
	alert_look()
	turn(delta)
	var altitude := simulation._missile_target_altitude(unit)
	var wanted_altitude := 0.0
	if unit.kind == "drone":
		var floor_altitude := maxf(float(Content.constants.GAME.AA_MIN_ALT) * 0.6, cruise_altitude * 0.6)
		wanted_altitude = floor_altitude if state == "ENGAGE" else cruise_altitude
		if state == "ENGAGE" and difficulty.tactic:
			var target_altitude := simulation._missile_target_altitude(enemy) if enemy != null and (enemy.is_hero() or enemy.kind == "heli") else 0.0
			wanted_altitude = minf(float(Content.balance.bot.cruise.max), maxf(floor_altitude, target_altitude + float(Content.constants.TARGET_H.tower)))
		var climb: float = Content.constants.UNITS[unit.kind].get("vspeed", 0)
		wanted_altitude = move_toward(altitude, wanted_altitude, climb * delta)
	elif unit.kind == "morph":
		wanted_altitude = altitude + ((cruise_altitude if state == "PUSH" else 0.0) - altitude) * minf(1, delta * 1.5)
		if state != "PUSH" and wanted_altitude < 1.5:
			wanted_altitude = 0
	simulation._bot_altitude(unit, wanted_altitude)
