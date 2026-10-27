extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
	var composition: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("pipFrames") is Array
		and not capture.pipFrames.is_empty() and capture.pipFrames[0] is Dictionary
		and capture.pipFrames[0].get("selected") is Array and capture.pipFrames[0].selected.size() >= 2
		and capture.pipFrames[0].get("draws") is Array and capture.pipFrames[0].draws.size() >= 2,
		"Capture original PiP selection and render methods")
	_check(composition.get("formatVersion") == 1 and composition.get("source") is Dictionary and composition.get("cases") is Array and composition.cases.size() == 8,
		"Capture original browser PiP composition at all three sizes")
	if failures > 0:
		_finish_pip()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "PiP capture generator is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "PiP oracle matches imported source: " + path)
	for path: String in composition.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == composition.source.inputs[path], "PiP composition generator is current: " + path)
	for path: String in composition.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == composition.source.sourceInputs[path], "PiP composition matches imported source: " + path)
	_check(composition.runtime.color == Content.side_info("STEEL").color, "PiP composition uses the original faction border color")
	_check(composition.runtime.webgl == "webgl2" and float(composition.runtime.deviceScaleFactor) == 1.0,
		"PiP composition retains its original WebGL and pixel-ratio capture")
	var configuration_matches: bool = Content.balance.get("pip") == capture.rules
	_check(configuration_matches, "Native PiP configuration matches the captured original rules")
	if configuration_matches:
		preload("res://tests/pip_suite.gd").run(self, capture)
		_lifecycle()
		_retiring_sources(capture.pipFrames[0])
		await _render_isolation(capture.pipFrames[0])
		await _render_composition(capture.pipFrames, capture.rules, composition.cases)
	_finish_pip()

func _lifecycle() -> void:
	var host := Control.new()
	add_child(host)
	var view := PipView.new()
	host.add_child(view)
	view._add_view()
	var slot: Dictionary = view.views[0]
	var world := World3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
	var original := mesh.layers
	for action: String in ["self_hide", "parent_hide", "detach", "retire"]:
		view.show()
		host.show()
		slot.border.show()
		slot.viewport.world_3d = world
		slot.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.pending_tags = [{"root": mesh, "mask": PipView.SOURCE_MASKS[0]}]
		view._begin_frame()
		_check(mesh.layers == PipView.SOURCE_MASKS[0], "Apply source exclusion only during the active render pass")
		match action:
			"self_hide": view.hide()
			"parent_hide": host.hide()
			"detach", "retire": host.remove_child(view)
		_check(slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and slot.viewport.world_3d == null and not slot.border.visible,
			"Inactive PiP stops rendering and releases its shared world: " + action)
		_check(view.pending_tags.is_empty() and view.layers.is_empty() and mesh.layers == original,
			"Inactive PiP clears pending source ownership and restores layers immediately: " + action)
		if action == "detach":
			host.add_child(view)
			_check(slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and view.pending_tags.is_empty(),
				"Reattachment requires a new accepted view update before rendering resumes")
	view.free()
	host.free()
	mesh.free()

