extends Node

const Suite = preload("res://tests/audio_music_envelope_suite.gd")

var failures := 0
var assertions := 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(description)

func _run() -> void:
	var result := Suite.run(self, Content.read_json("res://data/fixtures.json", ["audioMusicGain"]), Content.balance.audio)
	print("MUSIC_GAIN_%s assertions=%d failures=%d result=%s" % ["PASS" if failures == 0 else "FAIL", assertions, failures, JSON.stringify(result)])
	get_tree().quit(0 if failures == 0 else 1)
