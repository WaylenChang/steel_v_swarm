class_name WeatherPresentation
extends Node3D

static var retired_skies: Array[Resource] = []

var environment: Environment
var sky_material: ProceduralSkyMaterial
var light: DirectionalLight3D
var emitters: Dictionary = {}
var profiles: Dictionary = {}
var dynamics: Dictionary = {}
var base_light_energy := 0.0
var flash := 0.0
var visual_seed := 0
var lightning: Array = []
var retired := false
var configured := false
var configuring := false
var revision := 0

func _active() -> bool:
	return not retired and not is_queued_for_deletion()

func _current(token: int) -> bool:
	return _active() and token == revision

func _release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is WorldEnvironment:
		if node.environment != null:
			node.environment.sky = null
		node.environment = null
	if node is GPUParticles3D:
		node.emitting = false
	if node is Node3D:
		node.visible = false
	if is_instance_valid(node):
		node.queue_free()

func retire() -> void:
	if retired:
		return
	retired = true
	revision += 1
	configured = false
	configuring = false
	set_process(false)
	var pending_sky: Array[Resource] = []
	if environment != null:
		pending_sky.append(environment)
		if environment.sky != null:
			pending_sky.append(environment.sky)
	if sky_material != null:
		pending_sky.append(sky_material)
	var nodes := get_children()
	emitters.clear()
	profiles = {}
	dynamics = {}
	for record: Dictionary in lightning:
		record.clear()
	lightning.clear()
	environment = null
	sky_material = null
	light = null
	base_light_energy = 0
	flash = 0
	if not pending_sky.is_empty() and DisplayServer.get_name() != "headless":
		# Finish queued sky updates before releasing their native reflection textures.
		retired_skies.append_array(pending_sky)
		if not RenderingServer.frame_post_draw.is_connected(_drain_sky):
			RenderingServer.frame_post_draw.connect(_drain_sky, CONNECT_ONE_SHOT)
	for node: Node in nodes:
		_release(node)
	visible = false

static func _drain_sky() -> void:
	retired_skies.clear()

func _exit_tree() -> void:
	retire()

func _write(target: Object, values: Dictionary, token: int) -> bool:
	for property: String in values:
		if not _current(token):
			return false
		target.set(property, values[property])
	return _current(token)

func configure(seed_value: int) -> void:
	if not _active() or configured or configuring:
		return
	configuring = true
	set_process(false)
	visual_seed = seed_value & 0xffffffff
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
	environment.fog_depth_curve = 1.0
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	add_child(world_environment)
	if not _active():
		return
	light = DirectionalLight3D.new()
	light.shadow_enabled = true
	add_child(light)
	if not _active():
		return
	if Session.dedicated or DisplayServer.get_name() == "headless":
		configured = true
		configuring = false
		return
	var budgets: Dictionary = Content.balance.weather.visuals.particles
	for kind: String in budgets:
		var emitter := GPUParticles3D.new()
		emitter.name = kind.capitalize()
		emitter.amount = int(budgets[kind])
		emitter.amount_ratio = 0
		emitter.local_coords = true
		emitter.use_fixed_seed = true
		emitter.seed = (visual_seed ^ (kind.unicode_at(0) * 1997)) & 0xffffffff
		var cfg: Dictionary = Content.balance.weather.visuals
		emitter.visibility_aabb = AABB(Vector3(-cfg.box / 2, -cfg.height / 2, -cfg.box / 2), Vector3(cfg.box, cfg.height, cfg.box))
		emitter.lifetime = float(cfg.height) / (38 if kind == "rain" else 2.5 if kind == "snow" else 1.5)
		emitter.preprocess = minf(1, emitter.lifetime)
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(cfg.box / 2, cfg.height / 2, cfg.box / 2)
		process.gravity = Vector3.ZERO
		process.spread = 0
		emitter.process_material = process
		var mesh := QuadMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_color = Color("b6d7ed") if kind == "rain" else Color("e7f3ff") if kind == "snow" else Color("c7a16a")
		mesh.material = material
		emitter.draw_pass_1 = mesh
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitters[kind] = emitter
		add_child(emitter)
		if not _active():
			return
	configured = true
	configuring = false
	set_process(true)

func _color(value: float) -> Color:
	var number := int(value)
	return Color.from_rgba8((number >> 16) & 255, (number >> 8) & 255, number & 255).srgb_to_linear()

