extends Node

var assertions := 0
var failures: Array[String] = []
var reference: Dictionary

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func _state(key: String) -> Dictionary:
	var profile: Dictionary = Content.balance.hazard_visuals[key]
	return {"id": 7, "kind": profile.kind, "lightning": key == "fire_lightning", "position": Vector3(12, 3, -9),
		"scale": float(profile.radius) / float(Content.constants.HAZARDS[profile.kind].r)}

func _source() -> void:
	reference = Content.read_json("res://tests/fixtures/fire_clock.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original fire frame methods")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current source fire input: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original fire dependency agrees with shared source metadata: " + path)
	_check(Content.constants.FIRE_WEATHER == reference.weatherRules, "Original weather thresholds remain unchanged")

func _frames() -> void:
	for program: Dictionary in reference.programs:
		var view := FirePresentation.new()
		var wall := {"now": 0.0}
		view.wall_clock = func(): return wall.now
		add_child(view)
		view.set_process(false)
		for frame: Dictionary in program.frames:
			wall.now = str(frame.nowBits).hex_decode().decode_double(0)
			view.sync([_state(program.key)], frame.authority, frame.weather)
			view._process(str(frame.deltaBits).hex_decode().decode_double(0))
			_check(_bits(view.clock) == frame.nowBits, "Fire animation retains exact wall-clock bits across unrelated authority clocks and frame deltas")
			_check(_bits(EnvironmentRules.fire_multiplier(frame.weather)) == frame.strengthBits, "Original local rain/snow/wind multiplier")
			for expected: Dictionary in frame.flames + frame.smoke:
				var node: MeshInstance3D = view.entries[7].nodes["n_%d" % int(expected.id)]
				_check(node.visible == expected.visible, "Original quench hides flames and smoke while retaining their prior pose")
				_check(node.position == _point(expected.position), "Original fire position is evaluated in double precision before native Float32 storage")
				_check(node.scale == _point(expected.scale), "Original fire scale reaches native Float32 storage without early vector rounding")
				var rotation := Quaternion(expected.quaternion[0], expected.quaternion[1], expected.quaternion[2], expected.quaternion[3])
				_check(absf(node.quaternion.dot(rotation)) > .999999, "Original XYZ wind tilt remains on the existing packed node")
				var material := node.mesh.surface_get_material(0) as StandardMaterial3D
				_check(material.albedo_color.a == Color(1, 1, 1, expected.opacity).a, "Original fire opacity reaches its private native material")
				_check((material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS) == expected.depthWrite
					and material.get_meta("source_depth_write") == expected.depthWrite, "Original runtime depth-write state reaches native smoke materials and source metadata")
		view.free()

func _world_and_isolation() -> void:
	var world := BattleWorld.new()
	add_child(world)
	var before := BodyPresentation.time_now()
	world.sync_fires([_state("fire")], 100000, {})
	var after := BodyPresentation.time_now()
	_check(world.fire_visuals != null and world.fire_visuals.clock >= before and world.fire_visuals.clock <= after,
		"World binds fire to the same local wall clock as loot and airdrops")
	world.fire_visuals.set_process(false)
	var wall := {"now": 3.7}
	world.fire_visuals.wall_clock = func(): return wall.now
	world.sync_fires([_state("fire")], -100000, {})
	world.fire_visuals._process(99)
	_check(world.fire_visuals.clock == wall.now, "Repeated snapshots cannot rewind fire or add a second frame delta")
	var other := FirePresentation.new()
	add_child(other)
	other.set_process(false)
	other.sync([_state("fire")], 0, {"rain": 100})
	other._process(0)
	var id: int = int(Content.balance.hazard_visuals.fire.fx.flames[0].id)
	var first: MeshInstance3D = world.fire_visuals.entries[7].nodes["n_%d" % id]
	var second: MeshInstance3D = other.entries[7].nodes["n_%d" % id]
	_check(first.mesh != second.mesh and first.mesh.surface_get_material(0) != second.mesh.surface_get_material(0),
		"Fire instances retain private meshes and opacity materials")
	_check(first.visible and not second.visible, "Weather updates cannot hide a different fire owner")
	id = int(Content.balance.hazard_visuals.fire.fx.smoke[0].id)
	first = world.fire_visuals.entries[7].nodes["n_%d" % id]
	second = other.entries[7].nodes["n_%d" % id]
	var first_material := first.mesh.surface_get_material(0) as StandardMaterial3D
	var second_material := second.mesh.surface_get_material(0) as StandardMaterial3D
	_check(first_material != second_material, "Smoke depth and opacity updates own a private material")
	_check(first_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
		and second_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS,
		"A visible smoke update does not rewrite a separately born quenched smoke's source state")
	world.free()
	other.free()
	var explicit := FirePresentation.new()
	explicit.sync([], 9, {})
	explicit._process(.2)
	_check(explicit.clock == 9.2, "The existing explicit fixture clock remains available without a wall-clock provider")
	explicit.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fire clock/resource qualification requires the real renderer")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		_frames()
		_world_and_isolation()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("FIRE_CLOCK_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
