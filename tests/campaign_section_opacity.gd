extends "res://tests/run.gd"

const Section = preload("res://scripts/campaign_crawl_section.gd")
const Raster = preload("res://tests/raster_compare.gd")

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer
	func _update_scene() -> void:
		pass

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_section_opacity.json")
	var data: Dictionary = Content.read_json("res://data/campaign_section_opacity.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			output = argument.trim_prefix("--evidence-dir=")
	if not output.is_empty():
		var absolute := ProjectSettings.globalize_path(output)
		_check(not DirAccess.dir_exists_absolute(absolute), "Preserve existing section-opacity evidence")
		if not DirAccess.dir_exists_absolute(absolute):
			_check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "Create section-opacity evidence directory")
	_check(DisplayServer.get_name() != "headless", "Section opacity pixels require a real display driver")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native section opacity resource retains original CSS rules")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current section opacity capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original section opacity input: " + path)
	if failures == 0:
		await _check_programs(capture, output)
		await _check_view(capture)
		await _check_wall_clock()
	print("CAMPAIGN_SECTION_OPACITY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(capture: Dictionary, output: String) -> void:
	var marker_rules: Dictionary = Content.read_json("res://data/campaign_section_marker.json").rules
	var marker_geometry_rules: Dictionary = Content.read_json("res://data/campaign_marker_geometry.json").rules
	var geometry_rules: Dictionary = Content.read_json("res://data/campaign_section_geometry.json").rules
	for program_index in range(capture.programs.size()):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(96, 64)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var background := ColorRect.new()
		background.color = Color.BLACK
		background.size = Vector2(viewport.size)
		viewport.add_child(background)
		var group := CanvasGroup.new()
		viewport.add_child(group)
		var sections: Array = []
		for index in range(capture.scenes.size()):
			var section := Section.new()
			section.scene = capture.scenes[index]
			section.marker_rules = marker_rules
			section.marker_geometry_rules = marker_geometry_rules
			section.geometry_rules = geometry_rules
			section.opacity_rules = capture.rules
			group.add_child(section)
			section.size = Vector2(viewport.size)
			section.content.hide()
			for item: Dictionary in capture.layers[index]:
				var panel := ColorRect.new()
				panel.position = Vector2(item.rect[0], item.rect[1])
				panel.size = Vector2(item.rect[2], item.rect[3])
				panel.color = Color(item.rgba[0], item.rgba[1], item.rgba[2], item.rgba[3])
				section.layer.content.add_child(panel)
			section.select(index == 0, true)
			sections.append(section)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		for index in range(sections.size()):
			_near(sections[index].opacity, capture.initial.opacity[index], "Original initial section opacity")
			_check(sections[index].tween == null, "Initial section selection does not animate")
		if program_index == 0:
			var initial_actual := viewport.get_texture().get_image()
			var initial_expected := Image.new()
			var initial_decoded := initial_expected.load_png_from_buffer(Marshalls.base64_to_raw(capture.initial.png)) == OK \
				and initial_expected.get_size() == initial_actual.get_size()
			_check(initial_decoded, "Original initial section-opacity raster has matching dimensions")
			if initial_decoded:
				var initial_result := Raster.compare(initial_actual, initial_expected)
				_check(initial_result.pixels == 0, "Original initial section composition: pixels=%d maximum=%f" % [initial_result.pixels, initial_result.maximum])
				if not output.is_empty():
					Raster.diagnostic(initial_actual).save_png(output + "/native_initial.png")
					initial_expected.save_png(output + "/source_initial.png")
		for frame_index in range(capture.programs[program_index].frames.size()):
			var frame: Dictionary = capture.programs[program_index].frames[frame_index]
			if frame.select:
				for index in range(sections.size()):
					sections[index].select(index == int(frame.index))
			for section in sections:
				if section.tween != null and section.tween.is_valid():
					section.tween.pause()
					section.tween.custom_step(float(frame.delta))
			for index in range(sections.size()):
				_near(sections[index].opacity, frame.opacity[index], "Original independent section opacity and reversal")
				_check(sections[index].selected == bool(frame.selected[index]), "Original active section selection")
			if frame.has("png"):
				for repeat in range(2):
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image()
				var expected := Image.new()
				var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(frame.png)) == OK and expected.get_size() == actual.get_size()
				_check(decoded, "Original section-opacity raster has matching dimensions")
				if decoded:
					var result := Raster.compare(actual, expected)
					_check(result.pixels == 0, "Original section-opacity composition: frame=%d pixels=%d maximum=%f" % [frame_index, result.pixels, result.maximum])
					if not output.is_empty():
						Raster.diagnostic(actual).save_png(output + "/native_%d.png" % frame_index)
						expected.save_png(output + "/source_%d.png" % frame_index)
		for section in sections:
			var layer: Sprite2D = section.layer
			group.remove_child(section)
			_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"Retired section stops its isolated render target")
			section.free()
		viewport.free()

