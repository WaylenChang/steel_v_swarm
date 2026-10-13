class_name BattleSimulation
extends Node3D

signal result(winner: String)
signal message(peer: int, key: String)

var world: BattleWorld
var units: Dictionary = {}
var pilots: Dictionary = {}
var clock := 0.0
var wave := 0
var next_wave := 0.0
var over := false
var winner := ""
var next_id := 1
var authoritative := true
var rng := SourceRng.new(42)
var events: Array = []

func setup(map_data: Dictionary, roster: Array, env: Dictionary, authority: bool) -> void:
	set_physics_process(false)
	authoritative = authority
	world = BattleWorld.new()
	add_child(world)
	await world.build(map_data, env)
	if not authoritative:
		set_physics_process(true)
		return
	for info in map_data.structures:
		var data: Dictionary = info.duplicate()
		data.position = Vector3(info.position[0], info.position[1], info.position[2])
		data.position.y = world.ground_height(data.position.x, data.position.z)
		if not is_finite(data.position.y):
			push_error("Structure has no verified standing surface")
			get_tree().quit(1)
			return
		spawn(data)
	var slots := {"SWARM": 0, "STEEL": 0}
	for player in roster:
		var hero: Dictionary = Content.heroes[player.character]
		var data: Dictionary = player.duplicate()
		data.kind = hero.kind
		data.spawn_slot = slots[player.side]
		data.lane = slots[player.side] % world.paths.size()
		data.position = world.spawn_position(player.side, slots[player.side], hero.kind == "drone")
		if not data.position.is_finite():
			push_error("Hero spawn has no verified standing surface")
			get_tree().quit(1)
			return
		var unit := spawn(data)
		pilots[int(player.peer)] = unit
		slots[player.side] += 1
	set_physics_process(true)

