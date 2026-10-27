extends RefCounted

var sample_rate := 0.0
var base_frequency := 0.0
var quality := 0.0
var frequency := NAN
var b0 := 0.0
var a1 := 0.0
var a2 := 0.0
var x1 := 0.0
var x2 := 0.0
var y1 := 0.0
var y2 := 0.0
var dynamic := false

func configure(captured: Dictionary, rate: float) -> Error:
	if captured.get("type") != "bandpass" or AudioSourceFilter.create(captured) == null or not is_finite(rate) or rate < 8000:
		return ERR_UNAVAILABLE
	sample_rate = rate
	# AudioParam values enter the source DSP as float32.
	base_frequency = Vector2(float(captured.parameters.frequency.initial), 0).x * pow(2.0, Vector2(float(captured.parameters.detune.initial), 0).x / 1200.0)
	quality = Vector2(float(captured.parameters.Q.initial), 0).x
	if not is_finite(quality) or quality <= 0 or base_frequency <= 0 or base_frequency >= sample_rate * .5:
		return ERR_UNAVAILABLE
	return OK

func process_sample(value: float, scale: float) -> float:
	var result := process_buffer(PackedVector2Array([Vector2(value, value)]), PackedFloat64Array([scale]))
	return result[0].x if result.size() == 1 else NAN

func process_native_buffer(raw: PackedVector2Array, native: PackedVector2Array, scales: PackedFloat64Array, input_gain: float) -> PackedVector2Array:
	if raw.size() != native.size() or raw.size() != scales.size():
		return PackedVector2Array()
	if not dynamic and scales.count(1.0) == scales.size():
		if raw.size() > 1:
			x2 = float(raw[-2].x) * input_gain
			y2 = native[-2].x
		elif raw.size() == 1:
			x2 = x1
			y2 = y1
		if not raw.is_empty():
			x1 = float(raw[-1].x) * input_gain
			y1 = native[-1].x
		return native
	dynamic = true
	return process_buffer(raw, scales, input_gain)

func process_buffer(values: PackedVector2Array, scales: PackedFloat64Array, input_gain: float = 1.0) -> PackedVector2Array:
	if values.size() != scales.size():
		return PackedVector2Array()
	var output := PackedVector2Array()
	output.resize(values.size())
	var base := base_frequency
	var native_rate := sample_rate
	var q := quality
	var last_scale := NAN
	var last_frequency := frequency
	var numerator := b0
	var feedback1 := a1
	var feedback2 := a2
	var input1 := x1
	var input2 := x2
	var result1 := y1
	var result2 := y2
	for index in range(values.size()):
		if scales[index] != last_scale:
			last_scale = scales[index]
			var next_frequency := Vector2(base * last_scale, 0).x
			if not is_finite(next_frequency) or next_frequency <= 0 or next_frequency >= native_rate * .5:
				return PackedVector2Array()
			if next_frequency != last_frequency:
				last_frequency = next_frequency
				var omega := TAU * last_frequency / native_rate
				var alpha := sin(omega) / (2.0 * q)
				var denominator := 1.0 + alpha
				# Web Audio's constant-0-dB band-pass, in direct form I:
				# https://www.w3.org/TR/audio-eq-cookbook/
				numerator = alpha / denominator
				feedback1 = -2.0 * cos(omega) / denominator
				feedback2 = (1.0 - alpha) / denominator
		var value := float(values[index].x) * input_gain
		var result := numerator * (value - input2) - feedback1 * result1 - feedback2 * result2
		if not is_finite(result):
			return PackedVector2Array()
		input2 = input1
		input1 = value
		result2 = result1
		result1 = result
		output[index] = Vector2(result, result)
	frequency = last_frequency
	b0 = numerator
	a1 = feedback1
	a2 = feedback2
	x1 = input1
	x2 = input2
	y1 = result1
	y2 = result2
	return output
