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
var projectiles: Array[Dictionary] = []
var projectile_rng := SourceRng.new(4242)
var fire_controls: Dictionary = {}
var missiles: Array[Dictionary] = []
var missile_bodies: Dictionary = {}
var footprint_glows: FootprintGlows

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
	if unit.input_state.get("aim", false) and command.get("aim", false) != true:
		unit.aim_off_at = clock
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
			fire_controls.erase(unit.entity_id)
			if unit.is_hero() and unit.respawn_at > 0 and clock >= unit.respawn_at:
				respawn(unit)
			continue
		if unit.is_hero():
			_regenerate(unit, delta)
			var was_aiming: bool = unit.input_state.get("aim", false)
			if unit.is_bot:
				_bot_command(unit)
			elif clock - float(unit.input_state.get("received", clock)) > 0.5:
				unit.input_state = {}
			if was_aiming and not unit.input_state.get("aim", false):
				unit.aim_off_at = clock
			unit.simulate_movement(delta)
			if unit.input_state.get("aim", false) and unit.input_state.get("slot", "light") == "heavy":
				var weapon := Content.weapon(unit.character, "heavy", int(unit.upgrades.hw) + 1)
				if weapon.trajectory == "lob":
					fire_controls[unit.entity_id] = lob_control(unit, weapon)
				else:
					fire_controls.erase(unit.entity_id)
			else:
				fire_controls.erase(unit.entity_id)
			_tick_lock(unit)
			if unit.input_state.get("fire", false):
				fire(unit, unit.input_state.get("slot", "light"))
		else:
			_tick_npc(unit, delta)
		unit.visible = unit.alive() and unit.presentation_visible
		unit.position.y = minf(unit.position.y, world.ceiling)
		unit.buffs = unit.buffs.filter(func(buff): return buff.until > clock)
	_tick_projectiles(delta)
	_tick_missiles(delta)
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
	if unit.kind == "base":
		_tick_base_guns(unit, def.guns, delta)
		return
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
	var query := PhysicsRayQueryParameters3D.create(unit.sight_origin(), target.sight_target(), 1)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func visible_to_side(target: BattleUnit, side: String) -> bool:
	if target.side == side or target.kind in ["base", "tower"]:
		return true
	for observer: BattleUnit in units.values():
		if observer.side != side or not observer.alive():
			continue
		var offset := Vector2(target.position.x - observer.position.x, target.position.z - observer.position.z)
		if offset.length() <= observer.sight_radius() and visible_to(observer, target):
			return true
	return false

func apply_presentation_view(state: Dictionary) -> void:
	if not authoritative:
		return
	var shown := {}
	for actor in state.units:
		shown[int(actor.id)] = true
	for unit: BattleUnit in units.values():
		unit.presentation_visible = shown.has(unit.entity_id)
		unit.visible = unit.alive() and unit.presentation_visible

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
	if not authoritative or over or not unit.alive() or slot not in ["light", "heavy"]:
		return
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
	var launch_surface := NAN
	if def.trajectory in ["guide", "fnf", "lob", "flat"]:
		launch_surface = _projectile_surface(unit.eye())
		if not is_finite(launch_surface):
			message.emit(unit.peer_id, "unavailable_surface")
			return
	var control := {}
	if def.trajectory == "lob":
		control = fire_controls.get(unit.entity_id, {})
		if control.is_empty() or control.clock != clock or control.origin != unit.eye() or control.direction != unit.aim_direction() or control.level != int(unit.upgrades.hw):
			control = lob_control(unit, def)
			fire_controls[unit.entity_id] = control
		if control.is_empty():
			message.emit(unit.peer_id, "unavailable_surface")
			return
	var reach: float = def.range
	if def.trajectory != "lob":
		reach = _launch_range(unit, def, _aim_target(unit, TargetingMath.maximum_range(def)))
		if not is_finite(reach):
			message.emit(unit.peer_id, "unavailable_surface")
			return
	unit.ammo[slot] -= 1
	unit.power -= def.heavyMp
	unit.fire_at[slot] = clock + 1.0 / def.rate
	unit.play_action(slot)
	unit.fire_serial += 1
	events.append({"type": "weapon_fire", "actor": unit.entity_id, "slot": slot, "side": unit.side, "serial": unit.fire_serial, "clock": clock})
	var start := unit.eye()
	if def.trajectory == "flat":
		var state := ProjectileMotion.ballistic(start, unit.aim_direction() * def.projectile.speed, reach)
		state.actor = unit.entity_id
		state.side = unit.side
		state.definition = def.duplicate(true)
		state.origin_surface = launch_surface
		state.shooter_height = unit.position.y - launch_surface
		state.slot = slot
		projectiles.append(state)
		return
	if def.trajectory == "lob":
		var state := ProjectileMotion.ballistic(start, control.velocity, control.range)
		state.actor = unit.entity_id
		state.side = unit.side
		state.definition = def.duplicate(true)
		projectiles.append(state)
		return
	if def.trajectory in ["guide", "fnf"]:
		var aim := _projectile_aim(unit, reach)
		_launch_guided(unit, def, start, aim.point, aim.hit, launch_surface, reach)
		return
	var precise := _projectile_aim(unit, reach)
	var end: Vector3 = precise.point
	match def.area:
		"blast":
			blast(unit, def, end)
		"fan":
			_fire_fan(unit, def)
		"line":
			var obstruction := _arc_collision(start, start + unit.aim_direction() * reach)
			_fire_line(unit, def, start, obstruction.position if not obstruction.is_empty() else start + unit.aim_direction() * reach)
		_:
			if int(precise.missile) != 0:
				_damage_missile(unit, def, int(precise.missile))
			var target: BattleUnit = precise.target if precise.target != null else _aim_target(unit, reach) if int(precise.missile) == 0 else null
			if target != null:
				var surface := _projectile_surface(unit.position)
				var target_surface := _projectile_surface(target.position)
				if not is_finite(surface) or not is_finite(target_surface):
					return
				var target_height: float = target.position.y - target_surface if target.is_hero() else 0.0
				var offset := Vector3(target.position.x - unit.position.x, target_height - (unit.position.y - surface), target.position.z - unit.position.z)
				var budget: float = def.range * _settlement_range_factor(unit, def, start, surface, target, target_surface) * Content.constants.RANGE_TOL
				if visible_to_side(target, unit.side) and visible_to(unit, target) and CombatMath.direct_in_range(budget, offset, target.radius):
					var amount: float = def.dmg * CombatMath.damage_falloff(def, offset.length())
					if rng.next() < def.get("crit", 0):
						amount *= def.get("critX", 1)
					damage(unit, target, def, amount)
	events.append({"type": "shot", "actor": unit.entity_id, "start": start, "end": end, "side": unit.side})

