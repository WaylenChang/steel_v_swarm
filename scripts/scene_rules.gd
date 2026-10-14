class_name SceneRules
extends RefCounted

static func physical(kind: String) -> bool:
	return Content.constants.SCENE_STRUCT.TYPE.has(kind)

static func hash_value(x: float, native_z: float, kind: String = "") -> float:
	var value := 2166136261
	var key := "%d:%d:%s" % [int(floorf(x * 10 + 0.5)), int(floorf(-native_z * 10 + 0.5)), kind]
	for index in range(key.length()):
		value = ((value ^ key.unicode_at(index)) * 16777619) & 0xffffffff
	return float(value % 10000) / 10000

static func hp(kind: String, radius: float, scale_factor: float, x: float, native_z: float) -> float:
	var cfg: Dictionary = Content.constants.SCENE_STRUCT
	if not physical(kind):
		return 0.0
	var scale_value := scale_factor if scale_factor != 0 else 1.0
	var base: float = Content.constants.UNITS.base.hp
	var size := 0.6 + 0.4 * radius * scale_value / float(cfg.R_REF)
	var jitter := 1 + (hash_value(x, native_z, kind) - 0.5) * 2 * float(cfg.JITTER)
	return clampf(floorf(base * float(cfg.TYPE[kind].f) * size * jitter + 0.5), 40, base * float(cfg.MAX_F))

static func armor(kind: String, health: float) -> float:
	if not physical(kind):
		return 0.0
	return clampf(floorf(float(Content.constants.SCENE_STRUCT.TYPE[kind].armor) + health / 500 + 0.5), 0, 40)

static func electric_vehicle(x: float, native_z: float) -> bool:
	return hash_value(x, native_z, "ev") < float(Content.constants.SCENE_STRUCT.EV_FRACTION)

static func vehicle_fire_seconds(electric: bool) -> float:
	var cfg: Dictionary = Content.constants.SCENE_STRUCT
	return floorf(float(cfg.VEH_FIRE_TTL_S) * (float(cfg.EV_FIRE_MUL) if electric else 1.0) + 0.5)

static func fire_seconds(maximum_hp: float) -> float:
	var cfg: Dictionary = Content.constants.SCENE_STRUCT
	var cap := float(Content.constants.UNITS.base.hp) * float(cfg.MAX_F)
	var fraction := clampf(maximum_hp / cap, 0, 1)
	return floorf(float(cfg.FIRE_TTL_MIN) + (float(cfg.FIRE_TTL_MAX) - float(cfg.FIRE_TTL_MIN)) * fraction + 0.5)

static func collapse_pose(id: int, original_scale: Vector3, original_rotation: Vector3, progress: float) -> Dictionary:
	var sign_value := 1.0 if id % 2 == 0 else -1.0
	return {"scale": Vector3(original_scale.x, original_scale.y * (1 - 0.65 * progress), original_scale.z),
		"rotation": original_rotation + Vector3(0.08 * progress, 0, sign_value * 0.12 * progress)}

static func loot_plan(random: SourceRng, x: float, native_z: float, treasure_class: float) -> Dictionary:
	var cfg: Dictionary = Content.constants.LOOT
	var roll := random.next() + treasure_class * float(cfg.TC.SHIFT)
	var tier: Dictionary = cfg.TIERS[-1]
	for candidate: Dictionary in cfg.TIERS:
		roll -= float(candidate.p)
		if roll <= 0:
			tier = candidate
			break
	var result := {"x": x + (random.next() - 0.5) * 6, "z": native_z - (random.next() - 0.5) * 6, "ttl": cfg.TTL_S}
	if tier.get("ammo", false):
		result.ammo = true
	elif tier.get("affix", false):
		var ids := Content.constants.AFFIXES.keys()
		result.affix = ids[int(floorf(random.next() * ids.size()))]
	else:
		result.value = floorf(float(tier.min) + random.next() * (float(tier.max) - float(tier.min)) + 0.5)
	return result

