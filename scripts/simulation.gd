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
var match_stats: Dictionary = {"SWARM": {"kills": 0, "deaths": 0, "creepKills": 0, "assists": 0},
	"STEEL": {"kills": 0, "deaths": 0, "creepKills": 0, "assists": 0}}
var projectiles: Array[Dictionary] = []
var projectile_rng := SourceRng.new(4242)
var fire_controls: Dictionary = {}
var missiles: Array[Dictionary] = []
var missile_bodies: Dictionary = {}
var footprint_glows: FootprintGlows
var vision_until: Dictionary = {"SWARM": 0.0, "STEEL": 0.0}
var reflecting := false
var fogs: Array[Dictionary] = []
var cubic_cages: Array[Dictionary] = []
var next_field_id := 1
var fog_view: Array = []
var autonomous_summons: Array[int] = []
var hologram_decoys: Array[int] = []
var carrier_states: Dictionary = {}
var npc_phase_sequence := 0
var weather_fog := 0.0
var weather_start: Dictionary = {}
var weather_schedule: Dictionary = {}
var weather_vector: Dictionary = {}
var weather_dynamics: Dictionary = {}
var weather_surface: Dictionary = {}
var weather_seed := 0
var weather_elapsed := 0.0
var weather_accumulator := 0.0
var weather_last_freeze_step := -1
var lightning_timer := 0.0
var creep_upgrades: Dictionary = {"STEEL": [], "SWARM": []}
var npc_index: Array = []
var npc_index_active := false
var npc_accumulator := 0.0
var wave_anchors: Dictionary = {}
var npc_structures: Array = []
var authority_bounds: Dictionary = {}
var fire_fields: Array[Dictionary] = []
var weather_scars: Array[Dictionary] = []
var loots: Array[Dictionary] = []
var hazard_blockers: Array = []
var mines: Array[Dictionary] = []
var relay_states: Array[Dictionary] = []
var airdrops: Array[Dictionary] = []
var next_airdrop := 0.0
var camps: Array[Dictionary] = []
var civilian_respawns: Array[Dictionary] = []
const SUMMON_KINDS := ["drone_wingman", "assault_rover", "heli_squad", "main_battle_tank", "veteran_squad", "carnival_heli"]

func setup(map_data: Dictionary, roster: Array, env: Dictionary, authority: bool) -> void:
	set_physics_process(false)
	authoritative = authority
	authority_bounds = map_data.get("authority_bounds", {}).duplicate()
	world = BattleWorld.new()
	add_child(world)
	await world.build(map_data, env)
	_setup_weather(map_data, env)
	for side: String in creep_upgrades:
		creep_upgrades[side].resize(world.paths.size())
		creep_upgrades[side].fill(0)
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
	next_wave = Content.constants.GAME.FIRST_WAVE_DELAY_S
	next_airdrop = Content.constants.AIRDROP.INTERVAL_S
	_prefill_lanes(map_data)
	_seed_scene_hazards(map_data)
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

func _seed_scene_hazards(map_data: Dictionary) -> void:
	if not map_data.has("lane_turns") or not Content.balance.has("hazard_visuals") or not Content.balance.has("hazard_volumes"):
		push_error("Missing original hazard generation/model metadata; regenerate migration data")
		return
	var bases := {}
	for side: String in ["SWARM", "STEEL"]:
		bases[side] = [float(world.bases[side].x), float(world.bases[side].z)]
	var state := {"lanes": world.lane_points, "cumulative": world.lane_distances, "turns": map_data.lane_turns,
		"bases": bases, "bounds": authority_bounds, "towers": []}
	for unit: BattleUnit in units.values():
		if unit.kind == "tower":
			state.towers.append({"x": unit.position.x, "z": unit.position.z})
	var scene_seed := weather_seed ^ (int(map_data.config.get("teamSize", 5)) << 20)
	var random := SourceRng.new(scene_seed)
	SceneRules.seed_mines(random, state)
	SceneRules.seed_hazards(random, state, world.wet_at, map_data.config.get("venue", {}).get("mix", {}))
	SceneRules.seed_vehicles(random, state, world.wet_at)
	SceneRules.ensure_connectivity(state)
	SceneRules.seed_field_sites(random, state)
	SceneRules.prune_corridors(state, world.native_data.corridors)
	for mine: Dictionary in state.mines:
		mine.id = next_id
		next_id += 1
		mines.append(mine)
	hazard_blockers = state.blockers
	for entry: Dictionary in state.actors:
		var surface := world.source_height(entry.x, entry.z)
		if not is_finite(surface):
			push_error("Hazard has no original terrain anchor")
			continue
		if entry.kind == "ship" and world.water_y != null:
			surface = maxf(surface, world.water_y)
		var point := Vector3(entry.x, surface, entry.z)
		if entry.kind in ["fire", "forestfire", "grassfire", "factoryfire"]:
			_spawn_fire(entry.kind, point, entry.scale)
			continue
		var unit := spawn({"kind": entry.kind, "side": "", "position": point,
			"special": {"role": "hazard", "neutral": true, "hp": entry.hp, "armor": entry.armor,
				"scale": entry.scale, "electric": entry.electric, "vehicle": entry.vehicle, "invulnerable": entry.invulnerable,
				"relay_charge": 0.0, "relay_side": ""}})
		if entry.kind == "relay":
			entry.id = unit.entity_id
	# The original corridor prune removes visible relay actors but retains its capture roster.
	for entry: Dictionary in state.relays:
		if not entry.has("id"):
			entry.id = next_id
			next_id += 1
		relay_states.append({"id": entry.id, "position": Vector3(entry.x, 0, entry.z), "charge": 0.0, "side": ""})
	if _camp_content_ready():
		for camp: Dictionary in CampRules.seed(random, state, _terrain_blocked):
			_spawn_camp(camp)
		world.clear_camp_columns(camps)
		_seed_civilians()

func _camp_content_ready() -> bool:
	var profiles: Dictionary = Content.balance.get("companions", {})
	var keys: Array[String] = []
	for side: String in ["GUER", "MILI"]:
		for kind: String in ["bunker"] + Content.constants.THIRD.COMP[side]:
			keys.append("%s_%s" % [side.to_lower(), kind])
	for side: String in ["SWARM", "STEEL"]:
		for profession in range(Content.constants.CIVILIANS.size()):
			keys.append("%s_civilian_%02d" % [side.to_lower(), profession])
	for key: String in keys:
		if not profiles.has(key) or not ResourceLoader.exists("res://assets/companions/%s.scn" % key):
			push_error("Original camp/civilian content is unavailable; regenerate and pack companion resources: " + key)
			return false
	if not Content.balance.has("civilian_appearance"):
		push_error("Missing original civilian appearance tables")
		return false
	return true

func _spawn_camp(info: Dictionary) -> void:
	var camp: Dictionary = info.duplicate()
	camp.bunker = 0
	camp.bunker_remaining = 0.0
	camp.pool = []
	camp.freed = false
	var index := camps.size()
	camps.append(camp)
	camp.bunker = _spawn_camp_unit(index, "bunker", 0).entity_id
	for slot in range(Content.constants.THIRD.COMP[camp.side].size()):
		_spawn_camp_unit(index, Content.constants.THIRD.COMP[camp.side][slot], slot)

func _spawn_camp_unit(index: int, kind: String, slot: int) -> BattleUnit:
	var camp: Dictionary = camps[index]
	var point := {"x": camp.x, "z": camp.z} if kind == "bunker" else CampRules.home(camp, slot)
	var surface := world.source_height(point.x, point.z) if world != null else 0.0
	var altitude := float(Content.constants.GAME.HELI_ALT) if kind == "heli" else 0.0
	return spawn({"kind": kind, "side": camp.side, "position": Vector3(point.x, surface + altitude, point.z),
		"special": {"role": "third", "third": true, "camp_index": index, "slot": slot, "garrison": false,
			"retreat": false, "seek": false, "aggro_id": 0, "aggro_at": 0.0}})

func _camp_state(unit: BattleUnit) -> Dictionary:
	return {"kind": unit.kind, "side": unit.side, "slot": int(unit.special.slot), "x": float(unit.position.x), "z": float(unit.position.z),
		"hp": unit.hp, "max_hp": unit.max_hp, "garrison": unit.special.garrison, "retreat": unit.special.retreat,
		"seek": unit.special.seek, "aggro_at": unit.special.aggro_at,
		"stun": unit.has_status("stun_until", clock), "slow": unit.has_status("slow_until", clock),
		"slow_factor": float(unit.status.get("slow_factor", 0.6)), "confuse": unit.has_status("confuse_until", clock)}

func _set_scalar_point(unit: BattleUnit, point: Dictionary) -> void:
	var height := world.source_height(point.x, point.z) if world != null else 0.0
	if not is_finite(height):
		push_error("Scalar actor has no original terrain anchor")
		return
	unit.position = Vector3(point.x, height + (float(Content.constants.GAME.HELI_ALT) if unit.kind == "heli" else 0.0), point.z)

func _ungarrison(unit: BattleUnit) -> void:
	unit.special.garrison = false
	_set_scalar_point(unit, CampRules.home(camps[int(unit.special.camp_index)], int(unit.special.slot)))
	unit.refresh_collision()

func _camp_behavior(unit: BattleUnit, delta: float) -> void:
	if not authoritative:
		return
	var camp: Dictionary = camps[int(unit.special.camp_index)]
	var count := 0
	for member: BattleUnit in units.values():
		if member.special.get("third", false) and member.special.camp_index == unit.special.camp_index and member.special.get("garrison", false):
			count += 1
	var plan := CampRules.behavior(_camp_state(unit), camp, count, delta)
	var changed: bool = unit.special.garrison != plan.garrison
	unit.hp = plan.hp
	for key: String in ["garrison", "retreat", "seek"]:
		unit.special[key] = plan[key]
	_set_scalar_point(unit, plan)
	if changed:
		unit.refresh_collision()
	unit.visible = unit.presentation_visible and not unit.special.garrison

func _camp_aggro_target(unit: BattleUnit) -> BattleUnit:
	var target: BattleUnit = units.get(int(unit.special.aggro_id))
	if target != null and CampRules.aggro_valid(_camp_state(unit), {"hp": target.hp, "dead": not target.alive(), "side": target.side, "stealth": target.has_status("stealth_until", clock)}, clock):
		return target
	unit.special.aggro_id = 0
	return null

func _move_camp_unit(unit: BattleUnit, profile: Dictionary, delta: float) -> void:
	var camp: Dictionary = camps[int(unit.special.camp_index)]
	var target: BattleUnit
	if not unit.special.retreat and not unit.special.seek and not unit.special.garrison and not unit.has_status("stun_until", clock):
		target = _camp_aggro_target(unit)
		if target == null:
			target = _npc_acquire(unit, {"range": profile.get("sight", profile.range), "wid": profile.get("wid", "")})
	var goal := {"x": target.position.x, "z": target.position.z} if target != null else {}
	_set_scalar_point(unit, CampRules.move(_camp_state(unit), camp, profile, goal, delta, _terrain_blocked, hazard_blockers))

func _tick_camps(delta: float) -> void:
	if not authoritative:
		return
	for index in range(camps.size()):
		var camp: Dictionary = camps[index]
		if not camp.bunker:
			camp.bunker_remaining = float(camp.bunker_remaining) - delta
			if camp.bunker_remaining <= 0:
				camp.bunker = _spawn_camp_unit(index, "bunker", 0).entity_id
			continue
		for slot in range(camp.pool.size() - 1, -1, -1):
			var pending: Dictionary = camp.pool[slot]
			pending.remaining = float(pending.remaining) - delta
			if pending.remaining <= 0:
				camp.pool.remove_at(slot)
				_spawn_camp_unit(index, pending.kind, int(pending.slot))

func _on_third_death(unit: BattleUnit, attacker: BattleUnit) -> void:
	var index := int(unit.special.camp_index)
	var camp: Dictionary = camps[index]
	if unit.kind == "bunker":
		camp.bunker = 0
		camp.bunker_remaining = Content.constants.THIRD.BUNKER_RESPAWN_S
		for member: BattleUnit in units.values():
			if member.special.get("third", false) and int(member.special.camp_index) == index and member.special.get("garrison", false):
				_ungarrison(member)
	else:
		camp.pool.append({"kind": unit.kind, "slot": unit.special.slot, "remaining": Content.constants.THIRD.UNIT_RESPAWN_S})
	if camp.freed:
		return
	for member: BattleUnit in units.values():
		if member.special.get("third", false) and int(member.special.camp_index) == index:
			return
	camp.freed = true
	_free_camp_civilians(camp, attacker)

func _civilian_placement() -> Dictionary:
	var bases := {}
	for side: String in ["SWARM", "STEEL"]:
		bases[side] = [world.bases[side].x, world.bases[side].z]
	return {"bounds": authority_bounds, "lanes": world.lane_points, "bases": bases, "towers": [], "blockers": hazard_blockers}

func _spawn_civilian(side: String, spy: bool, profession: int, point: Dictionary) -> BattleUnit:
	var surface := world.source_height(point.x, point.z) if world != null else 0.0
	return spawn({"kind": "civilian", "side": "", "position": Vector3(point.x, surface, point.z),
		"special": {"role": "civilian", "neutral": true, "civil_side": side, "spy": spy, "profession": profession,
			"home": Vector2(point.x, point.z), "waypoint": null, "pause": rng.next() * float(Content.constants.CIVILIAN.WANDER_PAUSE[1]),
			"follow_peer": 0, "follow_time": 0.0, "flee": false, "flee_ttl": 0.0, "flee_point": Vector2.ZERO, "no_respawn": false}})

func _seed_civilians() -> void:
	if not authoritative:
		return
	var cfg: Dictionary = Content.constants.CIVILIAN
	var placement := _civilian_placement()
	var count: int = int(cfg.PER_SIDE_BASE) + int(cfg.PER_SIDE_PER_LANE) * placement.lanes.size()
	var spies := int(floorf(count * float(cfg.SPY_RATE) + 0.5))
	for side: String in ["SWARM", "STEEL"]:
		for index in range(count):
			var point := CivilianRules.point(rng, placement, _terrain_blocked)
			if not point.is_empty():
				_spawn_civilian(side, index < spies, int(floorf(rng.next() * Content.constants.CIVILIANS.size())), point)

func _free_camp_civilians(camp: Dictionary, attacker: BattleUnit) -> void:
	if not authoritative:
		return
	var owner: BattleUnit = attacker if attacker != null and attacker.is_hero() and pilots.has(attacker.peer_id) and attacker.alive() else null
	if owner == null:
		var nearest := INF
		for unit: BattleUnit in pilots.values():
			var distance := _planar_distance(unit.position, Vector3(camp.x, 0, camp.z))
			if unit.alive() and distance < nearest:
				nearest = distance
				owner = unit
	var count := int(Content.constants.THIRD.CLEAR_CIVS)
	for index in range(count):
		var angle := float(index) / count * TAU
		var point := {"x": float(camp.x) + cos(angle) * float(Content.constants.THIRD.FORM_R), "z": float(camp.z) - sin(angle) * float(Content.constants.THIRD.FORM_R)}
		var side := "SWARM" if rng.next() < 0.5 else "STEEL"
		var civilian := _spawn_civilian(side, false, int(floorf(rng.next() * Content.constants.CIVILIANS.size())), point)
		civilian.special.no_respawn = true
		civilian.special.home = Vector2(camp.x, camp.z)
		if owner != null:
			civilian.special.follow_peer = owner.peer_id
	if owner != null:
		events.append({"type": "civfree", "actor": owner.entity_id, "peer": owner.peer_id, "side": owner.side, "position": Vector3(camp.x, 0, camp.z), "count": count})

func _move_civilian(unit: BattleUnit, goal: Vector2, movement_speed: float, delta: float, away: bool = false) -> void:
	var point := CivilianRules.move({"x": unit.position.x, "z": unit.position.z}, goal, movement_speed, delta, authority_bounds, _terrain_blocked, away)
	if not point.is_empty():
		_set_scalar_point(unit, point)
		unit.yaw = point.yaw
		unit.rotation.y = unit.yaw

func _tick_civilians(delta: float) -> void:
	if not authoritative:
		return
	var cfg: Dictionary = Content.constants.CIVILIAN
	var placement := _civilian_placement()
	var remaining: Array[Dictionary] = []
	for pending: Dictionary in civilian_respawns:
		if clock < float(pending.at):
			remaining.append(pending)
			continue
		var point := CivilianRules.point(rng, placement, _terrain_blocked)
		if point.is_empty():
			remaining.append(pending)
		else:
			_spawn_civilian(pending.side, pending.spy, int(floorf(rng.next() * Content.constants.CIVILIANS.size())), point)
	civilian_respawns = remaining
	for unit: BattleUnit in units.values():
		if unit.special.get("role") != "civilian":
			continue
		var state: Dictionary = unit.special
		var movement_speed := CivilianRules.speed(state.spy)
		if state.flee:
			state.flee_ttl = float(state.flee_ttl) - delta
			if state.flee_ttl <= 0:
				_remove_field_unit(unit.entity_id)
			else:
				_move_civilian(unit, state.flee_point, movement_speed * float(cfg.FLEE_SPEED_F), delta, true)
			continue
		if int(state.follow_peer) != 0:
			var owner: BattleUnit = pilots.get(int(state.follow_peer))
			if owner == null or not owner.alive() or _planar_distance(unit.position, owner.position) > float(cfg.FOLLOW_LINK_M):
				state.follow_peer = 0
				state.follow_time = 0.0
			else:
				if _planar_distance(unit.position, owner.position) > float(cfg.FOLLOW_R):
					_move_civilian(unit, Vector2(owner.position.x, owner.position.z), movement_speed, delta)
				if state.civil_side == owner.side:
					state.follow_time = float(state.follow_time) + delta
					if state.follow_time >= float(cfg.FOLLOW_REWARD_S):
						state.follow_time -= float(cfg.FOLLOW_REWARD_S)
						var event := {"type": "civaid", "actor": owner.entity_id, "peer": owner.peer_id, "civilian": unit.entity_id, "profession": state.profession, "side": owner.side, "position": unit.position}
						event.merge(_grant_reward(owner, Content.constants.CIVILIANS[int(state.profession)].reward, cfg.FOLLOW_MUL))
						events.append(event)
				continue
		if state.pause > 0:
			state.pause = float(state.pause) - delta
			continue
		if state.waypoint == null or Vector2(unit.position.x, unit.position.z).distance_to(state.waypoint) < 2:
			var point := CivilianRules.wander(rng, placement, state.home, _terrain_blocked)
			state.waypoint = Vector2(point.x, point.z)
			state.pause = float(cfg.WANDER_PAUSE[0]) + rng.next() * (float(cfg.WANDER_PAUSE[1]) - float(cfg.WANDER_PAUSE[0]))
			continue
		_move_civilian(unit, state.waypoint, movement_speed, delta)

func _civilian_interact(unit: BattleUnit, id: int, action_name: String) -> void:
	var target: BattleUnit = units.get(id)
	if not authoritative or over or not unit.alive() or target == null or not target.alive() or target.special.get("role") != "civilian":
		return
	if _planar_distance(unit.position, target.position) > float(Content.constants.CIVILIAN.INTERACT_R) * 1.25:
		return
	var state: Dictionary = target.special
	state.follow_time = 0.0
	if action_name == "away":
		state.follow_peer = 0
		state.flee = true
		state.flee_ttl = Content.constants.CIVILIAN.FLEE_TTL_S
		state.flee_point = Vector2(unit.position.x, unit.position.z)
	else:
		state.flee = false
		state.follow_peer = unit.peer_id
	events.append({"type": "civact", "actor": unit.entity_id, "peer": unit.peer_id, "action": "away" if action_name == "away" else "follow", "position": target.position, "civil_side": state.civil_side})

func nearest_civilian(unit: BattleUnit) -> BattleUnit:
	if not unit.alive():
		return null
	var target: BattleUnit
	var best := float(Content.constants.CIVILIAN.INTERACT_R)
	for civilian: BattleUnit in units.values():
		if civilian.special.get("role") != "civilian" or not civilian.visible:
			continue
		var distance := _planar_distance(unit.position, civilian.position)
		if distance < best:
			best = distance
			target = civilian
	return target

func _kill_civilian(unit: BattleUnit, attacker: BattleUnit) -> void:
	var state: Dictionary = unit.special.duplicate(true)
	var point := unit.position
	_remove_field_unit(unit.entity_id, true)
	if attacker != null and attacker.is_hero():
		var amount := CivilianRules.kill_reward(attacker.side == state.civil_side, state.spy)
		attacker.money = maxf(0, attacker.money + amount)
		events.append({"type": "civkill", "actor": attacker.entity_id, "peer": attacker.peer_id, "side": attacker.side, "position": point, "value": amount, "spy": state.spy, "civil_side": state.civil_side})
	if not state.no_respawn:
		civilian_respawns.append({"side": state.civil_side, "spy": state.spy, "at": clock + float(Content.constants.CIVILIAN.RESPAWN_S)})

func _setup_weather(map_data: Dictionary, environment: Dictionary) -> void:
	if not Content.balance.has("weather"):
		push_error("Missing source weather rules; regenerate migration data before running the battle")
		return
	var center: Dictionary = map_data.config.get("center", {})
	weather_start = {"season": environment.get("season", "summer"), "time": environment.get("time", "day"),
		"weather": environment.get("weather", "clear"), "latitude": center.get("lat", 25.0)}
	weather_seed = int(floorf(float(center.get("lat", 0)) * 10000 + 0.5)) * 31 + int(floorf(float(center.get("lng", 0)) * 10000 + 0.5))
	weather_schedule = WeatherRules.solar_schedule(weather_start.season, weather_start.latitude, 0, int(environment.get("lunarDay", 15)))
	weather_vector = WeatherRules.vector_at(weather_start.season, weather_start.time, weather_start.weather, 0, weather_seed, weather_start.latitude)
	weather_dynamics = WeatherRules.dynamics(weather_vector)
	weather_surface = WeatherRules.surface_step()
	weather_fog = weather_dynamics.fog
	world.sync_weather(weather_dynamics, weather_surface, WeatherRules.clock_hour(weather_start.time, 0, weather_schedule), weather_schedule, weather_start.season, weather_seed)

func _weather_air(unit: BattleUnit) -> bool:
	return unit.flying or (unit.is_hero() and _air_unit(unit)) or unit.kind == "heli" or CombatMath.target_class(unit.kind) == "air" or _missile_target_altitude(unit) > 0

func _update_fluid_state(unit: BattleUnit) -> void:
	if world == null or world.native_data == null or world.native_data.water_profile.is_empty():
		return
	var surface := _movement_surface(unit.position)
	var bare := world.source_height(unit.position.x, unit.position.z)
	if not is_finite(surface) or not is_finite(bare):
		return
	unit.fluid_environment = EnvironmentRules.environment(world.water_code(unit.position.x, unit.position.z), world.water_y,
		unit.position.y, unit.height, bool(weather_dynamics.get("isFrozen", false)), unit.flying, surface, bare)
	unit.wet = int(unit.fluid_environment.code)