func lob_control(unit: BattleUnit, def: Dictionary) -> Dictionary:
	var origin := unit.eye()
	var direction := unit.aim_direction()
	var maximum := TargetingMath.maximum_range(def)
	var crosshair := _projectile_aim(unit, maximum)
	var aim: Vector3 = crosshair.point
	var target: BattleUnit = crosshair.target
	var anti_air := target != null and CombatMath.target_class(target.kind) == "air"
	if anti_air:
		aim = target.aim_point()
		if not aim.is_finite():
			return {}
	var reach := _launch_range(unit, def, target)
	if not is_finite(reach):
		return {}
	var control := LobFireControl.prepare(def, origin, aim, reach, anti_air, world.ground_height, _arc_collision)
	if control.is_empty():
		return {}
	control.clock = clock
	control.origin = origin
	control.direction = direction
	control.level = int(unit.upgrades.hw)
	control.target = target.entity_id if target != null else 0
	return control

func _launch_range(unit: BattleUnit, def: Dictionary, target: BattleUnit) -> float:
	if target == null:
		return def.range
	var surface := _height_reference(unit)
	var target_surface := world.ground_height(target.position.x, target.position.z)
	if not target.is_hero() and (not is_finite(surface) or not is_finite(target_surface)):
		return NAN
	return TargetingMath.launch_range(def, unit.position, unit.eye(), surface,
		{"hero": target.is_hero(), "position": target.position, "kind": target.kind,
		"altitude": target.position.y - target_surface})

func _aim_target(unit: BattleUnit, reach: float) -> BattleUnit:
	var control: Dictionary = fire_controls.get(unit.entity_id, {})
	if not control.is_empty() and unit.input_state.get("aim", false) and unit.input_state.get("slot", "light") == "heavy":
		var controlled: BattleUnit = units.get(int(control.get("target", 0)))
		var eligible := controlled != null and controlled.alive() and controlled.side != unit.side and visible_to_side(controlled, unit.side)
		return units.get(TargetingMath.aim_choice(unit.position, reach, {}, 0,
			{"on": true, "ok": control.ok and eligible, "target": int(control.get("target", 0))}))
	var precise := _projectile_aim(unit, reach)
	var exact := {} if precise.target == null else {"id": precise.target.entity_id, "point": precise.point}
	var exact_id := TargetingMath.aim_choice(unit.position, reach, exact, 0)
	if exact_id != 0:
		return units.get(exact_id)
	var candidates: Array = []
	for target: BattleUnit in units.values():
		if not target.is_hero() or not target.alive() or target.side == unit.side or not visible_to_side(target, unit.side):
			continue
		var point := target.aim_point()
		if not point.is_finite():
			continue
		var obstruction := world.obstruction_hit(unit.eye(), point)
		candidates.append({"id": target.entity_id, "hero": true, "point": point,
			"obstruction": INF if obstruction.is_empty() else unit.eye().distance_to(obstruction.position)})
	return units.get(TargetingMath.cone_acquire(unit.position, unit.eye(), unit.aim_direction(), reach, candidates, unit.aim_anchor))

