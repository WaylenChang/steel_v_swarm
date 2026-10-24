extends Node

const Identity = preload("res://scripts/audio_clip_identity.gd")
const Publisher = preload("res://tools/source_resource_publisher.gd")

class Library extends AudioSampleLibrary:
	var snapshot: NativeAudioCatalogue
	var files: Dictionary = {}
	var reads := 0
	func _load_catalogue() -> NativeAudioCatalogue:
		reads += 1
		return snapshot
	func _load_clip(path: String) -> NativeAudioClip:
		reads += 1
		return ResourceLoader.load(files[path], "", ResourceLoader.CACHE_MODE_IGNORE) as NativeAudioClip

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _ready() -> void:
	_run.call_deferred()

func _clip() -> NativeAudioClip:
	var clip := NativeAudioClip.new()
	clip.source = {"layer": "sample", "id": "probe", "url": "probe://controlled", "take": 2,
		"sha256": "0".repeat(64), "sampleRate": 48000, "frames": 2}
	var wave := AudioStreamWAV.new()
	wave.mix_rate = 48000
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.data = PackedByteArray([1, 0, 2, 0])
	clip.panned.append(wave)
	clip.panned_gains.append(1.25)
	return clip

func _catalogue(hash: String) -> NativeAudioCatalogue:
	var catalogue := NativeAudioCatalogue.new()
	catalogue.source = {"audioSha256": "1".repeat(64)}
	catalogue.sample_paths["probe"] = ["res://assets/audio/native/probe_%s.res" % hash]
	catalogue.sample_hashes["probe"] = [hash]
	return catalogue

func _run() -> void:
	var first := _clip()
	var hash := Identity.digest(first)
	_check(Identity.matches(first, "probe", hash), "A complete source clip matches its semantic fingerprint")
	for field: String in ["pcm", "gain", "rate", "loop", "take", "asset", "id", "frames"]:
		var changed := _clip()
		match field:
			"pcm": changed.panned[0].data = PackedByteArray([1, 0, 3, 0])
			"gain": changed.panned_gains[0] = 1.250000000000001
			"rate": changed.panned[0].mix_rate = 44100
			"loop": changed.panned[0].loop_mode = AudioStreamWAV.LOOP_FORWARD
			"take": changed.source.take = 3
			"asset": changed.source.sha256 = "2".repeat(64)
			"id": changed.source.id = "other"
			"frames": changed.source.frames = 3
		_check(not Identity.matches(changed, "probe", hash), "Fingerprint rejects changed " + field + " without accepting a mixed sample generation")
	var catalogue := _catalogue(hash)
	_check(catalogue.valid(), "Content-addressed paths and fingerprints form a valid catalogue")
	for field: String in ["missing", "size", "case", "hex", "path", "source"]:
		var changed := _catalogue(hash)
		match field:
			"missing": changed.sample_hashes.clear()
			"size": changed.sample_hashes.probe = []
			"case": changed.sample_hashes.probe = [hash.to_upper()]
			"hex": changed.sample_hashes.probe = ["g".repeat(64)]
			"path": changed.sample_paths.probe = ["res://assets/audio/native/probe_000.res"]
			"source": changed.source.clear()
		_check(not changed.valid(), "Catalogue rejects incomplete or mismatched " + field)
	var prefix := "user://audio-catalogue-%d" % Time.get_ticks_usec()
	var old_path := prefix + "-old.res"
	var new_path := prefix + "-new.res"
	var manifest := prefix + "-catalogue.res"
	_check(await Publisher.publish(first, old_path, get_tree()) == OK, "Publish a controlled native clip without changing original audio assets")
	var reloaded := ResourceLoader.load(old_path, "", ResourceLoader.CACHE_MODE_IGNORE) as NativeAudioClip
	_check(Identity.digest(reloaded) == hash, "PCM, metadata and full-precision gains retain identity after native disk reload")
	_check(await Publisher.publish(catalogue, manifest, get_tree()) == OK, "Publish the first complete catalogue")
	var old_bytes := FileAccess.get_sha256(manifest)
	var old_clip_bytes := FileAccess.get_sha256(old_path)
	var original := Library.new()
	original.snapshot = ResourceLoader.load(manifest, "", ResourceLoader.CACHE_MODE_IGNORE)
	original.files[catalogue.sample_paths.probe[0]] = old_path
	_check(original.load_samples(true) == OK and original.reads == 0, "Low-power registration does not load or hash native clips")
	_check(original.load_samples(false) == OK and original.buffers.probe[0].source.take == 2, "The first catalogue registers its original take")
	var second := _clip()
	second.source.take = 5
	second.panned[0].data = PackedByteArray([3, 0, 4, 0])
	var replacement := _catalogue(Identity.digest(second))
	_check(await Publisher.publish(second, new_path, get_tree()) == OK, "Stage the next sample generation independently of its catalogue")
	_check(FileAccess.get_sha256(manifest) == old_bytes and FileAccess.get_sha256(old_path) == old_clip_bytes,
		"An interrupted pre-catalogue publication leaves the old catalogue and its referenced sample unchanged")
	_check(original.buffers.probe[0].source.take == 2, "A retained library never acquires a staged replacement take")
	_check(await Publisher.publish(replacement, manifest, get_tree()) == OK, "Atomically publish the next complete catalogue")
	var next := Library.new()
	next.snapshot = ResourceLoader.load(manifest, "", ResourceLoader.CACHE_MODE_IGNORE)
	next.files[replacement.sample_paths.probe[0]] = new_path
	_check(next.load_samples(false) == OK and next.buffers.probe[0].source.take == 5 and original.buffers.probe[0].source.take == 2,
		"New readers acquire the complete replacement while existing readers retain their original generation")
	for path: String in [old_path, new_path, manifest]:
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only this controlled catalogue probe's native file")
	print("AUDIO_CATALOGUE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