func _movement_surface(point: Vector3) -> float:
	var surface := _weapon_surface(point)
	var tunnel := world.layers.tunnel_at(Vector2(point.x, point.z))
	if not tunnel.is_empty() and point.y < float(tunnel.ceil):
		return surface
	return EnvironmentRules.ice_surface(surface, point.y, world.water_plane(point.x, point.z), bool(weather_dynamics.get("isFrozen", false)))

func _ice_ceiling(point: Vector3) -> Variant:
	return EnvironmentRules.ice_ceiling(null, point.y, world.water_plane(point.x, point.z), bool(weather_dynamics.get("isFrozen", false)))

func weather_attack_rate(unit: BattleUnit) -> float:
	if weather_dynamics.is_empty():
		return 1.0
	return WeatherRules.air_rate(weather_dynamics) if _weather_air(unit) else WeatherRules.ground_rate(weather_surface)

func weather_movement(_unit: BattleUnit, direction: Vector3, airborne: bool, ground_mode: bool = false) -> float:
	if weather_dynamics.is_empty():
		return 1.0
	var factor := WeatherRules.ground_speed(weather_surface) if ground_mode or not airborne else 1.0
	if airborne:
		factor *= WeatherRules.wind_speed(direction.x, direction.z, weather_dynamics.windDir, weather_dynamics.wind)
	return factor

func _weather_accuracy_penalty() -> float:
	if weather_start.is_empty():
		return 0.0
	return WeatherRules.accuracy_penalty(float(weather_dynamics.get("effectiveFog", 0)), WeatherRules.clock_hour(weather_start.time, clock, weather_schedule), weather_schedule)

func _companion_weather_speed(unit: BattleUnit) -> float:
	return 1.0 if weather_dynamics.is_empty() or _weather_air(unit) else WeatherRules.ground_speed(weather_surface)

func _wave_weather_factor(unit: BattleUnit, controls: Dictionary) -> float:
	if weather_dynamics.is_empty():
		return 1.0
	var airborne := unit.kind == "heli" or CombatMath.target_class(unit.kind) == "air"
	if not airborne:
		return WeatherRules.ground_speed(weather_surface)
	var cumulative: Array = world.lane_distances[unit.lane]
	var points: Array = world.lane_points[unit.lane]
	var progress := unit.npc_progress if unit.side == "SWARM" else float(cumulative[-1]) - unit.npc_progress
	var index := 1
	while index < cumulative.size() - 1 and float(cumulative[index]) < progress:
		index += 1
	var sign_value := (1.0 if unit.side == "SWARM" else -1.0) * (-1.0 if controls.confuse else 1.0)
	return WeatherRules.wind_speed((float(points[index][0]) - float(points[index - 1][0])) * sign_value,
		(float(points[index][1]) - float(points[index - 1][1])) * sign_value, weather_dynamics.windDir, weather_dynamics.wind)

func _lightning_states(unit: BattleUnit, now: float) -> Array:
	var states: Array = []
	for key: String in ["emp_until", "blind_until", "stun_until", "slow_until", "confuse_until", "sup_until", "mark_until", "unbalanced_until",
		"stealth_until", "inv_until", "phase_until", "reflect_until", "rooted_until", "shield_expand_until", "shield_def_boost_until",
		"shield_bash_until", "no_reload_until", "no_light_reload_until", "no_heavy_reload_until", "clones_until", "def_jump_until"]:
		var until: float = unit.status.get(key, 0)
		if until > now:
			states.append([key, until])
	if float(unit.bleed.get("until", 0)) > now:
		states.append(["bleed", unit.bleed.until])
	for buff: Dictionary in unit.buffs:
		if float(buff.until) > now:
			states.append(buff.duplicate(true))
	return states

func _tick_weather(delta: float) -> void:
	if weather_start.is_empty():
		return
	weather_elapsed += delta
	weather_vector = WeatherRules.vector_at(weather_start.season, weather_start.time, weather_start.weather, weather_elapsed, weather_seed, weather_start.latitude)
	weather_dynamics = WeatherRules.dynamics(weather_vector, weather_dynamics, delta)
	weather_fog = weather_dynamics.fog
	weather_surface = WeatherRules.surface_step(weather_surface, weather_dynamics, delta)
	_tick_weather_effects(delta)
	if world != null:
		world.sync_weather(weather_dynamics, weather_surface, WeatherRules.clock_hour(weather_start.time, weather_elapsed, weather_schedule), weather_schedule, weather_start.season, weather_seed)

func _tick_weather_effects(delta: float) -> void:
	for unit: BattleUnit in units.values():
		var scorch: Dictionary = unit.status.get("lightning_scorch", {})
		if scorch.is_empty():
			continue
		var states := _lightning_states(unit, clock)
		if not unit.alive() or unit.hp >= unit.max_hp or unit.hp > float(scorch.hp) or states.any(func(state): return not scorch.states.has(state)):
			unit.status.erase("lightning_scorch")
		else:
			scorch.hp = unit.hp
	var snow: float = weather_dynamics.get("effectiveSnow", 0)
	var snow_cover := WeatherRules.surface_cover(float(weather_surface.get("snow", 0)))
	var step := int(floorf(clock))
	if (snow > 0 or snow_cover > 0) and weather_last_freeze_step != step:
		weather_last_freeze_step = step
		var random := SourceRng.new(weather_seed ^ (step * 0x85ebca6b))
		for unit: BattleUnit in units.values():
			if not unit.alive() or unit.special.get("invulnerable", false) or unit.special.get("role") == "slab":
				continue
			# Source `lastFreezeAt || -COOLDOWN` treats a zero timestamp as absent.
			var last: float = unit.status.get("last_weather_freeze", -Content.constants.WEATHER_FREEZE.COOLDOWN_S)
			if last == 0:
				last = -Content.constants.WEATHER_FREEZE.COOLDOWN_S
			if clock - last < float(Content.constants.WEATHER_FREEZE.COOLDOWN_S):
				continue
			var probability := (snow if _weather_air(unit) else snow_cover) * 0.05
			if probability <= 0 or random.next() >= probability:
				continue
			unit.status.freeze_until = clock + Content.constants.WEATHER_FREEZE.DUR_S
			unit.status.last_weather_freeze = clock
			events.append({"type": "freeze", "actor": unit.entity_id, "position": unit.position})
	var thunder: float = weather_dynamics.get("effectiveThunder", 0)
	if thunder <= 0:
		lightning_timer = 0.0
		return
	lightning_timer -= delta
	if lightning_timer > 0:
		return
	var cfg: Dictionary = Content.constants.WEATHER_DEBUFFS.LIGHTNING
	lightning_timer = maxf(cfg.INTERVAL_MIN, (1 - thunder) * (float(cfg.INTERVAL_MAX) - float(cfg.INTERVAL_MIN)) + float(cfg.INTERVAL_MIN))
	var random := SourceRng.new(weather_seed ^ (int(floorf(clock * 10)) * 0x9e3779b9))
	if random.next() >= float(cfg.PROB_MIN) + thunder * (float(cfg.PROB_MAX) - float(cfg.PROB_MIN)):
		return
	var candidates := units.values().filter(func(unit): return unit.alive() and not unit.special.get("invulnerable", false))
	var strikes: Array = []
	var count := 3 if thunder > 0.80 else 2 if thunder > 0.45 else 1
	for index in range(mini(count, candidates.size())):
		var target: BattleUnit = candidates.pop_at(int(floorf(random.next() * candidates.size())))
		var position := target.position + Vector3.UP * target.height
		damage(null, target, {"pen": cfg.PEN}, cfg.BASE_DMG, false, {"weather_weapon": false}, false)
		if units.has(target.entity_id):
			target.status.lightning_scorch = {"hp": target.hp, "states": _lightning_states(target, clock)}
		strikes.append({"id": target.entity_id, "position": position, "kind": target.kind})
		_lightning_shockwave(target.position, target.entity_id)
	if not strikes.is_empty():
		events.append({"type": "lightning_strike", "actor": 0, "points": strikes})
	_strike_weather_surface(SourceRng.new(weather_seed ^ int(floorf(clock * 10)) ^ 0x57ea7))

func _strike_weather_surface(random: SourceRng) -> void:
	if world == null or world.native_data == null or world.authority_height_grid.is_empty() or authority_bounds.is_empty():
		return
	var plan := EnvironmentRules.surface_strike(random, authority_bounds, world.authority_height, world.wet_at,
		func(x, z): return world.layers.inferred_level(Vector2(x, z)), world.weather_obstacles, weather_dynamics, fire_fields.size())
	if plan.is_empty():
		return
	var point := Vector3(plan.x, plan.y, plan.z)
	_mark_weather_scorch(point, plan.radius)
	events.append({"type": "lightning_strike", "actor": 0, "points": [{"id": 0, "position": point, "absolute": true}]})
	_lightning_shockwave(point)
	if plan.fire:
		var fire_point := Vector3(point.x, world.source_height(point.x, point.z), point.z)
		_spawn_fire("fire", fire_point, float(plan.radius) / float(Content.constants.HAZARDS.fire.r),
			24.0 / (float(Content.constants.DAYCLOCK.GAME_H) / float(Content.constants.DAYCLOCK.REAL_S)), true)

func _mark_weather_scorch(point: Vector3, radius: float) -> void:
	if not point.is_finite():
		return
	for scar: Dictionary in weather_scars:
		if scar.position.distance_to(point) < radius * 0.5:
			return
	weather_scars.append({"position": point, "radius": radius})

func _spawn_fire(kind: String, point: Vector3, scale_factor: float, lifetime: Variant = null, lightning_fire: bool = false) -> void:
	if kind not in ["fire", "forestfire", "grassfire", "factoryfire"] or not point.is_finite():
		return
	fire_fields.append({"id": next_id, "kind": kind, "position": point, "scale": scale_factor,
		"ttl": lifetime, "lightning": lightning_fire})
	next_id += 1

func _terrain_blocked(x: float, z: float) -> bool:
	if world != null and world.wet_at(x, z) > 0:
		return true
	for fire: Dictionary in fire_fields:
		var radius := float(Content.constants.HAZARDS[fire.kind].r) * float(fire.scale)
		if Vector2(x - fire.position.x, z - fire.position.z).length() < radius + 2:
			return true
	for unit: BattleUnit in units.values():
		if unit.kind == "flood" and unit.special.get("role") == "hazard":
			var radius := float(Content.constants.HAZARDS.flood.r) * float(unit.special.scale)
			if _planar_distance(Vector3(x, 0, z), unit.position) < radius + 2:
				return true
	return false

func _tick_fires(delta: float) -> void:
	for index in range(fire_fields.size() - 1, -1, -1):
		var fire: Dictionary = fire_fields[index]
		if fire.ttl == null:
			continue
		fire.ttl = float(fire.ttl) - delta
		if fire.lightning and EnvironmentRules.lightning_fire_wet(weather_dynamics):
			fire.ttl = 0.0
		if fire.ttl <= 0:
			events.append({"type": "fire_expired", "actor": 0, "hazard": fire.id, "position": fire.position})
			fire_fields.remove_at(index)
	var factor := EnvironmentRules.fire_multiplier(weather_dynamics)
	if factor > 0:
		for fire: Dictionary in fire_fields:
			var definition: Dictionary = Content.constants.HAZARDS[fire.kind]
			for unit: BattleUnit in pilots.values():
				var altitude := _missile_target_altitude(unit)
				if not unit.alive() or altitude > float(definition.maxY) or (unit.kind in Content.constants.AIR.KINDS and altitude > float(Content.constants.AIR.OFF_GROUND)):
					continue
				if _planar_distance(unit.position, fire.position) > float(definition.r) * float(fire.scale):
					continue
				_fire_burn(unit, float(definition.dot) * factor * delta)
				if float(unit.status.get("burn_report", 0)) + 2 < clock:
					unit.status.burn_report = clock
					events.append({"type": "burn", "actor": unit.entity_id, "position": fire.position, "factor": floorf(factor * 100 + 0.5) / 100})
	if world != null:
		world.sync_fires(fire_fields, clock, weather_dynamics)

func _spawn_loot(point: Vector3, treasure_class: float = 0.0) -> void:
	var plan := SceneRules.loot_plan(rng, point.x, point.z, treasure_class)
	var surface := world.source_height(plan.x, plan.z) if world != null else 0.0
	if not is_finite(surface):
		return
	plan.position = Vector3(plan.x, surface, plan.z)
	plan.erase("x")
	plan.erase("z")
	plan.id = next_id
	next_id += 1
	loots.append(plan)

func _tick_loots(delta: float) -> void:
	for index in range(loots.size() - 1, -1, -1):
		var loot: Dictionary = loots[index]
		loot.ttl = float(loot.ttl) - delta
		if loot.ttl <= 0:
			loots.remove_at(index)
			continue
		for unit: BattleUnit in pilots.values():
			if not unit.alive() or _missile_target_altitude(unit) > float(Content.constants.LOOT.MAX_Y):
				continue
			if _planar_distance(unit.position, loot.position) > float(Content.constants.LOOT.PICK_R):
				continue
			if loot.get("ammo", false):
				for slot: String in ["light", "heavy"]:
					unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1).mag
				unit.reload_at.clear()
			elif loot.has("affix"):
				var key: String = loot.affix
				var definition: Dictionary = Content.constants.AFFIXES[key]
				unit.buffs = unit.buffs.filter(func(buff): return buff.get("affix", "") != key)
				var modifiers := {}
				for property: String in ["reload", "dmgTaken", "killHeal", "bounty"]:
					if definition.has(property):
						modifiers[property] = definition[property]
				unit.buffs.append({"until": clock + definition.dur, "mul": modifiers, "affix": key})
			else:
				unit.money += float(loot.value)
			events.append({"type": "loot", "actor": unit.entity_id, "peer": unit.peer_id, "position": loot.position, "ammo": loot.get("ammo", false),
				"affix": loot.get("affix", ""), "value": loot.get("value", 0)})
			loots.remove_at(index)
			break
	if world != null:
		world.sync_loots(loots, clock)

func _flood_effect(unit: BattleUnit) -> Dictionary:
	var floods: Array = []
	for zone: BattleUnit in units.values():
		if zone.kind == "flood":
			var definition: Dictionary = Content.constants.HAZARDS.flood
			floods.append({"x": zone.position.x, "z": zone.position.z, "radius": float(definition.r) * float(zone.special.scale), "slow": definition.slow})
	return SceneRules.flood_effect(floods, Vector2(unit.position.x, unit.position.z), unit.flying, unit.fluid_environment.get("air", false))

func _terrain_jump_velocity(unit: BattleUnit) -> float:
	var flood := _flood_effect(unit)
	return float(flood.jump) if flood.active else EnvironmentRules.jump_velocity(unit.fluid_environment, bool(weather_dynamics.get("isFrozen", false)), unit.flying)

func _airdrop_point() -> Dictionary:
	var bases := {}
	for side: String in ["SWARM", "STEEL"]:
		bases[side] = [world.bases[side].x, world.bases[side].z]
	return SceneRules.airdrop_point(rng, {"bounds": authority_bounds, "lanes": world.lane_points, "bases": bases, "towers": [], "blockers": hazard_blockers}, _terrain_blocked)

func _spawn_airdrop_wave() -> void:
	if not authoritative or over:
		return
	var cfg: Dictionary = Content.constants.AIRDROP
	var players := pilots.size()
	var room := int(cfg.MAX_LIVE) - airdrops.size()
	if players <= 0 or room <= 0:
		return
	var count := mini(room, maxi(1, ceili(players * float(cfg.PER_PLAYER))))
	var dropped := 0
	for index in range(count):
		var point := _airdrop_point()
		if point.is_empty():
			continue
		var size := SceneRules.airdrop_size(rng)
		airdrops.append({"id": next_id, "x": point.x, "z": point.z, "size": size.key, "multiplier": size.mul,
			"ttl": cfg.TTL_S, "land_at": clock + float(cfg.LAND_S)})
		next_id += 1
		dropped += 1
	if dropped > 0:
		events.append({"type": "airfall", "actor": 0, "count": dropped})

func _grant_reward(unit: BattleUnit, reward: String, multiplier: float) -> Dictionary:
	if not authoritative:
		return {}
	var cfg: Dictionary = Content.constants.AIRDROP
	var result := {"reward": reward}
	if reward == "medkit":
		var health := floorf(unit.max_hp * float(cfg.MEDKIT_HP) * multiplier + 0.5)
		var shield_amount := floorf(unit.max_shield * float(cfg.MEDKIT_SP) * multiplier + 0.5)
		result.hp = floorf(_heal_body(unit, health, "item") + 0.5)
		unit.shield = minf(unit.max_shield, unit.shield + shield_amount)
		result.shield = shield_amount
	elif reward == "battery":
		var power_amount := floorf(unit.max_power * float(cfg.BATTERY_MP) * multiplier + 0.5)
		unit.power += power_amount
		var reduction := float(cfg.BATTERY_CD) * multiplier
		for slot: String in ["def", "atk"]:
			unit.cooldowns[slot] = maxf(0, float(unit.cooldowns.get(slot, 0)) - reduction)
			if unit.ability_charges.has(slot) and unit.ability_charges[slot].has("recharge_at"):
				unit.ability_charges[slot].recharge_at = unit.ability_charges[slot].recharge_at.map(func(deadline): return maxf(clock, float(deadline) - reduction))
		result.power = power_amount
		result.cooldown = floorf(reduction * 10 + 0.5) / 10
	else:
		var amount := floorf(float(cfg.MONEY) * multiplier + 0.5)
		unit.money += amount
		result.value = amount
	return result

func _open_airdrop(unit: BattleUnit, state: Dictionary) -> void:
	if not authoritative or over or not unit.alive():
		return
	var rewards: Array = Content.constants.AIRDROP.REWARDS
	var reward: String = rewards[int(floorf(rng.next() * rewards.size()))]
	var event := {"type": "airdrop", "actor": unit.entity_id, "peer": unit.peer_id, "side": unit.side, "position": Vector3(state.x, 0, state.z), "size": state.size}
	var received := _grant_reward(unit, reward, state.multiplier)
	event.merge(received)
	events.append(event)

func _tick_airdrops(delta: float) -> void:
	if not authoritative or over:
		return
	var cfg: Dictionary = Content.constants.AIRDROP
	for index in range(airdrops.size() - 1, -1, -1):
		var state: Dictionary = airdrops[index]
		state.ttl = float(state.ttl) - delta
		if state.ttl <= 0:
			airdrops.remove_at(index)
			continue
		if clock < float(state.land_at):
			continue
		var point := Vector3(state.x, 0, state.z)
		for unit: BattleUnit in pilots.values():
			if not unit.alive() or _missile_target_altitude(unit) > float(cfg.MAX_Y) or _planar_distance(unit.position, point) > float(cfg.PICK_R):
				continue
			_open_airdrop(unit, state)
			airdrops.remove_at(index)
			break
	if world != null:
		world.sync_airdrops(_airdrop_snapshot(), clock)

func _airdrop_snapshot() -> Array:
	var states: Array = []
	for state: Dictionary in airdrops:
		var x := floorf(float(state.x) * 10 + 0.5) / 10
		var z := -floorf(-float(state.z) * 10 + 0.5) / 10
		states.append({"id": state.id, "x": x, "z": z, "size": state.size, "landing": clock < float(state.land_at)})
	return states

func _tick_mines() -> void:
	var cfg: Dictionary = Content.constants.GAME.MINES
	for unit: BattleUnit in pilots.values():
		var grounded := unit.kind == "robot" and not _air_unit(unit) or unit.kind == "morph" and _missile_target_altitude(unit) <= float(Content.constants.MORPH.GROUND_Y)
		if not unit.alive() or not grounded or unit.has_status("third_cooldown_until", clock):
			continue
		for index in range(mines.size() - 1, -1, -1):
			var mine: Dictionary = mines[index]
			var point := Vector3(mine.x, 0, mine.z)
			if _planar_distance(unit.position, point) > float(cfg.TRIGGER_R):
				continue
			mines.remove_at(index)
			unit.status.third_cooldown_until = clock + float(Content.constants.GAME.THREAT_CD_S)
			events.append({"type": "mine_blast", "actor": unit.entity_id, "peer": unit.peer_id, "mine": mine.id, "position": point, "radius": cfg.R})
			for target: BattleUnit in units.values():
				if not target.alive() or target.is_hero() and _missile_target_altitude(target) > float(cfg.R):
					continue
				var factor := CombatMath.blast_falloff(cfg.R, _planar_distance(target.position, point))
				if factor > 0:
					damage(null, target, {"pen": cfg.PEN}, float(cfg.DMG) * factor, true, {"weather_weapon": false}, false)
			break
	if world != null:
		world.sync_mines(mines)

func _tick_ambush(delta: float) -> void:
	var cfg: Dictionary = Content.constants.GAME.AA_AMBUSH
	var site_cfg: Dictionary = Content.constants.FIELD.AA_SITE
	var count := 0
	for missile: Dictionary in missiles:
		if missile.get("ambush", false):
			count += 1
	for unit: BattleUnit in pilots.values():
		if count >= int(Content.constants.GAME.THREAT_MISSILES_MAX):
			return
		if not unit.alive() or unit.kind != "drone" and not (unit.kind == "morph" and _missile_target_altitude(unit) >= float(Content.constants.GAME.AA_MIN_ALT)):
			continue
		if unit.has_status("third_cooldown_until", clock) or unit.has_status("stealth_until", clock):
			continue
		if SceneRules.lane_distance(world.lane_points, unit.position.x, unit.position.z) <= float(Content.constants.GAME.AMBUSH_M):
			continue
		if rng.next() > float(cfg.CHANCE_PER_S) * delta:
			continue
		var best: BattleUnit
		var best_distance := INF
		for site: BattleUnit in units.values():
			if site.kind != "aasite" or not site.alive():
				continue
			var distance := _planar_distance(unit.position, site.position)
			if distance <= float(site_cfg.range) and distance < best_distance:
				best = site
				best_distance = distance
		if best == null:
			continue
		unit.status.third_cooldown_until = clock + float(Content.constants.GAME.THREAT_CD_S)
		var origin := Vector3(best.position.x, 2, best.position.z)
		var side := "SWARM" if unit.side == "STEEL" else "STEEL"
		_launch_missile({"actor": best.entity_id, "side": side, "target": unit.entity_id, "ambush": true,
			"position": origin, "origin": origin, "speed": cfg.SPEED, "dmg": cfg.DMG, "pen": cfg.PEN, "r": cfg.R,
			"hp": cfg.HP, "max_hp": cfg.HP, "ttl": 14.0, "range": site_cfg.range})
		events.append({"type": "sam", "actor": best.entity_id, "target": unit.entity_id, "target_peer": unit.peer_id, "position": best.position, "side": side, "ambush": true})
		count += 1