func _check_view(capture: Dictionary) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 3), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(view.sections.size() == 3 and view.scroll.get_global_rect().has_area(), "Cinematic creates three scrollable section groups")
	for index in range(view.sections.size()):
		var section = view.sections[index]
		_check(section is Section and section.selected == (index == 0) and section.size.y > 0,
			"Initial cinematic selection owns its section group")
		_near(section.opacity, capture.initial.opacity[index], "Cinematic starts with original section opacity")
	var first = view.sections[0]
	var text_image: Image = first.layer.viewport.get_texture().get_image()
	var text_visible := false
	for y in range(text_image.get_height()):
		for x in range(text_image.get_width()):
			if text_image.get_pixel(x, y).a > 0:
				text_visible = true
				break
		if text_visible:
			break
	_check(text_visible and first.layer.viewport.size.y >= ceili(first.content.size.y),
		"The isolated section surface renders narrative text without truncating its content")
	view._set_scene(1)
	for section in view.sections:
		if section.tween != null and section.tween.is_valid():
			section.tween.pause()
			section.tween.custom_step(.05)
	var frame: Dictionary = capture.programs[0].frames[1]
	for index in range(view.sections.size()):
		_near(view.sections[index].opacity, frame.opacity[index], "Scene changes animate original section opacity")
	view.hide()
	await get_tree().process_frame
	for section in view.sections:
		_check(section.layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"Hiding the cinematic stops its section render targets")
	view.show()
	await get_tree().process_frame
	for section in view.sections:
		_check(section.layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"Showing the cinematic resumes its section render targets")
	var retired := view.sections.duplicate()
	view.dispose()
	for section in retired:
		_check(section.layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
			and (section.tween == null or not section.tween.is_valid()), "Cinematic disposal retires section rendering and transitions")
	view.play(Content.campaign.prologue.slice(0, 3), "Continue", 2)
	view.set_process(false)
	for index in range(view.sections.size()):
		var section = view.sections[index]
		_check(section.selected == (index == 2) and section.tween == null,
			"Starting in a later chapter selects its section without a fade")
		_near(section.opacity, float(capture.rules.active) if index == 2 else float(capture.rules.inactive),
			"Later-chapter playback starts with original section opacity")
	view.dispose()
	view.free()
	await get_tree().process_frame

func _check_wall_clock() -> void:
	var parent := Node.new()
	parent.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(parent)
	var view := ProbeView.new()
	parent.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 2), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	view._set_scene(1)
	var previous_scale := Engine.time_scale
	Engine.time_scale = 0
	get_tree().paused = true
	var deadline := Time.get_ticks_usec() + 550000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	_check(view.sections[0].opacity <= .66 and view.sections[1].opacity >= .99,
		"Section transitions continue on wall time while gameplay is paused")
	get_tree().paused = false
	Engine.time_scale = previous_scale
	view.dispose()
	view.free()
	parent.free()