func _tick_lock(unit: BattleUnit) -> void:
	if not authoritative or over or not unit.alive():
		return
	if clock - unit.lock_check_at < Content.balance.targeting.lockInterval:
		return
	unit.lock_check_at = clock
	if clock - unit.lock_at > Content.constants.LOCK.TTL:
		unit.aim_anchor = 0
	var slot := "heavy" if unit.input_state.get("aim", false) else "light"
	var def := Content.weapon(unit.character, slot, int(unit.upgrades.hw if slot == "heavy" else unit.upgrades.lw) + 1)
	var target := _aim_target(unit, TargetingMath.maximum_range(def))
	var primary := {}
	if target != null:
		var multiplier: float = Content.constants.FAN_RANGE_CENTER_F if def.area == "fan" else 1.0
		primary = {"id": target.entity_id, "distance": unit.position.distance_to(target.position) - target.radius,
			"reach": _launch_range(unit, def, target) * multiplier}
	var flights: Array = []
	var heavy := Content.weapon(unit.character, "heavy", int(unit.upgrades.hw) + 1)
	if heavy.trajectory == "fnf":
		for projectile: Dictionary in projectiles:
			if projectile.actor != unit.entity_id or int(projectile.get("target", 0)) == 0:
				continue
			var pursued: BattleUnit = units.get(int(projectile.target))
			if pursued == null or not pursued.alive() or pursued.side == unit.side or not visible_to_side(pursued, unit.side):
				continue
			flights.append({"id": pursued.entity_id, "distance": unit.position.distance_to(pursued.position) - pursued.radius,
				"reach": _launch_range(unit, heavy, pursued)})
	var candidate := TargetingMath.lock_candidate(primary, flights, unit.lock_keep_index)
	unit.lock_keep_index = candidate.index
	if candidate.id == 0:
		unit.aim_anchor = 0
		return
	_confirm_lock(unit, int(candidate.id))

func _confirm_lock(unit: BattleUnit, target_id: int) -> void:
	if not authoritative or over:
		return
	var target: BattleUnit = units.get(target_id)
	if target == null or not unit.alive() or not target.alive() or target.side == unit.side or not visible_to_side(target, unit.side) or not visible_to(unit, target):
		return
	var slot := "heavy" if unit.input_state.get("aim", false) else "light"
	if slot == "light" and unit.lock_target == target_id and clock - unit.lock_at <= Content.constants.LOCK.TTL:
		var heavy := Content.weapon(unit.character, "heavy", int(unit.upgrades.hw) + 1)
		if clock - unit.aim_off_at <= heavy.projectile.flightCap:
			slot = "heavy"
	var def := Content.weapon(unit.character, slot, int(unit.upgrades.hw if slot == "heavy" else unit.upgrades.lw) + 1)
	var surface := _projectile_surface(unit.position)
	var target_surface := _projectile_surface(target.position)
	if not is_finite(surface) or not is_finite(target_surface):
		return
	var delta := target.position - unit.position
	if not target.is_hero() and target.kind != "heli":
		delta.y = - (unit.position.y - surface)
	var multiplier: float = Content.constants.FAN_RANGE_CENTER_F if def.area == "fan" else 1.0
	var reach: float = def.range * _settlement_range_factor(unit, def, unit.eye(), surface, target, target_surface) * Content.constants.RANGE_TOL * multiplier
	if maxf(0, delta.length() - target.radius) > reach:
		return
	unit.lock_target = target_id
	unit.aim_anchor = target_id
	unit.lock_at = clock

func _projectile_aim(unit: BattleUnit, reach: float) -> Dictionary:
	var origin := unit.eye()
	var end := origin + unit.aim_direction() * reach
	var excluded: Array[RID] = []
	for candidate: BattleUnit in units.values():
		if candidate.side == unit.side or not candidate.alive() or not visible_to_side(candidate, unit.side):
			excluded.append(candidate.hit_area.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2 | 512, excluded)
	query.collide_with_areas = true
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: BattleUnit
	if not hit.is_empty() and hit.collider is Area3D:
		target = hit.collider.get_parent() as BattleUnit
	return {"point": hit.position if not hit.is_empty() else end, "hit": hit, "target": target,
		"missile": int(hit.collider.get_meta("missile", 0)) if not hit.is_empty() else 0}

func _arc_collision(start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _launch_guided(unit: BattleUnit, def: Dictionary, start: Vector3, aim: Vector3, hit: Dictionary, surface: float, reach: float) -> void:
	var target_id := 0
	var launch_def := def.duplicate(true)
	if def.trajectory == "fnf":
		var target := _aim_target(unit, reach)
		if target != null:
			target_id = target.entity_id
	if not hit.is_empty() and hit.collider is Area3D:
		var target := hit.collider.get_parent() as BattleUnit
		if target != null and target.alive() and target.side != unit.side and visible_to_side(target, unit.side):
			if def.trajectory == "guide" and def.type == "launcher" and CombatMath.target_class(target.kind) == "air":
				launch_def.projectile.speed = launch_def.projectile.antiAirSpeed
	var state := ProjectileMotion.launch(launch_def, start, unit.aim_direction(), surface,
		projectile_rng.next(), projectile_rng.next(), aim, target_id)
	state.actor = unit.entity_id
	state.side = unit.side
	state.range = reach
	# Upgrading or switching weapons cannot retune a warhead already in flight.
	state.definition = launch_def
	projectiles.append(state)

func _projectile_surface(point: Vector3) -> float:
	var bottom: float = world.native_data.min_height - 100 if world.native_data != null else -100
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.01, Vector3(point.x, bottom, point.z), 8 | 16 | 32 | 64)
	# The synthetic test world uses only the ordinary static collision layer.
	if world.native_data == null:
		query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN

