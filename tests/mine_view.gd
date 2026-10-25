extends Node

class AnchorWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 0

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

func _binary_point(value: Array) -> Vector3:
	return Vector3(str(value[0]).hex_decode().decode_double(0), str(value[1]).hex_decode().decode_double(0), str(value[2]).hex_decode().decode_double(0))

func _source() -> void:
	reference = Content.read_json("res://tests/fixtures/mine_view.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original mine visibility controller")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current mine visibility capture: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original mine input agrees with shared metadata: " + path)
	_check(Content.constants.GAME.MINES.SEE_M == reference.rules.see and Content.constants.GAME.MINES.CLEAR_M == reference.rules.clear,
		"Original mine display thresholds remain unchanged")

func _poses(view: MinePresentation, expected: Array) -> void:
	for item: Dictionary in expected:
		var node: MeshInstance3D = view.entries[int(item.id)]
		_check(node.visible == item.visible, "Original strict 3D sight boundary and throttled visibility")
		for surface in range(node.mesh.get_surface_count()):
			var material := node.mesh.surface_get_material(surface) as StandardMaterial3D
			_check(material.albedo_color.a == Color(1, 1, 1, item.opacity).a,
				"Original opacity reaches private Float32 material storage, including retained hidden opacity")

func _program() -> void:
	var view := MinePresentation.new()
	add_child(view)
	var states: Array = []
	for index in range(reference.points.size()):
		states.append({"id": index + 1, "position": _point(reference.points[index])})
	view.sync(states)
	_check(view.last_check == reference.rules.initialCheck, "Original constructor initializes the absolute throttle clock at zero")
	_poses(view, reference.initial)
	for frame: Dictionary in reference.frames:
		var observer := _point(frame.observer)
		view.update_view(observer, str(frame.nowBits).hex_decode().decode_double(0))
		_check(_bits(view.last_check) == frame.lastCheckBits, "Original strict throttle interval, repeated/backward times and large clocks")
		_poses(view, frame.mines)
		for index in range(reference.points.size()):
			_check(_bits(MinePresentation._distance(observer, _point(reference.points[index]))) == frame.distances[index],
				"Original three-argument hypot retains exact distance bits before visibility and opacity")
	for index in range(states.size() - 1):
		var first: MeshInstance3D = view.entries[index + 1]
		var second: MeshInstance3D = view.entries[index + 2]
		_check(first.mesh != second.mesh and first.mesh.surface_get_material(0) != second.mesh.surface_get_material(0),
			"Different-distance mines retain independent visibility and opacity resources")
	var retained: MeshInstance3D = view.entries[2]
	view.sync(states.slice(1))
	_check(not view.entries.has(1) and view.entries[2] == retained, "Mine removal preserves surviving native instances")
	view.free()

func _distance_edges() -> void:
	for item: Dictionary in reference.distances:
		var value := MinePresentation._distance(_binary_point(item.first), _binary_point(item.second))
		if item.kind == "nan":
			_check(is_nan(value), "Original hypot preserves a NaN result without an infinity")
		elif item.kind == "inf":
			_check(value == INF, "Original hypot gives infinity priority over NaN")
		else:
			_check(_bits(value) == item.bits, "Original compensated hypot handles zero, tiny and large finite native coordinates")

func _world_clock() -> void:
	# The height probe isolates the world call contract, not a playable or qualified map.
	var world := AnchorWorld.new()
	add_child(world)
	world.sync_mines([{"id": 1, "x": 0.0, "z": 0.0}])
	var before := BodyPresentation.time_now()
	world.update_mine_view(Vector3.ZERO, -100000)
	var after := BodyPresentation.time_now()
	_check(world.mine_visuals.last_check >= before and world.mine_visuals.last_check <= after,
		"World uses the original local wall time rather than the incoming authority clock")
	var wall := {"now": 100.0}
	world.mine_visuals.wall_clock = func(): return wall.now
	world.update_mine_view(Vector3.ZERO, 100000)
	world.update_mine_view(Vector3(100, 100, 100), -100000)
	_check(world.mine_visuals.last_check == 100 and world.mine_visuals.entries[1].visible,
		"Unrelated or rewound authority times cannot bypass the source wall-clock throttle")
	wall.now = 100.125
	world.update_mine_view(Vector3(100, 100, 100), -100000)
	_check(not world.mine_visuals.entries[1].visible, "A paused authority clock does not stop a due local visibility check")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Mine visibility/resource qualification requires a real renderer")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		_program()
		_distance_edges()
		_world_clock()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("MINE_VIEW_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
