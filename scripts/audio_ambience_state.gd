class_name AudioAmbienceState
extends RefCounted

signal registered(id: String, url: String)

var rules: AudioRules
var beds: Dictionary = {}
var unlocked := false
var disposed := false
var enabled := true
var low_power := false

func configure(metadata: Dictionary) -> void:
	rules = AudioRules.new()
	rules.configure(metadata)

func set_ambience(query: Dictionary) -> void:
	if disposed or not unlocked or not enabled:
		return
	var winner: Variant = rules.ambience_mix(query)
	_ride(rules.rules.ambienceBase, float(rules.rules.ambienceBase.vol))
	for definition: Dictionary in rules.rules.ambience:
		var volume := float(definition.vol) * float(winner.g) if winner != null and winner.id == definition.id else 0.0
		_ride(definition, volume)

func _ride(definition: Dictionary, volume: float) -> void:
	if disposed:
		return
	var id: String = definition.id
	var low: bool = low_power and id != rules.rules.ambienceBase.id
	var timing: Dictionary = rules.rules.ambienceTiming
	if not beds.has(id):
		if low or volume <= float(timing.creationThreshold):
			return
		beds[id] = {"gain": float(timing.initialGain), "target": 0.0}
		registered.emit(id, definition.url)
		if disposed:
			return
	beds[id].target = 0.0 if low else clampf(volume, 0, 1)

func advance(seconds: float) -> void:
	if disposed or not is_finite(seconds) or seconds <= 0:
		return
	var decay := exp(-seconds / float(rules.rules.ambienceTiming.timeConstant))
	for bed: Dictionary in beds.values():
		bed.gain = float(bed.target) + (float(bed.gain) - float(bed.target)) * decay

func dispose() -> void:
	disposed = true
	beds.clear()