func _tick_relays(delta: float) -> void:
	var cfg: Dictionary = Content.constants.FIELD.RELAY
	for index in range(relay_states.size() - 1, -1, -1):
		var relay: Dictionary = relay_states[index]
		var side := ""
		var contested := false
		for unit: BattleUnit in pilots.values():
			if not unit.alive() or _planar_distance(unit.position, relay.position) > float(cfg.R):
				continue
			if not side.is_empty() and unit.side != side:
				contested = true
				break
			side = unit.side
		if side.is_empty() or contested:
			relay.charge = maxf(0, float(relay.charge) - delta * 2)
			_sync_relay_state(relay)
			continue
		if relay.side != side:
			relay.charge = 0.0
		relay.side = side
		relay.charge = float(relay.charge) + delta
		_sync_relay_state(relay)
		if relay.charge < float(cfg.CHANNEL_S):
			continue
		vision_until[side] = clock + float(cfg.VISION_S)
		events.append({"type": "relay", "actor": relay.id, "side": side, "position": relay.position})
		_remove_field_unit(int(relay.id), false)
		relay_states.remove_at(index)

func _sync_relay_state(state: Dictionary) -> void:
	var unit: BattleUnit = units.get(int(state.id))
	if unit != null:
		unit.special.relay_charge = state.charge
		unit.special.relay_side = state.side

func _collapse_scene(unit: BattleUnit) -> void:
	unit.hp = 0
	unit.special.collapsed = true
	unit.visible = unit.presentation_visible
	unit.refresh_collision()
	unit.apply_collapse()
	var radius := float(Content.constants.HAZARDS[unit.kind].r) * float(unit.special.scale) * float(Content.constants.SCENE_STRUCT.RUBBLE_F)
	for obstacle: Dictionary in hazard_blockers:
		if float(obstacle.x) == float(unit.position.x) and float(obstacle.z) == float(unit.position.z):
			obstacle.radius = radius
			break
	events.append({"type": "collapse", "actor": unit.entity_id, "position": unit.position, "electric": unit.special.get("electric", false)})
	if fire_fields.size() < 40:
		var duration := SceneRules.vehicle_fire_seconds(unit.special.get("electric", false)) if unit.kind in ["car", "ship"] else SceneRules.fire_seconds(unit.max_hp)
		_spawn_fire("fire", unit.position, maxf(0.3, radius / float(Content.constants.HAZARDS.fire.r)), duration)

func _drop_scene_loot(unit: BattleUnit) -> void:
	var probability: float = Content.constants.HAZARDS.get(unit.kind, {}).get("salvage", 0)
	if probability > 0 and rng.next() < probability:
		_spawn_loot(unit.position, minf(1, unit.max_hp / float(Content.constants.LOOT.TC.HP_REF)))

func _lightning_shockwave(center: Vector3, direct_id: int = 0) -> void:
	var cfg: Dictionary = Content.constants.WEATHER_DEBUFFS.LIGHTNING
	for unit: BattleUnit in units.values():
		if not unit.alive() or unit.entity_id == direct_id or unit.special.get("invulnerable", false):
			continue
		var offset := Vector2(unit.position.x - center.x, unit.position.z - center.z)
		var distance := offset.length()
		if distance > float(cfg.SHOCK_R):
			continue
		var fraction := 1 - distance / float(cfg.SHOCK_R)
		damage(null, unit, {}, float(cfg.SHOCK_DMG) * fraction, false, {}, false)
		var impulse := offset / maxf(0.1, distance) * float(cfg.SHOCK_IMP) * fraction
		if unit.is_hero() and not unit.is_bot:
			var human_impulse := float(cfg.SHOCK_IMP) * fraction
			if human_impulse == 0:
				human_impulse = 14.0
			var direction := offset / distance if distance > 0.05 else Vector2.RIGHT
			if unit.flying:
				unit.velocity += Vector3(direction.x, 0, direction.y) * human_impulse
			else:
				unit.impulse_velocity += direction * human_impulse
				unit.velocity.y += 2.5
			events.append({"type": "shockwave", "actor": unit.entity_id, "position": center, "impulse": impulse.length()})
		else:
			_place_solid(unit, impulse * 0.35)

func spawn(info: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	var data: Dictionary = info.duplicate()
	data.id = next_id if not info.has("id") else int(info.id)
	next_id = maxi(next_id, int(data.id) + 1)
	unit.name = "Unit_%d" % data.id
	add_child(unit)
	unit.configure(data)
	units[unit.entity_id] = unit
	if unit.is_pilot():
		unit.yaw = world.spawn_heading(unit.side, unit.spawn_slot)
		if authoritative:
			unit.ensure_weapon_pose()
	if authoritative and unit.speed > 0 and not unit.is_hero() and unit.special.is_empty():
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
		"jump_held": command.get("jump_held", false) == true,
		"sprint": command.get("sprint", false) == true, "aim": command.get("aim", false) == true,
		"slot": "heavy" if command.get("slot") == "heavy" else "light"}
	unit.input_state["received"] = clock

func action(peer: int, type: String, argument: String = "") -> void:
	if not authoritative or over or not pilots.has(peer):
		return
	var unit: BattleUnit = pilots[peer]
	if type == "buy":
		buy(unit, argument)
		return
	if type == "buy_creep":
		var lane := argument.strip_edges()
		if lane.is_valid_int():
			buy_creep(unit, int(lane))
		return
	if not unit.alive():
		return
	if type in ["civ_follow", "civ_away"]:
		if argument.is_valid_int():
			_civilian_interact(unit, int(argument), "away" if type == "civ_away" else "follow")
		return
	match type:
		"reload":
			reload_weapon(unit, argument if argument in ["light", "heavy"] else "light")
		"cast":
			cast(unit, argument)
		"defend":
			if argument == "off" or unit.shield > 0:
				unit.defending = argument != "off"

func request_iframe(unit: BattleUnit) -> bool:
	if not authoritative or over or not unit.alive() or unit.has_status("iframe_cooldown_until", clock):
		return false
	unit.status.iframe_cooldown_until = clock + (Content.constants.IFRAME.DRONE_CD if unit.kind == "drone" else Content.constants.IFRAME.CD)
	unit.status.inv_until = clock + Content.constants.IFRAME.DUR
	events.append({"type": "iframe", "actor": unit.entity_id, "side": unit.side, "duration": Content.constants.IFRAME.DUR})
	return true

func _physics_process(delta: float) -> void:
	if not authoritative:
		for unit in units.values():
			unit.interpolate(delta)
		return
	if over:
		return
	clock += delta
	weather_accumulator += delta
	var weather_delta: float = float(Content.constants.GAME.TICK_MS) / 1000
	while weather_accumulator + 0.000000001 >= weather_delta:
		weather_accumulator = maxf(0, weather_accumulator - weather_delta)
		_tick_weather(weather_delta)
	if clock >= next_wave:
		spawn_wave()
		next_wave = clock + Content.constants.GAME.WAVE_S
	if clock >= next_airdrop:
		next_airdrop = clock + float(Content.constants.AIRDROP.INTERVAL_S)
		_spawn_airdrop_wave()
	for unit: BattleUnit in pilots.values():
		if unit.alive():
			_update_fluid_state(unit)
			_regenerate(unit, delta)
		elif unit.respawn_at > 0 and clock >= unit.respawn_at:
			respawn(unit)
	_tick_ability_states(delta)
	for unit: BattleUnit in units.values():
		if not unit.alive():
			fire_controls.erase(unit.entity_id)
			_tick_weapon_pose(unit, delta)
			continue
		if unit.is_pilot():
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
			_tick_weapon_pose(unit, delta)
		unit.visible = (unit.alive() or unit.special.get("collapsed", false)) and unit.presentation_visible and not unit.special.get("garrison", false)
		if unit.special.get("role") != "carrier":
			unit.position.y = minf(unit.position.y, world.ceiling)
		unit.buffs = unit.buffs.filter(func(buff): return buff.until > clock)
	npc_accumulator += delta
	var npc_delta: float = float(Content.constants.GAME.TICK_MS) / 1000
	while npc_accumulator + 0.000000001 >= npc_delta:
		npc_accumulator = maxf(0, npc_accumulator - npc_delta)
		_tick_civilians(npc_delta)
		_tick_mines()
		_tick_ambush(npc_delta)
		_tick_relays(npc_delta)
		_tick_fires(npc_delta)
		_tick_loots(npc_delta)
		_tick_airdrops(npc_delta)
		_tick_camps(npc_delta)
		wave_anchors = _wave_anchors()
		npc_structures.clear()
		for structure: BattleUnit in units.values():
			if structure.alive() and structure.kind in ["tower", "base"]:
				npc_structures.append({"kind": structure.kind, "x": float(structure.position.x), "z": float(structure.position.z)})
		_begin_npc_index()
		for unit: BattleUnit in units.values():
			if unit.alive() and not unit.is_hero() and (unit.special.is_empty() or unit.special.get("third", false)):
				_tick_npc(unit, npc_delta)
		npc_index_active = false
		npc_index.clear()
		npc_structures.clear()
	_tick_projectiles(delta)
	_tick_missiles(delta)
	_prune_dead_creeps()

func spawn_wave() -> void:
	wave += 1
	for lane in range(world.paths.size()):
		for side in ["SWARM", "STEEL"]:
			_spawn_lane_wave(lane, side, wave, Content.constants.GAME.WAVE_SPAWN_OFF_M)
	events.append({"type": "wave", "actor": 0, "wave": wave})

func _prefill_lanes(map_data: Dictionary) -> void:
	if not map_data.has("wave_prefill"):
		push_error("Missing source prefill plan; regenerate migration data before running the battle")
		return
	for row: Dictionary in map_data.wave_prefill:
		_spawn_lane_wave(int(row.lane), row.side, int(row.wave), float(row.lead))

func _npc_surface(point: Vector2) -> float:
	var level := world.layers.inferred_level(point)
	if level == 2:
		var tunnel := world.layers.tunnel_at(point)
		if not tunnel.is_empty():
			return float(tunnel.floor)
	if level == 1:
		var deck: Variant = world.layers.deck_height(point, Content.balance.structure.deckMargin)
		if deck != null:
			return float(deck)
	return world.ground_height(point.x, point.y)

func _spawn_lane_wave(lane: int, side: String, wave_id: int, lead: float) -> void:
	if not Content.balance.has("wave_rules"):
		push_error("Missing source wave rules; regenerate migration data before running the battle")
		return
	var plan := WaveRules.spawn_plan(world.lane_points[lane], world.lane_distances[lane], side, lead, rng)
	var multiplier := NpcRules.creep_multiplier(float(creep_upgrades[side][lane]))
	for row: Dictionary in plan:
		var surface := _npc_surface(Vector2(row.x, row.z))
		if not is_finite(surface):
			push_error("Wave actor has no verified standing surface")
			continue
		var altitude: float = Content.constants.GAME.HELI_ALT if row.kind == "heli" else 0.0
		var unit := spawn({"side": side, "kind": row.kind, "lane": lane, "position": Vector3(row.x, surface + altitude, row.z), "creep_multiplier": multiplier})
		unit.npc_progress = row.progress
		unit.npc_has_wave = true
		unit.npc_wave = wave_id
		if unit.path_follower != null:
			unit.path_follower.progress_ratio = clampf(row.progress / float(world.lane_distances[lane][-1]), 0, 1) if side == "SWARM" else clampf(1 - row.progress / float(world.lane_distances[lane][-1]), 0, 1)

func _wave_anchors() -> Dictionary:
	var anchors := {}
	for unit: BattleUnit in units.values():
		if not unit.alive() or unit.is_hero() or unit.special.get("neutral", false) or not unit.has_lane or not unit.npc_has_wave or unit.npc_engaged:
			continue
		var key := "%s|%d|%d" % [unit.side, unit.lane, unit.npc_wave]
		anchors[key] = minf(float(anchors.get(key, INF)), unit.npc_progress)
	return anchors

func _advance_npc(unit: BattleUnit, delta: float) -> void:
	if not unit.has_lane or unit.lane >= world.lane_points.size():
		return
	var structures: Array = npc_structures.duplicate()
	var allies: Array = []
	for other: BattleUnit in units.values():
		if other.alive() and other != unit and other.side == unit.side and other.has_lane and other.lane == unit.lane and not other.is_hero() and not other.special.get("neutral", false):
			allies.append({"x": float(other.position.x), "z": float(other.position.z)})
	var state := {"x": float(unit.position.x), "z": float(unit.position.z), "progress": unit.npc_progress, "side": unit.side}
	var key := "%s|%d|%d" % [unit.side, unit.lane, unit.npc_wave]
	var controls := {"stun": unit.has_status("stun_until", clock), "slow": unit.has_status("slow_until", clock),
		"slow_factor": unit.status.get("slow_factor", 0.6), "confuse": unit.has_status("confuse_until", clock)}
	WaveRules.step(state, world.lane_points[unit.lane], world.lane_distances[unit.lane], unit.speed, delta, controls,
		float(wave_anchors.get(key, NAN)) if unit.npc_has_wave else NAN, structures, hazard_blockers, allies, _wave_weather_factor(unit, controls))
	unit.npc_progress = state.progress
	var surface := _npc_surface(Vector2(state.x, state.z))
	if not is_finite(surface):
		return
	var altitude: float = Content.constants.GAME.HELI_ALT if unit.kind == "heli" else 0.0
	var desired := Vector3(state.x, surface + altitude, state.z)
	var motion := desired - unit.position
	if Vector2(motion.x, motion.z).length_squared() > 0.0001:
		unit.yaw = atan2(-motion.x, -motion.z)
		unit.rotation.y = unit.yaw
	unit.move_and_collide(motion)

func _tick_npc(unit: BattleUnit, delta: float) -> void:
	var def: Dictionary = Content.constants.UNITS[unit.kind]
	unit.npc_cooldown = maxf(0, unit.npc_cooldown - delta)
	if unit.kind == "base":
		_tick_base_guns(unit, def.guns, delta)
		return
	if unit.special.get("third", false):
		_camp_behavior(unit, delta)
	var profile: Dictionary = def
	if unit.special.get("garrison", false):
		profile = def.duplicate()
		profile.range = float(def.range) * float(Content.constants.THIRD.GAR_RANGE_F)
	var target := _npc_acquire_cached(unit, profile)
	unit.npc_engaged = target != null
	if target != null and not unit.special.get("retreat", false):
		var direction := target.eye() - unit.eye()
		unit.yaw = atan2(-direction.x, -direction.z)
		unit.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		if unit.npc_cooldown == 0 and not unit.has_status("emp_until", clock):
			unit.npc_cooldown = 1.0 / (maxf(0.01, def.get("rate", 1)) * weather_attack_rate(unit))
			unit.fire_at.npc = clock + unit.npc_cooldown
			var weapon_def: Dictionary = Content.constants.WEAPONS.get(def.get("wid", ""), Content.constants.STRUCT_W.get(unit.kind, {}))
			if weapon_def.get("r", 0) > 0:
				var point := Vector3(target.position.x, _missile_target_altitude(target) if target.is_hero() or target.kind == "heli" else 0, target.position.z)
				blast(unit, weapon_def, point, false, true, _unit_level(target), def.dmg)
				events.append({"type": "boom", "actor": unit.entity_id, "position": target.position, "radius": weapon_def.r, "side": unit.side})
			elif not _roll_miss(unit, target, weapon_def):
				damage(unit, target, weapon_def, def.dmg * (1.0 if target.is_hero() else unit.creep_multiplier), false, {}, false)
			events.append({"type": "shot", "actor": unit.entity_id, "start": unit.eye(), "end": target.eye(), "side": unit.side})
		return
	if unit.special.get("third", false) and unit.speed > 0:
		_move_camp_unit(unit, def, delta)
		return
	if unit.speed <= 0 or not unit.has_lane:
		return
	_advance_npc(unit, delta)

func _npc_spec(unit: BattleUnit) -> Dictionary:
	return {"kind": unit.kind, "side": unit.side, "hero": unit.is_hero(), "hp": unit.hp, "dead": not unit.alive(),
		"neutral": unit.special.get("neutral", false), "garrison": unit.special.get("garrison", false),
		"third": unit.special.get("third", false), "siege_locked": unit.special.get("siege_locked", false),
		"stealth": unit.has_status("stealth_until", clock), "blind": unit.has_status("blind_until", clock),
		"altitude": _missile_target_altitude(unit), "sight_height": _relative_sight_height(unit), "hologram": unit.special.get("role") == "hologram"}

func _npc_blocked(observer: BattleUnit, target: BattleUnit, profile: Dictionary, weapon: Dictionary) -> bool:
	var observer_spec := _npc_spec(observer)
	var target_spec := _npc_spec(target)
	if target.kind in ["drone", "heli", "morph"]:
		var ceiling := minf(float(profile.range) * 0.9, Content.constants.GAME.GUN_CEIL_M)
		if absf(float(target_spec.altitude) - ceiling) <= MissileMotion.NATIVE_HEIGHT_TOLERANCE:
			target_spec.altitude = ceiling
	var range_factor := CombatMath.altitude_range(weapon, _height_difference(observer, target))
	if observer.is_hero():
		range_factor *= StatusRules.multiplier(observer.buffs, "range", clock)
	return NpcRules.blocked(observer_spec, target_spec, profile, weapon, _planar_distance(observer.position, target.position), range_factor, weather_fog)

func _begin_npc_index() -> void:
	npc_index_active = false
	npc_index.clear()
	var rules: Dictionary = Content.balance.get("npc", {})
	if not rules.has("cell"):
		return
	var sequence := 0
	for unit: BattleUnit in units.values():
		if unit.alive() and not unit.special.get("neutral", false):
			npc_index.append({"unit": unit, "x": int(floorf(unit.position.x / float(rules.cell))),
				"z": int(floorf(-unit.position.z / float(rules.cell))), "sequence": sequence})
		sequence += 1
	npc_index.sort_custom(func(first, second):
		if first.x != second.x:
			return first.x < second.x
		if first.z != second.z:
			return first.z < second.z
		return first.sequence < second.sequence)
	npc_index_active = true

func _npc_candidates(observer: BattleUnit, profile: Dictionary) -> Array:
	if not npc_index_active:
		return units.values()
	var rules: Dictionary = Content.balance.npc
	var radius: float = float(profile.range) * rules.candidate_range
	var low_x := int(floorf((observer.position.x - radius) / float(rules.cell)))
	var high_x := int(floorf((observer.position.x + radius) / float(rules.cell)))
	var low_z := int(floorf((-observer.position.z - radius) / float(rules.cell)))
	var high_z := int(floorf((-observer.position.z + radius) / float(rules.cell)))
	var candidates: Array = []
	for record: Dictionary in npc_index:
		if record.x >= low_x and record.x <= high_x and record.z >= low_z and record.z <= high_z:
			candidates.append(record.unit)
	return candidates

func _npc_acquire(observer: BattleUnit, profile: Dictionary) -> BattleUnit:
	var best: BattleUnit
	var best_score := INF
	var weapon: Dictionary = Content.constants.WEAPONS.get(profile.get("wid", ""), {})
	for target: BattleUnit in _npc_candidates(observer, profile):
		if _npc_blocked(observer, target, profile, weapon):
			continue
		var score := NpcRules.score(_planar_distance(observer.position, target.position), _npc_spec(target), weapon)
		if score >= best_score or not visible_to(observer, target):
			continue
		best = target
		best_score = score
	return best

func _npc_acquire_cached(observer: BattleUnit, profile: Dictionary) -> BattleUnit:
	# Preserve the source's targeting cadence while native physics can validate a held actor every frame.
	var rules: Dictionary = Content.balance.get("npc", {})
	if not rules.has("rescan"):
		return _npc_acquire(observer, profile)
	var period := maxi(1, int(rules.rescan))
	if observer.npc_cache_phase < 0:
		npc_phase_sequence = (npc_phase_sequence + 1) % period
		observer.npc_cache_phase = npc_phase_sequence
	var tick := int(floorf(clock / (float(Content.constants.GAME.TICK_MS) / 1000)))
	var held: BattleUnit = units.get(observer.npc_cached_target)
	if held != null and (observer.npc_cached_tick == tick or (tick + observer.npc_cache_phase) % period != 0):
		var weapon: Dictionary = Content.constants.WEAPONS.get(profile.get("wid", ""), {})
		if not _npc_blocked(observer, held, profile, weapon) and visible_to(observer, held):
			return held
	var target := _npc_acquire(observer, profile)
	observer.npc_cached_target = target.entity_id if target != null else 0
	observer.npc_cached_tick = tick
	return target

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
	if not cubic_cages.is_empty() and _skill_barriers_blocked(_relative_origin(unit), _relative_target(target)):
		return false
	var query := PhysicsRayQueryParameters3D.create(unit.sight_origin(), target.sight_target(), 1)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func visible_to_side(target: BattleUnit, side: String) -> bool:
	if target.side == side or target.special.get("neutral", false) or target.kind in ["base", "tower"]:
		return true
	if float(vision_until.get(side, 0)) > clock:
		return true
	var protection := AbilityFieldRules.protecting_fog(fogs, Vector2(target.position.x, target.position.z), target.side, clock)
	for observer: BattleUnit in units.values():
		if observer.side != side or not observer.alive() or observer.has_status("blind_until", clock) or not Content.constants.UNITS.get(observer.kind, {}).has("sight"):
			continue
		if target.has_status("stealth_until", clock):
			continue
		var point := Vector2(observer.position.x, observer.position.z)
		if not protection.is_empty() and not AbilityFieldRules.covers(protection, point, clock):
			continue
		var offset := Vector2(target.position.x - observer.position.x, target.position.z - observer.position.z)
		if offset.length() <= observer.sight_radius() * NpcRules.fog_sight(weather_fog) * AbilityFieldRules.observer_factor(fogs, point, side, clock) and visible_to(observer, target):
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
		unit.visible = (unit.alive() or unit.special.get("collapsed", false)) and unit.presentation_visible and not unit.special.get("garrison", false)

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
	unit.reload_at[slot] = clock + def.reload * StatusRules.multiplier(unit.buffs, "reload", clock) * float(weather_dynamics.get("snowCdMul", 1))

func _tick_weapon_pose(unit: BattleUnit, delta: float) -> void:
	if not authoritative or unit.weapon_pose == null:
		return
	var slot: String = unit.input_state.get("slot", "light")
	if slot not in ["light", "heavy"]:
		return
	var def := Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1)
	var control: Dictionary = fire_controls.get(unit.entity_id, {})
	var elevation := CockpitPose.barrel_elevation(control.velocity, control.direction) if not control.is_empty() and slot == "heavy" and unit.input_state.get("aim", false) else 0.0
	unit.weapon_pose.advance(delta, clock, slot, unit.flying, def, unit.reload_at.get(slot, NAN), elevation, unit.alive())

