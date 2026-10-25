class_name ProjectilePresentation
extends Node3D

var rounds: Dictionary = {}
var shells: Array[Dictionary] = []
var free_models: Dictionary = {}
var traces: Array[Dictionary] = []
var free_traces: Array[MeshInstance3D] = []
var retired_rounds: Dictionary = {}
var missile_collision := Callable()
var rounds_clock := -INF
var retired := false
var pool_max := int(Content.read_json("res://data/projectile_presentation.json").poolMax)

func sync_rounds(states: Array, clock: float = NAN) -> void:
	if not _active():
		return
	if is_finite(clock):
		if clock <= rounds_clock:
			return
		rounds_clock = clock
	var seen := {}
	for state: Dictionary in states:
		if retired_rounds.has(state.id):
			continue
		seen[state.id] = true
		if not rounds.has(state.id):
			var admitted := _take(state.key)
			if not _active() or admitted == null or admitted.is_queued_for_deletion():
				return
			rounds[state.id] = {"key": state.key, "model": admitted}
		var model: ProjectileVisual = rounds[state.id].model
		model.place(state.position, state.velocity, state.age, float(state.get("speed", state.velocity.length())))
		if not _active():
			return
	for id in rounds.keys():
		if seen.has(id):
			continue
		var record: Dictionary = rounds[id]
		rounds.erase(id)
		_drop(record.model, record.key)
		if not _active():
			return
	for id: String in retired_rounds.keys():
		if is_finite(clock) and clock > float(retired_rounds[id]) and not states.any(func(state): return state.id == id):
			retired_rounds.erase(id)

func retire_round(id: String, clock: float) -> void:
	if not _active():
		return
	retired_rounds[id] = maxf(float(retired_rounds.get(id, -INF)), clock)
	if rounds.has(id):
		var record: Dictionary = rounds[id]
		rounds.erase(id)
		_drop(record.model, record.key)

func spawn_shell(state: Dictionary, key: String) -> void:
	if not _active():
		return
	var model := _take(key)
	if not _active() or model == null or model.is_queued_for_deletion():
		return
	state.model = model
	state.key = key
	shells.append(state)
	model.position = state.position
	model.quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(state.velocity))
	if _active():
		model.step_fx(0, 0)

func tracer(start: Vector3, end: Vector3, color: Color, ttl: float = 0.35) -> void:
	if not _active():
		return
	var line: MeshInstance3D
	if free_traces.is_empty():
		line = _make_trace()
		if line == null:
			return
	else:
		line = free_traces.pop_back()
	var geometry := line.mesh as ArrayMesh
	geometry.surface_update_vertex_region(0, 0, PackedVector3Array([start, end]).to_byte_array())
	geometry.custom_aabb = AABB(start, Vector3.ZERO).expand(end)
	color.a = 0.9
	line.material_override.albedo_color = color
	if not _active():
		return
	line.visible = true
	if not _active():
		return
	traces.append({"line": line, "ttl": ttl, "duration": ttl, "age": 0.0})

func advance(delta: float, collision: Callable, impact: Callable = Callable()) -> void:
	if not _active() or not is_finite(delta) or delta <= 0:
		return
	for index in range(shells.size() - 1, -1, -1):
		var state: Dictionary = shells[index]
		var trace := collision
		if missile_collision.is_valid() and not state.get("pierce", false):
			trace = func(start: Vector3, end: Vector3) -> Dictionary:
				return MissileViewRay.nearer(start, collision.call(start, end), missile_collision.call(start, end))
		var result := VisualShellMotion.advance(state, delta, trace)
		if not _active():
			return
		if result.terminal:
			if result.hit and impact.is_valid():
				impact.call(state.position, 1.6, 0xffc79a)
			if not _active():
				return
			var model: ProjectileVisual = state.model
			state.model = null
			shells.remove_at(index)
			_drop(model, state.key)
			if not _active():
				return
			continue
		var direction: Vector3 = state.position - result.previous
		state.model.place(state.position, direction, state.age, state.velocity.length())
		if not _active():
			return
	for index in range(traces.size() - 1, -1, -1):
		var trace: Dictionary = traces[index]
		trace.ttl -= delta
		trace.age += delta
		var material: StandardMaterial3D = trace.line.material_override
		var color := material.albedo_color
		color.a = 0.9 * maxf(0, trace.ttl / (trace.ttl + trace.age))
		material.albedo_color = color
		if not _active():
			return
		if trace.ttl <= 0:
			traces.remove_at(index)
			_release_trace(trace)
			if not _active():
				return
			continue

func _make_trace() -> MeshInstance3D:
	if not _active():
		return null
	var geometry := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	var line := MeshInstance3D.new()
	line.mesh = geometry
	line.material_override = material
	line.visible = false
	add_child(line)
	if not _active():
		line.queue_free()
		return null
	return line

func _release_trace(trace: Dictionary) -> void:
	var line: MeshInstance3D = trace.get("line")
	if line == null:
		return
	trace.line = null
	trace.ttl = 0.0
	trace.age = 0.0
	trace.duration = 0.0
	line.visible = false
	if not _active():
		line.queue_free()
		return
	if not line.is_queued_for_deletion():
		free_traces.append(line)

func _take(key: String) -> ProjectileVisual:
	if not _active():
		return null
	var model: ProjectileVisual
	if not free_models.has(key):
		free_models[key] = []
	if free_models[key].is_empty():
		model = ProjectileVisual.new()
		add_child(model)
		if not _active():
			model.queue_free()
			return null
		model.configure(key)
		if not _active():
			model.queue_free()
			return null
	else:
		model = free_models[key].pop_back()
		model.scale = Vector3.ONE
	model.visible = true
	return model

func _drop(model: ProjectileVisual, key: String) -> void:
	model.visible = false
	if not _active():
		model.queue_free()
		return
	if not model.is_queued_for_deletion() and not free_models[key].has(model):
		if free_models[key].size() < pool_max:
			free_models[key].append(model)
		else:
			model.queue_free()

func _active() -> bool:
	return not retired and is_inside_tree() and not is_queued_for_deletion()

func retire() -> void:
	if retired:
		return
	retired = true
	for state: Dictionary in shells:
		state.model = null
	shells.clear()
	rounds.clear()
	retired_rounds.clear()
	for trace: Dictionary in traces:
		trace.line = null
	traces.clear()
	free_models.clear()
	free_traces.clear()
	missile_collision = Callable()
	for child: Node in get_children():
		if child is ProjectileVisual or child is MeshInstance3D:
			child.visible = false
			child.queue_free()

func _exit_tree() -> void:
	retire()