func _tick_projectiles(delta: float) -> void:
	if not authoritative or over:
		return
	var visibility: Dictionary = {}
	for index in range(projectiles.size() - 1, -1, -1):
		if over:
			return
		var state: Dictionary = projectiles[index]
		var def: Dictionary = state.definition
		if not visibility.has(state.side):
			var shown := {}
			for candidate: BattleUnit in units.values():
				if visible_to_side(candidate, state.side):
					shown[candidate.entity_id] = true
			visibility[state.side] = shown
		var target: BattleUnit = units.get(state.target)
		var target_data := {}
		if target != null and target.alive() and visibility[state.side].has(target.entity_id):
			target_data = {"position": target.global_position, "radius": target.radius}
		var previous := ProjectileMotion.advance(state, def, delta, target_data)
		var segment: Vector3 = state.position - previous
		var hit := {}
		if segment.length() > 0.01:
			var excluded: Array[RID] = []
			# Source client collision candidates contain only currently observed enemies.
			for unit: BattleUnit in units.values():
				if unit.side == state.side or not unit.alive() or not visibility[state.side].has(unit.entity_id):
					excluded.append(unit.hit_area.get_rid())
			var mask := 1 if def.area == "line" else 1 | 2 | 512
			var query := PhysicsRayQueryParameters3D.create(previous, state.position + segment.normalized() * 0.3, mask, excluded)
			query.collide_with_areas = true
			query.hit_back_faces = true
			hit = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			hit = ProjectileMotion.proximity(state, def, previous, target_data)
		var endpoint: Vector3 = hit.position if not hit.is_empty() else state.position
		var terminal := ProjectileMotion.finish(state, def, not hit.is_empty())
		events.append({"type": "shot", "actor": state.actor, "start": previous, "end": endpoint,
			"side": state.side, "slot": state.get("slot", "heavy"), "terminal": terminal})
		if not terminal:
			continue
		projectiles.remove_at(index)
		var attacker: BattleUnit = units.get(state.actor)
		if attacker == null or not attacker.alive():
			continue
		if def.trajectory == "flat":
			if def.area == "line":
				_fire_line(attacker, def, state.origin, endpoint, state.origin_surface)
			elif not hit.is_empty() and hit.collider.has_meta("missile"):
				if state.origin.distance_to(endpoint) <= def.range * Content.constants.RANGE_TOL:
					_damage_missile(attacker, def, int(hit.collider.get_meta("missile")))
			elif not hit.is_empty() and hit.collider is Area3D and hit.collider.get_parent() is BattleUnit:
				var victim: BattleUnit = hit.collider.get_parent()
				var surface := _projectile_surface(victim.position)
				if not is_finite(surface):
					continue
				var target_height: float = victim.position.y - surface if victim.is_hero() else 0.0
				var offset := Vector3(victim.position.x - state.origin.x, target_height - state.shooter_height, victim.position.z - state.origin.z)
				var reach: float = def.range * _settlement_range_factor(attacker, def, state.origin, state.origin_surface, victim, surface) * Content.constants.RANGE_TOL
				if visible_to_side(victim, state.side) and _visible_from(state.origin, victim) and CombatMath.direct_in_range(reach, offset, victim.radius):
					var amount: float = def.dmg * CombatMath.damage_falloff(def, offset.length())
					if def.get("crit", 0) > 0 and rng.next() < def.crit:
						amount *= def.get("critX", 1)
					damage(attacker, victim, def, amount)
			continue
		if state.dud or hit.is_empty():
			continue
		var level := world.layers.impact_level(endpoint)
		var tunnel := world.layers.tunnel_at(Vector2(endpoint.x, endpoint.z))
		var surface: float = tunnel.floor if level == 2 else world.ground_height(endpoint.x, endpoint.z)
		if not is_finite(surface):
			push_error("Projectile impact has no verified standing surface")
			continue
		var height := maxf(endpoint.y, surface + 1)
		# Source burst reports quantize height above the standing surface to decimetres.
		endpoint.y = surface + roundf((height - surface) * 10) / 10
		var friendly := LobFireControl.friendly_impact(def, state.origin, endpoint)
		blast(attacker, def, Vector3(endpoint.x, maxf(0, endpoint.y - surface), endpoint.z), friendly, true, level)

func blast(unit: BattleUnit, def: Dictionary, impact: Vector3, friendly: bool = false, relative_heights: bool = false, impact_level: int = -1) -> void:
	# Coverage deliberately ignores LOS; each victim consumes the original blast bands.
	for target: BattleUnit in units.values():
		if not target.alive() or (target.side == unit.side and not friendly):
			continue
		if impact_level >= 0 and not world.layers.slabs.is_empty() and world.layers.separated(impact_level, Vector2(impact.x, impact.z), Vector2(target.position.x, target.position.z), _unit_level(target)):
			continue
		var position := target.position
		if relative_heights:
			position.y = _missile_target_altitude(target) if target.is_hero() or target.kind == "heli" else 0.0
			if not position.is_finite():
				continue
		var flat := Vector2(impact.x - position.x, impact.z - position.z)
		var horizontal := maxf(0, flat.length() - target.radius)
		var vertical := maxf(0, maxf(position.y - impact.y, impact.y - position.y - target.height))
		var distance := Vector2(horizontal, vertical).length()
		var factor := CombatMath.blast_falloff(def.get("r", 0), distance)
		if factor > 0:
			damage(unit, target, def, def.get("dmg", 0) * factor, friendly)