func fire(unit: BattleUnit, slot: String) -> void:
	if not authoritative or over or not unit.alive() or not unit.is_pilot() or slot not in ["light", "heavy"]:
		return
	if unit.has_status("emp_until", clock) or unit.has_status("blind_until", clock) or unit.has_status("phase_until", clock) or unit.has_status("freeze_until", clock) or unit.has_status("cast_lock_until", clock) or not unit.cast_state.is_empty():
		return
	if slot == "heavy" and unit.has_status("clones_until", clock):
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
		if unit.has_status("no_reload_until", clock) or unit.has_status("no_%s_reload_until" % slot, clock):
			unit.ammo[slot] = def.mag
		else:
			reload_weapon(unit, slot)
			return
	if unit.power < def.heavyMp:
		return
	if def.get("needAim", false) and not unit.input_state.get("aim", false):
		return
	unit.ensure_weapon_pose()
	var start := unit.weapon_pose.muzzle(unit.aim_transform(), slot, unit.flying, true, false)
	var launch_surface := NAN
	var shooter_frame := {}
	if def.trajectory in ["guide", "fnf", "lob", "flat"]:
		launch_surface = _weapon_surface(start)
		var reference := _height_reference(unit)
		if not is_finite(launch_surface) or not is_finite(reference):
			message.emit(unit.peer_id, "unavailable_surface")
			return
		shooter_frame = _shooter_frame(unit, reference)
	var control := {}
	if def.trajectory == "lob":
		control = fire_controls.get(unit.entity_id, {})
		if control.is_empty() or control.clock != clock or control.camera != unit.aim_transform() or control.pose_clock != unit.weapon_pose.clock or control.direction != unit.aim_direction() or control.level != int(unit.upgrades.hw):
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
	unit.fire_at[slot] = clock + 1.0 / (def.rate * weather_attack_rate(unit) * (0.5 if unit.defending and unit.shield > 0 else 1.0))
	unit.last_fired_at[slot] = clock
	if unit.ammo[slot] <= 0 and not unit.has_status("no_reload_until", clock) and not unit.has_status("no_%s_reload_until" % slot, clock):
		unit.reload_at[slot] = clock + def.reload * StatusRules.multiplier(unit.buffs, "reload", clock) * float(weather_dynamics.get("snowCdMul", 1))
	if unit.has_status("alpha_arm_until", clock) and unit.has_status("stealth_until", clock):
		_add_modifier(unit, "dmg", float(unit.status.get("alpha_multiplier", 1)), Content.constants.SELF_ATK.ALPHA_S)
		unit.status.alpha_arm_until = 0
	unit.status.stealth_until = 0
	unit.play_action(slot)
	unit.fire_serial += 1
	unit.ensure_weapon_pose()
	var port := unit.weapon_pose.muzzle(unit.aim_transform(), slot, unit.flying)
	unit.weapon_pose.fire(unit.fire_serial, slot, clock, def)
	events.append({"type": "weapon_fire", "actor": unit.entity_id, "slot": slot, "side": unit.side,
		"serial": unit.fire_serial, "clock": clock, "muzzle": port,
		"level": int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1})
	if def.trajectory == "flat":
		var state := ProjectileMotion.ballistic(start, unit.aim_direction() * def.projectile.speed, reach)
		state.actor = unit.entity_id
		state.side = unit.side
		state.definition = def.duplicate(true)
		state.origin_surface = launch_surface
		state.shooter_frame = shooter_frame
		state.slot = slot
		_register_projectile(state)
		return
	if def.trajectory == "lob":
		var state := ProjectileMotion.ballistic(start, control.velocity, control.range)
		state.actor = unit.entity_id
		state.side = unit.side
		state.definition = def.duplicate(true)
		state.shooter_frame = shooter_frame
		_register_projectile(state)
		return
	if def.trajectory in ["guide", "fnf"]:
		var aim := _projectile_aim(unit, reach)
		_launch_guided(unit, def, start, aim.point, aim.hit, launch_surface, reach, shooter_frame)
		return
	var precise := _projectile_aim(unit, reach, def.area == "line")
	var end: Vector3 = precise.point
	match def.area:
		"blast":
			blast(unit, def, end)
		"fan":
			_fire_fan(unit, def, start)
		"line":
			var reference := _height_reference(unit)
			if is_finite(reference):
				_fire_line(unit, def, start, end, reference, _shooter_frame(unit, reference))
		_:
			if int(precise.missile) != 0 and start.distance_to(end) <= def.range * Content.constants.RANGE_TOL:
				_damage_missile(unit, def, int(precise.missile))
			var target: BattleUnit = precise.target if precise.target != null else _aim_target(unit, reach) if int(precise.missile) == 0 else null
			if target != null:
				var surface := _height_reference(unit)
				var target_surface := _projectile_surface(target.position)
				if not is_finite(surface) or not is_finite(target_surface):
					return
				var target_height: float = target.position.y - target_surface if target.is_hero() else 0.0
				var offset := Vector3(target.position.x - unit.position.x, target_height - (unit.position.y - surface), target.position.z - unit.position.z)
				var budget: float = def.range * _settlement_range_factor(unit, def, start, surface, target, target_surface, _shooter_frame(unit, surface)) * Content.constants.RANGE_TOL
				var launch_budget: float = _launch_range(unit, def, target) * Content.constants.RANGE_TOL
				if visible_to_side(target, unit.side) and visible_to(unit, target) and CombatMath.direct_in_range(budget, offset, target.radius) and CombatMath.direct_in_range(launch_budget, target.position - start, target.radius):
					if not _roll_miss(unit, target, def):
						var amount: float = def.dmg * CombatMath.damage_falloff(def, offset.length())
						amount = _roll_critical(unit, target, def, amount)
						damage(unit, target, def, amount)
	events.append({"type": "shot", "actor": unit.entity_id, "start": start, "end": end, "side": unit.side,
		"slot": slot, "weapon_type": def.type, "area": def.area})

func lob_control(unit: BattleUnit, def: Dictionary) -> Dictionary:
	var origin := _advisory_origin(unit)
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
	control.camera = unit.aim_transform()
	control.pose_clock = unit.weapon_pose.clock
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
	return TargetingMath.launch_range(def, unit.position, unit.view_origin(), surface,
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
	var camera := unit.view_origin()
	for target: BattleUnit in units.values():
		if not target.is_hero() or not target.alive() or target.side == unit.side or not visible_to_side(target, unit.side):
			continue
		var point := target.aim_point()
		if not point.is_finite():
			continue
		var obstruction := world.obstruction_hit(camera, point)
		candidates.append({"id": target.entity_id, "hero": true, "point": point,
			"obstruction": INF if obstruction.is_empty() else camera.distance_to(obstruction.position)})
	return units.get(TargetingMath.cone_acquire(unit.position, camera, unit.aim_direction(), reach, candidates, unit.aim_anchor))

func _tick_lock(unit: BattleUnit) -> void:
	if not authoritative or over or not unit.alive():
		return
	if unit.has_status("blind_until", clock):
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
	if unit.has_status("blind_until", clock):
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
	var reach: float = def.range * _settlement_range_factor(unit, def, unit.view_origin(), surface, target, target_surface, _shooter_frame(unit, surface)) * Content.constants.RANGE_TOL * multiplier
	if maxf(0, delta.length() - target.radius) > reach:
		return
	unit.lock_target = target_id
	unit.aim_anchor = target_id
	unit.lock_at = clock

func _hit_unit(hit: Dictionary) -> BattleUnit:
	if hit.is_empty() or not hit.has("collider"):
		return null
	if hit.collider is BattleUnit:
		return hit.collider
	return hit.collider.get_parent() as BattleUnit

func _projectile_aim(unit: BattleUnit, reach: float, pierce: bool = false) -> Dictionary:
	var origin := unit.view_origin()
	var end := origin + unit.aim_direction() * reach
	var excluded: Array[RID] = []
	for candidate: BattleUnit in units.values():
		if candidate.side == unit.side or not candidate.alive() or not visible_to_side(candidate, unit.side):
			excluded.append(candidate.hit_area.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 if pierce else 1 | 2 | 512, excluded)
	query.collide_with_areas = true
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: BattleUnit
	if not hit.is_empty():
		target = _hit_unit(hit)
	return {"point": hit.position if not hit.is_empty() else end, "hit": hit, "target": target,
		"missile": int(hit.collider.get_meta("missile", 0)) if not hit.is_empty() else 0}

func _arc_collision(start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _launch_guided(unit: BattleUnit, def: Dictionary, start: Vector3, aim: Vector3, hit: Dictionary, surface: float, reach: float, shooter_frame: Dictionary) -> void:
	var target_id := 0
	var launch_def := def.duplicate(true)
	if def.trajectory == "fnf":
		var target := _aim_target(unit, reach)
		if target != null:
			target_id = target.entity_id
	if not hit.is_empty():
		var target := _hit_unit(hit)
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
	state.shooter_frame = shooter_frame
	_register_projectile(state)

func _register_projectile(state: Dictionary) -> void:
	var unit: BattleUnit = units[state.actor]
	state.visual_id = "%d/%d" % [unit.entity_id, unit.fire_serial]
	projectiles.append(state)

func projectile_view(viewer: BattleUnit) -> Array:
	var states: Array = []
	if viewer == null:
		return states
	for state: Dictionary in projectiles:
		if state.actor != viewer.entity_id or not state.has("visual_id"):
			continue
		var definition: Dictionary = state.definition
		states.append({"id": state.visual_id, "key": "%s-%s-%s" % [definition.ch, definition.slot, state.side.to_lower()],
			"position": state.position, "velocity": state.velocity, "age": state.age})
	return states

func present_echo(definition: Dictionary, origin: Vector3, unit: BattleUnit) -> void:
	if world == null or over or not unit.alive():
		return
	var reach := _launch_range(unit, definition, _aim_target(unit, TargetingMath.maximum_range(definition)))
	if not is_finite(reach):
		return
	var presentation := world.ensure_projectile_visuals()
	if definition.type in ["beam", "rail"]:
		var point: Vector3 = _projectile_aim(unit, reach, definition.area == "line").point
		presentation.tracer(origin, point, _fpv_tracer_color(definition.type, unit.side))
		return
	var target := origin + unit.aim_direction() * reach
	var ground := world.ground_height(target.x, target.z) if definition.type == "launcher" else NAN
	var surface := _weapon_surface(origin) if definition.trajectory in ["guide", "fnf"] else NAN
	if (definition.type == "launcher" and not is_finite(ground)) or (definition.trajectory in ["guide", "fnf"] and not is_finite(surface)):
		return
	var state := VisualShellMotion.launch(definition, origin, target, ground, surface, definition.projectile.speed)
	presentation.spawn_shell(state, "%s-%s-%s" % [definition.ch, definition.slot, unit.side.to_lower()])

func _projectile_surface(point: Vector3) -> float:
	var bottom: float = world.native_data.min_height - 100 if world.native_data != null else -100
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.01, Vector3(point.x, bottom, point.z), 8 | 16 | 32 | 64)
	# The synthetic test world uses only the ordinary static collision layer.
	if world.native_data == null:
		query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN

func _weapon_surface(point: Vector3) -> float:
	var ground := world.ground_height(point.x, point.z)
	if not is_finite(ground):
		return NAN
	var surface := world.layers.projectile_surface(point, ground)
	var probe := Vector3(point.x, maxf(point.y, surface) + Content.balance.structure.deckStep, point.z)
	if not is_finite(_projectile_surface(probe)):
		return NAN
	var physical := _projectile_surface(point)
	if is_finite(physical) and physical > surface and point.y >= physical - Content.balance.structure.deckStep:
		surface = physical
	return surface

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
			"side": state.side, "slot": state.get("slot", "heavy"), "terminal": terminal, "physical": true})
		if not terminal:
			continue
		projectiles.remove_at(index)
		var attacker: BattleUnit = units.get(state.actor)
		if attacker == null or not attacker.alive():
			continue
		if def.trajectory == "flat":
			if def.area == "line":
				_fire_line(attacker, def, state.origin, endpoint, state.origin_surface, state.shooter_frame)
			elif not hit.is_empty() and hit.collider.has_meta("missile"):
				if state.origin.distance_to(endpoint) <= def.range * Content.constants.RANGE_TOL:
					var fired_position: Vector3 = state.shooter_frame.position
					fired_position.y = state.shooter_frame.altitude
					_damage_missile(attacker, def, int(hit.collider.get_meta("missile")), fired_position)
			elif not hit.is_empty() and _hit_unit(hit) != null:
				var victim: BattleUnit = _hit_unit(hit)
				var surface := _height_reference(victim) if victim.is_hero() else world.ground_height(victim.position.x, victim.position.z)
				if not is_finite(surface):
					continue
				var target_height: float = victim.position.y - surface if victim.is_hero() else 0.0
				var fired_position: Vector3 = state.shooter_frame.position
				var offset := Vector3(victim.position.x - fired_position.x, target_height - state.shooter_frame.altitude, victim.position.z - fired_position.z)
				var reach: float = def.range * _settlement_range_factor(attacker, def, state.origin, state.origin_surface, victim, surface, state.shooter_frame) * Content.constants.RANGE_TOL
				var launch_budget: float = _launch_range_from_frame(def, state.shooter_frame, victim, surface) * Content.constants.RANGE_TOL
				if visible_to_side(victim, state.side) and _visible_from(state.origin, victim) and CombatMath.direct_in_range(reach, offset, victim.radius) and CombatMath.direct_in_range(launch_budget, victim.position - state.origin, victim.radius):
					if not _roll_miss(attacker, victim, def):
						var amount: float = def.dmg * CombatMath.damage_falloff(def, offset.length())
						amount = _roll_critical(attacker, victim, def, amount)
						damage(attacker, victim, def, amount, false, {"origin": state.origin})
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
		var friendly := LobFireControl.friendly_impact(def, state.shooter_frame.position if state.has("shooter_frame") else state.origin, endpoint)
		blast(attacker, def, Vector3(endpoint.x, maxf(0, endpoint.y - surface), endpoint.z), friendly, true, level)

func blast(unit: BattleUnit, def: Dictionary, impact: Vector3, friendly: bool = false, relative_heights: bool = false, impact_level: int = -1, npc_damage: float = NAN) -> void:
	# Coverage deliberately ignores LOS; each victim consumes the original blast bands.
	for target: BattleUnit in units.values():
		if not target.alive() or (target.side == unit.side and not friendly):
			continue
		if impact_level >= 0 and not world.layers.slabs.is_empty() and world.layers.separated(impact_level, Vector2(impact.x, impact.z), Vector2(target.position.x, target.position.z), _unit_level(target)):
			continue
		var position := target.position
		if relative_heights:
			position.y = _body_altitude(target)
			if not position.is_finite():
				continue
		var flat := Vector2(impact.x - position.x, impact.z - position.z)
		var horizontal := maxf(0, flat.length() - target.radius)
		var vertical := maxf(0, maxf(position.y - impact.y, impact.y - position.y - target.height))
		var distance := Vector2(horizontal, vertical).length()
		var factor := CombatMath.blast_falloff(def.get("r", 0), distance)
		if factor > 0:
			var same := target.side == unit.side
			var probability := 0.0 if same else _dodge_probability(target, unit)
			if not same and _roll_miss(unit, target, def):
				continue
			var compensation := 1.0 / (1 - clampf(probability, 0, Content.constants.EVASION.P_MAX))
			var amount: float = (npc_damage if is_finite(npc_damage) else float(def.get("dmg", 0))) * factor * compensation
			if is_finite(npc_damage) and not target.is_hero():
				amount *= unit.creep_multiplier
			var context := {"blast": impact, "radius": def.get("r", 0)}
			if is_finite(npc_damage):
				_apply_hit_elements(null if same else unit, def, target)
				damage(null if same else unit, target, def, amount, friendly, context, false)
			elif same:
				_apply_hit_elements(null, def, target)
				damage(null, target, def, amount * _weapon_multiplier(unit, target, def), friendly, context, false)
			else:
				damage(unit, target, def, amount, friendly, context)

func _fire_fan(unit: BattleUnit, def: Dictionary, origin: Vector3 = Vector3(INF, INF, INF)) -> void:
	if not origin.is_finite():
		origin = _advisory_origin(unit)
	var reference := _height_reference(unit)
	if not is_finite(reference):
		return
	var frame := _shooter_frame(unit, reference)
	var candidates: Array = []
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		if not visible_to_side(target, unit.side) or not _visible_from(origin, target):
			continue
		var surface := _height_reference(target) if target.is_hero() else world.ground_height(target.position.x, target.position.z)
		if not is_finite(surface):
			continue
		var range_factor := _settlement_range_factor(unit, def, origin, reference, target, surface, frame)
		var position := target.global_position
		position.y = _body_altitude(target)
		candidates.append({"id": target.entity_id, "kind": target.kind, "position": position,
			"radius": target.radius, "height": target.height, "range_factor": range_factor})
	var relative_origin := Vector3(origin.x, origin.y - reference, origin.z)
	for hit in CombatMath.fan_hits(def, relative_origin, unit.aim_direction(), candidates):
		damage(unit, units[hit.id], def, hit.amount, false, {"origin": origin})

func _visible_from(origin: Vector3, target: BattleUnit) -> bool:
	if not cubic_cages.is_empty():
		var surface := _weapon_surface(origin)
		if not is_finite(surface) or _skill_barriers_blocked(Vector3(origin.x, origin.y - surface, origin.z), _relative_target(target)):
			return false
	var query := PhysicsRayQueryParameters3D.create(origin, target.sight_target(), 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _shooter_frame(unit: BattleUnit, surface: float) -> Dictionary:
	return {"position": unit.global_position, "altitude": unit.global_position.y - surface,
		"eye_y": unit.global_position.y + unit.view_eye_height(), "sight_y": unit.global_position.y - surface + Content.constants.LOS.EYE_M, "surface": surface}

func camera_origin(unit: BattleUnit) -> Vector3:
	var position := unit.global_position
	var signature: Array = [position, unit.yaw, unit.flying, unit.character, unit.charge]
	var frame := Engine.get_physics_frames()
	if unit.camera_cache_frame == frame and unit.camera_cache_signature == signature:
		return unit.camera_cache_origin
	var camera := CameraPose.anchor(unit.character, position, unit.yaw, unit.flying, unit.charge)
	if world == null:
		return camera
	var blockers: Array = world.active_columns if world.native_data != null else []
	var surface := _weapon_surface(position)
	camera = CameraPose.clip(position, camera, unit.view_eye_height(), blockers, [], _unit_level(unit) == 1, surface,
		func(start: Vector3, end: Vector3): return world.obstruction_hit(start, end, false), _weapon_surface)
	unit.camera_cache_frame = frame
	unit.camera_cache_signature = signature
	unit.camera_cache_origin = camera
	return camera

func _launch_range_from_frame(def: Dictionary, frame: Dictionary, target: BattleUnit, target_surface: float) -> float:
	var position: Vector3 = frame.position
	var eye := Vector3(position.x, frame.eye_y, position.z)
	return TargetingMath.launch_range(def, position, eye, frame.surface,
		{"hero": target.is_hero(), "position": target.position, "kind": target.kind,
		"altitude": target.position.y - target_surface})

func _advisory_origin(unit: BattleUnit) -> Vector3:
	unit.ensure_weapon_pose()
	return unit.weapon_pose.current_muzzle(unit.aim_transform())

func _settlement_range_factor(unit: BattleUnit, def: Dictionary, origin: Vector3, origin_surface: float, target: BattleUnit, target_surface: float, shooter_frame: Dictionary = {}) -> float:
	var gap: float
	if target.is_pilot():
		gap = shooter_frame.get("eye_y", origin.y) - (target.global_position.y + target.view_eye_height())
	else:
		# Source compares two absolute hero eyes, otherwise two heights above their own surfaces.
		var shooter_sight: float = shooter_frame.get("sight_y", origin.y - origin_surface - unit.height * Content.constants.SELF_F.eye + Content.constants.LOS.EYE_M)
		var target_sight: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["base", "tower"] else target.position.y - target_surface + (Content.constants.LOS.EYE_M if target.is_hero() or target.kind in ["heli", "decoy", "kami", "hyper"] else Content.constants.LOS.TGT_M)
		gap = shooter_sight - target_sight
	var factor := CombatMath.altitude_range(def, gap)
	for buff in unit.buffs:
		if buff.until > clock:
			factor *= buff.get("mul", {}).get("range", 1.0)
	return factor

func _fire_line(unit: BattleUnit, def: Dictionary, origin: Vector3, endpoint: Vector3, origin_surface: float = NAN, shooter_frame: Dictionary = {}) -> void:
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
	if not shooter_frame.is_empty():
		origin_surface = shooter_frame.surface
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive():
			continue
		if not visible_to_side(target, unit.side) or not _visible_from(origin, target):
			continue
		var surface := _height_reference(target) if target.is_hero() else world.ground_height(target.position.x, target.position.z)
		if not is_finite(surface):
			continue
		var relative_sample: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["tower", "base"] else Content.constants.LOS.TGT_M + (target.position.y - surface if target.is_hero() or target.kind == "heli" else 0.0)
		var relative_position := target.position
		relative_position.y = _body_altitude(target)
		candidates.append({"id": target.entity_id, "position": relative_position, "radius": target.radius,
			"height": target.height, "sample_y": relative_sample,
			"relative_y": relative_sample - (origin.y - origin_surface),
			"range_factor": _settlement_range_factor(unit, def, origin, origin_surface, target, surface, shooter_frame)})
	var relative_origin := Vector3(origin.x, origin.y - origin_surface, origin.z)
	for hit in CombatMath.line_hits(def, relative_origin, direction, length, candidates):
		var target: BattleUnit = units[hit.id]
		damage(unit, target, def, _roll_critical(unit, target, def, hit.amount), false, {"origin": origin, "direction": direction})
	for missile: Dictionary in missiles.duplicate():
		if missile.side != unit.side and MissileMotion.line_contains(def, relative_origin, direction, length, missile.position):
			_damage_missile(unit, def, int(missile.id), relative_origin)

func _acquire_base_target(unit: BattleUnit, reach: float) -> BattleUnit:
	return _npc_acquire(unit, {"range": reach})

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
		unit.gun_cooldowns[index] = 1.0 / (guns.rate * weather_attack_rate(unit))
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
	if not target.is_hero() and target.kind != "heli" and target.special.get("role") not in ["summon", "hologram", "carrier"]:
		return 0.0
	var surface := _height_reference(target) if target.is_hero() else world.ground_height(target.position.x, target.position.z)
	return target.position.y - surface

func _body_altitude(target: BattleUnit) -> float:
	# Source body/LOS target bands do not use the altitude of the newer non-hero summon kinds.
	return _missile_target_altitude(target) if target.is_hero() or target.kind in ["heli", "decoy", "kami", "hyper"] else 0.0

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
		"altitude": _missile_target_altitude(unit), "kami": unit.kind == "kami", "decoy": unit.kind == "decoy", "hyper": unit.kind == "hyper"}
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

