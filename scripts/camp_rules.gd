class_name CampRules
extends RefCounted

static func clears_building_instance(frame: Transform3D, camps: Array) -> bool:
	var x := frame.basis.x
	var z := frame.basis.z
	var sx := sqrt(float(x.x) * float(x.x) + float(x.y) * float(x.y) + float(x.z) * float(x.z))
	if sx == 0:
		return false
	var sz := sqrt(float(z.x) * float(z.x) + float(z.y) * float(z.y) + float(z.z) * float(z.z))
	var footprint := sqrt(sx * sx + sz * sz) / 2 * float(Content.balance.structure.instanceClearanceFactor)
	for camp: Dictionary in camps:
		var dx := float(frame.origin.x) - float(camp.x)
		var dz := float(frame.origin.z) + float(camp.z)
		if sqrt(dx * dx + dz * dz) - footprint < float(Content.constants.THIRD.BLD_CLEAR_R):
			return true
	return false

static func cleared_buildings(records: Array, camps: Array) -> Dictionary:
	var removed := {}
	for record: Dictionary in records:
		var bounds: Dictionary = record.bounds
		var width := float(bounds.w)
		var depth := float(bounds.d)
		var reach := float(Content.constants.THIRD.BLD_CLEAR_R) + sqrt(width * width + depth * depth) / 2
		for camp: Dictionary in camps:
			var dx := float(bounds.x) - float(camp.x)
			var dz := float(bounds.z) + float(camp.z)
			if sqrt(dx * dx + dz * dz) < reach:
				removed[record.key] = true
				break
	return removed

static func removes_blocker(blocker: Dictionary, camps: Array, buildings: Dictionary) -> bool:
	var building: String = blocker.get("buildingKey", "")
	if buildings.has(building):
		return true
	if not blocker.get("bld", false) or not building.is_empty() or blocker.get("osm", false):
		return false
	for camp: Dictionary in camps:
		var dx := float(blocker.x) - float(camp.x)
		var dz := float(blocker.z) + float(camp.z)
		if sqrt(dx * dx + dz * dz) - float(blocker.get("r", 0)) < float(Content.constants.THIRD.BLD_CLEAR_R):
			return true
	return false

static func clearance(obstacles: Array, camps: Array) -> Dictionary:
	var groups := {}
	for obstacle: Dictionary in obstacles:
		var key: String = obstacle.get("buildingKey", "")
		if key.is_empty():
			continue
		var shape: Array = obstacle.shape
		var rx := absf(float(shape[6])) * float(shape[4]) + absf(float(shape[7])) * float(shape[5])
		var rz := absf(float(shape[7])) * float(shape[4]) + absf(float(shape[6])) * float(shape[5])
		var group: Dictionary = groups.get(key, {"minX": INF, "maxX": -INF, "minZ": INF, "maxZ": -INF})
		group.minX = minf(group.minX, float(shape[0]) - rx)
		group.maxX = maxf(group.maxX, float(shape[0]) + rx)
		group.minZ = minf(group.minZ, float(shape[1]) - rz)
		group.maxZ = maxf(group.maxZ, float(shape[1]) + rz)
		groups[key] = group
	var buildings := {}
	var radius := float(Content.constants.THIRD.BLD_CLEAR_R)
	for key: String in groups:
		var group: Dictionary = groups[key]
		var x := (float(group.minX) + float(group.maxX)) / 2
		var z := (float(group.minZ) + float(group.maxZ)) / 2
		var width := float(group.maxX) - float(group.minX)
		var depth := float(group.maxZ) - float(group.minZ)
		var reach := radius + sqrt(width * width + depth * depth) / 2
		for camp: Dictionary in camps:
			var dx := x - float(camp.x)
			var dz := z + float(camp.z)
			if sqrt(dx * dx + dz * dz) < reach:
				buildings[key] = true
				break
	var removed: Array[int] = []
	for index in range(obstacles.size()):
		var obstacle: Dictionary = obstacles[index]
		var key: String = obstacle.get("buildingKey", "")
		if not key.is_empty():
			if buildings.has(key):
				removed.append(index)
			continue
		var shape: Array = obstacle.shape
		for camp: Dictionary in camps:
			var dx := float(shape[0]) - float(camp.x)
			var dz := float(shape[1]) + float(camp.z)
			if sqrt(dx * dx + dz * dz) < radius:
				removed.append(index)
				break
	return {"removed": removed, "buildings": buildings}