func _fire_fan(unit: BattleUnit, def: Dictionary) -> void:
	var candidates: Array = []
	var range_buff := 1.0
	for buff in unit.buffs:
		range_buff *= buff.get("mul", {}).get("range", 1.0)
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		if not visible_to_side(target, unit.side) or not visible_to(unit, target):
			continue
		var target_height: float = target.sight_origin().y if target.is_hero() or target.kind in ["heli", "tower"] else target.sight_target().y
		var range_factor := CombatMath.altitude_range(def, unit.sight_origin().y - target_height) * range_buff
		candidates.append({"id": target.entity_id, "kind": target.kind, "position": target.global_position,
			"radius": target.radius, "height": target.height, "range_factor": range_factor})
	for hit in CombatMath.fan_hits(def, unit.eye(), unit.aim_direction(), candidates):
		damage(unit, units[hit.id], def, hit.amount)

func _visible_from(origin: Vector3, target: BattleUnit) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, target.sight_target(), 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _settlement_range_factor(unit: BattleUnit, def: Dictionary, origin: Vector3, origin_surface: float, target: BattleUnit, target_surface: float) -> float:
	var gap: float
	if target.is_hero():
		gap = origin.y - target.eye().y
	else:
		# Source compares two absolute hero eyes, otherwise two heights above their own surfaces.
		var shooter_sight: float = origin.y - origin_surface - unit.height * Content.constants.SELF_F.eye + Content.constants.LOS.EYE_M
		var target_sight: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["base", "tower"] else target.position.y - target_surface + Content.constants.LOS.EYE_M if target.kind == "heli" else Content.constants.LOS.TGT_M
		gap = shooter_sight - target_sight
	var factor := CombatMath.altitude_range(def, gap)
	for buff in unit.buffs:
		if buff.until > clock:
			factor *= buff.get("mul", {}).get("range", 1.0)
	return factor

func _fire_line(unit: BattleUnit, def: Dictionary, origin: Vector3, endpoint: Vector3, origin_surface: float = NAN) -> void:
	var candidates: Array = []
	var segment := endpoint - origin
	if segment.length() < 0.01:
		return
	var maximum: float = def.range * (1 + Content.constants.ALTITUDE.RANGE * Content.constants.ALTITUDE.RANGE_HEAVY_MUL)
	var length := minf(segment.length(), maximum)
	var direction := segment.normalized()
	if not is_finite(origin_surface):
		origin_surface = _projectile_surface(origin)
	if not is_finite(origin_surface):
		return
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		if not visible_to_side(target, unit.side) or not _visible_from(origin, target):
			continue
		var surface := _projectile_surface(target.position)
		if not is_finite(surface):
			continue
		var relative_sample: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["tower", "base"] else Content.constants.LOS.TGT_M + (target.position.y - surface if target.is_hero() or target.kind == "heli" else 0.0)
		candidates.append({"id": target.entity_id, "position": target.position, "radius": target.radius,
			"height": target.height, "sample_y": target.sight_target().y,
			"relative_y": relative_sample - (origin.y - origin_surface),
			"range_factor": _settlement_range_factor(unit, def, origin, origin_surface, target, surface)})
	for hit in CombatMath.line_hits(def, origin, direction, length, candidates):
		damage(unit, units[hit.id], def, hit.amount)
	for missile: Dictionary in missiles.duplicate():
		var relative_origin := Vector3(origin.x, origin.y - origin_surface, origin.z)
		if missile.side != unit.side and MissileMotion.line_contains(def, relative_origin, direction, length, missile.position):
			_damage_missile(unit, def, int(missile.id), relative_origin)

func _acquire_base_target(unit: BattleUnit, reach: float) -> BattleUnit:
	var best: BattleUnit
	var best_distance := INF
	for target: BattleUnit in units.values():
		if not target.alive() or target.side == unit.side:
			continue
		var altitude := _missile_target_altitude(target)
		if not is_finite(altitude):
			continue
		# Native surface rays can put an exactly-on-ceiling hero a few micrometres above it.
		if target.kind in ["drone", "heli", "morph"] and altitude > minf(reach * 0.9, Content.constants.GAME.GUN_CEIL_M) + MissileMotion.NATIVE_HEIGHT_TOLERANCE:
			continue
		var sight: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["base", "tower"] else altitude + (Content.constants.LOS.EYE_M if target.is_hero() or target.kind == "heli" else Content.constants.LOS.TGT_M)
		var distance := Vector2(target.position.x - unit.position.x, target.position.z - unit.position.z).length()
		if distance > reach * CombatMath.altitude_range({}, Content.constants.LOS.TOWER_EYE_M - sight):
			continue
		if target.is_hero():
			distance /= Content.constants.GAME.CREEP_AGGRO_HERO_BIAS
		if distance >= best_distance or not visible_to(unit, target):
			continue
		best_distance = distance
		best = target
	return best