static func lane_distance(lanes: Array, x: float, z: float) -> float:
	var best := INF
	for lane: Array in lanes:
		for index in range(1, lane.size()):
			var a: Array = lane[index - 1]
			var b: Array = lane[index]
			var dx := float(b[0]) - float(a[0])
			var dz := float(b[1]) - float(a[1])
			var square := dx * dx + dz * dz
			if square == 0:
				square = 1.0
			var t := clampf(((x - float(a[0])) * dx + (z - float(a[1])) * dz) / square, 0, 1)
			var ox := x - (float(a[0]) + dx * t)
			var oz := z - (float(a[1]) + dz * t)
			best = minf(best, sqrt(ox * ox + oz * oz))
			if best == 0:
				return 0.0
	return best

static func in_bounds(bounds: Dictionary, x: float, z: float, radius: float = 0.0) -> bool:
	return x - radius >= float(bounds.minX) and x + radius <= float(bounds.maxX) and z - radius >= float(bounds.minZ) and z + radius <= float(bounds.maxZ)

static func touches_wet(wet: Callable, x: float, z: float, radius: float) -> bool:
	if int(wet.call(x, z)) > 0:
		return true
	for index in range(8):
		var angle := float(index) / 8 * TAU
		if int(wet.call(x + cos(angle) * radius, z - sin(angle) * radius)) > 0:
			return true
	return false

static func hazard_allowed(state: Dictionary, definition: Dictionary, x: float, z: float, scale_factor: float, wet: Callable, wall: float = INF) -> bool:
	var cfg: Dictionary = Content.constants.FIELD
	var radius := float(definition.r) * scale_factor
	if not in_bounds(state.bounds, x, z, radius) or lane_distance(state.lanes, x, z) - radius < float(cfg.HAZ_LANE_MIN):
		return false
	for side: String in ["SWARM", "STEEL"]:
		var point: Array = state.bases[side]
		var dx := x - float(point[0])
		var dz := z - float(point[1])
		if sqrt(dx * dx + dz * dz) < float(cfg.HAZ_BASE_CLEAR):
			return false
	if touches_wet(wet, x, z, radius):
		return false
	for other: Dictionary in state.footprints:
		if float(other.wall) == wall:
			continue
		var required := radius + float(other.radius)
		if definition.get("block", false) and other.block:
			required = maxf(Content.constants.FIELD.HAZ_GAP, required)
		var dx := x - float(other.x)
		var dz := z - float(other.z)
		if sqrt(dx * dx + dz * dz) < required:
			return false
	return true

static func _lane_position(random: SourceRng, state: Dictionary, lane: int, low: float, high: float) -> Dictionary:
	var cfg: Dictionary = Content.constants.FIELD
	var cumulative: Array = state.cumulative[lane]
	var total := float(cumulative[-1])
	var turns: Array = state.turns[lane]
	var distance := 0.0
	if not turns.is_empty() and random.next() < float(cfg.TURN_BIAS):
		distance = float(turns[int(floorf(random.next() * turns.size()))]) + (random.next() - 0.5) * 2 * float(cfg.TURN_R)
		distance = clampf(distance, total * low, total * high)
	elif random.next() < float(cfg.MID_BIAS):
		distance = total * (low + (random.next() + random.next()) / 2 * (high - low))
	else:
		distance = total * (low + random.next() * (high - low))
	return _point_normal(state, lane, distance)

static func _point_normal(state: Dictionary, lane: int, distance: float) -> Dictionary:
	var cumulative: Array = state.cumulative[lane]
	var points: Array = state.lanes[lane]
	var index := 1
	while index < cumulative.size() - 1 and float(cumulative[index]) < distance:
		index += 1
	var dx := float(points[index][0]) - float(points[index - 1][0])
	var dz := float(points[index][1]) - float(points[index - 1][1])
	var length := sqrt(dx * dx + dz * dz)
	if length == 0:
		length = 1.0
	var point := WaveRules.point_at(points, cumulative, distance)
	return {"x": point.x, "z": point.z, "nx": dz / length, "nz": -dx / length}

static func far_from_structures(state: Dictionary, x: float, z: float, base_clear: float, tower_clear: float) -> bool:
	for side: String in ["SWARM", "STEEL"]:
		var point: Array = state.bases[side]
		if Vector2(x - float(point[0]), z - float(point[1])).length() < base_clear:
			return false
	for tower: Dictionary in state.towers:
		if Vector2(x - float(tower.x), z - float(tower.z)).length() < tower_clear:
			return false
	return true