func _retiring_sources(frame: Dictionary) -> void:
	var previous_failures := failures
	var previous_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var battle := BattleSimulation.new()
	add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "tank"
	pilot.hp = 1
	battle.add_child(pilot)
	pilot.cockpit = CockpitRig.new()
	pilot.add_child(pilot.cockpit)
	var cockpit_mesh := MeshInstance3D.new()
	cockpit_mesh.mesh = BoxMesh.new()
	pilot.cockpit.add_child(cockpit_mesh)
	var sources: Array[BattleUnit] = []
	var meshes: Array[MeshInstance3D] = []
	for row: Dictionary in frame.selected:
		var actor := BattleUnit.new()
		actor.entity_id = int(row.id)
		actor.kind = "decoy"
		actor.special = {"owner_peer": pilot.peer_id}
		actor.yaw = float(row.yaw)
		battle.add_child(actor)
		actor.model = Node3D.new()
		actor.add_child(actor.model)
		actor.model.position = Vector3(row.position[0], row.position[1], row.position[2])
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		actor.model.add_child(mesh)
		battle.units[actor.entity_id] = actor
		sources.append(actor)
		meshes.append(mesh)
	var view := PipView.new()
	add_child(view)
	view.update_view(battle, pilot, "STEEL")
	_check(view.views.size() == 2, "Captured two-source selection creates two native PiP slots")
	if view.views.size() < 2:
		view.free()
		battle.free()
		Controls.power_pref = previous_power
		return
	var first: Dictionary = view.views[0]
	var second: Dictionary = view.views[1]
	view._begin_frame()
	_check(meshes[0].layers == PipView.SOURCE_MASKS[0] and meshes[1].layers == PipView.SOURCE_MASKS[1] and cockpit_mesh.layers == PipView.COCKPIT_MASK,
		"Both captured sources receive their separate render masks")
	sources[0].remove_child(sources[0].model)
	view._begin_frame()
	_check(not first.border.visible and first.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and first.viewport.world_3d == null,
		"A source detached after selection cannot leave its PiP drawing at the render boundary")
	_check(meshes[0].layers == 1 and second.border.visible and second.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and meshes[1].layers == PipView.SOURCE_MASKS[1],
		"Retiring one source preserves the other PiP and its exclusion mask")
	view._end_frame()
	view.update_view(battle, pilot, "STEEL")
	_check(not first.border.visible and first.viewport.world_3d == null,
		"A detached source is rejected before reading its global camera position")
	sources[0].add_child(sources[0].model)
	view.update_view(battle, pilot, "STEEL")
	_check(first.border.visible and first.viewport.world_3d == battle.get_world_3d(),
		"A fresh selection restores a reattached source")
	sources[0].model.free()
	view._begin_frame()
	_check(not first.border.visible and first.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and first.viewport.world_3d == null,
		"A freed source model cannot leave a stale PiP viewport active")
	view._end_frame()
	sources[0].model = Node3D.new()
	sources[0].add_child(sources[0].model)
	meshes[0] = MeshInstance3D.new()
	meshes[0].mesh = BoxMesh.new()
	sources[0].model.add_child(meshes[0])
	view.update_view(battle, pilot, "STEEL")
	sources[1].queue_free()
	view._begin_frame()
	_check(not second.border.visible and second.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and second.viewport.world_3d == null,
		"A queued source ancestor is retired before the next render")
	_check(first.border.visible and meshes[0].layers == PipView.SOURCE_MASKS[0] and meshes[1].layers == 1,
		"Source retirement restores its layers without disturbing the remaining camera")
	view._end_frame()
	view.update_view(battle, pilot, "STEEL")
	_check(not second.border.visible and second.viewport.world_3d == null,
		"A queued source cannot be selected again before deferred deletion")
	view._begin_frame()
	sources[0].remove_child(sources[0].model)
	view._begin_frame()
	_check(not first.border.visible and cockpit_mesh.layers == 1 and view.pending_tags.is_empty() and view.layers.is_empty(),
		"Losing the last source restores the cockpit when no PiP viewport can draw")
	view._end_frame()
	sources[0].add_child(sources[0].model)
	view.update_view(battle, pilot, "STEEL")
	view._begin_frame()
	_check(meshes[0].layers == PipView.SOURCE_MASKS[0], "A live PiP source is masked before owner retirement")
	view.queue_free()
	view._begin_frame()
	_check(first.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and first.viewport.world_3d == null and view.pending_tags.is_empty() and view.layers.is_empty() and meshes[0].layers == 1 and cockpit_mesh.layers == 1,
		"A queued PiP owner releases active views and masks before drawing")
	view.free()
	battle.free()
	Controls.power_pref = previous_power
	if failures == previous_failures:
		print("PIP_RETIREMENT_PASS detached=true freed=true queued_source=true queued_owner=true")