func damage(attacker: BattleUnit, target: BattleUnit, def: Dictionary, amount: float, friendly: bool = false,
		context: Dictionary = {}, attack_modifiers: bool = true) -> void:
	var same := attacker != null and target.side == attacker.side
	if not authoritative or over or not target.alive() or (same and not friendly) or amount <= 0:
		return
	if target.special.get("invulnerable", false) or target.special.get("garrison", false):
		return
	if attacker != null and (attacker.side == Content.constants.SUPER_SIDE and target.side in ["GUER", "MILI"] or target.side == Content.constants.SUPER_SIDE and attacker.side in ["GUER", "MILI"]):
		return
	if attack_modifiers:
		if def.get("area") not in ["fan", "blast"] and not context.has("blast"):
			_apply_hit_emp(def, target)
		_apply_hit_elements(attacker, def, target)
		amount *= _weapon_multiplier(attacker, target, def)
	if context.get("weather_weapon", not def.is_empty()) and not reflecting:
		amount *= float(weather_dynamics.get("rainAtkMul", 1))
	if target.has_status("freeze_until", clock):
		amount *= 1 - Content.constants.WEATHER_FREEZE.DMG_REDUCTION
	if target.has_status("inv_until", clock) or target.has_status("phase_until", clock):
		return
	if target.has_status("reflect_until", clock) and attacker != null:
		var offset := Vector2(attacker.position.x - target.position.x, attacker.position.z - target.position.z)
		var forward := Vector2(-sin(target.yaw), -cos(target.yaw))
		if offset.length() > 0.01 and forward.dot(offset.normalized()) >= cos(float(target.status.get("reflect_arc", deg_to_rad(120))) / 2):
			var reflected: float = amount * float(target.status.get("reflect_ratio", 0.6))
			if not same and not reflecting:
				reflecting = true
				damage(target, attacker, def, reflected, false, {}, false)
				reflecting = false
			events.append({"type": "reflect_hit", "actor": target.entity_id, "attacker": attacker.entity_id, "amount": reflected})
			return
	if target.is_hero():
		var wet := target.wet
		if not wet and target.special.get("role") == "clone":
			var owner: BattleUnit = units.get(int(target.special.owner_id))
			wet = owner.wet if owner != null else 0
		amount *= StatusRules.multiplier(target.buffs, "dmgTaken", clock) * StatusRules.fluid_factor(wet)
		var defense_factor := _shield_defense_factor(target, attacker, def, context)
		amount *= defense_factor
		_stamp_suppression(target, attacker)
		var blast_hit := def.get("area") == "blast" or context.has("blast")
		var unbalance: float = Content.constants.SHIELD_DEFENSE.FLIGHT_UNBAL_BLAST_F if blast_hit else Content.constants.SHIELD_DEFENSE.FLIGHT_UNBAL_DIRECT_F
		_stamp_unbalance(target, unbalance if defense_factor < 1 else 1.0)
		target.damaged_at = clock
		_break_on_hit(target)
		_interrupt_cast(target)
	var credit := _damage_credit(attacker)
	if credit != null and not same:
		target.assists[credit.peer_id] = true
		credit.last_hit_target = target.entity_id
	var split := CombatMath.shield_split(def, amount, target.shield)
	var shield_loss := minf(target.shield, split.toSp)
	var durability := 1.0
	if not target.is_hero() and (attacker == null or not attacker.is_hero()):
		durability = NpcRules.creep_damage_taken(target.creep_multiplier, target.armor, def.get("pen", 0))
	var hp_damage := split.toHp * CombatMath.armor_multiplier(target.armor, def.get("pen", 0)) * durability
	if target.special.get("third", false) and target.kind != "bunker" and attacker != null and not attacker.side.is_empty() and attacker.side != target.side and not attacker.special.get("neutral", false):
		target.special.aggro_id = attacker.entity_id
		target.special.aggro_at = clock
	var hp_loss := minf(target.hp, hp_damage)
	target.shield = maxf(0, target.shield - split.toSp)
	target.hp = maxf(0, target.hp - hp_damage)
	target.damaged_at = clock
	if target.shield <= 0:
		target.defending = false
	var dealt := shield_loss + hp_loss
	_record_air_sink(target, dealt)
	if attacker != null and not same and dealt > 0:
		attacker.damage_out += dealt
		target.threat[attacker.entity_id] = float(target.threat.get(attacker.entity_id, 0)) + dealt
		if attacker.is_hero() and attacker.alive():
			_heal_body(attacker, dealt * StatusRules.maximum(attacker.buffs, "vamp", clock))
		events.append({"type": "hurt", "actor": target.entity_id, "attacker": attacker.entity_id,
			"origin": attacker.position, "amount": dealt, "side": target.side})
	if target.hp > 0:
		return
	_kill_unit(target, attacker)

func _kill_unit(target: BattleUnit, attacker: BattleUnit) -> void:
	if not authoritative:
		return
	var same := attacker != null and target.side == attacker.side
	if target.special.get("role") == "civilian":
		_kill_civilian(target, attacker)
		return
	if target.special.get("role") == "slab":
		_remove_field_unit(target.entity_id, true)
		return
	if target.special.get("role") == "clone":
		var owner: BattleUnit = units.get(int(target.special.owner_id))
		if owner != null:
			owner.clone_ids.erase(target.entity_id)
		_remove_field_unit(target.entity_id, true)
		return
	if target.is_pilot() and _clone_death_swap(target):
		return
	target.visible = false
	target.collision_layer = 0
	target.collision_mask = 0
	target.hit_area.collision_layer = 0
	var bounty: float = Content.constants.ECON.BOUNTY.get(target.kind, 0)
	if attacker != null and attacker.is_hero() and not same:
		if attacker.is_pilot():
			attacker.money += bounty * StatusRules.multiplier(attacker.buffs, "bounty", clock)
		if not target.special.get("neutral", false):
			attacker.score = minf(Content.constants.BATTLE_SCORE.MAX, attacker.score + Content.constants.BATTLE_SCORE.KILL * (Content.constants.BATTLE_SCORE.HARD_F if target.is_hero() or target.kind == "tower" else 1))
	for peer in target.assists:
		var contributor: BattleUnit = pilots.get(peer)
		if contributor == null or contributor.side == target.side or (attacker != null and attacker.is_hero() and contributor.peer_id == attacker.peer_id):
			continue
		var height := _missile_target_altitude(target) - _missile_target_altitude(contributor)
		var radius: float = Content.constants.ECON.ASSIST.R_M
		var reach := maxf(radius, CombatMath.max_horizontal(radius, height))
		if Vector2(contributor.position.x - target.position.x, contributor.position.z - target.position.z).length() > reach:
			continue
		if not target.special.get("neutral", false):
			contributor.score = minf(Content.constants.BATTLE_SCORE.MAX, contributor.score + Content.constants.BATTLE_SCORE.ASSIST * (Content.constants.BATTLE_SCORE.HARD_F if target.is_hero() or target.kind == "tower" else 1))
		var earned: float = bounty * Content.constants.ECON.ASSIST.F * StatusRules.multiplier(contributor.buffs, "bounty", clock)
		contributor.money += earned
		if bounty > 0:
			if match_stats.has(contributor.side):
				match_stats[contributor.side].assists += 1
			events.append({"type": "assist", "actor": contributor.entity_id, "target": target.entity_id, "amount": roundf(earned)})
	target.assists.clear()
	if attacker != null and attacker.is_hero() and attacker.alive() and not same and not target.special.get("neutral", false):
		_heal_body(attacker, attacker.max_hp * StatusRules.maximum(attacker.buffs, "killHeal", clock))
	target.cast_state.clear()
	target.defending = false
	if target.is_hero():
		if match_stats.has(target.side):
			match_stats[target.side].deaths += 1
		if attacker != null and not same and match_stats.has(attacker.side):
			match_stats[attacker.side].kills += 1
	elif not target.special.get("neutral", false) and target.special.get("role") != "carrier" and attacker != null and attacker.is_hero() and not same and match_stats.has(attacker.side):
		var weight := float(Content.constants.UNITS.get(target.kind, {}).get("bounty", 1))
		match_stats[attacker.side].creepKills += weight if weight != 0 else 1
	if target.special.get("third", false):
		_remove_field_unit(target.entity_id, true)
		_on_third_death(target, attacker)
		return
	if target.special.get("role") == "hazard":
		if SceneRules.physical(target.kind) and Content.constants.HAZARDS[target.kind].get("block", false):
			_collapse_scene(target)
		else:
			hazard_blockers = hazard_blockers.filter(func(obstacle): return float(obstacle.x) != float(target.position.x) or float(obstacle.z) != float(target.position.z))
			_remove_field_unit(target.entity_id, true)
		_drop_scene_loot(target)
		return
	if target.special.get("role") == "carrier":
		_carrier_shot_down(target)
		return
	if target.kind == "base":
		over = true
		winner = "STEEL" if target.side == "SWARM" else "SWARM"
		result.emit(winner)
	elif target.is_pilot():
		target.deaths += 1
		var times: Dictionary = Content.constants.UNITS[target.kind].respawn
		target.respawn_at = clock + times.base + times.perDeath * target.deaths
		var penalty: float = (target.respawn_at - clock) * Content.constants.ECON.DEATH_PENALTY_PER_S
		target.money = maxf(0, target.money - penalty)
		events.append({"type": "penalty", "actor": target.entity_id, "amount": roundf(penalty)})

func _fire_burn(unit: BattleUnit, amount: float) -> void:
	if not authoritative or over or not unit.alive() or unit.special.get("invulnerable", false) or unit.special.get("garrison", false):
		return
	if unit.is_hero() and unit.has_status("inv_until", clock):
		return
	if unit.max_hp + unit.max_shield <= 0:
		return
	var state := EnvironmentRules.burn_split(unit.hp, unit.shield, unit.max_hp, unit.max_shield, amount, StatusRules.multiplier(unit.buffs, "dmgTaken", clock))
	unit.damaged_at = clock
	unit.hp = state.hp
	unit.shield = state.shield
	if unit.hp <= 0:
		var killer: BattleUnit = pilots.get(int(unit.bleed.get("peer", 0)))
		_kill_unit(unit, killer)

func _shield_defense_factor(target: BattleUnit, attacker: BattleUnit, definition: Dictionary, context: Dictionary) -> float:
	if not target.defending or target.shield <= 0:
		return 1.0
	var forward := Vector2(-sin(target.yaw), -cos(target.yaw))
	var center := Vector2(target.position.x, target.position.z)
	var attack_slot := ""
	for slot: String in ["heavy", "light"]:
		var weapon := Content.weapon(target.character, slot, int(target.upgrades.hw if slot == "heavy" else target.upgrades.lw) + 1)
		var fired: float = target.last_fired_at.get(slot, -INF)
		if fired != 0 and clock - fired < 1.0 / (weapon.rate * 0.5):
			attack_slot = slot
			break
	var boosted := target.has_status("shield_def_boost_until", clock)
	var arc: float = Content.constants.SHIELD_DEFENSE.EXPAND_ARC if target.has_status("shield_expand_until", clock) else Content.constants.SHIELD_DEFENSE.FRONT_ARC
	if context.has("blast") or definition.get("area") == "blast":
		var point: Vector3 = context.get("blast", attacker.position if attacker != null else Vector3(INF, INF, INF))
		var shield_center := center + forward * target.radius
		var fallback_radius: float = definition.get("radius", 8.0)
		var radius: float = context.get("radius", fallback_radius if fallback_radius else 8.0)
		if point.is_finite() and Vector2(point.x, point.z).distance_to(shield_center) <= radius + target.radius:
			return StatusRules.shield_kind_factor(target.kind, true, boosted, attack_slot)
		return 1.0
	var origin: Vector3 = context.get("origin", attacker.position if attacker != null else Vector3(INF, INF, INF))
	if not origin.is_finite():
		if context.has("direction"):
			var direction: Vector3 = context.direction
			if forward.dot(Vector2(direction.x, direction.z)) <= -cos(arc / 2):
				return StatusRules.shield_kind_factor(target.kind, false, boosted, attack_slot)
		return 1.0
	var offset := Vector2(origin.x, origin.z) - center
	if offset.length() > 0.01 and forward.dot(offset.normalized()) >= cos(arc / 2):
		return StatusRules.shield_kind_factor(target.kind, false, boosted, attack_slot)
	return 1.0

func _record_air_sink(target: BattleUnit, amount: float) -> void:
	if not target.is_hero() or not target.flying or amount <= 0:
		return
	if target.kind == "drone" and _missile_target_altitude(target) < WeatherRules.unbalance_threshold(float(weather_dynamics.get("wind", 0))):
		return
	var distance := MovementRules.sink_distance(amount, float(weather_dynamics.get("wind", 0)))
	if target.is_bot:
		target.move_and_collide(Vector3.DOWN * minf(_missile_target_altitude(target), distance))
	else:
		target.air_sink += distance
		target.air_sink_speed = target.air_sink / Content.constants.FLIGHT.SINK_S
		var factor: float = Content.constants.SHIELD_DEFENSE.FLIGHT_UNBAL_DIRECT_F if target.defending and target.shield > 0 else 1.0
		target.lift_lock_until = maxf(target.lift_lock_until, clock + Content.constants.FLIGHT.HIT_LOCK_S * factor)

func _weapon_multiplier(attacker: BattleUnit, target: BattleUnit, definition: Dictionary) -> float:
	var factor := CombatMath.vs_multiplier(definition, target.kind)
	if attacker == null:
		return factor
	if factor > 1 and CombatMath.target_class(target.kind) == "air" and _air_unit(attacker):
		factor = 1.0
	return factor * StatusRules.multiplier(attacker.buffs, "dmg", clock)

func _air_unit(unit: BattleUnit) -> bool:
	if unit.kind not in Content.constants.AIR.KINDS:
		return false
	var jump: float = Content.constants.UNITS[unit.kind].get("jump", 0)
	return _missile_target_altitude(unit) > jump * jump / (2 * Content.constants.AIR.GRAV)

func _stamp_unbalance(target: BattleUnit, factor: float) -> void:
	if not target.is_hero():
		return
	var altitude := _missile_target_altitude(target)
	if target.kind == "drone" and altitude < WeatherRules.unbalance_threshold(float(weather_dynamics.get("wind", 0))):
		return
	var flying := target.kind == "drone" or (target.kind == "morph" and altitude > Content.constants.MORPH.GROUND_Y) or altitude >= Content.constants.GAME.AA_MIN_ALT
	if not flying and not _air_unit(target):
		return
	target.status.unbalanced_until = maxf(float(target.status.get("unbalanced_until", 0)), clock + Content.constants.FLIGHT.UNBAL_S * maxf(0.1, factor))

func _height_difference(first: BattleUnit, second: BattleUnit) -> float:
	if first == null or second == null:
		return 0.0
	if first.is_pilot() and second.is_pilot():
		return first.position.y + first.view_eye_height() - second.position.y - second.view_eye_height()
	return _relative_sight_height(first) - _relative_sight_height(second)

func _relative_sight_height(unit: BattleUnit) -> float:
	if unit.kind in ["tower", "base"]:
		return Content.constants.LOS.TOWER_EYE_M
	var altitude := _missile_target_altitude(unit)
	return altitude + (Content.constants.LOS.EYE_M if unit.is_hero() or unit.kind in ["heli", "decoy", "kami", "hyper"] else Content.constants.LOS.TGT_M)

func _suppression(unit: BattleUnit) -> float:
	return float(unit.status.get("sup_factor", 0)) if unit != null and unit.has_status("sup_until", clock) else 0.0

func _stamp_suppression(target: BattleUnit, attacker: BattleUnit) -> void:
	var strength := StatusRules.suppression_strength(_height_difference(target, attacker)) if attacker != null else 0.0
	if strength <= 0:
		return
	target.status.sup_factor = maxf(_suppression(target), strength)
	target.status.sup_until = clock + Content.constants.HIGH_SUP.DUR_S

func _dodge_probability(target: BattleUnit, attacker: BattleUnit) -> float:
	if target == null or not target.is_hero():
		return 0.0
	if StatusRules.maximum(target.buffs, "dodge", clock) > 0:
		return 1.0
	var flying := target.kind == "drone" or _missile_target_altitude(target) >= Content.constants.GAME.AA_MIN_ALT
	var mobility: float = Content.heroes[target.character].flySpeed if flying else Content.heroes[target.character].speed
	if mobility <= StatusRules.evasion_min_speed() or Vector2(target.velocity.x, target.velocity.z).length() < Content.constants.EVASION.MOVING_SPD:
		return 0.0
	var probability: float = Content.constants.EVASION.GROUND + (Content.constants.EVASION.AIR_BONUS if flying else 0.0) + StatusRules.maximum(target.buffs, "evade", clock)
	var difference := _height_difference(target, attacker)
	if difference > 0:
		probability += Content.constants.ALTITUDE.DODGE * CombatMath.altitude_strength(difference)
	return minf(probability, Content.constants.EVASION.P_MAX) * (1 - Content.constants.HIGH_SUP.DODGE * _suppression(target))

func _roll_miss(attacker: BattleUnit, target: BattleUnit, definition: Dictionary) -> bool:
	if definition.is_empty() or definition.get("area") in ["fan", "line"]:
		return false
	var probability := StatusRules.miss_probability(_dodge_probability(target, attacker), _suppression(attacker),
		attacker != null and attacker.has_status("unbalanced_until", clock), _weather_accuracy_penalty())
	if probability <= 0 or rng.next() >= probability:
		return false
	events.append({"type": "dodge", "actor": target.entity_id, "attacker": attacker.entity_id if attacker != null else 0,
		"position": target.position, "side": target.side})
	return true

func _roll_critical(attacker: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float, prepared: bool = false) -> float:
	if attacker == null:
		return amount
	var forced: bool = attacker.status.get("phase_critical", false)
	if forced:
		attacker.status.phase_critical = false
	elif not definition.get("crit", 0):
		return amount
	var factors := StatusRules.critical_factors(_height_difference(attacker, target))
	var rate: float = definition.get("crit", 0) * factors.rate
	if attacker.has_status("unbalanced_until", clock):
		rate *= Content.constants.FLIGHT.UNBAL_CRIT_MUL
	if not forced and rng.next() >= rate:
		return amount
	var multiplier: float = definition.get("critX", 0)
	if multiplier == 0:
		multiplier = Content.constants.VITALS.CRIT_X
	amount *= 1 + (multiplier - 1) * factors.damage
	events.append({"type": "crit", "actor": attacker.entity_id, "target": target.entity_id,
		"position": target.position, "amount": floorf(amount * (1.0 if prepared else _weapon_multiplier(attacker, target, definition)) + 0.5)})
	return amount

func _apply_hit_emp(definition: Dictionary, target: BattleUnit) -> void:
	if not definition.get("emp", 0) or not target.is_hero() or StatusRules.maximum(target.buffs, "ccImm", clock) > 0:
		return
	target.status.emp_until = maxf(float(target.status.get("emp_until", 0)), clock + float(definition.emp))

func _apply_hit_elements(attacker: BattleUnit, definition: Dictionary, target: BattleUnit) -> void:
	var element: String = definition.get("elem") if definition.get("elem") is String else ""
	if element.is_empty() or element == "physical" or not target.alive() or target.kind in ["tower", "base", "bunker"]:
		return
	if target.is_hero() and (target.has_status("inv_until", clock) or StatusRules.maximum(target.buffs, "ccImm", clock) > 0):
		return
	var heavy := definition.get("id") == "heavy"
	var fast: bool = definition.get("rate", 0) > 5
	var effect := ""
	if element in ["shock", "impact", "shockwave"]:
		var probability: float = 0.35 if heavy else 0.12 if fast else 0.22
		if element != "shock":
			probability = 0.60 if heavy else 0.28 if fast else 0.45
		if definition.get("elemProb") != null:
			probability = float(definition.elemProb)
		if rng.next() >= probability:
			return
		if element == "shock":
			var duration: float = definition.get("empDur", 1.2)
			target.status.emp_until = maxf(float(target.status.get("emp_until", 0)), clock + (duration if duration else 1.2))
			effect = "emp_hit"
		else:
			target.status.stagger_stacks = mini(3, int(target.status.get("stagger_stacks", 0)) + 1)
			target.status.stun_until = minf(clock + 1.2, maxf(clock, float(target.status.get("stun_until", 0))) + 0.25)
			effect = "stagger"
	else:
		var buildup: Dictionary = target.status.get("element_buildup", {})
		var last_hit: Dictionary = target.status.get("element_last_hit", {})
		var increment: float = definition.get("elemBuildup", 0)
		if increment == 0:
			increment = 40 if heavy else 12 if fast else 25
		buildup[element] = float(buildup.get(element, 0)) + increment
		last_hit[element] = clock
		target.status.element_buildup = buildup
		target.status.element_last_hit = last_hit
		if float(buildup[element]) < (50 if element in ["poison", "sonic"] else 100):
			return
		buildup[element] = 0.0
		var peer := attacker.peer_id if attacker != null else 0
		var actor := attacker.entity_id if attacker != null else 0
		match element:
			"poison":
				target.status.poison_stacks = mini(5, int(target.status.get("poison_stacks", 0)) + 1)
				var base_damage: float = definition.get("dmg", 0)
				var dps := maxf(6, floorf((base_damage if base_damage else 50) * 0.15 + 0.5))
				target.bleed = {"dps": dps * target.status.poison_stacks, "until": clock + 3.0, "pen": 10, "peer": peer, "actor": actor}
				target.status.slow_until = maxf(float(target.status.get("slow_until", 0)), clock + 2.0)
				target.status.slow_factor = maxf(0.5, 1 - 0.08 * int(target.status.poison_stacks))
				effect = "poison_hit"
			"sonic":
				target.status.sonic_stacks = mini(4, int(target.status.get("sonic_stacks", 0)) + 1)
				target.status.confuse_until = minf(clock + 3.5, maxf(clock, float(target.status.get("confuse_until", 0))) + 0.8)
				effect = "confuse_hit"
			"fire":
				var base_damage: float = definition.get("dmg", 0)
				var penetration: float = definition.get("pen", 0)
				target.bleed = {"dps": maxf(15, floorf((base_damage if base_damage else 60) * 0.35 + 0.5)), "until": clock + 3.0,
					"pen": penetration if penetration else 8, "peer": peer, "actor": actor}
				effect = "burn"
			"frost":
				target.status.slow_until = maxf(float(target.status.get("slow_until", 0)), clock + 2.5)
				target.status.slow_factor = 0.45
				effect = "freeze"
	if not effect.is_empty():
		events.append({"type": effect, "actor": target.entity_id, "position": target.position, "element": element,
			"side": target.side, "stacks": target.status.get("poison_stacks", 0) if element == "poison" else target.status.get("sonic_stacks", 0) if element == "sonic" else target.status.get("stagger_stacks", 0)})

