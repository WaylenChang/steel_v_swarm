class_name AudioGeneratorFeed
extends AudioStream

var playback: AudioStreamGeneratorPlayback

const REFILL_FRAMES := 128

static func input_latency_frames(generator: bool) -> int:
	# Godot 4.7.2: 64-frame server lookahead, two interpolation history frames.
	# Generator.start() primes its first refill while the playback is inactive.
	return 64 + 2 + (REFILL_FRAMES if generator else 0)

static func startup_frames(interval: float, rate: float) -> int:
	# Godot 4.7.2's AudioStreamPlaybackResampled refills whole 128-frame blocks.
	return clampi(ceili(interval * rate / REFILL_FRAMES) * REFILL_FRAMES, REFILL_FRAMES, 4096) * 2

func configure(rate: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = rate
	generator.buffer_length = .25
	playback = generator.instantiate_playback() as AudioStreamGeneratorPlayback
	# Native generator playback holds a raw owner pointer; retain it through fade-out.
	playback.set_meta("_svs_generator", generator)

func _instantiate_playback() -> AudioStreamPlayback:
	# Each private feed belongs to one permanent player and is filled before play().
	return playback

func _get_length() -> float:
	return 0

func _is_monophonic() -> bool:
	return true