func spawn(info: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	var data: Dictionary = info.duplicate()
	data.id = next_id if not info.has("id") else int(info.id)
	next_id = maxi(next_id, int(data.id) + 1)
	unit.name = "Unit_%d" % data.id
	add_child(unit)
	unit.configure(data)
	units[unit.entity_id] = unit
	if unit.is_hero():
		unit.yaw = world.spawn_heading(unit.side, unit.spawn_slot)
	if authoritative and unit.speed > 0 and not unit.is_hero():
		unit.path_follower = PathFollow3D.new()
		unit.path_follower.loop = false
		unit.path_follower.rotation_mode = PathFollow3D.ROTATION_NONE
		world.paths[unit.lane].add_child(unit.path_follower)
		unit.path_follower.progress_ratio = 0.0 if unit.side == "SWARM" else 1.0
	return unit

func submit_input(peer: int, command: Dictionary) -> void:
	if not authoritative or over or not pilots.has(peer):
		return
	var motion = command.get("move")
	var heading = command.get("yaw")
	var elevation = command.get("pitch")
	var vertical = command.get("vertical", 0.0)
	if not motion is Vector2 or not motion.is_finite() or not heading is float or not elevation is float:
		return
	if not is_finite(heading) or not is_finite(elevation):
		return
	if not (vertical is float or vertical is int) or not is_finite(float(vertical)):
		return
	var unit: BattleUnit = pilots[peer]
	unit.input_state = {"move": motion.limit_length(), "yaw": wrapf(heading, -PI, PI),
		"pitch": clampf(elevation, -1.45, 1.45), "vertical": clampf(float(vertical), -1, 1),
		"jump": command.get("jump", false) == true, "fire": command.get("fire", false) == true,
		"sprint": command.get("sprint", false) == true, "aim": command.get("aim", false) == true,
		"slot": "heavy" if command.get("slot") == "heavy" else "light"}
	unit.input_state["received"] = clock

func action(peer: int, type: String, argument: String = "") -> void:
	if not authoritative or over or not pilots.has(peer):
		return
	var unit: BattleUnit = pilots[peer]
	if not unit.alive():
		return
	match type:
		"reload":
			reload_weapon(unit, argument if argument in ["light", "heavy"] else "light")
		"buy":
			buy(unit, argument)
		"cast":
			cast(unit, argument)
		"morph":
			if unit.kind == "morph":
				unit.flying = not unit.flying
				unit.refresh_collision()
				if unit.flying:
					unit.velocity.y = Content.constants.MORPH.JUMP_V

func _physics_process(delta: float) -> void:
	if not authoritative:
		for unit in units.values():
			unit.interpolate(delta)
		return
	if over:
		return
	clock += delta
	if clock >= next_wave:
		spawn_wave()
		next_wave = clock + Content.constants.GAME.WAVE_S
	for unit: BattleUnit in units.values():
		if not unit.alive():
			if unit.is_hero() and unit.respawn_at > 0 and clock >= unit.respawn_at:
				respawn(unit)
			continue
		if unit.is_hero():
			_regenerate(unit, delta)
			if unit.is_bot:
				_bot_command(unit)
			elif clock - float(unit.input_state.get("received", clock)) > 0.5:
				unit.input_state = {}
			unit.simulate_movement(delta)
			if unit.input_state.get("fire", false):
				fire(unit, unit.input_state.get("slot", "light"))
		else:
			_tick_npc(unit, delta)
		unit.visible = unit.alive()
		unit.position.y = minf(unit.position.y, world.ceiling)
		unit.buffs = unit.buffs.filter(func(buff): return buff.until > clock)
	_prune_dead_creeps()

func spawn_wave() -> void:
	var composition: Array = Content.balance.waves[mini(wave, Content.balance.waves.size() - 1)]
	for lane in range(world.paths.size()):
		for side in ["SWARM", "STEEL"]:
			var path: Path3D = world.paths[lane]
			for i in range(composition.size()):
				var progress: float = Content.constants.GAME.WAVE_SPAWN_OFF_M + i * 5.0
				var offset: float = progress if side == "SWARM" else path.curve.get_baked_length() - progress
				var pos := path.curve.sample_baked(offset)
				if composition[i] == "heli":
					pos.y += Content.constants.GAME.HELI_ALT
				else:
					pos.y += 0.1
				var unit := spawn({"side": side, "kind": composition[i], "lane": lane, "position": pos})
				unit.path_follower.progress = offset
	wave += 1

func _tick_npc(unit: BattleUnit, delta: float) -> void:
	var def: Dictionary = Content.constants.UNITS[unit.kind]
	var target := acquire_target(unit, def.get("range", 0))
	if target != null:
		var direction := target.eye() - unit.eye()
		unit.yaw = atan2(-direction.x, -direction.z)
		unit.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		if clock >= float(unit.fire_at.get("npc", 0)):
			unit.fire_at.npc = clock + 1.0 / maxf(0.01, def.get("rate", 1))
			var weapon_def: Dictionary = {"type": "gun", "dmg": def.dmg, "range": def.range, "vsSp": 1, "vsHp": 1}
			damage(unit, target, weapon_def, def.dmg)
			events.append({"type": "shot", "actor": unit.entity_id, "start": unit.eye(), "end": target.eye(), "side": unit.side})
		return
	if unit.path_follower == null:
		return
	var sign_value := 1.0 if unit.side == "SWARM" else -1.0
	unit.path_follower.progress += unit.speed * delta * sign_value
	var point: Vector3 = unit.path_follower.global_position
	var direction := point - unit.global_position
	direction.y = 0
	if direction.length_squared() > 0.01:
		unit.yaw = atan2(-direction.x, -direction.z)
		unit.input_state = {"move": Vector2(0, -1), "yaw": unit.yaw}
		unit.simulate_movement(delta)

func acquire_target(unit: BattleUnit, reach: float, fov: bool = false) -> BattleUnit:
	var nearest: BattleUnit
	var best := INF
	for candidate: BattleUnit in units.values():
		if not candidate.alive() or candidate.side == unit.side:
			continue
		var distance := unit.eye().distance_to(candidate.eye()) - candidate.radius
		if distance > reach or distance >= best:
			continue
		if fov:
			var delta := candidate.eye() - unit.eye()
			var half_vertical := deg_to_rad(Content.constants.UNITS[unit.kind].get("fov", 68)) / 2
			var half_horizontal := atan(tan(half_vertical) * Content.constants.BOT_VIEW.ASPECT)
			var yaw_error := wrapf(atan2(-delta.x, -delta.z) - unit.yaw, -PI, PI)
			var pitch_error := atan2(delta.y, Vector2(delta.x, delta.z).length()) - unit.pitch
			if absf(yaw_error) > half_horizontal or absf(pitch_error) > half_vertical:
				continue
		if not visible_to(unit, candidate):
			continue
		nearest = candidate
		best = distance
	return nearest

func visible_to(unit: BattleUnit, target: BattleUnit) -> bool:
	var query := PhysicsRayQueryParameters3D.create(unit.eye(), target.eye(), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _bot_command(unit: BattleUnit) -> void:
	var target: BattleUnit = units.get(unit.bot_target)
	if clock >= unit.reaction_at:
		unit.reaction_at = clock + Content.constants.BOT_DIFF[Content.constants.DEFAULT_BOT_DIFF].react
		target = acquire_target(unit, Content.constants.UNITS[unit.kind].sight, true)
		unit.bot_target = target.entity_id if target != null else 0
	var destination: Vector3 = world.bases["STEEL" if unit.side == "SWARM" else "SWARM"]
	var retreating := unit.hp < unit.max_hp * 0.25
	if retreating:
		destination = world.bases[unit.side]
	elif target != null:
		destination = target.eye()
	else:
		var path: Path3D = world.paths[unit.lane % world.paths.size()]
		var progress := path.curve.get_closest_offset(path.to_local(unit.global_position))
		destination = path.curve.sample_baked(clampf(progress + (20 if unit.side == "SWARM" else -20), 0, path.curve.get_baked_length()))
	var direction := destination - unit.eye()
	var desired_yaw := atan2(-direction.x, -direction.z)
	unit.yaw += CombatMath.view_lock_step(wrapf(desired_yaw - unit.yaw, -PI, PI), get_physics_process_delta_time())
	var desired_pitch := atan2(direction.y, maxf(1, Vector2(direction.x, direction.z).length()))
	unit.pitch += CombatMath.view_lock_step(desired_pitch - unit.pitch, get_physics_process_delta_time())
	var weapon_def := Content.weapon(unit.character, "light", int(unit.upgrades.lw) + 1)
	var distance := direction.length()
	var move_forward: bool = retreating or target == null or distance > weapon_def.range * 0.75
	var fire_now := target != null and not retreating and unit.aim_direction().dot(direction.normalized()) > 0.995
	var ground_reference := world.flight_reference(unit.position.x, unit.position.z)
	var vertical := clampf((ground_reference + 12 - unit.position.y) * 0.1, -1, 1) if unit.flying and is_finite(ground_reference) else 0.0
	unit.input_state = {"move": Vector2(0, -1 if move_forward else 0), "yaw": unit.yaw,
		"pitch": unit.pitch, "vertical": vertical,
		"slot": "light", "fire": fire_now}

func reload_weapon(unit: BattleUnit, slot: String) -> void:
	var def := Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1)
	if unit.reload_at.has(slot) or unit.ammo.get(slot, def.mag) >= def.mag:
		return
	unit.reload_at[slot] = clock + def.reload

func fire(unit: BattleUnit, slot: String) -> void:
	var def := Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1)
	if unit.reload_at.has(slot):
		if clock < unit.reload_at[slot]:
			return
		unit.ammo[slot] = def.mag
		unit.reload_at.erase(slot)
	if clock < float(unit.fire_at.get(slot, 0)):
		return
	if unit.ammo.get(slot, 0) <= 0:
		reload_weapon(unit, slot)
		return
	if unit.power < def.heavyMp:
		return
	if def.get("needAim", false) and not unit.input_state.get("aim", false):
		return
	unit.ammo[slot] -= 1
	unit.power -= def.heavyMp
	unit.fire_at[slot] = clock + 1.0 / def.rate
	unit.play_action(slot)
	var start := unit.eye()
	var end: Vector3 = start + unit.aim_direction() * def.range
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 2, [unit.get_rid(), unit.hit_area.get_rid()])
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	match def.area:
		"blast":
			blast(unit, def, end)
		"fan":
			_fire_fan(unit, def)
		"line":
			_fire_line(unit, def)
		_:
			if not hit.is_empty() and hit.collider is Area3D and hit.collider.get_parent() is BattleUnit:
				var target: BattleUnit = hit.collider.get_parent()
				if CombatMath.in_range(def.range, target.eye() - start, target.radius):
					var amount: float = def.dmg * CombatMath.damage_falloff(def, start.distance_to(target.eye()))
					if rng.next() < def.get("crit", 0):
						amount *= def.get("critX", 1)
					damage(unit, target, def, amount)
	events.append({"type": "shot", "actor": unit.entity_id, "start": start, "end": end, "side": unit.side})

