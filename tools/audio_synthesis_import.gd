extends RefCounted

static func build(sound: Dictionary, origin: Dictionary) -> NativeAudioSynthesis:
	if not sound.get("id") is String or not sound.id.is_valid_identifier() or origin.get("id") != sound.id:
		return null
	if not NativeAudioCatalogue._valid_hash(origin.get("audioSha256")) or not NativeAudioCatalogue._valid_hash(origin.get("noiseSha256")):
		return null
	for key: String in ["sampleRate", "frames", "reservationSeconds", "maximumGain"]:
		if not (sound.get(key) is int or sound.get(key) is float) or not is_finite(float(sound[key])):
			return null
	var rate := float(sound.sampleRate)
	var count := float(sound.frames)
	if rate < 8000 or rate > 384000 or rate != floor(rate) or count <= 0 or count > rate * 2 or count != floor(count):
		return null
	if not sound.get("stems") is Array or sound.stems.is_empty():
		return null
	var result := NativeAudioSynthesis.new()
	result.sample_rate = int(rate)
	result.frames = int(count)
	result.reservation_seconds = float(sound.reservationSeconds)
	result.maximum_gain = float(sound.maximumGain)
	result.source = origin.duplicate(true)
	for captured: Variant in sound.stems:
		if not captured is Dictionary or not captured.get("values") is String or not captured.get("envelope") is Array or not captured.get("effects") is Array or not captured.get("route") is String:
			return null
		var bytes := Marshalls.base64_to_raw(captured.values)
		if bytes.size() != result.frames * 4 or Marshalls.raw_to_base64(bytes) != captured.values:
			return null
		var stem := NativeAudioStem.new()
		stem.values = bytes.to_float32_array()
		for value: float in stem.values:
			if not is_finite(value):
				return null
		stem.route = captured.route
		for event: Variant in captured.envelope:
			if not event is Dictionary:
				return null
			for key: String in ["time", "constant", "scale", "floor"]:
				if event.has(key) and not (event[key] is int or event[key] is float):
					return null
		for effect: Variant in captured.effects:
			if not effect is Dictionary:
				return null
		stem.envelope.assign(captured.envelope)
		stem.effects.assign(captured.effects)
		result.stems.append(stem)
	return result if result.valid() else null
