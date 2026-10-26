extends RefCounted

const NoiseImport = preload("res://tools/audio_noise_import.gd")

static func build(data: Dictionary, origin: Dictionary, graphs: Dictionary) -> NativeAudioMoveBank:
	if data.get("formatVersion") != 1 or data.get("source") != origin or not NativeAudioCatalogue._valid_hash(origin.get("audioSha256")):
		return null
	if not data.get("noise") is Dictionary or not data.get("oscillators") is Array or graphs.is_empty():
		return null
	var noise_values := NoiseImport.decode(data.noise, data.get("noiseSha256"))
	if noise_values.is_empty():
		return null
	var bank := NativeAudioMoveBank.new()
	bank.source = origin.duplicate(true)
	bank.source.noiseSha256 = data.noiseSha256
	var stem := NativeAudioStem.new()
	stem.values = noise_values
	stem.envelope.assign([{"operation": "setValueAtTime", "time": 0.0, "constant": 1.0}])
	var rendered := stem.render(1, int(data.noise.sampleRate))
	if rendered.is_empty():
		return null
	bank.noise = rendered.stream
	bank.noise_gain = rendered.gain
	bank.noise.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bank.noise.loop_begin = 0
	bank.noise.loop_end = int(data.noise.frames)
	for captured: Variant in data.oscillators:
		if not captured is Dictionary or not captured.get("category") is String or not captured.get("values") is String:
			return null
		for key: String in ["node", "frames"]:
			if not (captured.get(key) is int or captured.get(key) is float) or not is_finite(float(captured[key])) or float(captured[key]) != floor(float(captured[key])):
				return null
		if captured.node < 0 or captured.frames < 2:
			return null
		var bytes := Marshalls.base64_to_raw(captured.values)
		if bytes.size() != int(captured.frames) * 4 or Marshalls.raw_to_base64(bytes) != captured.values:
			return null
		var values := bytes.to_float32_array()
		for value: float in values:
			if not is_finite(value):
				return null
		if not bank.oscillators.has(captured.category):
			bank.oscillators[captured.category] = {}
		var node := str(int(captured.node))
		if bank.oscillators[captured.category].has(node):
			return null
		bank.oscillators[captured.category][node] = values
	if bank.oscillators.size() != graphs.size():
		return null
	for category: String in graphs:
		var expected := []
		for node: Dictionary in graphs[category].nodes:
			if node.kind == "createOscillator":
				expected.append(str(int(node.id)))
		var actual: Array = bank.oscillators.get(category, {}).keys()
		expected.sort()
		actual.sort()
		if actual != expected:
			return null
	return bank if bank.valid() else null