func blast(unit: BattleUnit, def: Dictionary, impact: Vector3) -> void:
	# Coverage deliberately ignores LOS; each victim consumes the original blast bands.
	for target: BattleUnit in units.values():
		if not target.alive() or target.side == unit.side:
			continue
		var distance := maxf(0.0, impact.distance_to(target.eye()) - target.radius)
		var factor := CombatMath.blast_falloff(def.get("r", 0), distance)
		if factor > 0:
			damage(unit, target, def, def.get("dmg", 0) * factor)

func _fire_fan(unit: BattleUnit, def: Dictionary) -> void:
	var axis := Vector2(unit.aim_direction().x, unit.aim_direction().z).normalized()
	var count: int = int(def.fanSubs)
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		var delta := target.eye() - unit.eye()
		var horizontal := Vector2(delta.x, delta.z).length()
		var phi := axis.angle_to(Vector2(delta.x, delta.z))
		var hits := 0
		for bin in range(count):
			var near := CombatMath.fan_bin_distance(def, bin, horizontal, phi, target.radius)
			var vertical := maxf(0.0, absf(delta.y) - target.height / 2)
			if near >= 0 and Vector2(near, vertical).length() <= def.range * def.fanRangeFactors[bin]:
				hits += 1
		if CombatMath.target_class(target.kind) == "building":
			hits = mini(hits, int(def.fanMaxBuildingHits))
		if hits > 0:
			var half_arc := deg_to_rad(def.arc)
			var off_axis := clampf(absf(phi) / maxf(0.001, half_arc), 0, 1)
			damage(unit, target, def, def.dmg * Content.constants.FAN_SUB_F * hits * (1.0 - (1.0 - Content.constants.AOE_EDGE) * off_axis))