func sync(dyn: Dictionary, hour: float, schedule: Dictionary, season: String, span: float) -> void:
	if not _active() or not configured or dyn.is_empty():
		return
	revision += 1
	var token := revision
	dynamics = dyn
	profiles = WeatherRules.particle_profiles(dyn)
	var rules: Dictionary = Content.balance.weather
	var phase := WeatherRules.phase_blend(hour, schedule.phaseH)
	var a: Dictionary = rules.times[phase.a]
	var b: Dictionary = rules.times[phase.b]
	var season_tone: Dictionary = rules.seasons.get(season, rules.seasons.summer)
	var tint := _color(season_tone.tint)
	var sky := _color(a.sky).lerp(_color(b.sky), phase.t) * tint * (float(dyn.light) * 0.7 + 0.3)
	var fog := _color(a.fogC).lerp(_color(b.fogC), phase.t)
	if float(dyn.effectiveSand) > 0.1:
		fog = fog.lerp(_color(0xc89858), float(dyn.effectiveSand) * 0.7)
	elif dyn.isFrozen:
		fog = fog.lerp(_color(0xd8e6f0), 0.4)
	fog *= float(dyn.light) * 0.6 + 0.4
	var zenith := sky * 0.72
	var cap := minf(sky.get_luminance(), fog.get_luminance()) if float(dyn.fogFar) <= 1 else sky.get_luminance()
	if zenith.get_luminance() > cap and zenith.get_luminance() > 0.0001:
		zenith *= cap / zenith.get_luminance()
	# Native sky/fog replace the source's custom dome and air shaders.
	if not _write(sky_material, {"sky_top_color": zenith.linear_to_srgb(), "sky_horizon_color": fog.linear_to_srgb(),
		"ground_bottom_color": _color(a.hemiGnd).lerp(_color(b.hemiGnd), phase.t).linear_to_srgb(),
		"ground_horizon_color": fog.linear_to_srgb()}, token):
		return
	if not _write(environment, {"fog_light_color": fog.linear_to_srgb(), "fog_depth_begin": span * float(dyn.fogNear),
		"fog_depth_end": span * float(dyn.fogFar),
		"ambient_light_color": _color(a.hemiSky).lerp(_color(b.hemiSky), phase.t).linear_to_srgb(),
		"ambient_light_energy": lerpf(a.hemiI, b.hemiI, phase.t) * (float(dyn.light) * 0.6 + 0.4) * float(season_tone.mul)}, token):
		return
	var sun := WeatherRules.sun_direction(hour, schedule)
	var moon := WeatherRules.moon_direction(hour, schedule.lunarDay, schedule)
	var direction: Dictionary = sun if sun.y > 0 else moon
	var native_direction := Vector3(direction.x, direction.y, direction.z)
	if not _write(light, {"quaternion": Quaternion(Vector3.FORWARD, -native_direction.normalized()),
		"light_color": (_color(a.sun).lerp(_color(b.sun), phase.t) * tint).linear_to_srgb()}, token):
		return
	var moon_illumination := 0.08 + 0.92 * (1 - cos(float(schedule.lunarPhaseAngle))) * 0.5
	base_light_energy = lerpf(a.sunI, b.sunI, phase.t) * float(dyn.light) * float(season_tone.mul) * clampf(direction.y / float(Content.constants.DAYCLOCK.FADE_Y), 0, 1) * (1.0 if sun.y > 0 else moon_illumination)
	light.light_energy = base_light_energy + flash * 5

func strike(points: Array) -> void:
	if not _active() or not configured or not is_processing():
		return
	flash = 1.0
	for point: Dictionary in points:
		var endpoint: Vector3 = point.position
		var random := SourceRng.new(visual_seed ^ int(point.get("id", 0)) ^ int(Time.get_ticks_msec()))
		var segments := int(roundf(lerpf(10, float(Content.balance.weather.visuals.lightningSegments), float(dynamics.get("effectiveThunder", 0)))))
		var mesh := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("dbeeff")
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		var previous := endpoint + Vector3.UP * float(Content.balance.weather.visuals.height)
		for index in range(1, segments + 1):
			var fraction := float(index) / segments
			var vertex := endpoint + Vector3.UP * float(Content.balance.weather.visuals.height) * (1 - fraction)
			if index < segments:
				vertex += Vector3((random.next() - 0.5) * 8, 0, (random.next() - 0.5) * 8)
			mesh.surface_add_vertex(previous)
			mesh.surface_add_vertex(vertex)
			previous = vertex
		mesh.surface_end()
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lightning.append({"node": visual, "remaining": lerpf(0.18, 0.42, float(dynamics.get("effectiveThunder", 0)))})
		add_child(visual)
		if not _active():
			return

func _process(delta: float) -> void:
	if not _active() or not configured:
		return
	revision += 1
	var token := revision
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		for emitter: GPUParticles3D in emitters.values():
			emitter.global_position = camera.global_position
	for kind: String in emitters:
		if not profiles.has(kind):
			continue
		var emitter: GPUParticles3D = emitters[kind]
		var p: Dictionary = profiles[kind]
		emitter.amount_ratio = lerpf(emitter.amount_ratio, p.density, 1 - exp(-delta * 4))
		if not _current(token):
			return
		emitter.visible = emitter.amount_ratio > 0.003
		if not _current(token):
			return
		var mesh: QuadMesh = emitter.draw_pass_1
		mesh.size = Vector2(p.width, p.size) if kind == "rain" else Vector2(p.size, p.size)
		if not _current(token):
			return
		var material: StandardMaterial3D = mesh.material
		material.albedo_color.a = lerpf(material.albedo_color.a, p.opacity, 1 - exp(-delta * 4))
		if not _current(token):
			return
		var process: ParticleProcessMaterial = emitter.process_material
		var wind: Array = dynamics.get("windDir", [1, 0])
		var velocity := Vector3(float(wind[0]) * float(p.drift), -float(p.speed), float(wind[1]) * float(p.drift))
		if not _write(process, {"direction": velocity.normalized(), "initial_velocity_min": velocity.length(),
			"initial_velocity_max": velocity.length()}, token):
			return
	flash = maxf(0, flash - delta * 6)
	if light != null:
		light.light_energy = base_light_energy + flash * 5
		if not _current(token):
			return
	for index in range(lightning.size() - 1, -1, -1):
		lightning[index].remaining -= delta
		if lightning[index].remaining <= 0:
			var record: Dictionary = lightning[index]
			var node: MeshInstance3D = record.node
			lightning.remove_at(index)
			record.clear()
			_release(node)
			if not _current(token):
				return