static func seed_mines(random: SourceRng, state: Dictionary) -> void:
	var cfg: Dictionary = Content.constants.GAME.MINES
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var turns: Array[Dictionary] = []
	for lane in range(state.lanes.size()):
		for point: Array in state.lanes[lane]:
			min_x = minf(min_x, point[0])
			max_x = maxf(max_x, point[0])
			min_z = minf(min_z, point[1])
			max_z = maxf(max_z, point[1])
		for distance: float in state.turns[lane]:
			turns.append(WaveRules.point_at(state.lanes[lane], state.cumulative[lane], distance))
	min_x -= 220
	max_x += 220
	min_z -= 220
	max_z += 220
	state.mines = []
	var wanted: int = int(cfg.PER_LANE) * state.lanes.size()
	for attempt in range(wanted * 80):
		if state.mines.size() >= wanted:
			break
		var x := 0.0
		var z := 0.0
		if not turns.is_empty() and random.next() < float(cfg.CUT_BIAS):
			var point := turns[int(floorf(random.next() * turns.size()))]
			var angle := random.next() * TAU
			var radius := float(cfg.LANE_CLEAR) + random.next() * float(cfg.CUT_R)
			x = point.x + cos(angle) * radius
			z = float(point.z) - sin(angle) * radius
		else:
			x = min_x + random.next() * (max_x - min_x)
			z = max_z - random.next() * (max_z - min_z)
		if not in_bounds(state.bounds, x, z) or lane_distance(state.lanes, x, z) < float(cfg.LANE_CLEAR):
			continue
		if far_from_structures(state, x, z, cfg.BASE_CLEAR, cfg.TOWER_CLEAR):
			state.mines.append({"x": x, "z": z})

static func seed_field_sites(random: SourceRng, state: Dictionary) -> void:
	var cfg: Dictionary = Content.constants.FIELD.AA_SITE
	var sites: Array = []
	var wanted: int = int(Content.constants.FIELD.AA_SITES_PER_LANE) * state.lanes.size()
	for attempt in range(wanted * 30):
		if sites.size() >= wanted:
			break
		var lane := int(floorf(random.next() * state.lanes.size()))
		var point := _lane_position(random, state, lane, 0.1, 0.9)
		var sign_value := -1.0 if random.next() < 0.5 else 1.0
		var offset := float(cfg.laneMin) + random.next() * (float(cfg.laneMax) - float(cfg.laneMin))
		var x := float(point.x) + float(point.nx) * sign_value * offset
		var z := float(point.z) + float(point.nz) * sign_value * offset
		if not in_bounds(state.bounds, x, z, 6) or lane_distance(state.lanes, x, z) < float(cfg.laneMin):
			continue
		if not far_from_structures(state, x, z, cfg.baseClear, cfg.towerClear):
			continue
		var bad := false
		for other: Dictionary in sites:
			if Vector2(x - float(other.x), z - float(other.z)).length() < float(cfg.spacing):
				bad = true
				break
		if bad:
			continue
		sites.append({"x": x, "z": z})
		state.actors.append({"kind": "aasite", "x": x, "z": z, "scale": 1, "hp": cfg.hp, "armor": 0,
			"invulnerable": false, "vehicle": false, "electric": false})
	var relay: Dictionary = Content.constants.FIELD.RELAY
	state.relays = []
	var relays := 0
	for lane in range(state.lanes.size()):
		if relays >= int(relay.PER_LANE) * state.lanes.size():
			break
		var cumulative: Array = state.cumulative[lane]
		var total := float(cumulative[-1])
		for attempt in range(30):
			var point := _point_normal(state, lane, total * (float(relay.dLo) + random.next() * (float(relay.dHi) - float(relay.dLo))))
			var sign_value := -1.0 if random.next() < 0.5 else 1.0
			var offset := float(relay.laneMin) + random.next() * (float(relay.laneMax) - float(relay.laneMin))
			var x := float(point.x) + float(point.nx) * sign_value * offset
			var z := float(point.z) + float(point.nz) * sign_value * offset
			if not in_bounds(state.bounds, x, z, relay.R) or lane_distance(state.lanes, x, z) < float(relay.laneMin):
				continue
			var bad := false
			for obstacle: Dictionary in state.blockers:
				if Vector2(x - float(obstacle.x), z - float(obstacle.z)).length() < float(obstacle.radius) + 10:
					bad = true
					break
			if bad:
				continue
			var entry := {"kind": "relay", "x": x, "z": z, "scale": 1, "hp": 1, "armor": 0,
				"invulnerable": true, "vehicle": false, "electric": false}
			state.actors.append(entry)
			state.relays.append(entry)
			relays += 1
			break

