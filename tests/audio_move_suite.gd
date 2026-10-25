extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not metadata.has("moveGraphs") or not fixtures.has("audioMoveLifecycle"):
		h._check(false, "Regenerate original permanent movement graph/control references")
		return
	for program: Dictionary in fixtures.audioMoveLifecycle:
		var state := AudioMoveState.new()
		state.configure(metadata)
		state.low_power = program.low
		state.unlocked = program.unlocked
		var allocations := {"count": 0}
		state.registered.connect(func(_category: String) -> void: allocations.count += 1)
		for frame: Dictionary in program.frames:
			state.advance(float(frame.time) - state.clock)
			var action: Array = frame.action
			match action[0]:
				"set": state.set_move(program.category, action[1], action[2], action[3], action[4])
				"low": state.set_low_power(action[1])
				"stop": state.stop_move()
			Helper.compare(h, _snapshot(state), frame.result, "Original permanent movement creation gate, source base gains, pan/rate/wet clamps and low-power/stop time constants")
			h._check(allocations.count == state.voices.size(), "Movement gain zero and low power retain existing voices without reallocation")
	var graph: Dictionary = metadata.moveGraphs.stomp
	var oscillators := 0
	var noise_sources := 0
	for node: Dictionary in graph.nodes:
		if node.kind == "createOscillator":
			oscillators += 1
		elif node.get("buffer") == "sharedNoise":
			noise_sources += 1
	h._check(oscillators == 1 and noise_sources == 2, "Original dry and wet stomp chains retain one shared LFO and two reads of the same private noise buffer")
	h._near(float(graph.nodes[int(graph.dry)].parameters.gain.initial) + float(graph.nodes[int(graph.wet)].parameters.gain.initial), 1, "Original initial dry/wet weights are complementary")
	var plan := AudioMovePlan.compile(graph)
	h._check(not plan.is_empty() and plan.branches.size() == 2 and plan.lfos.size() == 1, "Native stomp playback plan retains both filtered noise branches and exactly one modulation phase")
	if not plan.is_empty() and plan.branches.size() == 2:
		h._check(plan.branches[0].modulation.node == plan.branches[1].modulation.node, "Both native stomp branches reference the same original oscillator")
		var weights: Array = plan.branches.map(func(branch: Dictionary) -> String: return branch.weight)
		h._check(weights.has("dry") and weights.has("wet"), "Native stomp planning retains complementary crossfade routes")
	for category: String in metadata.scene.categories:
		h._check(not AudioMovePlan.compile(metadata.moveGraphs[category]).is_empty(), "All original movement graphs have an explicit native playback plan")
	_bank(h)

static func _bank(h: Node) -> void:
	var bank := preload("res://scripts/audio_resource_snapshot.gd").new().movement()
	var data: Dictionary = Content.read_json("res://data/audio_move.json")
	h._check(bank != null and bank.valid(), "Native movement bank contains one shared looping noise source and captured oscillator periods")
	if bank == null or not bank.valid():
		return
	h._check(bank.source.audioSha256 == data.source.audioSha256 and bank.source.noiseSha256 == data.noiseSha256, "Movement waveforms retain the original module and same private noise realization as other audio")
	for oscillator: Dictionary in data.oscillators:
		var values := Marshalls.base64_to_raw(oscillator.values).to_float32_array()
		h._check(bank.waveform(oscillator.category, int(oscillator.node)) == values, "Native movement periods retain actual source oscillator samples")
		h._check(absf(float(oscillator.frames) * float(oscillator.frequency) / float(oscillator.sampleRate) - 1.0) < .000001, "Captured movement oscillator data represents one complete source cycle")
	var expected := Marshalls.base64_to_raw(data.noise.values).to_float32_array()
	var bytes: PackedByteArray = bank.noise.data
	var maximum_error := 0.0
	for index in range(expected.size()):
		maximum_error = maxf(maximum_error, absf(float(bytes.decode_s16(index * 2)) / 32768.0 * bank.noise_gain - expected[index]))
	h._check(maximum_error <= bank.noise_gain / 65536.0 + .0000001, "Shared native movement noise remains within one measured PCM conversion step")

static func _snapshot(state: AudioMoveState) -> Dictionary:
	var result := {}
	for category: String in state.voices:
		var voice: Dictionary = state.voices[category]
		var graph: Dictionary = state.metadata.moveGraphs[category]
		var rates: Array = []
		for binding: Dictionary in graph.rate:
			var automation: Dictionary = voice.targets.rate.duplicate()
			automation.target *= float(binding.base)
			automation.base = binding.base
			rates.append(automation)
		var wet: Variant = voice.targets.get("wet")
		var dry: Variant = null
		if wet != null:
			dry = wet.duplicate()
			dry.target = 1 - float(wet.target)
		result[category] = {"gain": voice.targets.gain, "pan": voice.targets.pan, "rate": rates, "wet": wet, "dry": dry}
	return result
