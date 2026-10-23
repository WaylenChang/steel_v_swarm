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
