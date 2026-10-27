extends RefCounted

const ParamCurve = preload("res://scripts/audio_param_curve.gd")
const Oscillator = preload("res://scripts/audio_move_oscillator.gd")

var output_curves: Dictionary = {}
var frequencies: Dictionary = {}
var oscillators: Dictionary = {}
var rate_bases: Dictionary = {}
var input_node := -1
var modulation_node := -1

func configure(graph: Dictionary, plan: Dictionary, initial: Dictionary, rate: float, tables: Dictionary) -> Error:
	if initial.rate != 1 or tables.get("sampleRate") != rate:
		return ERR_UNAVAILABLE
	for key: String in ["gain", "pan"]:
		output_curves[key] = _curve(float(initial[key]), rate)
	if graph.has("wet"):
		output_curves.wet = _curve(float(initial.wet), rate)
		output_curves.dry = _curve(1.0 - float(initial.wet), rate)
	for branch: Dictionary in plan.branches:
		if branch.kind == "oscillator":
			input_node = int(branch.source)
	for node: int in plan.lfos:
		modulation_node = node
	for node: Dictionary in graph.nodes:
		if node.kind == "createOscillator":
			if node.parameters.get("detune", {}).get("initial", 0) != 0:
				return ERR_UNAVAILABLE
			var oscillator := Oscillator.new()
			if oscillator.configure(tables, node.type) != OK:
				return ERR_INVALID_DATA
			oscillators[int(node.id)] = oscillator
			frequencies[int(node.id)] = _curve(float(node.parameters.frequency.initial), rate)
	for binding: Dictionary in graph.rate:
		if binding.parameter.parameter != "frequency":
			return ERR_UNAVAILABLE
		var node := int(binding.parameter.node)
		if graph.nodes[node].parameters.get("detune", {}).get("initial", 0) != 0:
			return ERR_UNAVAILABLE
		rate_bases[node] = float(binding.base)
		if not frequencies.has(node):
			frequencies[node] = _curve(float(graph.nodes[node].parameters.frequency.initial), rate)
	for curve: Variant in output_curves.values() + frequencies.values():
		if curve == null:
			return ERR_INVALID_DATA
	return OK

static func _curve(initial: float, rate: float) -> RefCounted:
	var curve := ParamCurve.new()
	return curve if curve.configure(initial, rate) == OK else null

func queue(key: String, target: float, tau: float, time: float) -> Error:
	if key == "rate":
		for node: int in rate_bases:
			var error: Error = frequencies[node].queue(float(rate_bases[node]) * target, time, tau)
			if error != OK:
				return error
		return OK
	if key == "wet" and not output_curves.has("wet"):
		return OK
	if not output_curves.has(key):
		return ERR_UNAVAILABLE
	var error: Error = output_curves[key].queue(target, time, tau)
	if error == OK and key == "wet":
		error = output_curves.dry.queue(1.0 - target, time, tau)
	return error

func render_input(count: int) -> PackedFloat32Array:
	if input_node < 0:
		return PackedFloat32Array()
	var values: PackedFloat32Array = frequencies[input_node].render(count)
	return oscillators[input_node].render(values, frequencies[input_node].rate_modes)

func render_output(count: int) -> Dictionary:
	var output := {"filters": {}, "modulation": PackedFloat32Array()}
	for key: String in output_curves:
		output[key] = output_curves[key].render(count)
	for node: int in frequencies:
		if node == input_node:
			continue
		var values: PackedFloat32Array = frequencies[node].render(count)
		if node == modulation_node:
			output.modulation = oscillators[node].render(values, frequencies[node].rate_modes)
		else:
			output.filters[node] = values
	return output

func snapshot() -> Dictionary:
	return {"input_frame": frequencies[input_node].frame if input_node >= 0 else 0,
		"output_frame": output_curves.gain.frame,
		"lfo_phase": oscillators[modulation_node].phase / oscillators[modulation_node].table_size if modulation_node >= 0 else 0.0}