func _tick_base_guns(unit: BattleUnit, guns: Dictionary, delta: float) -> void:
	if not authoritative or over or not unit.alive():
		return
	if unit.gun_cooldowns.is_empty():
		unit.gun_cooldowns.resize(int(guns.n))
		unit.gun_cooldowns.fill(0.0)
	for index in range(unit.gun_cooldowns.size()):
		unit.gun_cooldowns[index] = maxf(0, unit.gun_cooldowns[index] - delta)
		if unit.gun_cooldowns[index] > 0:
			continue
		var target := _acquire_base_target(unit, guns.range)
		if target == null:
			continue
		var config: Dictionary = Content.constants.BASE_MISSILE
		var offset: float = Content.balance.missile.launchOffset * (1 if index == 0 else -1)
		var origin := Vector3(unit.position.x + offset, config.LAUNCH_Y, unit.position.z)
		if not is_finite(world.ground_height(origin.x, origin.z)):
			continue
		unit.gun_cooldowns[index] = 1.0 / guns.rate
		var definition: Dictionary = Content.constants.STRUCT_W.base
		_launch_missile({"actor": unit.entity_id, "side": unit.side, "target": target.entity_id,
			"position": origin, "origin": origin, "speed": config.SPEED, "dmg": guns.dmg,
			"pen": definition.pen, "r": definition.r, "hp": config.HP, "max_hp": config.HP,
			"ttl": guns.range / config.SPEED + config.TTL_PAD, "range": guns.range})
		events.append({"type": "shot", "actor": unit.entity_id, "start": _missile_world_position(origin),
			"end": _missile_world_position(origin), "side": unit.side, "gun": index})

func _launch_missile(state: Dictionary) -> void:
	if not authoritative or over:
		return
	state.id = next_id
	next_id += 1
	missiles.append(state)
	_sync_missile_bodies()

func _missile_world_position(point: Vector3) -> Vector3:
	return Vector3(point.x, world.ground_height(point.x, point.z) + point.y, point.z)

func _missile_target_altitude(target: BattleUnit) -> float:
	if not target.is_hero() and target.kind != "heli":
		return 0.0
	var surface := _height_reference(target) if target.is_hero() else world.ground_height(target.position.x, target.position.z)
	return target.position.y - surface

func _height_reference(unit: BattleUnit) -> float:
	var surface := _projectile_surface(unit.position)
	var ground := world.ground_height(unit.position.x, unit.position.z)
	if not is_finite(surface) or not is_finite(ground):
		return NAN
	return world.layers.player_reference(unit.position, surface, ground)

func _unit_level(unit: BattleUnit) -> int:
	if unit.kind in ["tower", "base"]:
		return 0
	var spec := {"kind": unit.kind, "hero": unit.is_hero(), "has_lane": unit.has_lane,
		"altitude": _missile_target_altitude(unit)}
	if unit.is_hero() and not unit.is_bot:
		var surface := _projectile_surface(unit.position)
		var ground := world.ground_height(unit.position.x, unit.position.z)
		spec.level = world.layers.player_level(unit.position, surface, ground)
	return world.layers.unit_level(spec, Vector2(unit.position.x, unit.position.z))

func _missile_obstruction(start: Vector3, end: Vector3) -> bool:
	var from := _missile_world_position(start)
	var to := _missile_world_position(end)
	return from.is_finite() and to.is_finite() and not world.obstruction_hit(from, to, false).is_empty()

func _tick_missiles(delta: float) -> void:
	if not authoritative or over:
		return
	for index in range(missiles.size() - 1, -1, -1):
		var state: Dictionary = missiles[index]
		var target: BattleUnit = units.get(int(state.target))
		var target_data := {}
		if target != null and target.alive():
			var altitude := _missile_target_altitude(target)
			if is_finite(altitude):
				target_data.position = Vector3(target.position.x, altitude, target.position.z)
		var outcome := MissileMotion.advance(state, delta, target_data, _missile_obstruction)
		if not outcome.get("remove", false):
			continue
		_remove_missile(int(state.id))
		if outcome.has("blast"):
			var point := _missile_world_position(outcome.blast)
			if not point.is_finite():
				continue
			var owner: BattleUnit = units.get(int(state.actor))
			var detached := owner == null
			if detached:
				owner = BattleUnit.new()
				owner.side = state.side
			var victim: BattleUnit = units.get(int(outcome.get("target", 0)))
			var level := _unit_level(victim) if victim != null else -1
			blast(owner, {"dmg": state.dmg, "pen": state.pen, "r": state.r}, outcome.blast, false, true, level)
			if detached:
				owner.free()
			events.append({"type": "missile_blast", "actor": state.actor, "missile": state.id,
				"position": point, "radius": state.r, "side": state.side})
	_sync_missile_bodies()