static func flood_effect(floods: Array, point: Vector2, flying: bool, airborne: bool) -> Dictionary:
	if flying or airborne:
		return {"active": false, "slow": 1.0, "jump": 1.0}
	for flood: Dictionary in floods:
		if point.distance_to(Vector2(flood.x, flood.z)) <= float(flood.radius):
			return {"active": true, "slow": minf(float(Content.constants.WATER.SLOW), float(flood.get("slow", Content.constants.WATER.SLOW))),
				"jump": sqrt(float(Content.constants.WATER.SLOW))}
	return {"active": false, "slow": 1.0, "jump": 1.0}

static func airdrop_size(random: SourceRng) -> Dictionary:
	var sizes: Array = Content.constants.AIRDROP.SIZES
	var total := 0.0
	for size: Dictionary in sizes:
		total += float(size.w)
	var roll := random.next() * total
	for size: Dictionary in sizes:
		roll -= float(size.w)
		if roll <= 0:
			return size
	return sizes[0]

static func airdrop_point(random: SourceRng, state: Dictionary, terrain_blocked: Callable) -> Dictionary:
	var cfg: Dictionary = Content.constants.AIRDROP
	var bounds: Dictionary = state.bounds
	for attempt in range(40):
		var x := float(bounds.minX) + random.next() * (float(bounds.maxX) - float(bounds.minX))
		var z := float(bounds.maxZ) - random.next() * (float(bounds.maxZ) - float(bounds.minZ))
		if not in_bounds(bounds, x, z, cfg.PICK_R) or lane_distance(state.lanes, x, z) < float(cfg.LANE_MIN):
			continue
		if not far_from_structures(state, x, z, cfg.BASE_CLEAR, 0):
			continue
		var bad := false
		for obstacle: Dictionary in state.blockers:
			var dx := x - float(obstacle.x)
			var dz := z - float(obstacle.z)
			if sqrt(dx * dx + dz * dz) < float(obstacle.radius) + float(cfg.PICK_R):
				bad = true
				break
		if bad or terrain_blocked.call(x, z):
			continue
		return {"x": x, "z": z}
	return {}

static func corridor_distance(point: Vector2, corridors: Array, tunnel_only: bool = false) -> float:
	var best := INF
	for corridor: Array in corridors:
		if tunnel_only and not corridor[5]:
			continue
		var start := Vector2(corridor[0], -float(corridor[1]))
		var finish := Vector2(corridor[2], -float(corridor[3]))
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, finish)) - float(corridor[4]))
	return best

static func prune_corridors(state: Dictionary, corridors: Array) -> void:
	for index in range(state.actors.size() - 1, -1, -1):
		var actor: Dictionary = state.actors[index]
		var definition: Dictionary = Content.constants.HAZARDS.get(actor.kind, {})
		var radius := float(definition.get("r", 3)) * float(actor.scale)
		if corridor_distance(Vector2(actor.x, actor.z), corridors) >= radius + 2:
			continue
		state.actors.remove_at(index)
		if definition.get("block", false):
			state.blockers = state.blockers.filter(func(obstacle): return float(obstacle.x) != float(actor.x) or float(obstacle.z) != float(actor.z))
	state.mines = state.mines.filter(func(mine): return corridor_distance(Vector2(mine.x, mine.z), corridors, true) >= 2)

static func _record_hazard(state: Dictionary, kind: String, x: float, z: float, scale_factor: float, wall: int, vehicle: bool = false) -> void:
	var definition: Dictionary = Content.constants.HAZARDS[kind]
	var health := hp(kind, definition.r, scale_factor, x, z) if physical(kind) else 1.0
	var radius := float(definition.r) * scale_factor
	state.actors.append({"kind": kind, "x": x, "z": z, "scale": scale_factor, "hp": health,
		"armor": armor(kind, health) if physical(kind) else 0.0, "invulnerable": not physical(kind), "vehicle": vehicle,
		"electric": electric_vehicle(x, z) if kind == "car" else false})
	if definition.get("block", false):
		state.blockers.append({"x": x, "z": z, "radius": radius})
	state.footprints.append({"x": x, "z": z, "radius": radius, "block": definition.get("block", false), "wall": wall})

