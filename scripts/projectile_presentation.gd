class_name ProjectilePresentation
extends Node3D

var rounds: Dictionary = {}
var shells: Array[Dictionary] = []
var free_models: Dictionary = {}
var traces: Array[Dictionary] = []
var free_traces: Array[MeshInstance3D] = []

func sync_rounds(states: Array) -> void:
	var seen := {}
	for state: Dictionary in states:
		seen[state.id] = true
		if not rounds.has(state.id):
			rounds[state.id] = {"key": state.key, "model": _take(state.key)}
		var model: ProjectileVisual = rounds[state.id].model
		model.place(state.position, state.velocity, state.age, state.velocity.length())
	for id in rounds.keys():
		if seen.has(id):
			continue
		_drop(rounds[id].model, rounds[id].key)
		rounds.erase(id)

func spawn_shell(state: Dictionary, key: String) -> void:
	state.model = _take(key)
	state.key = key
	state.model.place(state.position, state.velocity, state.age, state.velocity.length())
	shells.append(state)

func tracer(start: Vector3, end: Vector3, color: Color, ttl: float = 0.35) -> void:
	var line: MeshInstance3D
	if free_traces.is_empty():
		line = MeshInstance3D.new()
		line.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		line.material_override = material
		add_child(line)
	else:
		line = free_traces.pop_back()
	var geometry := line.mesh as ImmediateMesh
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	geometry.surface_add_vertex(start)
	geometry.surface_add_vertex(end)
	geometry.surface_end()
	color.a = 0.9
	line.material_override.albedo_color = color
	line.visible = true
	traces.append({"line": line, "ttl": ttl, "duration": ttl})

func advance(delta: float, collision: Callable) -> void:
	if not is_finite(delta) or delta <= 0:
		return
	for index in range(shells.size() - 1, -1, -1):
		var state: Dictionary = shells[index]
		var result := VisualShellMotion.advance(state, delta, collision)
		if result.terminal:
			_drop(state.model, state.key)
			shells.remove_at(index)
			continue
		var direction: Vector3 = state.position - result.previous
		state.model.place(state.position, direction, state.age, state.velocity.length())
	for index in range(traces.size() - 1, -1, -1):
		var trace: Dictionary = traces[index]
		trace.ttl -= delta
		var material: StandardMaterial3D = trace.line.material_override
		var color := material.albedo_color
		color.a = 0.9 * maxf(0, trace.ttl / trace.duration)
		material.albedo_color = color
		if trace.ttl <= 0:
			trace.line.visible = false
			free_traces.append(trace.line)
			traces.remove_at(index)
			continue

func _take(key: String) -> ProjectileVisual:
	var model: ProjectileVisual
	if not free_models.has(key):
		free_models[key] = []
	if free_models[key].is_empty():
		model = ProjectileVisual.new()
		add_child(model)
		model.configure(key)
	else:
		model = free_models[key].pop_back()
	model.visible = true
	return model

func _drop(model: ProjectileVisual, key: String) -> void:
	model.visible = false
	free_models[key].append(model)
