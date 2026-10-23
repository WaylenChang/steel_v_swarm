class_name AudioVoiceBudget
extends RefCounted

var rules: Dictionary = {}
var last: Dictionary = {}
var last_take: Dictionary = {}
var active := 0
var releases: Array[float] = []

func configure(metadata: Dictionary) -> void:
	rules = metadata
	last.clear()
	last_take.clear()
	active = 0
	releases.clear()

func allow(id: String, now: float, timer_now: float = NAN) -> bool:
	advance(now if is_nan(timer_now) else timer_now)
	if now - float(last.get(id, 0)) < float(rules.dedupSeconds):
		return false
	# Source updates deduplication even when the voice limit rejects this sound.
	last[id] = now
	return active < int(rules.maxVoices)

func reserve(duration: float, now: float) -> void:
	active += 1
	releases.append(now + duration + float(rules.releaseGrace))

func advance(now: float) -> void:
	var remaining: Array[float] = []
	for deadline: float in releases:
		if deadline <= now:
			active = maxi(0, active - 1)
		else:
			remaining.append(deadline)
	releases = remaining

func sample_choice(id: String, durations: Array, random: Callable) -> Dictionary:
	if durations.is_empty():
		push_error("Audio sample selection requires loaded takes")
		return {}
	var index := 0
	if durations.size() > 1:
		index = floori(float(random.call()) * durations.size()) % durations.size()
		if index == int(last_take.get(id, -1)):
			index = (index + 1) % durations.size()
		last_take[id] = index
	var rate := 1.0 + (float(random.call()) * 2.0 - 1.0) * float(rules.rateJitter)
	return {"index": index, "rate": rate, "duration": minf(float(durations[index]) / rate, float(rules.sampleCountCap))}
