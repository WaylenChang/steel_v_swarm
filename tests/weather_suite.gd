extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class WeatherSimulation extends BattleSimulation:
	var hits: Array = []

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _place_solid(unit: BattleUnit, offset: Vector2) -> void:
		unit.position += Vector3(offset.x, 0, offset.y)

	func damage(_attacker: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float,
			_friendly: bool = false, _context: Dictionary = {}, _attack_modifiers: bool = true) -> void:
		hits.append({"id": target.entity_id, "amount": amount, "pen": definition.get("pen", 0)})
		target.hp -= amount

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["weatherSolar", "weatherVectors", "weatherDynamics", "weatherSurface", "weatherMath", "weatherParticles", "weatherEffects", "weatherSettlement", "weatherReload", "weatherCelestial"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original weather oracle: " + key)
			return
	for item: Dictionary in fixtures.weatherSolar:
		StatusHelper.compare(h, WeatherRules.solar_schedule(item.season, item.latitude, 0, int(item.lunarDay)), item.schedule, "Original latitude/season/lunar solar schedule")
	for item: Dictionary in fixtures.weatherCelestial:
		StatusHelper.compare(h, WeatherRules.sun_direction(item.hour, item.schedule), item.sun, "Original client scheduled/rotated solar direction")
		StatusHelper.compare(h, WeatherRules.moon_direction(item.hour, item.schedule.lunarDay, item.schedule), item.moon, "Original client lunar direction and full-moon exception")
	for item: Dictionary in fixtures.weatherVectors:
		StatusHelper.compare(h, WeatherRules.vector_at(item.season, item.start, item.preset, item.elapsed, int(item.seed), item.latitude), item.vector, "Original independently seeded climate vector")
	for item: Dictionary in fixtures.weatherDynamics:
		StatusHelper.compare(h, WeatherRules.dynamics(item.vector, item.previous, item.delta), item.result, "Original precipitation thresholds and thermal freeze/thaw history")
	for item: Dictionary in fixtures.weatherSurface:
		var surface := WeatherRules.surface_step(item.previous, item.dyn, item.delta)
		StatusHelper.compare(h, surface, item.result, "Original intensity-dependent deposit capacities and exponential drying")
		h._near(WeatherRules.ground_speed(surface), item.ground, "Original accumulated surface walking penalty")
		h._near(WeatherRules.jump_velocity(surface), item.jump, "Original square-root jump penalty")
		h._near(WeatherRules.ground_rate(surface), item.rate, "Original dune attack-rate penalty")
	for item: Dictionary in fixtures.weatherMath:
		match item.type:
			"wind":
				h._near(WeatherRules.wind_speed(item.motion[0], item.motion[1], item.direction, item.wind), item.result, "Original wind direction, zero vector and threshold")
				h._near(WeatherRules.unbalance_threshold(item.wind), item.threshold, "Original wind-dependent low-flight unbalance threshold")
			"air":
				h._near(WeatherRules.air_lift(item.dyn), item.lift, "Original airborne lift intensity precedence")
				h._near(WeatherRules.air_rate(item.dyn), item.rate, "Original airborne sand attack rate")
				h._near(1.0, item.speed, "Original canceled airborne precipitation speed penalty")
			"accuracy":
				h._near(WeatherRules.accuracy_penalty(item.fog, item.hour, item.schedule), item.result, "Original authority fog/night/moon accuracy")
	for item: Dictionary in fixtures.weatherParticles:
		var profiles := WeatherRules.particle_profiles(item.dyn)
		for kind: String in ["rain", "snow", "sand"]:
			StatusHelper.compare(h, profiles[kind], item.result[kind], "Original native precipitation presentation profile: " + kind)
	for item: Dictionary in fixtures.weatherSettlement:
		var simulation := StatusHelper.SettlementSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.reflecting = item.reflected
		simulation.weather_dynamics = WeatherRules.dynamics({"rain": item.rain})
		var target := StatusHelper.actor(simulation, {"id": 1, "character": "", "kind": "tank", "side": "STEEL", "position": [0, 0, 0], "hp": 10000, "max_hp": 10000, "armor": 30})
		if item.frozen:
			target.status.freeze_until = 20.0
		simulation.damage(null, target, {"type": "gun", "pen": 10} if item.weapon else {"pen": 10}, 80, false, {"weather_weapon": item.weapon}, false)
		h._near(10000 - target.hp, item.loss, "Original weapon-only rain and freeze damage order; reflected rain applies once")
		simulation.free()
	for item: Dictionary in fixtures.weatherReload:
		var simulation := BattleSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.weather_dynamics = WeatherRules.dynamics({"snow": item.snow})
		var unit := StatusHelper.actor(simulation, {"id": 1, "character": item.character, "kind": "", "side": "STEEL", "position": [0, 0, 0], "ammo": {"light": 0, "heavy": 0}})
		unit.buffs.append({"until": 20.0, "mul": {"reload": item.modifier}})
		simulation.reload_weapon(unit, item.slot)
		h._near(float(unit.reload_at.get(item.slot, -INF)) - simulation.clock, item.duration, "Original all-character snow reload / modifier composition")
		simulation.free()
	for item: Dictionary in fixtures.weatherEffects:
		var simulation := WeatherSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.weather_seed = int(item.seed)
		simulation.weather_dynamics = {"effectiveThunder": item.thunder, "effectiveSnow": item.snow, "wind": 100.0}
		simulation.weather_surface = {"snow": 1.0}
		for id in range(1, 5):
			StatusHelper.actor(simulation, {"id": id, "character": "", "kind": "heli" if id == 3 else "tower" if id == 4 else "soldier",
				"side": "STEEL" if id in [1, 3] else "SWARM", "position": [0 if id == 1 else 9 if id == 2 else 40 if id == 3 else 80, 20 if id == 3 else 0, 0],
				"hp": 10000.0, "max_hp": 10000.0})
		var random_state := simulation.rng.state
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation.events.clear()
			simulation.hits.clear()
			simulation.weather_surface = WeatherRules.surface_step(simulation.weather_surface, simulation.weather_dynamics, step.delta)
			simulation._tick_weather_effects(step.delta)
			StatusHelper.compare(h, simulation.weather_surface, step.surface, "Original weather effect surface history")
			h._near(simulation.lightning_timer, step.timer, "Original thunder timer resets and intensity-dependent intervals")
			h._check(simulation.hits.size() == step.hits.size(), "Original independent lightning target and shockwave draw order")
			for index in range(mini(simulation.hits.size(), step.hits.size())):
				var hit: Dictionary = simulation.hits[index]
				var expected: Dictionary = step.hits[index]
				h._check(hit.id == expected.id and hit.pen == expected.pen, "Original lightning target / armor-penetration choice")
				h._check(absf(float(hit.amount) - float(expected.amount)) < 0.0001, "Original shockwave planar attenuation within native vector precision")
			for expected: Dictionary in step.frozen:
				var unit: BattleUnit = simulation.units[int(expected.id)]
				h._near(float(unit.status.get("freeze_until", 0)), expected.until, "Original once-per-second snow draws and per-actor freeze cooldown")
				if expected.last == null:
					h._check(not unit.status.has("last_weather_freeze"), "Skipped weather freeze preserves absent timestamp")
				else:
					h._near(float(unit.status.get("last_weather_freeze", -INF)), expected.last, "Original weather freeze timestamp")
			for expected: Dictionary in step.actors:
				var unit: BattleUnit = simulation.units[int(expected.id)]
				h._check(absf(unit.hp - float(expected.hp)) < 0.0001, "Original weather effect damage account")
				h._check(absf(unit.position.x - float(expected.x)) < 0.0001 and absf(unit.position.z - float(expected.z)) < 0.0001, "Original NPC shockwave solid placement")
				h._check(unit.status.has("lightning_scorch") == expected.scorched, "Original lightning scorch cleared by healing/death/new statuses")
			var strikes: Array = []
			for event: Dictionary in simulation.events:
				if event.type == "lightning_strike":
					for point: Dictionary in event.points:
						strikes.append(int(point.id))
			StatusHelper.compare(h, strikes, step.strikes, "Original deterministic lightning selection without replacement")
			h._check(simulation.rng.state == random_state, "Climate never consumes the combat RNG stream")
		simulation.free()
	print("WEATHER_REFERENCE_PASS vectors=", fixtures.weatherVectors.size(), " dynamics=", fixtures.weatherDynamics.size(), " effects=", fixtures.weatherEffects.size())