func _fire_line(unit: BattleUnit, def: Dictionary) -> void:
	var candidates: Array = []
	var direction := unit.aim_direction()
	var horizontal := Vector2(direction.x, direction.z).length()
	var vertical := horizontal < 0.15
	var forward := Vector2(direction.x, direction.z).normalized() if not vertical else Vector2.ZERO
	var slope := direction.y / horizontal if not vertical else 0.0
	var length_limit: float = def.range if vertical else def.range * horizontal
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		var delta := target.eye() - unit.eye()
		var flat := Vector2(delta.x, delta.z)
		var along := delta.y * (1.0 if direction.y >= 0 else -1.0) if vertical else flat.dot(forward)
		var clamped := clampf(along, 0, length_limit)
		var offset := flat if vertical else flat - forward * clamped
		var deviation := Vector2(offset.length(), along - clamped).length()
		var band: float = def.lanceRadius * Content.constants.LANCE.VBAND_F
		var ray_y := unit.eye().y + slope * clamped
		var outside_height := maxf(target.position.y - ray_y, ray_y - target.position.y - target.height)
		if deviation > target.radius + def.lanceRadius or (not vertical and outside_height > band) or not visible_to(unit, target):
			continue
		for zone in CombatMath.lance_zones(offset, target.radius, def.lanceRadius):
			candidates.append({"unit": target, "distance": along, "zone": zone, "off": minf(1, deviation / (target.radius + def.lanceRadius))})
	candidates.sort_custom(func(a, b): return a.distance < b.distance if a.distance != b.distance else a.zone < b.zone)
	var budgets := {}
	var counts := {}
	var seen := {}
	for candidate in candidates:
		var zone: int = candidate.zone
		if float(budgets.get(zone, 0)) < 0:
			continue
		if not budgets.has(zone):
			budgets[zone] = def.lancePen * (3.0 if zone == 0 else 1.0) / 9.0
		var target: BattleUnit = candidate.unit
		budgets[zone] -= PI * target.radius * target.radius
		var index: int = counts.get(zone, 0)
		counts[zone] = index + 1
		var repeat_factor: float = Content.constants.LANCE.REHIT_F if seen.has(target.entity_id) else 1.0
		seen[target.entity_id] = true
		var offset_factor: float = 1.0 - (1.0 - Content.constants.AOE_EDGE) * candidate.off
		damage(unit, target, def, def.dmg * CombatMath.damage_falloff(def, unit.eye().distance_to(target.eye())) * pow(Content.constants.LANCE.DECAY, index) * repeat_factor * offset_factor)