static func seed(random: SourceRng, state: Dictionary, terrain_blocked: Callable) -> Array:
	var cfg: Dictionary = Content.constants.THIRD
	var camps: Array = []
	var tower_clear := float(Content.constants.UNITS.tower.range) * float(cfg.CLEAR_F)
	var base_clear := maxf(float(Content.constants.UNITS.base.range), float(Content.constants.UNITS.base.guns.range)) * float(cfg.CLEAR_F)
	for lane in range(state.lanes.size()):
		var cumulative: Array = state.cumulative[lane]
		var total := float(cumulative[-1])
		for direction in [-1, 1]:
			var best := {}
			var best_score := -INF
			for maximum in [float(cfg.LANE_MAX), float(cfg.LANE_MAX) * 1.6]:
				for attempt in range(320):
					var point := SceneRules._point_normal(state, lane, total * (0.1 + random.next() * 0.8))
					var offset: float = float(cfg.LANE_MIN) + random.next() * (maximum - float(cfg.LANE_MIN))
					var x: float = float(point.x) + float(point.nx) * direction * offset
					var z: float = float(point.z) + float(point.nz) * direction * offset
					if not SceneRules.in_bounds(state.bounds, x, z, 16):
						continue
					var distance := SceneRules.lane_distance(state.lanes, x, z)
					if distance < float(cfg.LANE_MIN) or not SceneRules.far_from_structures(state, x, z, base_clear, tower_clear):
						continue
					var bad := false
					for other: Dictionary in camps:
						if _distance(x, z, other.x, other.z) < float(cfg.SPACING):
							bad = true
							break
					if bad:
						continue
					for obstacle: Dictionary in state.blockers:
						if _distance(x, z, obstacle.x, obstacle.z) < float(obstacle.radius) + 16:
							bad = true
							break
					if bad or terrain_blocked.call(x, z):
						continue
					var score := -absf(distance - (float(cfg.LANE_MIN) + 90))
					if score > best_score:
						best_score = score
						best = {"side": "GUER" if direction < 0 else "MILI", "lane": lane, "x": x, "z": z,
							"exit_angle": atan2(float(point.nz) * direction, -float(point.nx) * direction)}
				if not best.is_empty():
					break
			if not best.is_empty():
				camps.append(best)
	return camps

static func _distance(x: float, z: float, other_x: float, other_z: float) -> float:
	var dx := x - other_x
	var dz := z - other_z
	return sqrt(dx * dx + dz * dz)

static func home(camp: Dictionary, slot: int) -> Dictionary:
	var cfg: Dictionary = Content.constants.THIRD
	var count: int = cfg.COMP[camp.side].size()
	var spread := (float(slot) / (count - 1) - 0.5) * 2 * float(cfg.EXIT_ARC) if count > 1 else 0.0
	var angle := float(camp.exit_angle) + spread
	return {"x": float(camp.x) + cos(angle) * float(cfg.FORM_R), "z": float(camp.z) - sin(angle) * float(cfg.FORM_R)}

static func behavior(state: Dictionary, camp: Dictionary, occupancy: int, delta: float) -> Dictionary:
	var result: Dictionary = state.duplicate()
	if camp.is_empty() or state.kind == "bunker":
		return result
	var cfg: Dictionary = Content.constants.THIRD
	if state.garrison:
		if not camp.bunker:
			return _ungarrison(result, camp)
		result.hp = minf(float(state.max_hp), float(state.hp) + float(state.max_hp) * float(cfg.GAR_REGEN_PS) * delta)
		result.x = camp.x
		result.z = camp.z
		if result.hp >= float(state.max_hp) * float(cfg.GAR_EXIT_F):
			return _ungarrison(result, camp)
		return result
	var distance := _distance(state.x, state.z, camp.x, camp.z)
	if not state.retreat and distance > float(cfg.TETHER_M):
		result.retreat = true
	elif state.retreat and distance <= float(cfg.HOME_R):
		result.retreat = false
	result.seek = false
	if state.kind == "soldier" and camp.bunker and state.hp <= float(state.max_hp) * float(cfg.GAR_ENTER_F):
		if distance > 7:
			result.seek = true
		elif occupancy < int(cfg.GAR_CAP):
			result.garrison = true
			result.retreat = false
			result.x = camp.x
			result.z = camp.z
	return result

static func _ungarrison(state: Dictionary, camp: Dictionary) -> Dictionary:
	state.garrison = false
	var point := home(camp, int(state.slot))
	state.x = point.x
	state.z = point.z
	return state

static func aggro_valid(state: Dictionary, target: Dictionary, now: float) -> bool:
	return not target.is_empty() and now - float(state.aggro_at) <= float(Content.constants.THIRD.AGGRO_TTL) and target.hp > 0 and not target.dead and target.side != state.side and not target.stealth

static func move(state: Dictionary, camp: Dictionary, profile: Dictionary, target: Dictionary, delta: float,
		terrain_blocked: Callable, blockers: Array) -> Dictionary:
	var point := {"x": state.x, "z": state.z}
	if camp.is_empty() or state.garrison or state.stun:
		return point
	var factor := float(state.slow_factor) if state.slow else 1.0
	if state.confuse:
		factor *= 0.5
	if factor <= 0:
		return point
	var goal: Dictionary
	var arrive := 2.0
	if state.retreat or state.seek:
		goal = camp
		arrive = 5.0 if state.seek else float(Content.constants.THIRD.HOME_R) * 0.6
	elif not target.is_empty():
		goal = target
		arrive = maxf(6, float(profile.range) * 0.7)
	else:
		goal = home(camp, int(state.slot))
	var dx := float(goal.x) - float(state.x)
	var dz := float(goal.z) - float(state.z)
	var distance := sqrt(dx * dx + dz * dz)
	if distance <= arrive:
		return point
	var step := minf(distance, float(profile.speed) * factor * delta)
	point.x = float(state.x) + dx / distance * step
	point.z = float(state.z) + dz / distance * step
	if state.kind != "heli":
		if terrain_blocked.call(point.x, point.z) and not terrain_blocked.call(state.x, state.z):
			return {"x": state.x, "z": state.z}
		for obstacle: Dictionary in blockers:
			var gap := _distance(point.x, point.z, obstacle.x, obstacle.z)
			if gap >= float(obstacle.radius) or gap == 0:
				continue
			point.x = float(obstacle.x) + (float(point.x) - float(obstacle.x)) / gap * float(obstacle.radius)
			point.z = float(obstacle.z) + (float(point.z) - float(obstacle.z)) / gap * float(obstacle.radius)
	return point
