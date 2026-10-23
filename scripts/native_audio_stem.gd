class_name NativeAudioStem
extends Resource

@export var values := PackedFloat32Array()
@export var route := "panned"
@export var envelope: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []

func valid(frames: int) -> bool:
	if values.size() != frames or route not in ["panned", "centered"] or envelope.is_empty():
		return false
	var previous := -1.0
	for event: Dictionary in envelope:
		if event.get("operation") not in ["setValueAtTime", "exponentialRampToValueAtTime", "linearRampToValueAtTime"]:
			return false
		var time := float(event.get("time", -1))
		if not is_finite(time) or time < 0 or time < previous:
			return false
		previous = time
		for key: String in ["constant", "scale", "floor"]:
			if event.has(key) and (not is_finite(float(event[key])) or float(event[key]) < 0):
				return false
		if not event.has("constant") and (not event.has("scale") or not event.has("floor")):
			return false
	return true

func render(gain: float, rate: int) -> Dictionary:
	if not valid(values.size()) or rate <= 0 or not is_finite(gain) or gain < 0:
		return {}
	var output := PackedFloat32Array()
	output.resize(values.size())
	var begin := 0
	var previous_time := 0.0
	var previous_gain := 1.0
	for event: Dictionary in envelope:
		var time: float = event.time
		var next_gain := float(event.constant) if event.has("constant") else maxf(float(event.floor), gain * float(event.scale))
		var end := mini(values.size(), ceili(time * rate))
		var level := previous_gain
		var multiplier := 1.0
		var increment := 0.0
		if event.operation == "exponentialRampToValueAtTime":
			if previous_gain <= 0 or next_gain <= 0 or time <= previous_time:
				return {}
			var logarithm := log(next_gain / previous_gain) / (time - previous_time)
			level *= exp(logarithm * (float(begin) / rate - previous_time))
			multiplier = exp(logarithm / rate)
		elif event.operation == "linearRampToValueAtTime":
			if time <= previous_time:
				return {}
			var slope := (next_gain - previous_gain) / (time - previous_time)
			level += slope * (float(begin) / rate - previous_time)
			increment = slope / rate
		for frame in range(begin, end):
			output[frame] = values[frame] * level
			level = level * multiplier + increment
		begin = end
		previous_time = time
		previous_gain = next_gain
	for frame in range(begin, values.size()):
		output[frame] = values[frame] * previous_gain
	var peak := 0.0
	for value: float in output:
		if not is_finite(value):
			return {}
		peak = maxf(peak, absf(value))
	var normalization := peak * 32768.0 / 32767.0 if peak > 0 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(output.size() * 2)
	for frame in range(output.size()):
		bytes.encode_s16(frame * 2, clampi(floori(output[frame] / normalization * 32768.0 + .5), -32767, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return {"stream": stream, "gain": normalization, "route": route, "effects": effects}