func damage(attacker: BattleUnit, target: BattleUnit, def: Dictionary, amount: float) -> void:
	if not authoritative or over or not target.alive() or target.side == attacker.side or amount <= 0:
		return
	amount *= CombatMath.vs_multiplier(def, target.kind)
	for buff in target.buffs:
		amount *= buff.get("mul", {}).get("dmgTaken", 1.0)
	var split := CombatMath.shield_split(def, amount, target.shield)
	target.shield = maxf(0, target.shield - split.toSp)
	target.hp = maxf(0, target.hp - split.toHp * CombatMath.armor_multiplier(target.armor, def.get("pen", 0)))
	target.damaged_at = clock
	if target.hp > 0:
		return
	target.visible = false
	target.collision_layer = 0
	target.collision_mask = 0
	target.hit_area.collision_layer = 0
	if attacker.is_hero():
		attacker.money += Content.constants.ECON.BOUNTY.get(target.kind, 0)
		attacker.score = minf(Content.constants.BATTLE_SCORE.MAX, attacker.score + Content.constants.BATTLE_SCORE.KILL * (Content.constants.BATTLE_SCORE.HARD_F if target.is_hero() or target.kind == "tower" else 1))
	if target.kind == "base":
		over = true
		winner = attacker.side
		result.emit(winner)
	elif target.is_hero():
		target.deaths += 1
		var times: Dictionary = Content.constants.UNITS[target.kind].respawn
		target.respawn_at = clock + times.base + times.perDeath * target.deaths

func respawn(unit: BattleUnit) -> void:
	unit.hp = unit.max_hp
	unit.shield = unit.max_shield
	unit.power = unit.max_power
	unit.flying = unit.kind == "drone"
	unit.position = world.spawn_position(unit.side, unit.spawn_slot, unit.kind == "drone")
	unit.yaw = world.spawn_heading(unit.side, unit.spawn_slot)
	unit.velocity = Vector3.ZERO
	unit.respawn_at = 0
	unit.collision_mask = 1 | 4
	unit.refresh_collision()
	unit.visible = true
	unit.buffs.clear()
	unit.reload_at.clear()
	for slot in ["light", "heavy"]:
		unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1).mag

func _regenerate(unit: BattleUnit, delta: float) -> void:
	var charge: float = Content.balance.charge[int(unit.upgrades.ch)]
	unit.power = minf(unit.max_power, unit.power + Content.constants.UNITS[unit.kind].mpRegen * charge * delta)
	if clock - unit.damaged_at < Content.constants.VITALS.OOC_S:
		return
	unit.shield = minf(unit.max_shield, unit.shield + unit.max_shield * Content.constants.VITALS.SP_REGEN_PS * charge * delta)
	if unit.position.distance_to(world.bases[unit.side]) < Content.constants.GAME.HERO_HEAL_RADIUS:
		unit.hp = minf(unit.max_hp, unit.hp + Content.constants.UNITS[unit.kind].regen * delta)

func buy(unit: BattleUnit, item: String) -> bool:
	var definitions: Dictionary = Content.constants.ECON.UPGRADES
	if not definitions.has(item) or not unit.alive():
		return false
	if unit.position.distance_to(world.bases[unit.side]) > Content.constants.GAME.HERO_HEAL_RADIUS:
		return false
	var level: int = int(unit.upgrades[item])
	if level >= int(definitions[item].max):
		return false
	var step: Dictionary = Content.constants.ECON.UPG_STEPS[level]
	if unit.money < step.price or unit.score < step.score:
		return false
	unit.money -= step.price
	unit.upgrades[item] += 1
	var hero: Dictionary = Content.heroes[unit.character]
	var stats: Dictionary = Content.constants.UNITS[unit.kind]
	match item:
		"hp":
			var maximum := roundf(stats.hp * hero.mods.get("hp", 1) * (1 + definitions.hp.step * unit.upgrades.hp))
			unit.hp += maximum - unit.max_hp
			unit.max_hp = maximum
		"sp":
			var maximum := roundf(stats.shield * hero.mods.get("sp", 1) * (1 + definitions.sp.step * unit.upgrades.sp))
			unit.shield += maximum - unit.max_shield
			unit.max_shield = maximum
		"ar":
			unit.armor = hero.armor + definitions.ar.step * unit.upgrades.ar
		"lw", "hw":
			var slot := "light" if item == "lw" else "heavy"
			unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades[item]) + 1).mag
			unit.reload_at.erase(slot)
	return true

