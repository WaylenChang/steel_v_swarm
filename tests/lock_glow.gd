extends Node

class Target extends BattleUnit:
	var measured: Dictionary
	func visual_dimensions() -> Dictionary:
		return measured

var assertions := 0
var failures := 0
var differences: Array = []
var scalar_failures := 0
var native_failures := 0

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if message.begins_with("Exact original double lock-glow state"):
			scalar_failures += 1
		else:
			native_failures += 1
		if failures <= 12:
			push_error(message)

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lock-glow qualification requires a real renderer")
		get_tree().quit(1)
		return
	var reference: Dictionary = Content.read_json("res://tests/fixtures/lock_glow.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Original lock-glow render callback is captured")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current lock-glow producer: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original lock-glow dependency matches imported provenance: " + path)
	if failures > 0:
		_finish()
		return
	var target := Target.new()
	target.hp = 100
	target.entity_id = 1
	target.side = "SWARM"
	add_child(target)
	var view := LockGlowPresentation.new()
	add_child(view)
	for index in range(reference.cases.size()):
		var item: Dictionary = reference.cases[index]
		var now := str(item.nowBits).hex_decode().decode_double(0)
		var hit := str(item.hitBits).hex_decode().decode_double(0)
		var pose := LockGlowPresentation.pose(item.dimensions, now, hit)
		_check(_bits(now * 6) == item.phaseBits, "Original double pulse phase reaches the trigonometric boundary unchanged")
		for key: String in item.pose:
			if _bits(pose[key]) != item.poseBits[key]:
				differences.append({"case": index, "field": key, "actual": pose[key], "expected": item.pose[key],
					"actual_bits": _bits(pose[key]), "expected_bits": item.poseBits[key],
					"phase_bits": item.phaseBits, "native_sine_bits": _bits(sin(now * 6)), "source_sine_bits": item.sineBits})
			_check(_bits(pose[key]) == item.poseBits[key], "Exact original double lock-glow state %d/%s" % [index, key])
		target.measured = item.dimensions
		view.clear()
		_check(view.apply({1: target}, {"target": 1, "anchor": 1}), "Actual native lock-glow admission")
		view.flash(hit)
		view.advance(now)
		_check(view.halo.position.y == Vector3(0, item.pose.centre, 0).y
			and view.halo.scale == Vector3.ONE * float(item.pose.halo_size), "Original native Float32 halo pose")
		_check(view.halo_material.albedo_color.a == Color(1, 1, 1, item.pose.halo_opacity).a
			and view.ring_material.albedo_color.a == Color(1, 1, 1, item.pose.ring_opacity).a, "Original native Float32 flash/pulse opacity")
		_check(view.ring.scale == Vector3.ONE * float(item.pose.radius) * float(item.pose.ring_scale),
			"Source radius and pulse reach the native ring scale without altered scalar inputs")
		var actual := view.ring.basis.orthonormalized()
		for axis in range(3):
			var expected: Array = item.basis[axis]
			_check(actual[axis].distance_to(Vector3(expected[0], expected[1], expected[2])) < .000001,
				"Original ring orientation from double phase %d/%d" % [index, axis])
	var mesh: WeakRef = weakref(view.ring.mesh)
	var material: WeakRef = weakref(view.ring_material)
	view.free()
	target.free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(mesh.get_ref() == null and material.get_ref() == null, "Private ring resources release after native destruction")
	_finish()

func _finish() -> void:
	_check(DirAccess.make_dir_recursive_absolute("res://artifacts/sol") == OK, "Create lock-glow diagnostic directory")
	var report := FileAccess.open("res://artifacts/sol/lock-glow-differences.json", FileAccess.WRITE)
	_check(report != null, "Open lock-glow scalar diagnostics")
	if report != null:
		report.store_string(JSON.stringify(differences))
		report.close()
	print("LOCK_GLOW_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures,
		"scalar_failures": scalar_failures, "native_failures": native_failures}))
	get_tree().quit(0 if failures == 0 else 1)
