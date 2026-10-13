extends Node

var failures: Array[String] = []
var assertions := 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < 0.000001, description + " actual=" + str(actual) + " expected=" + str(expected))

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	for fixture in fixtures.volumes:
		var actor := BattleUnit.new()
		add_child(actor)
		actor.configure({"id":90001,"side":fixture.side,"kind":fixture.kind,"character":fixture.character,"position":Vector3.ZERO})
		var target: CylinderShape3D = actor.hit_area.get_child(0).shape
		_near(target.radius, fixture.radius, "Source target radius: " + fixture.kind)
		_near(target.height, fixture.height, "Source target height: " + fixture.kind)
		if not fixture.character.is_empty():
			_near(actor.camera.position.y, fixture.eye, "Source hero eye height")
			for mode in ["ground", "air"]:
				actor.flying = mode == "air"
				actor.refresh_collision()
				var movement: CylinderShape3D = actor.movement_shape.shape
				var spec: Dictionary = fixture[mode]
				_near(movement.radius, spec.r, "Source movement radius")
				_near(movement.height, spec.top - spec.bot, "Source movement vertical band")
				_near(actor.movement_shape.position.y, (spec.bot + spec.top) / 2, "Source movement band offset")
		actor.free()
	var rng := SourceRng.new(123456789)
	for value in fixtures.rng:
		_near(rng.next(), value, "Source RNG parity")
	for fixture in fixtures.shield:
		var split := CombatMath.shield_split(fixture.def, fixture.damage, fixture.shield)
		_near(split.toSp, fixture.result.toSp, "Shield budget parity")
		_near(split.toHp, fixture.result.toHp, "Shield overflow parity")
	for fixture in fixtures.envelope:
		var delta := Vector3(fixture.delta[0], fixture.delta[1], fixture.delta[2])
		_check(CombatMath.in_range(fixture.range, delta) == fixture.result, "Range envelope parity")
	for fixture in fixtures.falloff:
		for sample in fixture.samples:
			_near(CombatMath.damage_falloff(fixture.def, sample.distance), sample.result, "Weapon falloff parity")
	for fixture in fixtures.fan:
		var distance := CombatMath.fan_bin_distance(fixture.def, int(fixture.bin), fixture.distance, fixture.phi, fixture.radius)
		if fixture.result == null:
			_check(distance < 0, "Fan bin misses outside wedge")
		else:
			_near(distance, fixture.result, "Fan bin surface parity")
	for fixture in fixtures.zones:
		var zones := CombatMath.lance_zones(Vector2(fixture.offset[0], fixture.offset[1]), fixture.radius, fixture.beam)
		var expected: Array[int] = []
		for zone in fixture.result:
			expected.append(int(zone))
		_check(zones == expected, "Lance zone overlap parity actual=" + str(zones) + " expected=" + str(expected))
	_near(CombatMath.armor_multiplier(0, 100), 1.0, "Penetration does not create negative armor")
	_near(CombatMath.blast_falloff(10, 18), 0.0, "Blast edge excludes damage")
	_near(CombatMath.blast_falloff(10, 5), 1.0, "Blast core has full damage")
	_check(Content.heroes.size() == 32, "Complete character roster")
	for character in Content.heroes:
		_check(Content.heroes[character].weapons.light.size() == 4, "Four light weapon tiers")
		_check(Content.heroes[character].abilities.atk.size() == 4, "Four attack tiers")
	for map_data in Content.maps:
		for team_size in range(1, 6):
			var variant: Dictionary = map_data.variants[str(team_size)]
			_check(variant.lanes.size() == ceili(team_size / 2.0), "Active lane subset")
			_check(variant.structures.filter(func(info): return info.kind == "tower").size() == variant.lanes.size() * 4, "Source tower pairs")
	await _settlement_tests()
	if failures.is_empty():
		print("TEST_PASS assertions=", assertions)
	else:
		print("TEST_FAIL count=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _settlement_tests() -> void:
	var sim := BattleSimulation.new()
	add_child(sim)
	var fixture_map := Content.map_variant(0, 1)
	fixture_map.erase("native_world")
	await sim.setup(fixture_map, [
		{"peer": 1, "side": "STEEL", "character": "t01", "bot": false},
		{"peer": 2, "side": "SWARM", "character": "s01", "bot": false}], {"time": "day", "weather": "clear"}, true)
	sim.set_physics_process(false)
	var player: BattleUnit = sim.pilots[1]
	var enemy: BattleUnit = sim.pilots[2]
	await get_tree().physics_frame
	var starting_money := player.money
	_check(sim.buy(player, "lw"), "First tier purchase in supply radius")
	_near(player.money, starting_money - Content.constants.ECON.UPG_STEPS[0].price, "Server charges exactly once")
	_check(not sim.buy(player, "lw"), "Score threshold rejects a second tier")
	_near(player.score, 0, "Purchase does not spend battle score")
	player.money = 10000
	player.score = 100
	player.position = Vector3.ZERO
	_check(not sim.buy(player, "hp"), "Remote supply purchase rejected")
	_check(not sim.buy(player, "forged_item"), "Unknown upgrade rejected")
	sim.submit_input(1, {"move": Vector2(1000, -1000), "yaw": 0.0, "pitch": 100.0})
	_check(player.input_state.move.length() <= 1.000001, "Movement magnitude clamped")
	_check(player.input_state.pitch <= 1.45, "Pitch clamped")
	var before: Dictionary = player.input_state.duplicate()
	sim.submit_input(1, {"move": Vector2(NAN, 0), "yaw": 0.0, "pitch": 0.0})
	_check(player.input_state == before, "Nonfinite movement rejected")
	sim.submit_input(1, {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "vertical": []})
	_check(player.input_state == before, "Malformed vertical input rejected")
	var health := enemy.hp
	sim.authoritative = false
	sim.damage(player, enemy, {"vsSp": 1, "vsHp": 1}, 999999)
	_near(enemy.hp, health, "Client damage does not settle HP")
	sim.authoritative = true
	var own_health := player.hp
	sim.damage(player, player, {}, 999999)
	_near(player.hp, own_health, "Friendly shot rejected")
	player.ammo.light = 0
	sim.reload_weapon(player, "light")
	var reload_time: float = player.reload_at.light
	sim.reload_weapon(player, "light")
	_near(player.reload_at.light, reload_time, "Repeated reload cannot extend deadline")
	sim.clock = reload_time + 0.01
	player.input_state = {"yaw": 0.0, "pitch": 0.0}
	sim.fire(player, "light")
	var magazine: float = Content.weapon(player.character, "light", 2).mag
	_near(player.ammo.light, magazine - 1, "Reload refills lazily before firing")
	sim.fire(player, "light")
	_near(player.ammo.light, magazine - 1, "Fire rate rejects same-frame duplicate")
	player.position = Vector3(0, 0.1, 0)
	enemy.position = Vector3(0, 0.1, -10)
	var direction := enemy.eye() - player.eye()
	player.yaw = atan2(-direction.x, -direction.z)
	player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	_check(player.aim_direction().dot(direction.normalized()) > 0.99999, "Native pitch convention targets the correct altitude")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shield_before := enemy.shield
	sim.clock += 1
	sim.fire(player, "light")
	_check(enemy.shield < shield_before, "Native ray query damages the aimed enemy")
	sim.damage(player, enemy, {"vsSp": 1, "vsHp": 1}, 999999)
	_check(not enemy.alive() and enemy.respawn_at > sim.clock, "Server schedules hero respawn")
	sim.respawn(enemy)
	_near(enemy.hp, enemy.max_hp, "Respawn restores HP")
	_near(enemy.shield, enemy.max_shield, "Respawn restores shields")
	var enemy_base: BattleUnit
	for unit: BattleUnit in sim.units.values():
		if unit.kind == "base" and unit.side == "SWARM":
			enemy_base = unit
	sim.damage(player, enemy_base, {}, 9999999)
	_check(sim.over and sim.winner == "STEEL", "Server settles battle outcome")
	var money_after := player.money
	sim.damage(player, enemy_base, {}, 9999999)
	_near(player.money, money_after, "Repeated lethal reports cannot duplicate bounty")
	sim.queue_free()
	await get_tree().process_frame
