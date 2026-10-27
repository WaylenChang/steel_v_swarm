extends RefCounted

# Source a-rate synthesis consumes precomputed Float32 frequency values.
const TWO_POINT := 0.30000001192092896
const THREE_POINT := 0.1599999964237213
const LOG_TWO := 0.6931471805599453

var sample_rate := 0
var table_size := 0
var tables: Array[PackedFloat32Array] = []
var phase := 0.0
var frame := 0

func configure(captured: Dictionary, shape: String) -> Error:
	var rate: Variant = captured.get("sampleRate")
	if not (rate is int or rate is float) or not is_finite(float(rate)) or float(rate) != floor(float(rate)) or rate < 8000 or rate > 384000:
		return ERR_INVALID_DATA
	var size := 2048 if rate <= 24000 else (4096 if rate <= 88200 else 16384)
	var ranges := int(.5 + 3 * log(float(size)) / LOG_TWO)
	if captured.get("frames") != size or captured.get("ranges") != ranges or not captured.get("types") is Array:
		return ERR_INVALID_DATA
	var selected: Dictionary = {}
	for entry: Variant in captured.types:
		if not entry is Dictionary or not entry.get("type") is String:
			return ERR_INVALID_DATA
		if entry.type == shape:
			if not selected.is_empty():
				return ERR_INVALID_DATA
			selected = entry
	if selected.is_empty() or not shape in ["sine", "square", "sawtooth"]:
		return ERR_UNAVAILABLE
	if not selected.get("tables") is Array or selected.tables.size() != ranges:
		return ERR_INVALID_DATA
	var decoded: Array[PackedFloat32Array] = []
	for entry: Variant in selected.tables:
		if not entry is Dictionary or not entry.get("values") is String:
			return ERR_INVALID_DATA
		var payload: String = entry.values
		if payload.length() != ceili(size * 4 / 3.0) * 4:
			return ERR_INVALID_DATA
		var unpadded := payload.rstrip("=")
		if payload.length() - unpadded.length() > 2 or not unpadded.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/").is_empty():
			return ERR_INVALID_DATA
		var bytes := Marshalls.base64_to_raw(entry.values)
		if bytes.size() != size * 4 or Marshalls.raw_to_base64(bytes) != entry.values:
			return ERR_INVALID_DATA
		var values := bytes.to_float32_array()
		for value: float in values:
			if not is_finite(value):
				return ERR_INVALID_DATA
		decoded.append(values)
	sample_rate = int(rate)
	table_size = size
	tables = decoded
	phase = 0
	frame = 0
	return OK

func render(frequencies: PackedFloat32Array) -> PackedFloat32Array:
	# Chromium selects its interpolation path for four source samples together.
	# Reject incomplete groups rather than making their path depend on caller buffers.
	if tables.is_empty() or frequencies.size() % 4 != 0:
		return PackedFloat32Array()
	for frequency: float in frequencies:
		if not is_finite(frequency) or frequency <= 0 or frequency >= sample_rate * .5:
			return PackedFloat32Array()
	var output := PackedFloat32Array()
	output.resize(frequencies.size())
	var rate_scale := Vector2(float(table_size) / sample_rate, 0).x
	var inverse_scale := Vector2(1.0 / rate_scale, 0).x
	var lowest := float(sample_rate) / table_size
	var position := phase
	var mask := table_size - 1
	for group in range(0, frequencies.size(), 4):
		var increments := Vector4(frequencies[group] * rate_scale, frequencies[group + 1] * rate_scale, frequencies[group + 2] * rate_scale, frequencies[group + 3] * rate_scale)
		var linear := increments.x >= TWO_POINT and increments.y >= TWO_POINT and increments.z >= TWO_POINT and increments.w >= TWO_POINT
		for offset in range(4):
			var increment: float = increments[offset]
			var fundamental := Vector2(inverse_scale * increment, 0).x
			var ratio := Vector2(fundamental / lowest, 0).x
			var cents := Vector2(Vector2(log(ratio) / LOG_TWO, 0).x * 1200, 0).x
			var pitch := clampf(Vector2(1.0 + Vector2(cents / 400.0, 0).x, 0).x, 0, tables.size() - 1)
			var higher := int(pitch)
			var lower := mini(higher + 1, tables.size() - 1)
			var blend := Vector2(pitch - higher, 0).x
			var index := int(position)
			var high := tables[higher]
			var low := tables[lower]
			var high_value := 0.0
			var low_value := 0.0
			if linear:
				var fraction := Vector2(position, 0).x - index
				var differences := Vector2(high[(index + 1) & mask] - high[index], low[(index + 1) & mask] - low[index])
				var products := Vector2(fraction * differences.x, fraction * differences.y)
				var interpolated := Vector2(high[index] + products.x, low[index] + products.y)
				var delta := Vector2(interpolated.y - interpolated.x, 0).x
				output[group + offset] = interpolated.x + Vector2(blend * delta, 0).x
			else:
				var t := position - index
				var t2 := t * t
				var weights := PackedFloat64Array()
				if increment >= TWO_POINT:
					var fraction := Vector2(position, 0).x - index
					high_value = (1.0 - fraction) * high[index] + fraction * high[(index + 1) & mask]
					low_value = (1.0 - fraction) * low[index] + fraction * low[(index + 1) & mask]
				elif increment >= THREE_POINT:
					weights = PackedFloat64Array([.5 * t * (t - 1), 1 - t2, .5 * t * (t + 1)])
				else:
					weights = PackedFloat64Array([t * (t2 - 1) * (t - 2) / 24, -t * (t - 1) * (t2 - 4) / 6, (t2 - 1) * (t2 - 4) / 4, -t * (t + 1) * (t2 - 4) / 6, t * (t2 - 1) * (t + 2) / 24])
				for point in range(weights.size()):
					var sample_index := (index + point - (weights.size() >> 1)) & mask
					high_value += weights[point] * high[sample_index]
					low_value += weights[point] * low[sample_index]
				output[group + offset] = Vector2(1.0 - blend, 0).x * high_value + blend * low_value
			position = fposmod(position + increment, table_size)
	phase = position
	frame += frequencies.size()
	return output