static func seed_hazards(random: SourceRng, state: Dictionary, wet: Callable, mix: Dictionary = {}) -> void:
	var cfg: Dictionary = Content.constants.FIELD
	var types: Array = Content.constants.HAZARDS.keys().filter(func(kind): return not Content.constants.HAZARDS[kind].get("parked", false))
	var weights: Array = []
	var sum := 0.0
	for kind: String in types:
		var weight := float(mix.get(Content.constants.HAZARDS[kind].biome, 0)) + 0.05 if not mix.is_empty() else 1.0
		weights.append(weight)
		sum += weight
	state.blockers = []
	state.footprints = []
	state.actors = []
	var wanted: int = int(cfg.HAZ_PER_LANE) * state.lanes.size()
	var placed := 0
	for attempt in range(wanted * 20):
		if placed >= wanted:
			break
		var roll := random.next() * sum
		var kind: String = types[0]
		for index in range(types.size()):
			roll -= float(weights[index])
			if roll <= 0:
				kind = types[index]
				break
		var definition: Dictionary = Content.constants.HAZARDS[kind]
		var lane := int(floorf(random.next() * state.lanes.size()))
		var point := _lane_position(random, state, lane, 0.08, 0.92)
		var sign_value := -1.0 if random.next() < 0.5 else 1.0
		var offset := float(cfg.HAZ_LANE_MIN) + (float(cfg.HAZ_LANE_MAX) - float(cfg.HAZ_LANE_MIN)) * pow(random.next(), cfg.HAZ_EDGE_BIAS)
		var count := 1 + int(floorf(random.next() * float(cfg.CLUSTER_MAX)))
		var wall: int = state.footprints.size()
		for member in range(count):
			if placed >= wanted:
				break
			var x := float(point.x) + float(point.nx) * sign_value * offset + (random.next() - 0.5) * float(definition.r) * 3
			var z := float(point.z) + float(point.nz) * sign_value * offset - (random.next() - 0.5) * float(definition.r) * 3
			var scale_factor := floorf((0.75 + random.next() * 0.6) * 100 + 0.5) / 100
			if not hazard_allowed(state, definition, x, z, scale_factor, wet, wall):
				continue
			_record_hazard(state, kind, x, z, scale_factor, wall)
			placed += 1

static func seed_vehicles(random: SourceRng, state: Dictionary, wet: Callable) -> void:
	var cfg: Dictionary = Content.constants.FIELD.VEHICLES
	var cars := 0
	for attempt in range(int(cfg.CARS) * 30):
		if cars >= int(cfg.CARS):
			break
		var lane := int(floorf(random.next() * state.lanes.size()))
		var point := _lane_position(random, state, lane, 0.08, 0.92)
		var sign_value := -1.0 if random.next() < 0.5 else 1.0
		var offset := float(cfg.CAR_LANE_MIN) + random.next() * (float(cfg.CAR_LANE_MAX) - float(cfg.CAR_LANE_MIN))
		var x := float(point.x) + float(point.nx) * sign_value * offset
		var z := float(point.z) + float(point.nz) * sign_value * offset
		var scale_factor := floorf((0.9 + random.next() * 0.2) * 100 + 0.5) / 100
		if not hazard_allowed(state, Content.constants.HAZARDS.car, x, z, scale_factor, wet, state.footprints.size()):
			continue
		_record_hazard(state, "car", x, z, scale_factor, state.footprints.size(), true)
		cars += 1
	var ships := 0
	for attempt in range(int(cfg.SHIPS) * int(cfg.SHIP_TRIES)):
		if ships >= int(cfg.SHIPS):
			break
		var x := float(state.bounds.minX) + random.next() * (float(state.bounds.maxX) - float(state.bounds.minX))
		var z := float(state.bounds.maxZ) - random.next() * (float(state.bounds.maxZ) - float(state.bounds.minZ))
		var scale_factor := floorf((0.85 + random.next() * 0.15) * 100 + 0.5) / 100
		var radius := float(Content.constants.HAZARDS.ship.r) * scale_factor
		if not in_bounds(state.bounds, x, z, radius) or int(wet.call(x, z)) != 1 or lane_distance(state.lanes, x, z) - radius < float(Content.constants.FIELD.HAZ_LANE_MIN):
			continue
		var bad := false
		for side: String in ["SWARM", "STEEL"]:
			var point: Array = state.bases[side]
			var dx := x - float(point[0])
			var dz := z - float(point[1])
			if sqrt(dx * dx + dz * dz) < float(Content.constants.FIELD.HAZ_BASE_CLEAR):
				bad = true
				break
		if bad:
			continue
		for other: Dictionary in state.footprints:
			var dx := x - float(other.x)
			var dz := z - float(other.z)
			if sqrt(dx * dx + dz * dz) < radius + float(other.radius):
				bad = true
				break
		if bad:
			continue
		_record_hazard(state, "ship", x, z, scale_factor, state.footprints.size(), true)
		ships += 1