func _render_isolation(frame: Dictionary) -> void:
	_check(DisplayServer.get_name() != "headless", "PiP isolation requires actual rendered frames")
	if DisplayServer.get_name() == "headless":
		return
	# Simple primary-color probes test visibility only, without substituting actor geometry.
	var main := SubViewport.new()
	main.size = Vector2i(128, 96)
	main.world_3d = World3D.new()
	main.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(main)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	main.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	camera.position.z = 8
	main.add_child(camera)
	camera.current = true
	var meshes: Array[MeshInstance3D] = []
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = Vector3([-1.6, 1.6, 0][index], 0, 0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = [Color.RED, Color.GREEN, Color.BLUE][index]
		mesh.material_override = material
		main.add_child(mesh)
		meshes.append(mesh)
	var view := PipView.new()
	add_child(view)
	for index in range(2):
		view._add_view()
		var slot: Dictionary = view.views[index]
		slot.viewport.size = main.size
		slot.viewport.world_3d = main.world_3d
		slot.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		slot.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		slot.camera.size = camera.size
		slot.camera.position = camera.position
		slot.camera.cull_mask = PipView.ALL_LAYERS & ~PipView.COCKPIT_MASK & ~PipView.SOURCE_MASKS[index]
		view.pending_tags.append({"root": meshes[index], "mask": PipView.SOURCE_MASKS[index]})
	view.pending_tags.append({"root": meshes[2], "mask": PipView.COCKPIT_MASK})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var output := "res://build/pip_native"
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "Create native PiP pixel evidence directory")
	var main_image := main.get_texture().get_image()
	_check(main_image.save_png(output + "/main.png") == OK, "Retain the actual main-camera render")
	var main_counts := _colors(main_image)
	print("PIP_PIXELS main=", main_counts)
	_check(main_counts.all(func(count): return count > 0), "Main camera retains both PiP sources and the cockpit during rendering")
	for index in range(2):
		var image: Image = view.views[index].viewport.get_texture().get_image()
		_check(image.save_png(output + "/pip_%d.png" % index) == OK, "Retain the actual PiP render")
		var counts := _colors(image)
		print("PIP_PIXELS slot=", index, " counts=", counts)
		var expected: Dictionary = frame.draws[index]
		for source in range(2):
			var visible: bool = not expected.hidden.has(frame.selected[source].id)
			_check((counts[source] > 0) == visible, "Actual PiP pixels hide only their own source and retain the other camera's source")
		_check((counts[2] > 0) == bool(expected.cockpit), "Actual PiP pixels exclude the cockpit as in the original render pass")
	_check(view.layers.is_empty() and meshes.all(func(mesh): return mesh.layers == 1),
		"Completed native render frames restore source layers before gameplay can copy a body")
	view.free()
	main.free()

func _colors(image: Image) -> Array:
	var counts := [0, 0, 0]
	_check(image != null and not image.is_empty(), "Native shared-world viewport produces readable pixels")
	if image == null or image.is_empty():
		return counts
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > .8 and color.g < .2 and color.b < .2:
				counts[0] += 1
			elif color.g > .8 and color.r < .2 and color.b < .2:
				counts[1] += 1
			elif color.b > .8 and color.r < .2 and color.g < .2:
				counts[2] += 1
	return counts

