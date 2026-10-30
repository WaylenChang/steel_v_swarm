extends TextureRect

var rules: Dictionary
var target_opacity := -1.0
var opacity := 1.0:
	set(value):
		opacity = value
		modulate.a = value
var tween: Tween
var transition: Dictionary = {}

func set_speaking(speaking: bool, initial: bool = false) -> void:
	var target := float(rules.active) if speaking else float(rules.inactive)
	if initial:
		if tween != null and tween.is_valid():
			tween.kill()
		tween = null
		transition.clear()
		target_opacity = target
		opacity = target
		return
	if target_opacity == target:
		return
	target_opacity = target
	tween = preload("res://scripts/css_transition.gd").start(self, "opacity", target,
		float(rules.duration), tween, transition, HurtFlashState._ease_out)
	if tween != null:
		tween.set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

func cancel() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null

func _exit_tree() -> void:
	cancel()