static func ensure_connectivity(state: Dictionary) -> void:
	var cell: float = Content.constants.FIELD.CONNECT_CELL_M
	var start: Array = state.bases.SWARM
	var finish: Array = state.bases.STEEL
	var min_x := minf(start[0], finish[0])
	var max_x := maxf(start[0], finish[0])
	var min_z := minf(-float(start[1]), -float(finish[1]))
	var max_z := maxf(-float(start[1]), -float(finish[1]))
	for lane: Array in state.lanes:
		for point: Array in lane:
			min_x = minf(min_x, point[0])
			max_x = maxf(max_x, point[0])
			min_z = minf(min_z, -float(point[1]))
			max_z = maxf(max_z, -float(point[1]))
	min_x -= cell * 2
	max_x += cell * 2
	min_z -= cell * 2
	max_z += cell * 2
	var width := ceili((max_x - min_x) / cell)
	var height := ceili((max_z - min_z) / cell)
	var index := func(x, z): return Vector2i(clampi(floori((x - min_x) / cell), 0, width - 1), clampi(floori((-z - min_z) / cell), 0, height - 1))
	var samples: Array = [finish]
	for lane in range(state.lanes.size()):
		var cumulative: Array = state.cumulative[lane]
		var total := float(cumulative[-1])
		if total <= 0:
			continue
		var distance := 0.0
		while distance < total:
			var point := WaveRules.point_at(state.lanes[lane], cumulative, distance)
			samples.append([point.x, point.z])
			distance += cell
		var end := WaveRules.point_at(state.lanes[lane], cumulative, total)
		samples.append([end.x, end.z])
	for attempt in range(12):
		if state.blockers.is_empty():
			break
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(0, 0, width, height)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		grid.update()
		for obstacle: Dictionary in state.blockers:
			var radius := float(obstacle.radius) + 2.5
			for row in range(floori((-float(obstacle.z) - radius - min_z) / cell), floori((-float(obstacle.z) + radius - min_z) / cell) + 1):
				for column in range(floori((float(obstacle.x) - radius - min_x) / cell), floori((float(obstacle.x) + radius - min_x) / cell) + 1):
					if column >= 0 and row >= 0 and column < width and row < height:
						grid.set_point_solid(Vector2i(column, row))
		var beginning: Vector2i = index.call(start[0], start[1])
		grid.set_point_solid(beginning, false)
		var missed: Variant = null
		for point: Array in samples:
			var goal: Vector2i = index.call(point[0], point[1])
			if grid.is_point_solid(goal) or grid.get_id_path(beginning, goal).is_empty():
				missed = point
				break
		if missed == null:
			break
		var nearest := 0
		var minimum := INF
		for candidate in range(state.blockers.size()):
			var obstacle: Dictionary = state.blockers[candidate]
			var dx := float(obstacle.x) - float(missed[0])
			var dz := float(obstacle.z) - float(missed[1])
			var distance := sqrt(dx * dx + dz * dz)
			if distance < minimum:
				minimum = distance
				nearest = candidate
		var removed: Dictionary = state.blockers.pop_at(nearest)
		for actor in range(state.actors.size()):
			if float(state.actors[actor].x) == float(removed.x) and float(state.actors[actor].z) == float(removed.z):
				state.actors.remove_at(actor)
				break