func _render_composition(frames: Array, rules: Dictionary, browser_cases: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_check(frames.size() >= 6, "Captured PiP composition contains all three resolution pairs")
	if frames.size() < 6:
		return
	for frame_index in [0, 2, 4]:
		var full: Dictionary = frames[frame_index]
		var low: Dictionary = frames[frame_index + 1]
		var valid: bool = full.get("draws") is Array and low.get("draws") is Array and full.draws.size() == 2 and low.draws.size() == 1 and full.get("size") == low.get("size")
		_check(valid, "Captured PiP composition retains its full and low-power source frames")
		if not valid:
			return
	var previous_failures := failures
	var previous_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var stage := SubViewport.new()
	stage.size = Vector2i(320, 568)
	stage.world_3d = World3D.new()
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLUE
	stage.add_child(environment)
	var battle := BattleSimulation.new()
	stage.add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "tank"
	pilot.hp = 1
	battle.add_child(pilot)
	var actors: Array[BattleUnit] = []
	for row: Dictionary in frames[0].selected:
		var actor := BattleUnit.new()
		actor.entity_id = int(row.id)
		actor.kind = "decoy"
		actor.special = {"owner_peer": pilot.peer_id}
		actor.yaw = float(row.yaw)
		battle.add_child(actor)
		actor.model = Node3D.new()
		actor.add_child(actor.model)
		actor.model.position = Vector3(row.position[0], row.position[1], row.position[2])
		battle.units[actor.entity_id] = actor
		actors.append(actor)
	var background := ColorRect.new()
	background.color = Color.BLACK
	stage.add_child(background)
	var view := PipView.new()
	stage.add_child(view)
	var overlay := ColorRect.new()
	overlay.color = Color.RED
	overlay.position = Vector2(20, 65)
	overlay.size = Vector2(8, 8)
	stage.add_child(overlay)
	for frame_index in [0, 2, 4]:
		var full: Dictionary = frames[frame_index]
		var low: Dictionary = frames[frame_index + 1]
		stage.size = Vector2i(int(full.size[0]), int(full.size[1]))
		background.size = Vector2(stage.size)
		environment.environment.background_color = Color.BLUE
		view.update_view(battle, pilot, "STEEL", 1.0)
		await RenderingServer.frame_post_draw
		_check_composite(stage, full, rules, Color.BLUE, "full", browser_cases[frame_index])
		environment.environment.background_color = Color.GREEN
		view.update_view(battle, pilot, "STEEL", 0.5)
		await RenderingServer.frame_post_draw
		_check_composite(stage, low, rules, Color.GREEN, "low", browser_cases[frame_index + 1])
		if frame_index == 0:
			view.hide()
			await RenderingServer.frame_post_draw
			_check_composite(stage, {"draws": []}, rules, Color.GREEN, "hidden")
			view.show()
			await RenderingServer.frame_post_draw
			_check_composite(stage, {"draws": []}, rules, Color.GREEN, "reshown")
			view.update_view(battle, pilot, "STEEL", 0.5)
			await RenderingServer.frame_post_draw
			_check_composite(stage, low, rules, Color.GREEN, "reattained")
			pilot.hp = 0
			view.update_view(battle, pilot, "STEEL", 1.0)
			await RenderingServer.frame_post_draw
			_check_composite(stage, {"draws": []}, rules, Color.GREEN, "dead")
			pilot.hp = 1
			for actor: BattleUnit in actors:
				actor.special.lost = true
			view.update_view(battle, pilot, "STEEL", 1.0)
			await RenderingServer.frame_post_draw
			_check_composite(stage, {"draws": []}, rules, Color.GREEN, "lost")
			actors[1].special.lost = false
			view.update_view(battle, pilot, "STEEL", 1.0)
			_check(view.pending_tags.size() == 1 and view.pending_tags[0].root == actors[1].model,
				"After a lost-link transition the remaining source owns the first slot")
			await RenderingServer.frame_post_draw
			_check_composite(stage, low, rules, Color.GREEN, "remaining")
			actors[0].special.lost = false
			Controls.power_pref = "1"
			view.update_view(battle, pilot, "STEEL", 1.0)
			await RenderingServer.frame_post_draw
			_check_composite(stage, low, rules, Color.GREEN, "power", browser_cases[7])
			Controls.power_pref = "0"
			pilot.cockpit = CockpitRig.new()
			pilot.add_child(pilot.cockpit)
			pilot.cockpit.hide()
			actors[0].model.hide()
			environment.environment.background_color = Color.BLUE
			view.update_view(battle, pilot, "STEEL", 1.0)
			await RenderingServer.frame_post_draw
			_check(not pilot.cockpit.visible and not actors[0].model.visible and actors[1].model.visible,
				"PiP drawing preserves an initially hidden cockpit and source model")
			_check_composite(stage, full, rules, Color.BLUE, "hidden_source", browser_cases[6])
			actors[0].model.show()
			pilot.cockpit.free()
			pilot.cockpit = null
	view.free()
	stage.free()
	Controls.power_pref = previous_power
	if failures == previous_failures:
		print("PIP_COMPOSITION_PASS sizes=3 low_power=true hud_order=true current_frame=true retirement=true")

func _check_composite(stage: SubViewport, frame: Dictionary, rules: Dictionary, scene_color: Color, mode: String, browser: Dictionary = {}) -> void:
	var actual := stage.get_texture().get_image()
	_check(actual != null and not actual.is_empty(), "Read the complete native PiP composition")
	if actual == null or actual.is_empty():
		return
	actual.convert(Image.FORMAT_RGBA8)
	var expected := Image.create(stage.size.x, stage.size.y, false, Image.FORMAT_RGBA8)
	expected.fill(Color.BLACK)
	var margin := int(rules.BORDER)
	for draw: Dictionary in frame.draws:
		var rect := Rect2i(int(draw.rect[0]), int(draw.rect[1]), int(draw.rect[2]), int(draw.rect[3]))
		expected.fill_rect(Rect2i(rect.position - Vector2i.ONE * margin, rect.size + Vector2i.ONE * margin * 2), Color(Content.side_info("STEEL").color))
		expected.fill_rect(rect, scene_color)
	expected.fill_rect(Rect2i(20, 65, 8, 8), Color.RED)
	var actual_bytes := actual.get_data()
	var expected_bytes := expected.get_data()
	var equal := actual_bytes == expected_bytes
	if not equal:
		var result := Raster.compare(actual, expected)
		equal = result.pixels == 0
		print("PIP_COMPOSITION_RASTER size=", stage.size, " mode=", mode, " pixels=", result.pixels, " maximum=", result.maximum)
		if not equal:
			for byte_index in range(0, actual_bytes.size(), 4):
				if actual_bytes[byte_index] != expected_bytes[byte_index] or actual_bytes[byte_index + 1] != expected_bytes[byte_index + 1] or actual_bytes[byte_index + 2] != expected_bytes[byte_index + 2] or actual_bytes[byte_index + 3] != expected_bytes[byte_index + 3]:
					var pixel := byte_index / 4
					print("PIP_COMPOSITION_WITNESS mode=", mode, " size=", stage.size, " x=", pixel % stage.size.x,
						" y=", pixel / stage.size.x, " actual=", actual_bytes.slice(byte_index, byte_index + 4),
						" expected=", expected_bytes.slice(byte_index, byte_index + 4))
					break
			var path := "res://artifacts/terra/pip-composition-%dx%d-%s.png" % [stage.size.x, stage.size.y, mode]
			_check(actual.save_png(path) == OK, "Retain failed PiP composition evidence")
	_check(equal, "Native PiP border, source viewport and foreground HUD match the complete original rectangle: " + str(stage.size) + " " + mode)
	if browser.is_empty():
		return
	var browser_size: Array = browser.size
	var viewport: Array = browser.viewport
	var client: Array = browser.client
	var backing: Array = browser.backing
	var source_visibility: Array = browser.sourceVisibility
	var hidden_source := mode == "hidden_source"
	var state_matches: bool = browser_size.size() == 2 and int(browser_size[0]) == stage.size.x and int(browser_size[1]) == stage.size.y
	state_matches = state_matches and browser.mode == mode and bool(browser.cockpit) == (not hidden_source) and not browser.scissor and viewport.size() == 4 and browser.clear == "000000" and float(browser.alpha) == 1.0
	state_matches = state_matches and int(viewport[0]) == 0 and int(viewport[1]) == 0 and int(viewport[2]) == stage.size.x and int(viewport[3]) == stage.size.y
	state_matches = state_matches and client.size() == 2 and backing.size() == 2
	state_matches = state_matches and int(client[0]) == stage.size.x and int(client[1]) == stage.size.y and int(backing[0]) == stage.size.x and int(backing[1]) == stage.size.y
	state_matches = state_matches and source_visibility.size() == 2
	state_matches = state_matches and int(source_visibility[0].id) == 7 and bool(source_visibility[0].visible) == (not hidden_source) and int(source_visibility[1].id) == 9 and bool(source_visibility[1].visible)
	_check(state_matches,
		"Original PiP frame retains viewport, scissor, clear color and visibility state")
	var selected: Array = browser.selected
	var selection_matches: bool = selected.size() == frame.selected.size()
	for index in range(mini(selected.size(), frame.selected.size())):
		selection_matches = selection_matches and int(selected[index]) == int(frame.selected[index].id)
	_check(selection_matches, "Browser and original source fixture select the same PiP cameras")
	var bytes := Marshalls.base64_to_raw(browser.png)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	_check(hash.finish().hex_encode() == browser.sha256, "Original PiP browser raster retains its captured bytes")
	var source := Image.new()
	var decoded := source.load_png_from_buffer(bytes) == OK and source.get_size() == actual.get_size()
	_check(decoded, "Original browser PiP raster decodes at the native viewport size")
	if not decoded:
		return
	source.convert(Image.FORMAT_RGBA8)
	var same := actual_bytes == source.get_data()
	if not same:
		var result := Raster.compare(actual, source)
		same = result.pixels == 0
		print("PIP_BROWSER_RASTER size=", stage.size, " mode=", mode, " pixels=", result.pixels, " maximum=", result.maximum)
		if not same:
			var prefix := "res://artifacts/terra/pip-browser-%dx%d-%s" % [stage.size.x, stage.size.y, mode]
			_check(actual.save_png(prefix + "-native.png") == OK and source.save_png(prefix + "-source.png") == OK,
				"Retain mismatched browser and native PiP rasters")
	_check(same, "Original browser and native PiP compositions match: " + str(stage.size) + " " + mode)

func _finish_pip() -> void:
	print("PIP_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
