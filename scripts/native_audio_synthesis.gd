class_name NativeAudioSynthesis
extends Resource

@export var sample_rate := 0
@export var frames := 0
@export var reservation_seconds := 0.0
@export var maximum_gain := 0.0
@export var stems: Array[NativeAudioStem] = []
@export var source: Dictionary = {}

func valid() -> bool:
	if sample_rate <= 0 or frames <= 0 or not is_finite(reservation_seconds) or reservation_seconds <= 0 or not is_finite(maximum_gain) or maximum_gain <= 0 or stems.is_empty():
		return false
	for stem: NativeAudioStem in stems:
		if stem == null or not stem.valid(frames):
			return false
	return true

func render(gain: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not valid() or not is_finite(gain) or gain < 0 or gain > maximum_gain + .00000001:
		return result
	for stem: NativeAudioStem in stems:
		var rendered := stem.render(gain, sample_rate)
		if rendered.is_empty():
			return []
		result.append(rendered)
	return result