func cast(unit: BattleUnit, slot: String) -> bool:
	if slot not in ["def", "atk"]:
		return false
	var def := Content.ability(unit.character, slot, int(unit.upgrades[slot]) + 1)
	# Carrier, persistent field, and revive mechanics must not masquerade as generic damage.
	if def.carrier or def.support or def.fx not in ["buff", "heal"] or def.charges > 1 or def.get("revive", 0) > 0 or def.get("cleanse", false) or def.get("shieldExpand", false) or def.get("shieldDefBoost", 0) > 0 or def.get("aura", false):
		message.emit(unit.peer_id, "unsupported")
		return false
	if clock < float(unit.cooldowns.get(slot, 0)) or unit.power < def.mp:
		return false
	unit.cooldowns[slot] = clock + def.cd
	unit.power -= def.mp
	var targets: Array = [unit]
	if def.get("target", "self") == "team":
		targets = units.values().filter(func(target): return target.side == unit.side and target.alive() and unit.position.distance_to(target.position) <= def.r)
	for target: BattleUnit in targets:
		target.hp = minf(target.max_hp, target.hp + def.get("heal", 0))
		target.shield = minf(target.max_shield, target.shield + def.get("spRestore", 0) + (def.get("heal", 0) if def.get("sp", false) else 0))
		if not def.mul.is_empty():
			target.buffs.append({"until": clock + def.dur, "mul": def.mul})
	return true

func _prune_dead_creeps() -> void:
	for id in units.keys():
		var unit: BattleUnit = units[id]
		if unit.alive() or unit.is_hero() or unit.kind in ["base", "tower"]:
			continue
		if unit.path_follower != null:
			unit.path_follower.queue_free()
		unit.queue_free()
		units.erase(id)

func snapshot(peer: int = 0) -> Dictionary:
	var visible_units: Array = []
	var viewer: BattleUnit = pilots.get(peer)
	for unit: BattleUnit in units.values():
		if viewer != null and unit.side != viewer.side and unit.kind not in ["base", "tower"]:
			var spotted := false
			for ally: BattleUnit in units.values():
				if ally.side == viewer.side and ally.alive() and ally.eye().distance_to(unit.eye()) <= Content.constants.UNITS[ally.kind].get("sight", 0) and visible_to(ally, unit):
					spotted = true
					break
			if not spotted:
				continue
		visible_units.append(unit.snapshot())
	var visible_ids := {}
	for unit in visible_units:
		visible_ids[unit.id] = true
	var visible_events: Array = events
	if viewer != null:
		visible_events = events.filter(func(event): return visible_ids.has(event.actor))
	return {"clock": clock, "wave": wave, "over": over, "winner": winner,
		"units": visible_units, "events": visible_events.duplicate()}

func apply_snapshot(data: Dictionary) -> void:
	if authoritative or data.clock < clock:
		return
	clock = data.clock
	wave = int(data.wave)
	var seen := {}
	for state in data.units:
		var id: int = int(state.id)
		seen[id] = true
		var fresh := not units.has(id)
		var unit: BattleUnit = spawn(state) if fresh else units[id]
		unit.apply_snapshot(state, fresh)
		if unit.is_hero():
			pilots[unit.peer_id] = unit
	for id in units.keys():
		if seen.has(id):
			continue
		var removed: BattleUnit = units[id]
		if removed.is_hero():
			pilots.erase(removed.peer_id)
		removed.queue_free()
		units.erase(id)
	for event in data.events:
		if event.type == "shot":
			world.tracer(event.start, event.end, event.side)
	if data.over and not over:
		over = true
		winner = data.winner
		result.emit(winner)
