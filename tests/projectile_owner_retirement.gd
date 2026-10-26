extends Node

class PoolProbe extends ProjectilePresentation:
	var returns: Array[Dictionary] = []
	var discarded := 0
	func _drop(model: ProjectileVisual, key: String) -> void:
		super._drop(model, key)
		if model.is_queued_for_deletion():
			discarded += 1
		returns.append({"model": model, "free": free_models.get(key, []).size(), "disposed": discarded})

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

func _shell() -> Dictionary:
	return {"position": Vector3(0, 100, 0), "origin": Vector3(0, 100, 0), "target": Vector3(0, 100, -100),
		"velocity": Vector3(0, 0, -120), "guided": false, "pierce": false, "age": 0.0,
		"launch_distance": 0.0, "range": .01}

func _source() -> void:
	reference = Content.read_json("res://data/projectile_presentation.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original projectile ownership programs")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Original projectile ownership producer is current: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original projectile dependency matches imported metadata: " + path)

func _pool() -> void:
	var view := PoolProbe.new()
	add_child(view)
	var states: Array[Dictionary] = []
	var models: Array[ProjectileVisual] = []
	for index in range(int(reference.reuse.created)):
		var state := _shell()
		view.spawn_shell(state, reference.key)
		states.append(state)
		models.append(state.model)
	view.advance(1.0 / 60, func(_start, _end): return {})
	_check(view.shells.is_empty() and view.returns.size() == reference.steps.size(), "All range-expired records retire once")
	for index in range(reference.steps.size()):
		var expected: Dictionary = reference.steps[index]
		var actual: Dictionary = view.returns[index]
		_check(actual.model == models[int(expected.index)] and states[int(expected.index)].model == null and expected.cleared,
			"Original reverse retirement clears the record before its model can be reused")
		_check(actual.free == int(expected.free) and actual.disposed == int(expected.disposed),
			"Original per-variant pool bound retains the same models and disposes overflow")
	var reused := _shell()
	view.spawn_shell(reused, reference.key)
	_check(reused.model == models[int(reference.reuse.index)], "The native matching pool retains the original LIFO reuse order")
	reused.model.scale = Vector3(2, 3, 4)
	view.advance(1.0 / 60, func(_start, _end): return {})
	var live := _shell()
	view.spawn_shell(live, reference.key)
	_check(live.model.scale == Vector3(reference.reuse.scale[0], reference.reuse.scale[1], reference.reuse.scale[2])
		and live.model.visible == reference.reuse.visible, "Reacquisition resets source root scale and visibility")
	var round_state := {"id": "owner/1", "key": reference.key, "position": Vector3(1, 2, 3), "velocity": Vector3.FORWARD, "age": 0.0}
	view.sync_rounds([round_state], 10)
	view.tracer(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	var tracked: WeakRef = weakref(live.model)
	var material: WeakRef = weakref(live.model.animated_materials.values()[0])
	view.retire()
	_check(live.model == null and view.rounds.is_empty() and view.shells.is_empty() and view.traces.is_empty()
		and view.free_models.is_empty() and view.free_traces.is_empty(), "Owner retirement releases live rounds, shell records, tracers and cached models")
	var before := view.get_child_count()
	view.spawn_shell(_shell(), reference.key)
	view.sync_rounds([round_state], 11)
	view.tracer(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	view.retire_round("late", 12)
	_check(view.get_child_count() == before and view.retired_rounds.is_empty(), "Retired inputs cannot allocate models or mutate terminal guards")
	await get_tree().process_frame
	_check(tracked.get_ref() == null and view.get_child_count() == 0, "Native children release their packed resources after deferred destruction")
	_check(material.get_ref() == null, "The retired owner's private animation material is released with its native mesh")
	view.free()

func _callbacks() -> void:
	for during_collision: bool in [true, false]:
		var view := PoolProbe.new()
		add_child(view)
		var state := _shell()
		view.spawn_shell(state, reference.key)
		var impacts := {"count": 0}
		var collision := func(start, end):
			if during_collision:
				view.retire()
			return {"position": start.lerp(end, .5)}
		var impact := func(_point, _radius, _color):
			impacts.count += 1
			view.retire()
		view.advance(1.0 / 60, collision, impact)
		_check(view.retired and state.model == null and view.shells.is_empty() and view.returns.is_empty(),
			"Reentrant collision or impact retirement cannot return a disposed model to a cleared pool")
		_check(impacts.count == (0 if during_collision else 1), "Collision retirement cancels impact; impact retirement is delivered once")
		view.free()
	var hidden := PoolProbe.new()
	add_child(hidden)
	var state := _shell()
	hidden.spawn_shell(state, reference.key)
	state.model.visibility_changed.connect(hidden.retire, CONNECT_ONE_SHOT)
	hidden.advance(1.0 / 60, func(_start, _end): return {})
	_check(hidden.retired and state.model == null and hidden.free_models.is_empty(), "Visibility retirement cannot repopulate a cleared model pool")
	hidden.free()
	var admission := ProjectilePresentation.new()
	add_child(admission)
	admission.child_entered_tree.connect(func(_child): admission.retire(), CONNECT_ONE_SHOT)
	admission.sync_rounds([{"id": "interrupted", "key": "must-not-load", "position": Vector3.ZERO,
		"velocity": Vector3.FORWARD, "age": 0.0}], 1)
	_check(admission.retired and admission.rounds.is_empty(), "Model admission retirement prevents source configuration and late round insertion")
	admission.free()
	var tracer := ProjectilePresentation.new()
	add_child(tracer)
	tracer.child_entered_tree.connect(func(_child): tracer.retire(), CONNECT_ONE_SHOT)
	tracer.tracer(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	_check(tracer.retired and tracer.traces.is_empty(), "Tracer admission retirement cannot publish an abandoned line")
	tracer.free()

func _flight() -> void:
	var view := ProjectilePresentation.new()
	add_child(view)
	for program: Dictionary in reference.flight:
		var definition := Content.weapon(program.character, program.slot, int(program.level))
		var origin := Vector3(program.origin[0], program.origin[1], program.origin[2])
		var target := Vector3(program.target[0], program.target[1], program.target[2])
		var state := VisualShellMotion.launch(definition, origin, target, program.ground, program.surface,
			NAN if program.speed == null else float(program.speed))
		view.spawn_shell(state, reference.key)
		var model: ProjectileVisual = state.model
		var impacts := {"count": 0}
		for frame in range(program.steps.size()):
			var expected: Dictionary = program.steps[frame]
			var collision := func(start, end):
				return {"position": start.lerp(end, .6)} if frame == int(program.hitFrame) else {}
			var impact := func(_point, _radius, _color): impacts.count += 1
			view.advance(program.delta, collision, impact)
			var point := Vector3(expected.position[0], expected.position[1], expected.position[2])
			_check(state.position.distance_to(point) < .001 and model.visible != expected.terminal,
				"Original visual flight and terminal visibility remain unchanged: " + program.name)
			_check((state.model == null) == bool(expected.terminal), "Only a source terminal frame releases its model reference")
		_check(impacts.count == (1 if int(program.hitFrame) >= 0 else 0), "Only genuine source collision emits an impact; range retirement is silent")
	view.free()

func _transfer() -> void:
	# An unbuilt world isolates native tree ownership; it does not qualify scenery.
	var world := BattleWorld.new()
	add_child(world)
	var previous := world.ensure_projectile_visuals()
	var state := _shell()
	previous.spawn_shell(state, reference.key)
	remove_child(world)
	_check(previous.retired and state.model == null, "World detachment retires its old visual-shell owner")
	add_child(world)
	var fresh := world.ensure_projectile_visuals()
	_check(fresh != previous and not fresh.retired and fresh.shells.is_empty(), "Reattachment creates a fresh presentation owner without old flights")
	fresh.queue_free()
	var replaced := world.ensure_projectile_visuals()
	_check(replaced != fresh and not replaced.retired, "Queued presentation loss cannot return an obsolete owner")
	world.free()

func _tracers() -> void:
	for program: Dictionary in reference.tracerSequences:
		var sequence := ProjectilePresentation.new()
		add_child(sequence)
		sequence.tracer(Vector3(1, 2, 3), Vector3(-4, 5, -6), Color.WHITE, str(program.ttlBits).hex_decode().decode_double(0))
		var record: Dictionary = sequence.traces[0]
		var line: MeshInstance3D = record.line
		for frame: Dictionary in program.frames:
			sequence.advance(str(frame.deltaBits).hex_decode().decode_double(0), func(_start, _end): return {})
			_check(sequence.traces.is_empty() != bool(frame.active) and line.visible == frame.visible
				and absf(line.material_override.albedo_color.a - float(frame.opacity)) < .000001,
				"Original multi-frame tracer fade and expiration remain unchanged")
			if frame.active:
				_check(PackedFloat64Array([record.ttl]).to_byte_array().hex_encode() == frame.ttlBits
					and PackedFloat64Array([record.age]).to_byte_array().hex_encode() == frame.ageBits,
					"Tracer lifetime and age retain the original exact double accumulation")
		sequence.free()
	for frame: Dictionary in reference.tracerFrames:
		var view := ProjectilePresentation.new()
		add_child(view)
		view.tracer(Vector3(1, 2, 3), Vector3(-4, 5, -6), Color.hex((int(frame.color) << 8) | 0xff), frame.ttl)
		var record: Dictionary = view.traces[0]
		var line: MeshInstance3D = record.line
		view.advance(frame.delta, func(_start, _end): return {})
		_check(absf(line.material_override.albedo_color.a - float(frame.opacity)) < .000001 and line.visible == frame.visible,
			"Original tracer frame fade and visibility remain unchanged")
		var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(vertices == PackedVector3Array([Vector3(1, 2, 3), Vector3(-4, 5, -6)]), "Native dynamic tracer vertices retain original source endpoints")
		if not frame.visible:
			_check(record.line == null, "A released trace record cannot retain its recycled line")
		view.free()
	var view := ProjectilePresentation.new()
	add_child(view)
	var previous_line: MeshInstance3D
	var previous_mesh: ArrayMesh
	var previous_material: Material
	for update: Dictionary in reference.tracerUpdates:
		var start := Vector3(update.start[0], update.start[1], update.start[2])
		var end := Vector3(update.end[0], update.end[1], update.end[2])
		view.tracer(start, end, Color.hex((int(update.color) << 8) | 0xff), update.ttl)
		var record: Dictionary = view.traces[0]
		var line: MeshInstance3D = record.line
		var mesh := line.mesh as ArrayMesh
		if previous_line != null:
			_check(line == previous_line and mesh == previous_mesh and line.material_override == previous_material
				and update.geometrySame and update.materialSame, "Reused tracers update the existing line, native mesh and private material")
		_check(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) == 2
			and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES, "A tracer owns one fixed two-vertex surface")
		var points: Array = update.vertices
		var expected := PackedVector3Array([Vector3(points[0], points[1], points[2]), Vector3(points[3], points[4], points[5])])
		_check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == expected, "Repeated and large-coordinate updates retain original Float32 vertex writes")
		_check(mesh.custom_aabb == AABB(start, Vector3.ZERO).expand(end), "Updating endpoints refreshes the native culling override")
		_check(absf(line.material_override.albedo_color.a - float(update.opacity)) < .000001,
			"Reacquisition resets the original starting opacity")
		previous_line = line
		previous_mesh = mesh
		previous_material = line.material_override
		view.advance(update.ttl + .01, func(_start, _end): return {})
		view._release_trace(record)
		_check(record.line == null and view.free_traces.size() == 1, "Trace release is idempotent and cannot duplicate a pool entry")
	view.free()

func _tracer_render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := WorldEnvironment.new()
	background.environment = Environment.new()
	background.environment.background_mode = Environment.BG_COLOR
	background.environment.background_color = Color.BLACK
	viewport.add_child(background)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var view := ProjectilePresentation.new()
	viewport.add_child(view)
	for center: float in [100.0, 200.0]:
		view.advance(1.0, func(_start, _end): return {})
		camera.position = Vector3(center, 0, 5)
		camera.look_at(Vector3(center, 0, 0))
		view.tracer(Vector3(center - 1, 0, 0), Vector3(center + 1, 0, 0), Color.WHITE)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		var lit := 0
		for y in range(pixels.get_height()):
			for x in range(pixels.get_width()):
				if pixels.get_pixel(x, y).r > .5:
					lit += 1
		_check(lit > 0, "Reused GPU vertices render at the new bounds, outside the original surface AABB")
	var record: Dictionary = view.traces[0]
	var mesh: WeakRef = weakref(record.line.mesh)
	var material: WeakRef = weakref(record.line.material_override)
	view.retire()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(record.line == null and mesh.get_ref() == null and material.get_ref() == null,
		"Retiring rendered tracers releases their fixed mesh buffers and private materials")
	viewport.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Projectile ownership and dynamic vertex qualification require a rendered session")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		await _pool()
		_flight()
		_callbacks()
		_transfer()
		_tracers()
		await _tracer_render()
	await get_tree().process_frame
	print("PROJECTILE_OWNER_RETIREMENT assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