func _heal_body(unit: BattleUnit, amount: float, source: String = "def") -> float:
	if not authoritative or not unit.alive() or amount <= 0:
		return 0.0
	var factor := 1.0
	var cap := unit.max_hp
	if unit.special.get("boss", false):
		if source != "def":
			return 0.0
		factor = float(Content.constants.BOSS.HEAL_DEF_F)
		cap *= StatusRules.boss_hp_cap(float(unit.special.get("boss_segment", 0)))
	if factor <= 0:
		return 0.0
	var amplification := StatusRules.multiplier(unit.buffs, "healAmp", clock) if unit.is_hero() else 1.0
	var before := unit.hp
	unit.hp = minf(cap, unit.hp + amount * factor * amplification)
	if unit.hp > before:
		unit.status.erase("lightning_scorch")
	return maxf(0, unit.hp - before)

func _break_on_hit(unit: BattleUnit) -> void:
	var broken := unit.buffs.any(func(buff): return buff.get("break_on_hit", false))
	unit.buffs = unit.buffs.filter(func(buff): return not buff.get("break_on_hit", false))
	if broken:
		unit.status.no_reload_until = 0

func respawn(unit: BattleUnit) -> void:
	unit.hp = unit.max_hp
	unit.shield = unit.max_shield
	unit.power = unit.max_power
	unit.flying = unit.kind == "drone"
	unit.position = world.spawn_position(unit.side, unit.spawn_slot, unit.kind == "drone")
	unit.yaw = world.spawn_heading(unit.side, unit.spawn_slot)
	unit.velocity = Vector3.ZERO
	unit.impulse_velocity = Vector2.ZERO
	unit.charge = 0
	unit.low_gravity = false
	unit.lift = Content.constants.FLIGHT.LIFT_MAX
	unit.air_sink = 0
	unit.air_sink_speed = 0
	unit.lift_lock_until = 0
	unit.damaged_at = -99
	unit.wet = 0
	unit.fluid_environment.clear()
	unit.respawn_at = 0
	unit.collision_mask = 1 | 4
	unit.refresh_collision()
	unit.visible = unit.presentation_visible
	unit.buffs.clear()
	unit.status.erase("lightning_scorch")
	unit.status.last_weather_freeze = -Content.constants.WEATHER_FREEZE.COOLDOWN_S
	for key: String in ["stun_until", "slow_until", "confuse_until", "blind_until", "inv_until", "emp_until", "stealth_until", "mark_until", "unbalanced_until", "cast_lock_until", "freeze_until", "sup_until", "sup_factor", "element_buildup", "element_last_hit", "poison_stacks", "sonic_stacks", "stagger_stacks"]:
		unit.status.erase(key)
	unit.cast_state.clear()
	unit.bleed.clear()
	unit.heal_aura.clear()
	unit.assists.clear()
	unit.defending = false
	unit.aim_anchor = 0
	unit.lock_target = 0
	unit.lock_at = -100.0
	unit.aim_off_at = -100.0
	unit.reload_at.clear()
	unit.fire_at.clear()
	for slot in ["light", "heavy"]:
		unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades.lw if slot == "light" else unit.upgrades.hw) + 1).mag

func _regenerate(unit: BattleUnit, delta: float) -> void:
	var charge: float = Content.balance.charge[int(unit.upgrades.ch)]
	var fluid := StatusRules.fluid_factor(unit.wet)
	var regen := StatusRules.multiplier(unit.buffs, "regen", clock)
	if unit.power < unit.max_power:
		unit.power = minf(unit.max_power, unit.power + Content.constants.UNITS[unit.kind].mpRegen * charge * fluid * delta)
	var out_of_combat: bool = clock - unit.damaged_at > Content.constants.VITALS.OOC_S
	if out_of_combat or unit.has_status("sp_regen_hit_until", clock):
		unit.shield = minf(unit.max_shield, unit.shield + unit.max_shield * Content.constants.VITALS.SP_REGEN_PS * charge * regen * fluid * delta)
	if out_of_combat:
		_heal_body(unit, unit.max_hp * Content.constants.VITALS.HP_REGEN_PS * charge * regen * fluid * delta, "ooc")
	var near_base := Vector2(unit.position.x - world.bases[unit.side].x, unit.position.z - world.bases[unit.side].z).length() < Content.constants.GAME.HERO_HEAL_RADIUS
	if regen > 1 or near_base:
		_heal_body(unit, Content.constants.UNITS[unit.kind].regen * regen * delta, "def" if regen > 1 else "base")
	if unit.wet == 3 and unit.alive():
		_fire_burn(unit, float(Content.constants.TERRAIN_FX.FROZEN_DOT) * delta)
		if float(unit.status.get("fluid_freeze_report", 0)) + 2 < clock:
			unit.status.fluid_freeze_report = clock
			events.append({"type": "fluid_freeze", "actor": unit.entity_id, "position": unit.position})

func buy(unit: BattleUnit, item: String) -> bool:
	if not authoritative or over:
		return false
	var definitions: Dictionary = Content.constants.ECON.UPGRADES
	if not definitions.has(item) or not unit.is_pilot() or unit.special.get("boss", false) or unit.side == Content.constants.SUPER_SIDE:
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
			if unit.alive():
				unit.hp += maximum - unit.max_hp
			unit.max_hp = maximum
		"sp":
			var maximum := roundf(stats.shield * hero.mods.get("sp", 1) * (1 + definitions.sp.step * unit.upgrades.sp))
			if unit.alive():
				unit.shield += maximum - unit.max_shield
			unit.max_shield = maximum
		"ar":
			unit.armor = hero.armor + definitions.ar.step * unit.upgrades.ar
		"lw", "hw":
			var slot := "light" if item == "lw" else "heavy"
			unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades[item]) + 1).mag
			unit.reload_at.erase(slot)
	return true

func upgrades_maxed(unit: BattleUnit) -> bool:
	for key: String in Content.constants.ECON.UPGRADES:
		if int(unit.upgrades.get(key, 0)) < int(Content.constants.ECON.UPGRADES[key].max):
			return false
	return true

func buy_creep(unit: BattleUnit, lane: int) -> bool:
	if not authoritative or over or not unit.is_pilot() or unit.special.get("boss", false) or not upgrades_maxed(unit):
		return false
	var levels: Array = creep_upgrades.get(unit.side, [])
	if lane < 0 or lane >= levels.size():
		return false
	var definition: Dictionary = Content.constants.CREEP_UPG
	if int(levels[lane]) >= int(definition.MAX) or unit.money < float(definition.PRICE):
		return false
	unit.money -= definition.PRICE
	levels[lane] = int(levels[lane]) + 1
	events.append({"type": "creep_upgrade", "actor": unit.entity_id, "side": unit.side, "lane": lane, "level": levels[lane]})
	return true

func cast(unit: BattleUnit, slot: String) -> bool:
	if not authoritative or over or not unit.alive() or not unit.is_pilot() or slot not in ["def", "atk"]:
		return false
	var def := Content.ability(unit.character, slot, int(unit.upgrades[slot]) + 1)
	if not _ability_supported(def):
		message.emit(unit.peer_id, "unsupported")
		return false
	var point := _ability_point(unit, def)
	if not point.is_finite() or not _companion_surfaces_available(unit, def, point):
		message.emit(unit.peer_id, "unavailable_surface")
		return false
	if def.fx == "cube":
		for index in range(6):
			var angle := index * PI / 3
			if world == null or not is_finite(world.ground_height(unit.position.x + cos(angle) * 5.5, unit.position.z - sin(angle) * 5.5)):
				message.emit(unit.peer_id, "unavailable_surface")
				return false
	if _ready_charges(unit, slot, def) <= 0 or unit.has_status("emp_until", clock) or unit.has_status("cast_lock_until", clock) or not unit.cast_state.is_empty():
		return false
	var cost := floorf(float(def.mp) + 0.5)
	if unit.power < cost:
		return false
	unit.power -= cost
	var deadline: float = clock + def.cd * float(weather_dynamics.get("snowCdMul", 1))
	if int(def.charges) > 1:
		var charge: Dictionary = unit.ability_charges.get(slot, {"max": int(def.charges), "recharge_at": []})
		charge.max = int(def.charges)
		charge.recharge_at.append(deadline)
		unit.ability_charges[slot] = charge
		unit.cooldowns[slot] = 0 if charge.recharge_at.size() < charge.max else charge.recharge_at.min()
	else:
		unit.cooldowns[slot] = deadline
	if def.fx not in ["stealth", "vision", "rally", "recon"]:
		unit.status.stealth_until = 0
	if slot == "def":
		unit.cast_state = {"slot": slot, "start": clock, "duration": def.castTime, "point": point,
			"definition": def.duplicate(true), "level": int(unit.upgrades[slot]) + 1}
		events.append({"type": "cast_start", "actor": unit.entity_id, "slot": slot, "fx": def.fx, "duration": def.castTime})
		return true
	unit.defending = false
	unit.status.cast_lock_until = clock + (def.castTime if def.castTime else Content.constants.ATK_CAST_S)
	if def.carrier:
		_launch_carriers(unit, def, point, _ability_origin(unit, slot))
	else:
		_cast_effect(unit, def, unit.position if def.target == "self" or (def.add is Dictionary and def.add.get("fx") == "clone") else point)
	events.append({"type": "cast", "actor": unit.entity_id, "slot": slot, "fx": def.fx, "point": point,
		"radius": def.r, "duration": def.dur, "fraction": 1.0})
	return true

func _ability_point(unit: BattleUnit, definition: Dictionary) -> Vector3:
	if not definition.range:
		return unit.position
	var hit := _projectile_aim(unit, maxf(float(definition.range) * 1.4, 200))
	var point: Vector3 = hit.point
	point.x = floorf(point.x * 10 + 0.5) / 10
	point.z = -floorf(-point.z * 10 + 0.5) / 10
	var offset := Vector2(point.x - unit.position.x, point.z - unit.position.z)
	if offset.length() > float(definition.range):
		offset = offset.normalized() * float(definition.range)
		point.x = unit.position.x + offset.x
		point.z = unit.position.z + offset.y
	point.y = world.ground_height(point.x, point.z)
	return point

func _ability_origin(unit: BattleUnit, slot: String) -> Vector3:
	if slot != "atk":
		return unit.position
	var origin := unit.position
	var distance := INF
	for structure: BattleUnit in units.values():
		if not structure.alive() or structure.side != unit.side or structure.kind not in ["tower", "base"]:
			continue
		var candidate := _planar_distance(unit.position, structure.position)
		if candidate < distance:
			origin = structure.position
			distance = candidate
	return origin

func _carrier_resources_available() -> bool:
	if not Content.balance.has("carrier"):
		return false
	for key: String in ["steel_s01_kami", "swarm_s01_kami", "steel_decoy", "swarm_decoy", "steel_hyper", "swarm_hyper"]:
		if not Content.balance.get("companions", {}).has(key) or not ResourceLoader.exists("res://assets/companions/%s.scn" % key):
			return false
	return true

func _launch_carriers(owner: BattleUnit, definition: Dictionary, point: Vector3, origin: Vector3) -> void:
	var surface := world.ground_height(origin.x, origin.z)
	if not is_finite(surface):
		message.emit(owner.peer_id, "unavailable_surface")
		return
	var start := {"x": float(origin.x), "y": float(origin.y - surface), "z": -float(origin.z)}
	var destination := CarrierRules.destination(start, point.x, -point.z, owner.yaw)
	var parts := CarrierRules.parts(owner.kind, definition.fx)
	var total: float = definition.count if definition.fx in ["strike", "summon"] else 0.0
	if owner.character == "s01" or owner.kind == "drone" and owner.character not in ["t09", "m07"]:
		var rule: Dictionary = Content.constants.SQUAD.KAMI
		var count: int = int(definition.count if definition.count else rule.N) if owner.character == "s01" else parts
		var speed: float = Content.constants.UNITS.drone.speed * rule.SPEED_MUL
		for index in range(count):
			var side := CarrierRules.side(index)
			var state := {"kind": "kami", "x": start.x - sin(destination.yaw) * rule.FWD + cos(destination.yaw) * rule.SIDE * side,
				"z": start.z + cos(destination.yaw) * rule.FWD + sin(destination.yaw) * rule.SIDE * side, "y": start.y,
				"yaw": destination.yaw + rule.SPREAD * side, "tx": destination.x, "tz": destination.z,
				"fraction": 1.0 / count, "count": CarrierRules.integer_part(total, parts, index) if total else -1,
				"die_at": clock + destination.distance / speed + rule.TTL_S, "target": 0}
			_spawn_carrier(owner, definition, state)
	elif owner.character == "m06" or owner.kind == "morph" and owner.character != "m07":
		var rule: Dictionary = Content.constants.DECOY
		var count: int = int(definition.count if definition.count else 5) if owner.character == "m06" else parts
		var drops: Array = []
		for index in range(count):
			drops.append({"fraction": 1.0 / count, "count": CarrierRules.integer_part(total, parts, index) if total else -1})
		_spawn_carrier(owner, definition, {"kind": "decoy", "x": start.x, "z": start.z, "y": start.y + rule.ALT,
			"yaw": destination.yaw, "tx": destination.x, "tz": destination.z, "drops": drops, "next_bomb": 0.0,
			"die_at": clock + destination.distance / rule.SPEED + count * rule.BOMB_GAP + rule.TTL_S, "target": 0})
	else:
		var count := 1
		if owner.character in ["t09", "m07"]:
			count = int(definition.count if definition.count else 8 if owner.character == "t09" else 6)
		for index in range(count):
			var tx: float = destination.x
			var tz: float = destination.z
			if owner.character == "t09":
				var angle := float(index) / count * TAU + (rng.next() - 0.5) * 0.5
				var radius: float = 0.0 if index == 0 else (0.2 + 0.8 * rng.next()) * (definition.scatter if definition.scatter else 50.0)
				tx += cos(angle) * radius
				tz += sin(angle) * radius
			elif owner.character == "m07":
				var radius: float = (definition.scatter if definition.scatter else 35.0) * (0.2 + float(index) / count * 1.2)
				var angle := rng.next() * TAU
				tx += cos(angle) * radius
				tz += sin(angle) * radius
			var dx: float = tx - start.x
			var dz: float = tz - start.z
			var distance := maxf(1, sqrt(dx * dx + dz * dz))
			_spawn_carrier(owner, definition, {"kind": "hyper", "x": start.x, "z": start.z, "y": start.y,
				"x0": start.x, "z0": start.z, "y0": start.y, "yaw": atan2(-dx, dz), "tx": tx, "tz": tz,
				"ux": dx / distance, "uz": dz / distance, "distance": distance, "travel": 0.0,
				"phase": "climb", "spin": 0.0, "dive": {}, "chase": false, "target": 0,
				"fraction": 1.0 / count, "count": CarrierRules.integer_part(total, parts, index) if total else -1,
				"launch_at": clock + index * 0.22 if owner.character == "m07" else 0.0})

func _spawn_carrier(owner: BattleUnit, definition: Dictionary, state: Dictionary) -> BattleUnit:
	var position := _missile_world_position(Vector3(state.x, state.y, -state.z))
	if not position.is_finite():
		message.emit(owner.peer_id, "unavailable_surface")
		return null
	var model_key := "%s_%s_kami" % [owner.side.to_lower(), owner.character] if state.kind == "kami" else "%s_%s" % [owner.side.to_lower(), state.kind]
	var unit := spawn({"kind": state.kind, "side": owner.side, "position": position, "yaw": state.yaw,
		"special": {"role": "carrier", "owner_id": owner.entity_id, "owner_peer": owner.peer_id, "model_key": model_key, "hp": Content.balance.carrier.hp[state.kind]}})
	unit.collision_layer = 0
	unit.collision_mask = 0
	state.owner_id = owner.entity_id
	state.definition = definition.duplicate(true)
	carrier_states[unit.entity_id] = state
	owner.carrier_ids.append(unit.entity_id)
	events.append({"type": "carrier_spawn", "actor": unit.entity_id, "owner": owner.entity_id, "kind": state.kind,
		"side": owner.side, "position": position, "slot": definition.id})
	return unit

func _tick_carriers(delta: float) -> void:
	# Original producers run bomber, kamikaze and hypersonic rosters in separate passes.
	for kind: String in ["decoy", "kami", "hyper"]:
		for owner: BattleUnit in pilots.values():
			for index in range(owner.carrier_ids.size() - 1, -1, -1):
				var id: int = owner.carrier_ids[index]
				var unit: BattleUnit = units.get(id)
				if unit == null or not carrier_states.has(id):
					owner.carrier_ids.remove_at(index)
					carrier_states.erase(id)
					continue
				var state: Dictionary = carrier_states[id]
				if state.kind != kind:
					continue
				if not unit.alive():
					_remove_carrier(id)
					continue
				var target: BattleUnit = units.get(int(state.target))
				var target_data := {}
				if target != null and target.alive():
					target_data = {"x": float(target.position.x), "z": -float(target.position.z), "height": _relative_target(target).y}
				var outcome := CarrierRules.advance(state, delta, clock, target_data)
				var position := _missile_world_position(Vector3(state.x, state.y, -state.z))
				if not position.is_finite():
					message.emit(owner.peer_id, "unavailable_surface")
					_remove_carrier(id)
					continue
				unit.position = position
				unit.yaw = state.yaw
				unit.rotation.y = unit.yaw
				unit.special.phase = state.get("phase", "flight")
				for arrival: Dictionary in outcome.arrivals:
					_carrier_arrive(unit, Vector3(arrival.x, 0, -arrival.z), arrival.fraction, int(arrival.count))
				if outcome.remove:
					events.append({"type": "boom", "actor": owner.entity_id, "position": unit.position, "radius": 6.0 if kind == "kami" else 8.0, "side": unit.side})
					_remove_carrier(id)
					continue

func _carrier_arrive(unit: BattleUnit, point: Vector3, fraction: float, count_override: int = -1) -> void:
	var state: Dictionary = carrier_states.get(unit.entity_id, {})
	var owner: BattleUnit = pilots.get(int(unit.special.owner_peer))
	if state.is_empty() or owner == null or not owner.is_pilot():
		return
	point.y = world.ground_height(point.x, point.z)
	if not point.is_finite():
		message.emit(owner.peer_id, "unavailable_surface")
		return
	_cast_effect(owner, state.definition, point, fraction, true, count_override)
	events.append({"type": "ability_arrive", "actor": owner.entity_id, "carrier": unit.entity_id, "position": point,
		"fraction": fraction, "count": count_override, "fx": state.definition.fx, "side": owner.side})

func _carrier_shot_down(unit: BattleUnit) -> void:
	events.append({"type": "boom", "actor": int(unit.special.owner_id), "position": unit.position, "radius": 6.0,
		"side": unit.side, "intercept": true})
	_remove_carrier(unit.entity_id)

func _remove_carrier(id: int) -> void:
	var state: Dictionary = carrier_states.get(id, {})
	var owner: BattleUnit = units.get(int(state.get("owner_id", 0)))
	if owner != null:
		owner.carrier_ids.erase(id)
	carrier_states.erase(id)
	_remove_field_unit(id)

func _ability_supported(definition: Dictionary) -> bool:
	if definition.support or definition.fx not in ["buff", "heal", "emp", "vision", "stealth", "rally", "recon", "intercept", "reflect", "phaseshift", "shield_bash", "strike", "fog", "cube", "summon", "decoy_beacon"]:
		return false
	if definition.carrier and not _carrier_resources_available():
		return false
	if definition.fx == "summon" and definition.unit not in SUMMON_KINDS:
		return false
	if definition.fx in ["summon", "decoy_beacon"]:
		var kind: String = definition.unit if definition.fx == "summon" else "decoy_beacon"
		for side: String in ["steel", "swarm"]:
			if not Content.balance.get("companions", {}).has(side + "_" + kind) or not ResourceLoader.exists("res://assets/companions/%s_%s.scn" % [side, kind]):
				return false
	var added: Variant = definition.get("add")
	return not added is Dictionary or added.fx in ["haste", "leap", "dodge", "vamp", "mark", "evade", "overdrive", "alpha", "stun", "slow", "confuse", "bleed", "pull", "siege", "clone"]

func _ready_charges(unit: BattleUnit, slot: String, definition: Dictionary) -> int:
	var maximum := maxi(1, int(definition.charges))
	if maximum <= 1:
		return 1 if float(unit.cooldowns.get(slot, 0)) <= clock else 0
	if not unit.ability_charges.has(slot):
		return maximum
	var state: Dictionary = unit.ability_charges[slot]
	state.max = maximum
	state.recharge_at = state.recharge_at.filter(func(deadline): return float(deadline) > clock)
	var available := maxi(0, maximum - state.recharge_at.size())
	unit.cooldowns[slot] = 0 if available > 0 else state.recharge_at.min()
	return available

func _add_modifier(unit: BattleUnit, key: String, value: float, duration: float, break_on_hit: bool = false) -> void:
	unit.buffs.append({"until": clock + duration, "mul": {key: value}, "break_on_hit": break_on_hit})

func _ability_allies(unit: BattleUnit, center: Vector3, radius: float, global_team: bool = false) -> Array:
	return pilots.values().filter(func(ally): return ally.side == unit.side and (global_team or (ally.alive() and Vector2(ally.position.x - center.x, ally.position.z - center.z).length() <= radius)))

