class_name AudioMoveControls
extends RefCounted

const INDEX := {"gain": 0, "pan": 1, "rate": 2, "wet": 3}

var values := PackedFloat64Array()
var targets := PackedFloat64Array()
var decay := PackedFloat64Array([1, 1, 1, 1])
var events: Array[Dictionary] = []
var cursor := 0
var frame := 0
var sample_rate := 0.0

func configure(initial: Dictionary, rate: float) -> void:
	sample_rate = rate
	values = PackedFloat64Array([initial.gain, initial.pan, initial.rate, initial.wet])
	targets = values.duplicate()

func queue(key: String, target: float, tau: float, at_frame: int) -> void:
	var event := {"index": int(INDEX[key]), "target": target, "decay": exp(-1.0 / (sample_rate * tau)), "frame": maxi(frame, at_frame)}
	# Repeated same-time targets replace one another, including during driver suspension.
	for index in range(events.size() - 1, cursor - 1, -1):
		if int(events[index].frame) < int(event.frame):
			break
		if events[index].frame == event.frame and events[index].index == event.index:
			events[index] = event
			return
	events.append(event)

func begin_frame() -> void:
	while cursor < events.size() and int(events[cursor].frame) <= frame:
		var event: Dictionary = events[cursor]
		targets[int(event.index)] = float(event.target)
		decay[int(event.index)] = float(event.decay)
		cursor += 1
	if cursor > 64 and cursor * 2 > events.size():
		events = events.slice(cursor)
		cursor = 0

func end_frame() -> void:
	for index in range(4):
		values[index] = targets[index] + (values[index] - targets[index]) * decay[index]
	frame += 1

func consume_frames(count: int) -> Array[PackedFloat64Array]:
	var output: Array[PackedFloat64Array] = []
	for channel in range(4):
		var samples := PackedFloat64Array()
		samples.resize(maxi(0, count))
		output.append(samples)
	if count <= 0:
		return output
	# Keep the scalar recurrence order while avoiding per-sample property calls.
	var gain_value := values[0]
	var pan_value := values[1]
	var rate_value := values[2]
	var wet_value := values[3]
	var gain_target := targets[0]
	var pan_target := targets[1]
	var rate_target := targets[2]
	var wet_target := targets[3]
	var gain_decay := decay[0]
	var pan_decay := decay[1]
	var rate_decay := decay[2]
	var wet_decay := decay[3]
	var next := cursor
	var gains := output[0]
	var pans := output[1]
	var rates := output[2]
	var wets := output[3]
	for index in range(count):
		while next < events.size() and int(events[next].frame) <= frame + index:
			var event: Dictionary = events[next]
			match int(event.index):
				0:
					gain_target = float(event.target)
					gain_decay = float(event.decay)
				1:
					pan_target = float(event.target)
					pan_decay = float(event.decay)
				2:
					rate_target = float(event.target)
					rate_decay = float(event.decay)
				3:
					wet_target = float(event.target)
					wet_decay = float(event.decay)
			next += 1
		gains[index] = gain_value
		pans[index] = pan_value
		rates[index] = rate_value
		wets[index] = wet_value
		gain_value = gain_target + (gain_value - gain_target) * gain_decay
		pan_value = pan_target + (pan_value - pan_target) * pan_decay
		rate_value = rate_target + (rate_value - rate_target) * rate_decay
		wet_value = wet_target + (wet_value - wet_target) * wet_decay
	values = PackedFloat64Array([gain_value, pan_value, rate_value, wet_value])
	targets = PackedFloat64Array([gain_target, pan_target, rate_target, wet_target])
	decay = PackedFloat64Array([gain_decay, pan_decay, rate_decay, wet_decay])
	frame += count
	cursor = next
	if cursor > 64 and cursor * 2 > events.size():
		events = events.slice(cursor)
		cursor = 0
	output[0] = gains
	output[1] = pans
	output[2] = rates
	output[3] = wets
	return output

func preview_rate(count: int) -> PackedFloat64Array:
	return _rate_frames(count, false)

func consume_rate(count: int) -> PackedFloat64Array:
	return _rate_frames(count, true)

func _rate_frames(count: int, advance: bool) -> PackedFloat64Array:
	if count <= 0:
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(count)
	var value := values[2]
	var target := targets[2]
	var multiplier := decay[2]
	var constant := value == target
	for index in range(cursor, events.size()):
		var event: Dictionary = events[index]
		if int(event.frame) >= frame + count:
			break
		if event.index == 2 and event.target != value:
			constant = false
	if constant:
		result.fill(value)
	var next := cursor
	if constant:
		while next < events.size() and int(events[next].frame) < frame + count:
			var event: Dictionary = events[next]
			if advance and event.index != 2:
				return PackedFloat64Array()
			if event.index == 2:
				target = float(event.target)
				multiplier = float(event.decay)
			next += 1
	else:
		for index in range(count):
			while next < events.size() and int(events[next].frame) <= frame + index:
				var event: Dictionary = events[next]
				if advance and event.index != 2:
					return PackedFloat64Array()
				if event.index == 2:
					target = float(event.target)
					multiplier = float(event.decay)
				next += 1
			result[index] = value
			value = target + (value - target) * multiplier
	if advance:
		values[2] = value
		targets[2] = target
		decay[2] = multiplier
		cursor = next
		frame += count
		if cursor > 64 and cursor * 2 > events.size():
			events = events.slice(cursor)
			cursor = 0
	return result
