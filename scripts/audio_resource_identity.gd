extends RefCounted

const ClipIdentity = preload("res://scripts/audio_clip_identity.gd")

static func digest(resource: Resource) -> String:
	if resource is NativeAudioClip:
		return ClipIdentity.digest(resource)
	var header: Dictionary
	var blocks: Array[PackedByteArray] = []
	if resource is NativeAudioSynthesis:
		if not resource.valid():
			return ""
		var stems := []
		for stem: NativeAudioStem in resource.stems:
			for value: float in stem.values:
				if not is_finite(value):
					return ""
			stems.append({"frames": stem.values.size(), "route": stem.route,
				"envelope": stem.envelope, "effects": stem.effects})
			blocks.append(stem.values.to_byte_array())
		header = {"version": 1, "kind": "synthesis", "source": resource.source,
			"rate": resource.sample_rate, "frames": resource.frames, "stems": stems}
		blocks.push_front(PackedFloat64Array([resource.reservation_seconds, resource.maximum_gain]).to_byte_array())
	elif resource is NativeAudioMoveBank:
		if not resource.valid():
			return ""
		var noise := NativeAudioClip.new()
		noise.channel_count = 0
		noise.centered = resource.noise
		noise.centered_gain = resource.noise_gain
		noise.source = resource.source
		var noise_hash := ClipIdentity.digest(noise)
		if noise_hash.is_empty():
			return ""
		var oscillators := []
		var categories: Array = resource.oscillators.keys()
		if categories.any(func(value): return not value is String):
			return ""
		categories.sort()
		for category: String in categories:
			var nodes: Array = resource.oscillators[category].keys()
			if nodes.any(func(value): return not value is String):
				return ""
			nodes.sort()
			for node: String in nodes:
				var values: PackedFloat32Array = resource.oscillators[category][node]
				for value: float in values:
					if not is_finite(value):
						return ""
				oscillators.append({"category": category, "node": node, "frames": values.size()})
				blocks.append(values.to_byte_array())
		header = {"version": 1, "kind": "movement", "noise": noise_hash, "oscillators": oscillators}
	else:
		return ""
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(header, "", true, true).to_utf8_buffer())
	for bytes: PackedByteArray in blocks:
		hash.update(bytes)
	return hash.finish().hex_encode()