func _cast_effect(unit: BattleUnit, definition: Dictionary, center: Vector3, fraction: float = 1.0, once: bool = true, count_override: int = -1) -> void:
	if not authoritative or over:
		return
	var boost := {"dmgMul": 0.0, "heal": 0.0, "alphaX": 1.0}
	if definition.id == "atk":
		boost = StatusRules.self_attack_boost(unit.character, int(unit.upgrades.atk) + 1, int(unit.upgrades.lw) + 1, int(unit.upgrades.hw) + 1)
	var allies: Array = _ability_allies(unit, center, definition.r) if definition.target == "team" else [unit]
	var modifiers: Dictionary = definition.mul if definition.mul is Dictionary else {}
	var added: Dictionary = definition.add if definition.add is Dictionary else {}
	match definition.fx:
		"buff":
			for ally: BattleUnit in allies:
				for key: String in modifiers:
					var value: float = modifiers[key] + (boost.dmgMul if key == "dmg" else 0)
					_add_modifier(ally, key, 1 + (value - 1) * fraction, definition.dur, definition.brk)
				match added.get("fx", ""):
					"haste", "leap":
						var key := "speed" if added.fx == "haste" else "jump"
						var value := float(added.get("f", 1.25 if added.fx == "haste" else 2))
						_add_modifier(ally, key, 1 + (value - 1) * fraction, definition.dur)
					"dodge": _add_modifier(ally, "dodge", 1, definition.dur)
					"vamp": _add_modifier(ally, "vamp", float(added.get("f", 0.12)) * fraction, definition.dur)
					"evade", "overdrive":
						_add_modifier(ally, "evade", float(added.get("evade", 0)) * fraction, definition.dur, definition.brk)
						if added.fx == "overdrive" and once:
							_refill_all(ally)
							ally.status.no_reload_until = clock + definition.dur
					"mark":
						if once:
							ally.status.mark_until = clock + float(added.get("dur", definition.dur))
					"clone":
						if once:
							ally.status.clones_until = clock + definition.dur
							ally.status.no_light_reload_until = clock + definition.dur
							_spawn_clones(ally, int(added.get("count", 2)) if added.get("count", 2) else 2)
					"siege":
						if once:
							_refill_all(ally)
							ally.status.no_heavy_reload_until = clock + definition.dur
							ally.status.rooted_until = clock + definition.dur + float(added.get("recoverS", 1.5))
							ally.status.root_position = ally.position
							events.append({"type": "siege_mode", "actor": ally.entity_id, "side": ally.side, "until": clock + definition.dur})
		"heal":
			var amount: float = definition.heal + boost.heal
			for ally: BattleUnit in allies:
				if amount > 0:
					_heal_body(ally, amount * fraction)
					if definition.sp and not definition.aura:
						ally.shield = minf(ally.max_shield, ally.shield + ally.max_shield * fraction)
				if definition.cleanse and once:
					_cleanse(ally)
				var duration: float = definition.dur * fraction
				if duration > 0:
					if definition.ccImm or (definition.cleanse and not definition.aura and definition.id == "def"):
						_add_modifier(ally, "ccImm", 1, duration)
					if definition.healAmp > 0:
						_add_modifier(ally, "healAmp", 1 + definition.healAmp * fraction, duration)
					if definition.regen > 0:
						_add_modifier(ally, "regen", 1 + (definition.regen - 1) * fraction, duration)
			if definition.aura and once:
				var duration: float = (definition.dur if definition.dur else 6) * fraction
				unit.heal_aura = {"until": clock + duration, "radius": definition.r if definition.r else 28,
					"hps": (definition.hot if definition.hot else 35) * fraction,
					"sp_hps": (definition.spRestore / duration if definition.spRestore and duration > 0 else 15 if definition.sp else 0) * fraction,
					"cleanse": definition.cleanse}
		"emp":
			for target: BattleUnit in units.values():
				if target.side == unit.side or not target.alive() or target.kind in ["tower", "base", "bunker"] or Vector2(target.position.x - center.x, target.position.z - center.z).length() > definition.r:
					continue
				if target.is_hero() and StatusRules.maximum(target.buffs, "ccImm", clock) > 0:
					continue
				target.status.emp_until = maxf(float(target.status.get("emp_until", 0)), clock + definition.dur * fraction)
				if definition.dmg > 0:
					damage(unit, target, definition, definition.dmg * fraction, false, {"origin": center}, false)
			if not added.is_empty():
				_apply_cc(unit, added, center, definition.r)
			vision_until[unit.side] = maxf(float(vision_until[unit.side]), clock + definition.vision * fraction)
		"vision", "intercept":
			if definition.fx == "intercept":
				var radius: float = definition.r * sqrt(maxf(0.01, fraction))
				for missile: Dictionary in missiles.duplicate():
					if missile.side == unit.side or Vector2(missile.position.x - unit.position.x, missile.position.z - unit.position.z).length() > radius:
						continue
					_remove_missile(int(missile.id))
					events.append({"type": "missile_intercept", "actor": unit.entity_id, "missile": missile.id,
						"position": _missile_world_position(missile.position), "radius": 8.0, "side": unit.side})
			vision_until[unit.side] = maxf(float(vision_until[unit.side]), clock + definition.vision * fraction)
		"stealth":
			if once:
				unit.status.stealth_until = clock + definition.dur * fraction
				if added.get("fx") == "alpha":
					unit.status.alpha_multiplier = boost.alphaX
					unit.status.alpha_arm_until = clock + definition.dur
		"reflect":
			unit.status.reflect_until = clock + (definition.dur if definition.dur else 3.0) * fraction
			unit.status.reflect_arc = deg_to_rad(float(definition.get("arc", 120)))
			unit.status.reflect_ratio = definition.get("ratio", 0.6)
		"phaseshift":
			unit.status.phase_until = clock + (definition.dur if definition.dur else 1.8) * fraction
			unit.status.phase_damage = (definition.dmg if definition.dmg else 50) * fraction
		"fog": _spawn_fog(unit, definition, center)
		"cube": _spawn_cubic_slabs(unit, definition, center, fraction)
		"summon": _spawn_autonomous_summons(unit, definition, center, fraction, count_override)
		"decoy_beacon": _spawn_holograms(unit, definition, fraction)
		"rally", "recon":
			for ally: BattleUnit in _ability_allies(unit, center, 0, true):
				if definition.revive > 0 and once and not ally.alive() and ally.respawn_at > clock:
					_revive_body(ally, definition.revive)
				if not ally.alive():
					continue
				for key: String in modifiers:
					_add_modifier(ally, key, 1 + (float(modifiers[key]) - 1) * fraction, definition.dur)
				if definition.regen > 0:
					_add_modifier(ally, "regen", 1 + (definition.regen - 1) * fraction, definition.dur)
				if added.get("fx") == "evade":
					_add_modifier(ally, "evade", float(added.get("evade", 0)) * fraction, definition.dur)
				if definition.cleanse:
					if once:
						_cleanse(ally)
					_add_modifier(ally, "ccImm", 1, definition.dur)
			if definition.vision and once:
				vision_until[unit.side] = maxf(float(vision_until[unit.side]), clock + definition.vision)
		"strike":
			for index in range(count_override if count_override >= 0 else maxi(0, ceili(float(definition.count)))):
				var angle := rng.next() * TAU
				var radius := 0.0 if index == 0 else rng.next() * (definition.scatter if definition.scatter else definition.r * 2)
				var point := center + Vector3(cos(angle) * radius, 0, -sin(angle) * radius)
				point.y = 0
				var attack := {"dmg": definition.dmg * fraction, "r": definition.r, "vs": definition.vs, "pen": definition.pen,
					"vsSp": definition.vsSp, "vsHp": definition.vsHp, "spPierce": definition.spPierce,
					"elem": definition.elem, "elemBuildup": definition.elemBuildup}
				blast(unit, attack, point, false, true, 0)
				if not added.is_empty():
					_apply_cc(unit, added, point, definition.r)
	if definition.fx == "buff" and definition.vision and once:
		vision_until[unit.side] = maxf(float(vision_until[unit.side]), clock + definition.vision * fraction)
	for ally: BattleUnit in allies:
		if definition.spRestore and once and not definition.aura and ally.alive():
			ally.shield = minf(ally.max_shield, ally.shield + definition.spRestore * fraction)
		var duration: float = (definition.dur if definition.dur else 8) * fraction
		if definition.spRegenHit:
			ally.status.sp_regen_hit_until = maxf(float(ally.status.get("sp_regen_hit_until", 0)), clock + duration)
		if definition.shieldDefBoost:
			ally.status.shield_def_boost_until = maxf(float(ally.status.get("shield_def_boost_until", 0)), clock + duration)
	var duration: float = (definition.dur if definition.dur else 8) * fraction
	for flag: String in ["shieldExpand", "shieldBash", "defJump"]:
		if definition[flag]:
			var key: String = {"shieldExpand": "shield_expand_until", "shieldBash": "shield_bash_until", "defJump": "def_jump_until"}[flag]
			unit.status[key] = maxf(float(unit.status.get(key, 0)), clock + duration)

func _refill_all(unit: BattleUnit) -> void:
	unit.reload_at.clear()
	for slot: String in ["light", "heavy"]:
		unit.ammo[slot] = Content.weapon(unit.character, slot, int(unit.upgrades.hw if slot == "heavy" else unit.upgrades.lw) + 1).mag

func _cleanse(unit: BattleUnit) -> void:
	for key: String in ["stun_until", "slow_until", "confuse_until", "emp_until"]:
		unit.status[key] = 0
	unit.bleed.clear()
	for key: String in ["element_buildup", "element_last_hit"]:
		unit.status.erase(key)
	for key: String in ["poison_stacks", "sonic_stacks", "stagger_stacks"]:
		unit.status[key] = 0
	events.append({"type": "cleanse", "actor": unit.entity_id, "side": unit.side})

func _revive_body(unit: BattleUnit, fraction: float) -> void:
	unit.hp = maxf(1, floorf(unit.max_hp * fraction + 0.5))
	unit.shield = unit.max_shield * fraction
	unit.respawn_at = 0
	unit.damaged_at = clock
	unit.status.inv_until = clock + Content.constants.SELF_ATK.REVIVE_INV_S
	for key: String in ["stun_until", "slow_until", "confuse_until", "blind_until", "sup_until", "sup_factor"]:
		unit.status[key] = 0
	unit.bleed.clear()
	unit.assists.clear()
	unit.status.erase("element_buildup")
	unit.status.erase("element_last_hit")
	unit.collision_mask = 1 | 4
	unit.refresh_collision()
	unit.visible = unit.presentation_visible
	events.append({"type": "revive", "actor": unit.entity_id, "side": unit.side})

func _interrupt_cast(unit: BattleUnit) -> void:
	if unit.special.get("role") == "clone":
		unit = units.get(int(unit.special.owner_id))
		if unit == null:
			return
	if unit.cast_state.is_empty():
		return
	var state := unit.cast_state.duplicate(true)
	unit.cast_state.clear()
	unit.status.cast_lock_until = 0
	var ratio: float = clampf(clock - state.start, 0, state.duration) / state.duration if state.duration > 0 else 1.0
	var fraction := ratio * ratio
	_cast_effect(unit, state.definition, state.point, fraction)
	events.append({"type": "cast", "actor": unit.entity_id, "slot": "def", "fx": state.definition.fx,
		"fraction": fraction, "interrupted": true, "point": state.point})

func _apply_cc(unit: BattleUnit, added: Dictionary, center: Vector3, radius: float) -> void:
	for target: BattleUnit in units.values():
		if target.side == unit.side or not target.alive() or target.kind in ["tower", "base", "bunker"]:
			continue
		if target.is_hero() and (target.has_status("inv_until", clock) or StatusRules.maximum(target.buffs, "ccImm", clock) > 0):
			continue
		if Vector2(target.position.x - center.x, target.position.z - center.z).length() > radius * 1.5:
			continue
		match added.fx:
			"stun", "slow", "confuse":
				var key: String = {"stun": "stun_until", "slow": "slow_until", "confuse": "confuse_until"}[added.fx]
				var default_duration: float = {"stun": 1.0, "slow": 2.5, "confuse": 2.0}[added.fx]
				target.status[key] = maxf(float(target.status.get(key, 0)), clock + float(added.get("dur", default_duration)))
				if added.fx == "slow":
					target.status.slow_factor = added.get("f", 0.6)
			"bleed":
				target.bleed = {"dps": added.get("dps", 15), "until": clock + float(added.get("dur", 4)), "pen": added.get("pen", 10), "peer": unit.peer_id}
			"pull":
				var offset := Vector2(center.x - target.position.x, center.z - target.position.z)
				var distance := offset.length()
				var impulse: float = added.get("imp", 18)
				if impulse == 0:
					impulse = 18
				if target.is_hero() and not target.is_bot:
					if distance > 1:
						var push := offset / distance * minf(impulse, distance * 2)
						if target.flying:
							target.velocity.x += push.x
							target.velocity.z += push.y
						else:
							target.impulse_velocity += push
							target.velocity.y += 3
				else:
					var denominator := distance if distance else 1.0
					_place_solid(target, offset / denominator * minf(impulse * 0.5, denominator))

func _place_solid(unit: BattleUnit, offset: Vector2) -> void:
	if not unit.alive() or not offset.is_finite():
		return
	unit.move_and_collide(Vector3(offset.x, 0, offset.y))

func _tick_element_buildup(unit: BattleUnit, delta: float) -> void:
	var buildup: Dictionary = unit.status.get("element_buildup", {})
	var last_hit: Dictionary = unit.status.get("element_last_hit", {})
	for element: String in buildup.keys():
		if clock - float(last_hit.get(element, 0)) > 2.5:
			buildup[element] = maxf(0, float(buildup[element]) - 20 * delta)
			if float(buildup[element]) <= 0:
				buildup.erase(element)
	if unit.bleed.is_empty() or float(unit.bleed.until) <= clock:
		unit.status.poison_stacks = 0
	if not unit.has_status("confuse_until", clock):
		unit.status.sonic_stacks = 0
	if not unit.has_status("stun_until", clock):
		unit.status.stagger_stacks = 0

func _tick_shield_bash(unit: BattleUnit, delta: float) -> void:
	if not unit.is_hero() or not unit.defending or unit.shield <= 0 or not unit.has_status("shield_bash_until", clock):
		return
	var forward := Vector2(-sin(unit.yaw), -cos(unit.yaw))
	for target: BattleUnit in units.values():
		if not target.alive() or target.side == unit.side:
			continue
		var offset := Vector2(target.position.x - unit.position.x, target.position.z - unit.position.z)
		var distance := offset.length()
		var denominator := distance if distance else 1.0
		if distance > 4.0 + (target.effect_radius if target.effect_radius else 1.0) or forward.dot(offset / denominator) < 0.5:
			continue
		_place_solid(target, offset / denominator * 12 * delta)
		damage(unit, target, {"pen": 10}, 35 * delta, false, {"weather_weapon": false}, false)
		if float(target.status.get("bash_at", 0)) + 1.0 < clock:
			target.status.bash_at = clock
			events.append({"type": "shield_bash", "actor": unit.entity_id, "target": target.entity_id, "position": target.position})

func _damage_credit(attacker: BattleUnit) -> BattleUnit:
	if attacker == null:
		return null
	return attacker if attacker.is_hero() else units.get(int(attacker.special.get("owner_id", 0)))

func _auto_target(companion: BattleUnit, owner: BattleUnit) -> BattleUnit:
	var sight: float = companion.special.get("sight", 200)
	if not sight:
		sight = 200
	if owner != null and owner.last_hit_target:
		var focus: BattleUnit = units.get(owner.last_hit_target)
		if focus != null and focus.alive() and focus.side != companion.side and _planar_distance(companion.position, focus.position) <= sight * 1.5:
			return focus
	var best: BattleUnit
	var best_score := INF
	for candidate: BattleUnit in units.values():
		if not candidate.alive() or candidate.side == companion.side or candidate.side.is_empty() or candidate.special.get("neutral", false):
			continue
		var distance := _planar_distance(companion.position, candidate.position)
		if distance > sight:
			continue
		var score := distance + (0.0 if candidate.is_hero() else 50.0 if candidate.kind in ["tower", "base"] else 100.0)
		if score < best_score:
			best = candidate
			best_score = score
	return best

func _planar_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()

func _companion_position(center: Vector3, offset: Vector2, altitude: float) -> Vector3:
	if world == null:
		return Vector3(NAN, NAN, NAN)
	var point := Vector3(center.x + offset.x, 0, center.z + offset.y)
	point.y = world.ground_height(point.x, point.z) + altitude
	return point

func _summon_plan(_unit: BattleUnit, definition: Dictionary, center: Vector3, fraction: float, random: SourceRng, count_override: int = -1) -> Array:
	var profile: Dictionary = Content.constants.UNITS[definition.unit]
	var count := count_override if count_override >= 0 else maxi(1, int(floorf(float(definition.count if definition.count else 2) * fraction + 0.5)))
	var altitude: float = (Content.constants.GAME.HELI_ALT if "heli" in definition.unit else Content.constants.GAME.DRONE_ALT) if profile.get("fly", false) else 0.0
	var plan: Array = []
	for index in range(count):
		var angle := float(index) / count * TAU + (random.next() - 0.5) * 0.5
		var direction := Vector2(cos(angle), -sin(angle))
		plan.append({"position": _companion_position(center, direction * (6 + index * 4), altitude), "offset": direction * 12})
	return plan

func _companion_surfaces_available(unit: BattleUnit, definition: Dictionary, center: Vector3 = Vector3(NAN, NAN, NAN)) -> bool:
	if not center.is_finite():
		center = unit.position
	if definition.fx == "summon":
		for entry: Dictionary in _summon_plan(unit, definition, center, 1, SourceRng.new(rng.state)):
			if not entry.position.is_finite():
				return false
	elif definition.fx == "decoy_beacon":
		for index in range(int(definition.count if definition.count else 2)):
			var offset := Vector2(cos(unit.yaw), -sin(unit.yaw)) * (-3 if index == 0 else 3)
			if not _companion_position(unit.position, offset, 2).is_finite():
				return false
	elif definition.add is Dictionary and definition.add.get("fx") == "clone":
		for index in range(int(definition.add.get("count", 2)) if definition.add.get("count", 2) else 2):
			var angle := unit.yaw + (2.1 if index == 0 else -2.1)
			if not _companion_position(unit.position, Vector2(cos(angle), -sin(angle)) * 4, _missile_target_altitude(unit)).is_finite():
				return false
	return true

func _spawn_clones(owner: BattleUnit, count: int = 2) -> void:
	_despawn_clones(owner)
	owner.clones_initialized = true
	var altitude := _missile_target_altitude(owner)
	for index in range(count):
		var angle := owner.yaw + (2.1 if index == 0 else -2.1)
		var direction := Vector2(cos(angle), -sin(angle))
		var point := _companion_position(owner.position, direction * 4, altitude)
		if not point.is_finite():
			message.emit(owner.peer_id, "unavailable_surface")
			continue
		var clone := spawn({"character": owner.character, "kind": owner.kind, "side": owner.side,
			"peer": owner.peer_id, "position": point, "yaw": owner.yaw, "effect_radius": owner.effect_radius if owner.effect_radius else 1.8,
			"special": {"role": "clone", "owner_id": owner.entity_id, "offset": direction * 12,
				"hp": owner.hp, "max_hp": owner.max_hp, "shield": owner.shield, "max_shield": owner.max_shield, "armor": owner.armor, "speed": 0.0, "cd": 0.0}})
		clone.flying = owner.flying
		clone.refresh_collision()
		owner.clone_ids.append(clone.entity_id)
	events.append({"type": "clone_spawn", "actor": owner.entity_id, "side": owner.side, "count": count})

func _despawn_clones(owner: BattleUnit) -> void:
	if not owner.clones_initialized:
		return
	for id: int in owner.clone_ids:
		_remove_field_unit(id)
	owner.clone_ids.clear()
	# The source spawn helper clears these flags on every subsequent cast, including an empty previous roster.
	owner.status.erase("clones_until")
	owner.status.erase("no_light_reload_until")

func _clone_death_swap(owner: BattleUnit) -> bool:
	var best: BattleUnit
	for id: int in owner.clone_ids:
		var clone: BattleUnit = units.get(id)
		if clone != null and clone.alive() and (best == null or clone.hp > best.hp):
			best = clone
	if best == null:
		return false
	owner.hp = best.hp
	owner.shield = best.shield
	# Lethal swaps bypass horizontal collision; expiry swaps use the source placement seam.
	owner.position.x = best.position.x
	owner.position.z = best.position.z
	owner.clone_ids.erase(best.entity_id)
	_remove_field_unit(best.entity_id)
	events.append({"type": "clone_death_swap", "actor": owner.entity_id, "side": owner.side, "position": owner.position})
	return true

func _tick_clones(delta: float) -> void:
	for owner: BattleUnit in pilots.values():
		if owner.clone_ids.is_empty():
			continue
		if not owner.alive():
			_despawn_clones(owner)
			continue
		if clock >= float(owner.status.get("clones_until", 0)):
			var best := owner
			for id: int in owner.clone_ids:
				var clone: BattleUnit = units.get(id)
				if clone != null and clone.alive() and clone.hp > best.hp:
					best = clone
			if best != owner:
				owner.hp = best.hp
				owner.shield = best.shield
				_place_solid(owner, Vector2(best.position.x - owner.position.x, best.position.z - owner.position.z))
				events.append({"type": "clone_time_swap", "actor": owner.entity_id, "side": owner.side, "position": owner.position})
			_despawn_clones(owner)
			continue
		var weapon := Content.weapon(owner.character, "light", int(owner.upgrades.lw) + 1)
		var sight: float = Content.constants.UNITS[owner.kind].get("sight", weapon.range if weapon.range else 200)
		for id: int in owner.clone_ids.duplicate():
			var clone: BattleUnit = units.get(id)
			if clone == null or not clone.alive():
				continue
			clone.special.cd = maxf(0, float(clone.special.cd) - delta)
			clone.special.sight = sight
			if clone.flying != owner.flying:
				clone.flying = owner.flying
				clone.refresh_collision()
			var ground := world.ground_height(clone.position.x, clone.position.z)
			if is_finite(ground):
				clone.position.y = ground + _missile_target_altitude(owner)
			var target := _auto_target(clone, owner)
			if target != null:
				var distance := _planar_distance(clone.position, target.position)
				if distance <= weapon.range:
					_face_companion(clone, target.position)
					if clone.special.cd == 0:
						clone.special.cd = 1.0 / ((float(weapon.rate) if weapon.rate else 3.0) * weather_attack_rate(clone))
						var amount: float = weapon.dmg * _weapon_multiplier(owner, target, weapon) * CombatMath.damage_falloff(weapon, distance)
						amount = _roll_critical(clone, target, weapon, amount, true)
						damage(clone, target, weapon, amount, false, {"origin": clone.position}, false)
						_companion_shot(clone, target, weapon)
				else:
					_move_companion(clone, target.position, minf(21 * _companion_weather_speed(clone) * delta, distance - float(weapon.range) * 0.85))
					_face_companion(clone, target.position)
				continue
			var point := owner.position + Vector3(clone.special.offset.x, 0, clone.special.offset.y)
			var distance := _planar_distance(clone.position, point)
			if distance > 6:
				_move_companion(clone, point, minf(21 * _companion_weather_speed(clone) * delta, distance - 4))
			clone.yaw = owner.yaw
			clone.rotation.y = clone.yaw