func _remove_missile(id: int) -> void:
	for index in range(missiles.size()):
		if int(missiles[index].id) == id:
			missiles.remove_at(index)
			break
	if missile_bodies.has(id):
		var body: MissileBody = missile_bodies[id]
		body.collision_layer = 0
		body.visible = false
		body.queue_free()
		missile_bodies.erase(id)

func _damage_missile(unit: BattleUnit, def: Dictionary, id: int, origin: Vector3 = Vector3(INF, INF, INF)) -> void:
	if not authoritative or over or not unit.alive():
		return
	if def.get("needAim", false) and not unit.input_state.get("aim", false):
		if not origin.is_finite() or clock - unit.aim_off_at > def.projectile.flightCap:
			return
	if not origin.is_finite():
		var altitude := _missile_target_altitude(unit)
		if not is_finite(altitude):
			return
		origin = Vector3(unit.position.x, altitude, unit.position.z)
	for state: Dictionary in missiles:
		if int(state.id) != id or state.side == unit.side:
			continue
		var distance := origin.distance_to(state.position)
		if distance > def.range * Content.constants.RANGE_TOL:
			return
		# Source missiles have no TARGET_CLASS entry, so vsMult is exactly one.
		var amount: float = def.dmg * CombatMath.damage_falloff(def, distance)
		for buff: Dictionary in unit.buffs:
			if buff.until > clock:
				amount *= buff.get("mul", {}).get("dmg", 1.0)
		state.hp -= amount
		if state.hp <= 0:
			var point := _missile_world_position(state.position)
			_remove_missile(id)
			unit.money += Content.constants.ECON.BOUNTY.missile
			events.append({"type": "missile_intercept", "actor": unit.entity_id, "missile": id,
				"position": point, "radius": Content.balance.missile.interceptRadius, "side": unit.side})
		return

func _sync_missile_bodies() -> void:
	for state: Dictionary in missiles:
		var id := int(state.id)
		var point := _missile_world_position(state.position)
		var created := not missile_bodies.has(id)
		if not missile_bodies.has(id):
			var fresh := MissileBody.new()
			# Register collision at the launch pose, without a transient body at the world origin.
			fresh.position = point if point.is_finite() else Vector3.ZERO
			fresh.set_meta("missile", id)
			add_child(fresh)
			missile_bodies[id] = fresh
		var body: MissileBody = missile_bodies[id]
		body.visible = point.is_finite()
		body.collision_layer = 512 if point.is_finite() else 0
		if point.is_finite():
			body.place(point, point - body.position if not created and body.position.is_finite() else Vector3.ZERO)

func damage(attacker: BattleUnit, target: BattleUnit, def: Dictionary, amount: float, friendly: bool = false) -> void:
	var same := target.side == attacker.side
	if not authoritative or over or not target.alive() or (same and not friendly) or amount <= 0:
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
	if attacker.is_hero() and not same:
		attacker.money += Content.constants.ECON.BOUNTY.get(target.kind, 0)
		attacker.score = minf(Content.constants.BATTLE_SCORE.MAX, attacker.score + Content.constants.BATTLE_SCORE.KILL * (Content.constants.BATTLE_SCORE.HARD_F if target.is_hero() or target.kind == "tower" else 1))
	if target.kind == "base":
		over = true
		winner = "STEEL" if target.side == "SWARM" else "SWARM"
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
	unit.visible = unit.presentation_visible
	unit.buffs.clear()
	unit.aim_anchor = 0
	unit.lock_target = 0
	unit.lock_at = -100.0
	unit.aim_off_at = -100.0
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
		if viewer != null and not visible_to_side(unit, viewer.side):
			continue
		visible_units.append(unit.snapshot())
	var visible_ids := {}
	for unit in visible_units:
		visible_ids[unit.id] = true
	var visible_events: Array = events
	if viewer != null:
		visible_events = events.filter(func(event): return event.has("missile") or visible_ids.has(event.actor))
	return {"clock": clock, "wave": wave, "over": over, "winner": winner,
		"units": visible_units, "events": visible_events.duplicate(), "fire_control": _control_snapshot(viewer),
		"lock": _lock_snapshot(viewer), "reachability": _reachability_snapshot(viewer),
		"footprint": _footprint_snapshot(viewer), "missiles": _missile_snapshot()}

