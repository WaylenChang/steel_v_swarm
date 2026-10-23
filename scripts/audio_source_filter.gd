class_name AudioSourceFilter
extends RefCounted

static func create(captured: Dictionary) -> AudioEffect:
	if captured.get("kind") != "createBiquadFilter" or captured.get("type") not in ["lowpass", "bandpass"]:
		return null
	var parameters: Dictionary = captured.get("parameters", {})
	for key: String in ["frequency", "Q", "detune", "gain"]:
		if not parameters.get(key) is Dictionary or not parameters[key].get("events") is Array or not parameters[key].events.is_empty():
			return null
	var cutoff := float(parameters.frequency.initial) * pow(2.0, float(parameters.detune.initial) / 1200.0)
	# Web Audio low-pass Q is in decibels; the native biquad takes linear Q.
	# Native band-pass doubles resonance; its numerator trim is applied by callers.
	var resonance := pow(10.0, float(parameters.Q.initial) / 20.0) if captured.type == "lowpass" else float(parameters.Q.initial) / 2.0
	if not is_finite(cutoff) or cutoff < 1 or not is_finite(resonance) or resonance <= 0:
		return null
	var effect: AudioEffectFilter = AudioEffectLowPassFilter.new() if captured.type == "lowpass" else AudioEffectBandPassFilter.new()
	effect.cutoff_hz = cutoff
	effect.resonance = resonance
	effect.gain = 1
	# This native enum selects one biquad stage, matching the source node.
	effect.db = AudioEffectFilter.FILTER_6DB
	return effect

static func gain_correction(captured: Dictionary) -> float:
	# The native band-pass numerator has an additional sqrt(Q + 1) factor.
	return 1.0 / sqrt(float(captured.parameters.Q.initial) + 1.0) if captured.type == "bandpass" else 1.0