func _spawn_autonomous_summons(owner: BattleUnit, definition: Dictionary, center: Vector3, fraction: float = 1.0, count_override: int = -1) -> void:
	var profile: Dictionary = Content.constants.UNITS[definition.unit]
	var scale_factor := 1.0 + float(int(owner.upgrades[definition.id]) if definition.id in ["def", "atk"] else 0) * 0.35
	for entry: Dictionary in _summon_plan(owner, definition, center, fraction, rng, count_override):
		if not entry.position.is_finite():
			message.emit(owner.peer_id, "unavailable_surface")
			continue
		var health := floorf(float(profile.hp) * scale_factor + 0.5)
		var summon := spawn({"kind": definition.unit, "side": owner.side, "position": entry.position,
			"special": {"role": "summon", "owner_id": owner.entity_id, "offset": entry.offset, "hp": health, "max_hp": health,
				"dmg": floorf(float(profile.dmg) * scale_factor + 0.5), "armor": profile.get("armor", 0), "speed": profile.get("speed", 15),
				"range": profile.get("range", 150), "rate": profile.get("rate", 0.8), "sight": profile.get("sight", 200), "wid": profile.get("wid", ""), "cd": 0.0}})
		autonomous_summons.append(summon.entity_id)
		events.append({"type": "summon_spawn", "actor": summon.entity_id, "kind": summon.kind, "side": summon.side, "position": summon.position})

func _tick_summons(delta: float) -> void:
	for index in range(autonomous_summons.size() - 1, -1, -1):
		var summon: BattleUnit = units.get(autonomous_summons[index])
		if summon == null or not summon.alive():
			_remove_field_unit(autonomous_summons[index])
			autonomous_summons.remove_at(index)
			continue
		var owner: BattleUnit = units.get(int(summon.special.owner_id))
		var target := _auto_target(summon, owner)
		summon.special.cd = maxf(0, float(summon.special.cd) - delta)
		if target != null:
			var distance := _planar_distance(summon.position, target.position)
			if distance <= float(summon.special.range):
				if summon.special.cd == 0:
					summon.special.cd = 1.0 / ((float(summon.special.rate) if summon.special.rate else 0.8) * weather_attack_rate(summon))
					var weapon: Dictionary = Content.constants.WEAPONS.get(summon.special.wid, {"dmg": summon.special.dmg, "pen": 0})
					damage(summon, target, weapon, float(summon.special.dmg) * CombatMath.damage_falloff(weapon, distance), false, {}, false)
					_companion_shot(summon, target, weapon)
			else:
				_move_companion(summon, target.position, minf(summon.speed * _companion_weather_speed(summon) * delta, distance - float(summon.special.range) * 0.85))
		elif owner != null and owner.alive():
			var point := owner.position + Vector3(summon.special.offset.x, 0, summon.special.offset.y)
			var distance := _planar_distance(summon.position, point)
			if distance > 6:
				_move_companion(summon, point, minf(summon.speed * _companion_weather_speed(summon) * delta, distance - 4))

func _spawn_holograms(owner: BattleUnit, definition: Dictionary, fraction: float = 1.0) -> void:
	var weapon := Content.weapon(owner.character, "light", int(owner.upgrades.lw) + 1)
	var duration: float = (definition.dur if definition.dur else 6.0) * fraction
	for index in range(int(definition.count if definition.count else 2)):
		var offset := Vector2(cos(owner.yaw), -sin(owner.yaw)) * (-3 if index == 0 else 3)
		var point := _companion_position(owner.position, offset, 2)
		if not point.is_finite():
			message.emit(owner.peer_id, "unavailable_surface")
			continue
		var decoy := spawn({"kind": "decoy_beacon", "side": owner.side, "position": point, "yaw": owner.yaw, "effect_radius": 1.5,
			"special": {"role": "hologram", "owner_id": owner.entity_id, "offset": offset * 3, "cd": 0.0,
				"range": weapon.range if weapon.range else 200, "sight": weapon.range if weapon.range else 200, "rate": weapon.rate if weapon.rate else 3,
				"until": clock + duration, "blind_radius": definition.get("blindR", 14) if definition.get("blindR", 14) else 14,
				"blind_duration": definition.get("blindDur", 1.5) if definition.get("blindDur", 1.5) else 1.5}})
		hologram_decoys.append(decoy.entity_id)
		events.append({"type": "decoy_beacon_spawn", "actor": decoy.entity_id, "owner": owner.entity_id, "side": owner.side, "position": point, "duration": duration})

func _tick_holograms(delta: float) -> void:
	for index in range(hologram_decoys.size() - 1, -1, -1):
		var decoy: BattleUnit = units.get(hologram_decoys[index])
		if decoy == null:
			hologram_decoys.remove_at(index)
			continue
		var owner: BattleUnit = units.get(int(decoy.special.owner_id))
		if not decoy.alive() or clock >= float(decoy.special.until):
			if owner != null:
				_apply_cc(owner, {"fx": "confuse", "dur": decoy.special.blind_duration}, decoy.position, float(decoy.special.blind_radius))
			events.append({"type": "flashbang_detonate", "actor": decoy.entity_id, "position": decoy.position, "radius": decoy.special.blind_radius, "duration": decoy.special.blind_duration})
			_remove_field_unit(decoy.entity_id)
			hologram_decoys.remove_at(index)
			continue
		decoy.special.cd = maxf(0, float(decoy.special.cd) - delta)
		var target := _auto_target(decoy, owner)
		if target != null and owner != null and owner.alive():
			var weapon := Content.weapon(owner.character, "light", int(owner.upgrades.lw) + 1)
			var distance := _planar_distance(decoy.position, target.position)
			if distance <= float(decoy.special.range):
				_face_companion(decoy, target.position)
				if decoy.special.cd == 0:
					decoy.special.cd = 1.0 / (float(decoy.special.rate) * weather_attack_rate(decoy))
					var amount: float = weapon.dmg * _weapon_multiplier(owner, target, weapon) * CombatMath.damage_falloff(weapon, distance) * 0.3
					damage(decoy, target, weapon, amount, false, {"origin": decoy.position}, false)
					_companion_shot(decoy, target, weapon)
			else:
				_move_companion(decoy, target.position, minf(decoy.speed * delta, distance - float(decoy.special.range) * 0.85), false)
				_face_companion(decoy, target.position)
			continue
		if owner != null and owner.alive():
			var point := owner.position + Vector3(decoy.special.offset.x, 0, decoy.special.offset.y)
			var distance := _planar_distance(decoy.position, point)
			if distance > 4:
				_move_companion(decoy, point, minf(decoy.speed * delta, distance), false)
				_face_companion(decoy, point)
		else:
			var forward := Vector3(-sin(decoy.yaw), 0, -cos(decoy.yaw))
			_move_companion(decoy, decoy.position + forward, decoy.speed * delta, false)

func _move_companion(unit: BattleUnit, point: Vector3, distance: float, solid: bool = true) -> void:
	var offset := Vector2(point.x - unit.position.x, point.z - unit.position.z)
	if distance <= 0 or offset.is_zero_approx():
		return
	var displacement := offset.normalized() * distance
	var previous := unit.position
	var altitude := _missile_target_altitude(unit)
	if solid:
		_place_solid(unit, displacement)
	else:
		unit.position += Vector3(displacement.x, 0, displacement.y)
	var ground := world.ground_height(unit.position.x, unit.position.z)
	if not is_finite(ground):
		unit.position = previous
		return
	unit.position.y = ground + altitude
	if unit.special.get("role") == "summon":
		_face_companion(unit, point)

func _face_companion(unit: BattleUnit, point: Vector3) -> void:
	unit.yaw = atan2(-(point.x - unit.position.x), -(point.z - unit.position.z))
	unit.rotation.y = unit.yaw

func _companion_shot(unit: BattleUnit, target: BattleUnit, weapon: Dictionary) -> void:
	events.append({"type": "shot", "actor": unit.entity_id, "start": unit.position, "end": target.position, "side": unit.side,
		"weapon_type": weapon.get("type", ""), "companion": true})

func _spawn_fog(unit: BattleUnit, definition: Dictionary, center: Vector3) -> void:
	var duration: float = definition.dur if definition.dur else 8.0
	var radius: float = definition.r if definition.r else 35.0
	fogs.append({"id": next_field_id, "center": Vector2(center.x, center.z), "radius": radius,
		"duration": duration, "start": clock, "until": clock + duration, "side": unit.side,
		"owner": unit.entity_id, "add": definition.add.duplicate(true) if definition.add is Dictionary else {}})
	next_field_id += 1
	events.append({"type": "fog_spawn", "actor": unit.entity_id, "position": center, "radius": radius, "duration": duration, "side": unit.side})

func _spawn_cubic_slabs(unit: BattleUnit, definition: Dictionary, center: Vector3, fraction: float) -> void:
	var duration: float = definition.dur if definition.dur else 5.0
	var hp := floorf((float(definition.hp) if definition.hp else 350.0) * fraction + 0.5)
	var members: Array = []
	for index in range(6):
		var angle := index * PI / 3
		var point := center + Vector3(cos(angle) * 5.5, 0, -sin(angle) * 5.5)
		point.y = world.ground_height(point.x, point.z)
		var slab := spawn({"kind": "slab", "side": unit.side, "position": point, "effect_radius": 1.75,
			"yaw": -angle, "special": {"role": "slab", "hp": hp, "angle": angle, "height": 6.0, "until": clock + duration}})
		members.append(slab.entity_id)
	cubic_cages.append({"center": Vector2(center.x, center.z), "radius": 5.5, "until": clock + duration,
		"duration": duration, "dps": (float(definition.dmg) if definition.dmg else 50.0) * fraction,
		"owner": unit.entity_id, "members": members})
	events.append({"type": "cube_spawn", "actor": unit.entity_id, "position": center, "radius": 5.5, "duration": duration, "side": unit.side})

func _remove_field_unit(id: int, report: bool = false) -> void:
	var unit: BattleUnit = units.get(id)
	if unit == null:
		return
	if report:
		events.append({"type": "die", "actor": id, "kind": unit.kind, "position": unit.position, "side": unit.side})
	unit.hp = 0
	unit.visible = false
	unit.collision_layer = 0
	unit.hit_area.collision_layer = 0
	units.erase(id)
	unit.queue_free()

func _tick_cubic_slabs(delta: float) -> void:
	for index in range(cubic_cages.size() - 1, -1, -1):
		var cage: Dictionary = cubic_cages[index]
		var remaining: Array = cage.members.filter(func(id): return units.has(id) and units[id].alive())
		if clock >= float(cage.until) or remaining.is_empty():
			for id in cage.members:
				_remove_field_unit(int(id))
			cubic_cages.remove_at(index)
			continue
		var owner: BattleUnit = units.get(int(cage.owner))
		if owner == null:
			continue
		var center: Vector2 = cage.center
		for target: BattleUnit in units.values():
			if target.side == owner.side or not target.alive() or center.distance_to(Vector2(target.position.x, target.position.z)) > float(cage.radius):
				continue
			damage(owner, target, {"pen": 12}, float(cage.dps) * delta, false, {"weather_weapon": false}, false)

func _tick_fogs(delta: float) -> void:
	for index in range(fogs.size() - 1, -1, -1):
		var fog: Dictionary = fogs[index]
		if clock >= float(fog.until):
			fogs.remove_at(index)
			continue
		var owner: BattleUnit = units.get(int(fog.owner))
		var added: Dictionary = fog.add
		if owner == null or added.get("fx") != "bleed":
			continue
		var center: Vector2 = fog.center
		for target: BattleUnit in units.values():
			if target.side == fog.side or not target.alive():
				continue
			var radius: float = float(fog.radius) + (target.effect_radius if target.effect_radius else 1.0)
			if center.distance_to(Vector2(target.position.x, target.position.z)) > radius:
				continue
			var dps: float = added.get("dps", 12)
			var pen: float = added.get("pen", 8)
			damage(owner, target, {"pen": pen if pen else 8}, (dps if dps else 12) * delta, false, {"weather_weapon": false}, false)
			_apply_hit_elements(owner, {"elem": "poison", "elemBuildup": 20 * delta}, target)

func _slab_records() -> Array:
	var records: Array = []
	for cage: Dictionary in cubic_cages:
		for id in cage.members:
			var slab: BattleUnit = units.get(int(id))
			if slab == null or not slab.alive():
				continue
			records.append({"center": Vector2(slab.position.x, slab.position.z), "angle": slab.special.angle,
				"hp": slab.hp, "height": slab.special.height})
	return records

func _relative_origin(unit: BattleUnit) -> Vector3:
	return Vector3(unit.position.x, _missile_target_altitude(unit) + (Content.constants.LOS.TOWER_EYE_M if unit.kind == "tower" else Content.constants.LOS.EYE_M), unit.position.z)

func _relative_target(unit: BattleUnit) -> Vector3:
	var height: float = Content.constants.LOS.TOWER_EYE_M if unit.kind in ["tower", "base"] else Content.constants.LOS.TGT_M
	return Vector3(unit.position.x, _body_altitude(unit) + height, unit.position.z)

func _skill_barriers_blocked(start: Vector3, end: Vector3) -> bool:
	return is_finite(AbilityFieldRules.slab_hit(start, end, _slab_records()))

func _fog_snapshot() -> Array:
	var states: Array = []
	for fog: Dictionary in fogs:
		states.append({"id": fog.id, "center": fog.center, "radius": fog.radius, "start": fog.start,
			"until": fog.until, "duration": fog.duration, "side": fog.side})
	return states

func _tick_ability_states(delta: float) -> void:
	# Preserve source ordering across actors, including the separate autonomous producer ticks.
	for unit: BattleUnit in units.values():
		unit.buffs = unit.buffs.filter(func(buff): return float(buff.until) > clock)
		if not unit.alive():
			unit.cast_state.clear()
			unit.heal_aura.clear()
			unit.bleed.clear()
			unit.status.erase("phase_until")
	for unit: BattleUnit in pilots.values():
		if unit.alive():
			_tick_shield_bash(unit, delta)
	for unit: BattleUnit in units.values():
		if not unit.bleed.is_empty():
			if float(unit.bleed.until) <= clock:
				unit.bleed.clear()
			else:
				var attacker: BattleUnit = pilots.get(int(unit.bleed.get("peer", 0)), units.get(int(unit.bleed.get("actor", 0))))
				damage(attacker, unit, {"pen": unit.bleed.pen}, float(unit.bleed.dps) * delta, false, {"weather_weapon": false}, false)
	for unit: BattleUnit in pilots.values():
		if unit.alive() and not unit.cast_state.is_empty() and clock >= float(unit.cast_state.start) + float(unit.cast_state.duration):
			var state := unit.cast_state.duplicate(true)
			unit.cast_state.clear()
			_cast_effect(unit, state.definition, state.point)
			events.append({"type": "cast", "actor": unit.entity_id, "slot": "def", "fx": state.definition.fx, "fraction": 1.0, "point": state.point})
	_tick_carriers(delta)
	for unit: BattleUnit in pilots.values():
		if not unit.heal_aura.is_empty():
			if not unit.alive() or float(unit.heal_aura.until) <= clock:
				unit.heal_aura.clear()
				continue
			var aura := unit.heal_aura
			# Source visits hero representatives and the entity roster separately.
			for ally: BattleUnit in pilots.values() + units.values():
				if ally.side != unit.side or not ally.alive() or Vector2(ally.position.x - unit.position.x, ally.position.z - unit.position.z).length() > float(aura.radius) + ally.effect_radius:
					continue
				_heal_body(ally, float(aura.hps) * delta)
				ally.shield = minf(ally.max_shield, ally.shield + float(aura.sp_hps) * delta)
				if aura.cleanse and ally.is_hero():
					_cleanse(ally)
	_tick_clones(delta)
	_tick_cubic_slabs(delta)
	_tick_fogs(delta)
	_tick_summons(delta)
	for unit: BattleUnit in pilots.values():
		if not unit.alive():
			unit.status.erase("phase_until")
			continue
		if unit.status.has("phase_until") and float(unit.status.phase_until) != 0 and clock >= float(unit.status.phase_until):
			unit.status.erase("phase_until")
			unit.status.phase_critical = true
			var amount: float = unit.status.get("phase_damage", 50)
			blast(unit, {"dmg": amount if amount else 50, "r": 6, "pen": 10}, Vector3(unit.position.x, 0, unit.position.z), false, true, 0)
			_apply_cc(unit, {"fx": "pull", "imp": -20}, unit.position, 6)
			events.append({"type": "phase_exit", "actor": unit.entity_id, "side": unit.side, "position": unit.position, "radius": 6.0})
	_tick_holograms(delta)
	for unit: BattleUnit in units.values():
		_tick_element_buildup(unit, delta)

func _prune_dead_creeps() -> void:
	for id in units.keys():
		var unit: BattleUnit = units[id]
		if unit.alive() or unit.is_hero() or not unit.special.is_empty() or unit.kind in ["base", "tower"]:
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
		visible_events = []
		for event: Dictionary in events:
			if event.type == "lightning_strike":
				var points: Array = event.points.filter(func(point): return point.get("absolute", false) or visible_ids.has(int(point.id)))
				if not points.is_empty():
					visible_events.append({"type": "lightning_strike", "actor": 0, "points": points})
			elif event.type in ["airfall", "airdrop", "relay"] or event.has("missile") or visible_ids.has(event.actor):
				visible_events.append(event)
	return {"clock": clock, "wave": wave, "over": over, "winner": winner, "stats": match_stats.duplicate(true),
		"weather": {"vector": weather_vector.duplicate(true), "dynamics": weather_dynamics.duplicate(true), "surface": weather_surface.duplicate(true),
			"seed": weather_seed, "schedule": weather_schedule.duplicate(true), "season": weather_start.get("season", "summer"), "hour": WeatherRules.clock_hour(weather_start.get("time", "day"), weather_elapsed, weather_schedule)},
		"creep_upgrades": creep_upgrades.duplicate(true),
		"fires": fire_fields.duplicate(true), "weather_scars": weather_scars.duplicate(true),
		"loots": loots.duplicate(true),
		"mines": mines.duplicate(true),
		"airdrops": _airdrop_snapshot(),
		"fogs": _fog_snapshot(),
		"units": visible_units, "events": visible_events.duplicate(), "fire_control": _control_snapshot(viewer),
		"lock": _lock_snapshot(viewer), "reachability": _reachability_snapshot(viewer),
		"footprint": _footprint_snapshot(viewer), "missiles": _missile_snapshot(), "weapon_pose": _weapon_pose_snapshot(viewer),
		"projectile_view": projectile_view(viewer)}

func _weapon_pose_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or viewer.weapon_pose == null or not viewer.alive() or over:
		return {}
	var pose := viewer.weapon_pose
	if not is_finite(pose.clock):
		return {}
	return {"clock": pose.clock, "serial": pose.accepted_serial, "visual_serial": pose.weapons.last_serial, "slot": pose.slot, "form": pose.form,
		"gun": pose.gun, "kick": pose.kick, "muzzle": pose.current_muzzle(viewer.aim_transform())}

func _footprint_snapshot(viewer: BattleUnit) -> Dictionary:
	if viewer == null or world == null or over or not viewer.alive() or not viewer.is_hero():
		return {}
	var slot: String = viewer.input_state.get("slot", "light")
	if slot not in ["light", "heavy"]:
		return {}
	var definition := Content.weapon(viewer.character, slot, int(viewer.upgrades.hw if slot == "heavy" else viewer.upgrades.lw) + 1)
	if definition.get("needAim", false) and not viewer.input_state.get("aim", false):
		return {}
	var origin := _advisory_origin(viewer)
	var maximum := TargetingMath.maximum_range(definition)
	var ray: Dictionary
	if definition.area == "line":
		ray = _projectile_aim(viewer, maximum, true)
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
		if cached.clock != clock or cached.camera != viewer.aim_transform() or cached.direction != viewer.aim_direction() or int(cached.level) != int(viewer.upgrades.hw):
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
	var advice := ReachabilityMath.evaluate(definition, _advisory_origin(viewer),
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
	return {"points": control.arc.points, "origin": control.origin, "impact": control.arc.impact, "has_impact": control.arc.has_impact,
		"ok": control.ok, "aa": control.aa, "high": control.high, "close": control.close, "side": viewer.side,
		"elevation": CockpitPose.barrel_elevation(control.velocity, control.direction)}

func apply_snapshot(data: Dictionary) -> void:
	if authoritative or data.clock < clock:
		return
	clock = data.clock
	match_stats = data.get("stats", match_stats).duplicate(true)
	loots.clear()
	for loot: Dictionary in data.get("loots", []):
		loots.append(loot.duplicate(true))
	mines.clear()
	for mine: Dictionary in data.get("mines", []):
		mines.append(mine.duplicate())
	fire_fields.clear()
	for fire: Dictionary in data.get("fires", []):
		fire_fields.append(fire.duplicate(true))
	weather_scars.clear()
	for scar: Dictionary in data.get("weather_scars", []):
		weather_scars.append(scar.duplicate(true))
	var weather: Dictionary = data.get("weather", {})
	if not weather.is_empty():
		weather_vector = weather.vector.duplicate(true)
		weather_dynamics = weather.dynamics.duplicate(true)
		weather_surface = weather.surface.duplicate(true)
		weather_fog = weather_dynamics.fog
		weather_schedule = weather.schedule.duplicate(true)
		weather_seed = int(weather.seed)
		world.sync_weather(weather_dynamics, weather_surface, float(weather.hour), weather_schedule, weather.season, weather_seed)
	world.sync_fires(fire_fields, clock, weather_dynamics)
	world.sync_loots(loots, clock)
	world.sync_mines(mines)
	world.sync_airdrops(data.get("airdrops", []), clock)
	creep_upgrades = data.get("creep_upgrades", creep_upgrades).duplicate(true)
	fog_view = data.get("fogs", []).duplicate(true)
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
		if fresh and unit.kind == "bunker":
			world.clear_camp_columns([{"x": state.position.x, "z": state.position.z}])
		if unit.is_pilot():
			pilots[unit.peer_id] = unit
	for id in units.keys():
		if seen.has(id):
			continue
		var removed: BattleUnit = units[id]
		if removed.is_pilot():
			pilots.erase(removed.peer_id)
		removed.queue_free()
		units.erase(id)
	for event in data.events:
		if event.type == "lightning_strike":
			world.present_lightning(event.points)
		if event.type == "shot":
			present_shot(event)
	if data.over and not over:
		over = true
		winner = data.winner
		result.emit(winner)

func present_shot(event: Dictionary) -> void:
	var owner: BattleUnit = units.get(int(event.actor))
	if owner != null and owner.is_pilot() and owner.peer_id == multiplayer.get_unique_id():
		if event.get("physical", false):
			return
		if event.get("slot") == "light" and event.get("area") == null and event.get("weapon_type") in ["beam", "rail"]:
			world.ensure_projectile_visuals().tracer(event.start, event.end, _fpv_tracer_color(event.weapon_type, event.side))
			return
	world.tracer(event.start, event.end, event.side)

func _fpv_tracer_color(type: String, side: String) -> Color:
	var style: Dictionary = Content.balance.projectileVisual
	var hex: int = style.beamColors[side] if type == "beam" else style.colors[side].col
	return Color.hex((hex << 8) | 0xff)
