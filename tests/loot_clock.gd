extends "res://tests/run.gd"

class ClockWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 7.0

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/loot_clock.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("programs") is Array,
		"Capture original loot and airdrop clock methods")
	if not failures.is_empty():
		_finish_clock()
		return
	var source: Dictionary = capture.source
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == source.inputs[path], "Original clock generator is current")
	for path: String in source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == source.sourceInputs[path], "Clock oracle matches imported source: " + path)
	if not failures.is_empty():
		_finish_clock()
		return
	for program: Dictionary in capture.programs:
		var ticks := {"now": float(program.born)}
		var drop := AirdropPresentation.new()
		var loot := LootPresentation.new()
		drop.wall_clock = func(): return ticks.now
		loot.wall_clock = func(): return ticks.now
		add_child(drop)
		add_child(loot)
		drop.set_process(false)
		loot.set_process(false)
		for step: Dictionary in program.steps:
			ticks.now = float(step.wall)
			if step.sync:
				drop.sync([{"id": 1, "position": Vector3(12, 7, -8), "size": program.size, "landing": program.landing}], step.authority)
				loot.sync([{"id": 2, "position": Vector3(12, 7, -8)}], step.authority)
			if step.has("seedYaw"):
				var seed_yaw := String(step.seedYawBits).hex_decode().decode_double(0)
				var initial: Dictionary = drop.entries[1]
				initial.root_yaw = seed_yaw
				initial.crate_yaw = seed_yaw
				initial.root.quaternion = SourceQuaternion.axis_angle(Vector3.UP, seed_yaw)
				initial.crate.quaternion = SourceQuaternion.axis_angle(Vector3.UP, seed_yaw)
				loot.entries[2].yaw = seed_yaw
				loot.entries[2].root.quaternion = SourceQuaternion.axis_angle(Vector3.UP, seed_yaw)
			for frame: Array in step.get("advance", [[step.wall, step.delta, step.deltaBits]]):
				ticks.now = float(frame[0])
				var delta := String(frame[2]).hex_decode().decode_double(0)
				drop._process(delta)
				loot._process(delta)
			var entry: Dictionary = drop.entries[1]
			_near(drop.clock, step.wall, "Airdrop animation follows the wall clock across delayed and rewound snapshots")
			_near(entry.born, step.drop.born, "First-observed landing uses the same local clock as its update")
			_check(entry.root.position == Vector3(12, step.drop.y, -8), "Original descent retains its exact native Float32 pose and zero-born behavior")
			_check(entry.root_yaw == String(step.drop.yawBits).hex_decode().decode_double(0) and
				entry.crate_yaw == String(step.drop.crateYawBits).hex_decode().decode_double(0),
				"Drop/crate phase retains the exact original double accumulation")
			_rotation(entry.root.quaternion, step.drop.rotation, "Original drop orientation after long-lived angle accumulation")
			_rotation(entry.crate.quaternion, step.drop.crateRotation, "Original crate orientation after long-lived angle accumulation")
			if step.drop.crateY != null:
				_near(entry.crate.position.y, step.drop.crateY, "Landed crate bob uses absolute local wall time")
			for key: String in ["chute", "groundChute", "halo"]:
				_check(entry[key].visible == step.drop[key], "Original landing visibility: " + key)
			_near(loot.clock, step.wall, "Loot float phase cannot be reset by authority time")
			_check(loot.entries[2].yaw == String(step.loot.yawBits).hex_decode().decode_double(0), "Loot spin preserves the exact original double phase")
			_rotation(loot.entries[2].root.quaternion, step.loot.rotation, "Original loot orientation cannot quantize a large Euler phase")
			_near(loot.entries[2].body.position.y, step.loot.y, "Loot bob uses source local wall-clock phase")
		drop.free()
		loot.free()
	_world_clock()
	_explicit_clock()
	_finish_clock()

func _world_clock() -> void:
	_check(DisplayServer.get_name() != "headless", "World presentation clock binding requires a rendered session")
	if DisplayServer.get_name() == "headless":
		return
	var world := ClockWorld.new()
	add_child(world)
	var drops := [{"id": 7, "x": 12, "z": -8, "size": "S", "landing": true}]
	var loots := [{"id": 8, "position": Vector3(12, 7, -8)}]
	var before := BodyPresentation.time_now()
	world.sync_airdrops(drops, 100000)
	world.sync_loots(loots, 100000)
	var after := BodyPresentation.time_now()
	_check(world.airdrop_visuals.clock >= before and world.airdrop_visuals.clock <= after,
		"World binds airdrop time to the existing local wall clock")
	_check(world.loot_visuals.clock >= before and world.loot_visuals.clock <= after,
		"World binds loot time to the existing local wall clock")
	var born: float = world.airdrop_visuals.entries[7].born
	world.sync_airdrops(drops, -100000)
	world.sync_loots(loots, -100000)
	_check(world.airdrop_visuals.entries[7].born == born and world.airdrop_visuals.clock >= born and world.loot_visuals.clock >= born,
		"Repeated authority publications neither restart descent nor rewind either clock")
	world.free()

func _explicit_clock() -> void:
	var drop := AirdropPresentation.new()
	var loot := LootPresentation.new()
	drop.sync([], 9)
	loot.sync([], 9)
	drop._process(.2)
	loot._process(.2)
	_near(drop.clock, 9.2, "Explicit fixture clock remains available without a wall-clock provider")
	_near(loot.clock, 9.2, "Explicit loot fixture clock retains its existing contract")
	drop.free()
	loot.free()

func _finish_clock() -> void:
	print("LOOT_CLOCK assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _rotation(actual: Quaternion, source: Array, description: String) -> void:
	var value := Vector4(actual.x, actual.y, actual.z, actual.w)
	var expected := Vector4(source[0], source[1], source[2], source[3])
	_check(minf(value.distance_to(expected), value.distance_to(-expected)) < .000001, description)
