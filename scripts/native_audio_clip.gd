class_name NativeAudioClip
extends Resource

@export var channel_count := 1
@export var panned: Array[AudioStreamWAV] = []
@export var panned_gains: Array[float] = []
@export var centered: AudioStreamWAV
@export var centered_gain := 1.0
@export var reservation_seconds := 0.0
@export var source: Dictionary = {}

func valid() -> bool:
	if channel_count not in [0, 1, 2] or panned.size() != channel_count:
		return false
	if panned.is_empty() and centered == null:
		return false
	if not panned_gains.is_empty() and panned_gains.size() != channel_count:
		return false
	for gain: float in panned_gains:
		if not is_finite(gain) or gain < 0:
			return false
	if not is_finite(centered_gain) or centered_gain < 0:
		return false
	if not is_finite(reservation_seconds) or reservation_seconds < 0:
		return false
	for stream: AudioStreamWAV in panned:
		if stream == null or stream.stereo or not is_finite(stream.get_length()) or stream.get_length() <= 0:
			return false
	return centered == null or not centered.stereo and is_finite(centered.get_length()) and centered.get_length() > 0

func duration() -> float:
	var result := centered.get_length() if centered != null else 0.0
	for stream: AudioStreamWAV in panned:
		result = maxf(result, stream.get_length())
	return result
