extends Node

const Importer = preload("res://tools/audio_synthesis_import.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")
const PcmGain = preload("res://scripts/audio_pcm_gain.gd")
var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	var library := AudioSynthesisLibrary.new()
	library.configure(Content.balance.audio)
	var original: Dictionary = Content.read_json("res://data/audio_synth.json")
	for sound: Dictionary in original.sounds:
		var imported := Importer.build(sound, {"id": sound.id, "audioSha256": original.source.audioSha256, "noiseSha256": original.noiseSha256})
		_check(imported != null and Identity.digest(imported) == Identity.digest(library.definition(sound.id)), "Existing native synthesis identity survives the shared importer: " + str(sound.id))
	var profile: Dictionary = Content.read_json("res://data/audio_sfx_rates/48000.json")
	var ids: Array = []
	for sound: Dictionary in profile.sounds:
		ids.append(sound.id)
		var imported := Importer.build(sound, {"id": sound.id, "audioSha256": profile.source.audioSha256, "noiseSha256": profile.noise.sha256})
		_check(imported != null and imported.sample_rate == 48000, "Explicit source rate remains unchanged: " + str(sound.id))
	ids.sort()
	var expected: Array = Content.balance.audio.synthesisIds.duplicate()
	expected.sort()
	_check(ids == expected, "The rate profile contains every source synthesis exactly once")
	var sound: Dictionary = profile.sounds[0]
	var origin := {"id": sound.id, "audioSha256": profile.source.audioSha256, "noiseSha256": profile.noise.sha256}
	for key: String in ["sampleRate", "frames", "reservationSeconds", "maximumGain"]:
		var malformed := sound.duplicate(true)
		malformed[key] = "invalid"
		_check(Importer.build(malformed, origin) == null, "Reject nonnumeric " + key)
	for patch: Dictionary in [{"sampleRate": 7999}, {"sampleRate": 48000.5}, {"frames": 1.5}, {"frames": 0}, {"stems": []}]:
		var malformed := sound.duplicate(true)
		malformed.merge(patch, true)
		_check(Importer.build(malformed, origin) == null, "Reject malformed synthesis bounds")
	for key: String in ["time", "constant", "scale", "floor"]:
		var malformed := sound.duplicate(true)
		malformed.stems[0].envelope[0][key] = "invalid"
		_check(Importer.build(malformed, origin) == null, "Reject nonnumeric envelope " + key)
	var malformed := sound.duplicate(true)
	malformed.stems[0].values = ""
	_check(Importer.build(malformed, origin) == null, "Reject incomplete float storage")
	var wrong_origin := origin.duplicate()
	wrong_origin.id = "wrong"
	_check(Importer.build(sound, wrong_origin) == null, "Reject mismatched source identity")
	wrong_origin = origin.duplicate()
	wrong_origin.noiseSha256 = "invalid"
	_check(Importer.build(sound, wrong_origin) == null, "Reject malformed source fingerprint")
	_check(PcmGain.native_gain(AudioStreamWAV.new(), .35) == .35 * 32767.0 / 32768.0, "WAV gain restores the source PCM denominator")
	for stream: AudioStream in [AudioStreamGenerator.new(), AudioStreamOggVorbis.new(), AudioStreamMP3.new()]:
		_check(PcmGain.native_gain(stream, .35) == .35, "Non-WAV gain remains unchanged")
	print("AUDIO_SYNTHESIS_IMPORT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
