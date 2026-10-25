extends Node

class SetterProbe extends RefCounted:
	var calls := 0
	var callback: Callable
	func _set(_property: StringName, _value: Variant) -> bool:
		calls += 1
		callback.call()
		return true

var assertions := 0
var failures: Array[String] = []
var held: Array[WeatherPresentation] = []
var released: Array[WeakRef] = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _owner() -> WeatherPresentation:
	var view := WeatherPresentation.new()
	add_child(view)
	held.append(view)
	view.child_entered_tree.connect(func(child: Node) -> void:
		released.append(weakref(child))
		if child is WorldEnvironment:
			released.append(weakref(child.environment))
			released.append(weakref(child.environment.sky))
			released.append(weakref(child.environment.sky.sky_material))
		elif child is GPUParticles3D:
			released.append(weakref(child.process_material))
			released.append(weakref(child.draw_pass_1))
			released.append(weakref(child.draw_pass_1.material))
		elif child is MeshInstance3D:
			released.append(weakref(child.mesh))
			released.append(weakref(child.mesh.surface_get_material(0))))
	return view

func _weather() -> Dictionary:
	return {"light": 1.0, "fogNear": .1, "fogFar": .9, "isFrozen": false,
		"effectiveSand": 0.0, "effectiveRain": 1.0, "effectiveThunder": .5, "wind": 50.0}

func _closed(view: WeatherPresentation) -> void:
	var before := [view.revision, view.visual_seed, view.get_child_count()]
	view.configure(999)
	view.sync(_weather(), 12, {}, "summer", 100)
	view.strike([{"position": Vector3.ZERO}])
	view._process(1)
	view.retire()
	_check(view.retired and not view.configured and not view.configuring and not view.visible and not view.is_processing(), "Terminal weather owners cannot resume processing")
	_check(view.environment == null and view.sky_material == null and view.light == null
		and view.emitters.is_empty() and view.profiles.is_empty() and view.dynamics.is_empty()
		and view.lightning.is_empty(), "Weather retirement releases every native resource owner")
	_check(before == [view.revision, view.visual_seed, view.get_child_count()] and view.flash == 0,
		"Late weather configure/sync/strike/frame calls cannot allocate or mutate a closed owner")

func _source(reference: Dictionary) -> void:
	_check(reference.formatVersion == 1, "Capture original weather particle profiles")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current weather profile producer: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original weather input agrees with imported metadata: " + path)
	_check(reference.budgets == Content.balance.weather.visuals.particles, "Original particle budgets remain unchanged")
	for item: Dictionary in reference.cases:
		var view := _owner()
		view.configure(123)
		view.set_process(false)
		view.dynamics = item.dynamics
		view.profiles = WeatherRules.particle_profiles(item.dynamics)
		view._process(0)
		for kind: String in reference.budgets:
			var emitter: GPUParticles3D = view.emitters[kind]
			var profile: Dictionary = item.profiles[kind]
			_check(emitter.amount == int(reference.budgets[kind]) and emitter.use_fixed_seed,
				"Native weather retains original construction budgets and isolated visual seeds")
			_check(emitter.draw_pass_1.size == (Vector2(profile.width, profile.size) if kind == "rain" else Vector2(profile.size, profile.size)),
				"Original browser precipitation profile reaches native quad size")
			var wind: Array = item.dynamics.windDir
			var velocity := Vector3(wind[0] * float(profile.drift), -float(profile.speed), wind[1] * float(profile.drift))
			_check(emitter.process_material.direction == velocity.normalized()
				and emitter.process_material.initial_velocity_min == velocity.length()
				and emitter.process_material.initial_velocity_max == velocity.length(), "Original browser drift/speed reaches native process parameters")
		view.retire()
		_closed(view)