func _footprint_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or world == null or over or not viewer.alive() or not viewer.is_hero():
		return {}
	var slot: String = viewer.input_state.get("slot", "light")
	if slot not in ["light", "heavy"]:
		return {}
	var definition := Content.weapon(viewer.character, slot, int(viewer.upgrades.hw if slot == "heavy" else viewer.upgrades.lw) + 1)
	if definition.get("needAim", false) and not viewer.input_state.get("aim", false):
		return {}
	var origin := viewer.eye()
	var maximum := TargetingMath.maximum_range(definition)
	var ray: Dictionary
	if definition.area == "line":
		var end := origin + viewer.aim_direction() * maximum
		var obstruction := _arc_collision(origin, end)
		ray = {"point": obstruction.position if not obstruction.is_empty() else end, "target": null}
	else:
		ray = _projectile_aim(viewer, maximum)
	var targets: Array = []
	for target: BattleUnit in units.values():
		if target.side == viewer.side or not target.alive() or not visible_to_side(target, viewer.side):
			continue
		var dimensions := target.visual_dimensions()
		if dimensions.is_empty():
			continue
		var reach := _launch_range(viewer, definition, target)
		if not is_finite(reach):
			continue
		targets.append({"id": target.entity_id, "kind": target.kind, "position": target.position,
			"radius": target.radius, "height": dimensions.height, "top": dimensions.top, "reach": reach,
			"self": target == viewer, "ally": target.side == viewer.side, "foe": target.side != viewer.side,
			"visible": target.alive() and visible_to_side(target, viewer.side), "dead": not target.alive()})
	var control := {}
	if definition.trajectory == "lob":
		var cached: Dictionary = fire_controls.get(viewer.entity_id, {})
		if cached.is_empty():
			return {}
		if cached.clock != clock or cached.origin != origin or cached.direction != viewer.aim_direction() or int(cached.level) != int(viewer.upgrades.hw):
			return {}
		control = {"on": true, "ok": cached.ok, "close": cached.close, "has_impact": cached.arc.has_impact,
			"impact": cached.arc.impact, "aim": cached.aim}
	var footprint := ShotFootprintMath.evaluate(definition, origin, viewer.aim_direction(), targets,
		{"point": ray.point, "target": ray.target.entity_id if ray.target != null else 0}, control, _arc_collision)
	return {} if footprint.is_empty() else {"hits": footprint.hits, "warn": footprint.warn, "slot": slot, "side": viewer.side}

func apply_footprint(footprint: Dictionary, lock_state: Dictionary = {}) -> void:
	if footprint_glows == null:
		footprint_glows = FootprintGlows.new()
		add_child(footprint_glows)
	footprint_glows.apply(units, footprint, int(lock_state.get("anchor", 0)))

func _reachability_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or world == null or over or not viewer.alive() or not viewer.is_hero():
		return {}
	var slot: String = viewer.input_state.get("slot", "light")
	if slot not in ["light", "heavy"]:
		return {}
	var level := int(viewer.upgrades.hw if slot == "heavy" else viewer.upgrades.lw) + 1
	var definition := Content.weapon(viewer.character, slot, level)
	# Source fan/line footprints have no single-target entrance gate.
	if definition.area in ["fan", "line"]:
		return {}
	var maximum := TargetingMath.maximum_range(definition)
	# Flat rounds and frozen laser points do not steer toward cone candidates.
	var target: BattleUnit
	if definition.trajectory in ["flat", "guide"]:
		target = _projectile_aim(viewer, maximum).target
	else:
		target = _aim_target(viewer, maximum)
	if target == null or not target.alive() or target.side == viewer.side or not visible_to_side(target, viewer.side):
		return {}
	var reach := _launch_range(viewer, definition, target)
	if not is_finite(reach):
		return {}
	var dimensions := target.visual_dimensions()
	if dimensions.is_empty():
		return {}
	var advice := ReachabilityMath.evaluate(definition, viewer.eye(),
		{"position": target.position, "kind": target.kind, "height": dimensions.height, "top": dimensions.top,
			"radius": target.radius}, reach, _arc_collision)
	return {"target": target.entity_id, "slot": slot, "ok": advice.ok, "warn": advice.warn}

func _missile_snapshot() -> Array:
	var states: Array = []
	for state: Dictionary in missiles:
		states.append({"id": state.id, "position": MissileMotion.snapshot_position(state), "hp": ceilf(state.hp), "max_hp": state.max_hp})
	return states

func _lock_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or over or not viewer.alive() or clock - viewer.lock_at > Content.constants.LOCK.TTL:
		return {}
	var target: BattleUnit = units.get(viewer.lock_target)
	if target == null or not target.alive() or target.side == viewer.side or not visible_to_side(target, viewer.side):
		return {}
	return {"target": target.entity_id, "confirmed_at": viewer.lock_at, "anchor": viewer.aim_anchor}

func _control_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or over or not viewer.alive() or not viewer.input_state.get("aim", false) or viewer.input_state.get("slot", "light") != "heavy":
		return {}
	var control: Dictionary = fire_controls.get(viewer.entity_id, {})
	if control.is_empty():
		return {}
	return {"points": control.arc.points, "impact": control.arc.impact, "has_impact": control.arc.has_impact,
		"ok": control.ok, "aa": control.aa, "high": control.high, "close": control.close, "side": viewer.side,
		"elevation": CockpitPose.barrel_elevation(control.velocity, control.direction)}

func apply_snapshot(data: Dictionary) -> void:
	if authoritative or data.clock < clock:
		return
	clock = data.clock
	var received_missiles: Array[Dictionary] = []
	for state: Dictionary in data.get("missiles", []):
		received_missiles.append(state)
	var received_ids: Array = received_missiles.map(func(state): return int(state.id))
	for id: int in missile_bodies.keys():
		if not received_ids.has(id):
			_remove_missile(id)
	missiles = received_missiles
	_sync_missile_bodies()
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