func _lifetimes() -> void:
	for stage in ["WorldEnvironment", "DirectionalLight3D", "GPUParticles3D"]:
		var view := _owner()
		var owner := view
		view.child_entered_tree.connect(func(child: Node) -> void:
			if child.get_class() == stage:
				if child is GPUParticles3D:
					_check(owner.emitters.values().has(child) and child.draw_pass_1 != null and child.process_material != null,
						"Emitter admission owns its completed native process and draw resources")
				owner.retire())
		view.configure(123)
		_check(view.retired and view.get_child_count() == (1 if stage == "WorldEnvironment" else 2 if stage == "DirectionalLight3D" else 3),
			"Reentrant weather configuration retirement stops later allocations")
		_closed(view)
	var view := _owner()
	view.configure(123)
	view.set_process(false)
	var children := view.get_child_count()
	view.configure(999)
	_check(view.visual_seed == 123 and view.get_child_count() == children, "Repeated weather configuration retains the original owner and construction seed")
	view.set_process(true)
	view.strike([{"position": Vector3.ZERO, "id": 1}])
	view.set_process(false)
	var record: Dictionary = view.lightning[0]
	var retiring := view
	view.emitters.rain.visibility_changed.connect(func() -> void:
		_check(retiring.emitters.is_empty() and retiring.lightning.is_empty() and record.is_empty()
			and retiring.environment == null, "Weather retirement seals native ownership before visibility callbacks"), CONNECT_ONE_SHOT)
	view.retire()
	_closed(view)
	view = _owner()
	view.configure(123)
	var striking := view
	view.child_entered_tree.connect(func(child: Node) -> void:
		if child is MeshInstance3D:
			_check(striking.lightning.size() == 1 and striking.lightning[0].node == child, "Lightning ownership is registered before native admission")
			striking.retire())
	view.strike([{"position": Vector3.ZERO}, {"position": Vector3.ONE}])
	_check(view.retired, "Lightning admission retirement closes the remaining strike batch")
	_closed(view)
	view = _owner()
	view.configure(123)
	var nested_strike := view
	view.child_entered_tree.connect(func(_child: Node) -> void:
		nested_strike.strike([{"position": Vector3(9, 9, 9)}]), CONNECT_ONE_SHOT)
	view.strike([{"position": Vector3.ZERO}, {"position": Vector3.ONE}])
	_check(view.lightning.size() == 3, "Independent reentrant strikes preserve every point in both event batches")
	view.retire()
	_closed(view)
	view = _owner()
	view.configure(123)
	view.strike([{"position": Vector3.ZERO}])
	var expiring := view
	var expired: Dictionary = view.lightning[0]
	var old_bolt: MeshInstance3D = expired.node
	old_bolt.visibility_changed.connect(func() -> void:
		_check(expired.is_empty() and expiring.lightning.is_empty(), "Lightning expiry seals its record before visibility callbacks")
		expiring.strike([{"position": Vector3.ONE}]), CONNECT_ONE_SHOT)
	view._process(1)
	_check(view.lightning.size() == 1 and view.lightning[0].node != old_bolt and view.lightning[0].remaining == .18,
		"A strike born during expiry retains its complete first lifetime")
	view.retire()
	_closed(view)
	view = _owner()
	view.configure(123)
	view.set_process(false)
	view.profiles = WeatherRules.particle_profiles({})
	var updating := view
	view.emitters.rain.visibility_changed.connect(updating.retire, CONNECT_ONE_SHOT)
	view._process(0)
	_closed(view)
	view = _owner()
	view.configure(123)
	var probe := SetterProbe.new()
	probe.callback = view.retire
	_check(not view._write(probe, {"first": 1, "second": 2}, view.revision) and probe.calls == 1,
		"A reentrant native property boundary prevents every later weather property write")
	_closed(view)
	view = _owner()
	view.queue_free()
	view.configure(123)
	view.strike([{"position": Vector3.ZERO}])
	view._process(1)
	_check(view.get_child_count() == 0 and view.visual_seed == 0 and view.lightning.is_empty(), "Queued weather owners reject native allocation and strike state")
	held.erase(view)

func _world_lifetime() -> void:
	var world := BattleWorld.new()
	world.bounds = {"minX": -100, "maxX": 100, "minZ": -100, "maxZ": 100}
	add_child(world)
	var schedule := WeatherRules.solar_schedule()
	world.sync_weather(_weather(), {}, 12, schedule, "summer", 123)
	var old := world.weather_visuals
	remove_child(world)
	_check(old.retired, "World detachment closes sky, light, precipitation and lightning ownership")
	add_child(world)
	world.sync_weather(_weather(), {}, 12, schedule, "summer", 123)
	_check(world.weather_visuals != old and world.weather_visuals.configured, "World reuse acquires fresh native weather resources")
	world.free()
	world = BattleWorld.new()
	world.bounds = {"minX": -100, "maxX": 100, "minZ": -100, "maxZ": 100}
	add_child(world)
	var admitting_world := world
	var latest := _weather()
	latest.isFrozen = true
	latest.light = .2
	world.child_entered_tree.connect(func(child: Node) -> void:
		if child is WeatherPresentation:
			_check(child.configured and child.emitters.size() == 3, "World admission receives fully configured native weather resources")
			admitting_world.sync_weather(latest, {}, 18, schedule, "winter", 999), CONNECT_ONE_SHOT)
	world.sync_weather(_weather(), {}, 12, schedule, "summer", 123)
	_check(world.weather_visuals.dynamics == latest and world.visual_frozen
		and world.weather_visuals.visual_seed == 123,
		"A newer weather publication during world admission retains its state and the original construction seed")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Weather retirement qualification requires a real renderer")
		get_tree().quit(1)
		return
	if "--live-exit" in OS.get_cmdline_user_args():
		var live := WeatherPresentation.new()
		add_child(live)
		live.configure(123)
		live.sync(_weather(), 12, WeatherRules.solar_schedule(), "summer", 200)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(live.configured and not live.retired, "Application exit starts with a live weather owner")
		print("WEATHER_LIVE_EXIT_READY")
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	var reference: Dictionary = Content.read_json("res://tests/fixtures/weather_owner.json")
	_source(reference)
	if failures.is_empty():
		_lifetimes()
		_world_lifetime()
	get_tree().paused = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(WeatherPresentation.retired_skies.is_empty(), "Independent native sky drainage releases every pending resource after the rendered frame while the SceneTree is paused")
	get_tree().paused = false
	for resource: WeakRef in released:
		_check(resource.get_ref() == null, "Closed weather owners release native node, sky, environment, particle and lightning resources")
	for view: WeatherPresentation in held:
		_check(view.get_child_count() == 0, "Retained terminal weather owners have no native children")
		view.free()
	held.clear()
	print("WEATHER_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
