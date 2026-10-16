class_name DeathOverlayState
extends RefCounted

var active := false
var started := 0.0
var flash_live := false
var flash_at := 0.0

func receive(on: bool, flash: bool, now: float) -> void:
	if on and not active:
		started = now
	active = on
	if flash:
		flash_live = true
		flash_at = now

func pulse(now: float) -> float:
	if not active or now < started:
		return 0.0
	var rules: Dictionary = Content.balance.deathOverlay
	var progress := fposmod((now - started) / float(rules.pulseDuration), 1.0)
	var weight := HurtFlashState.ease_in_out(progress * 2 if progress < .5 else (progress - .5) * 2)
	return lerpf(float(rules.low), float(rules.high), weight) if progress < .5 else lerpf(float(rules.high), float(rules.low), weight)

func white(now: float) -> float:
	if not flash_live:
		return 0.0
	var rules: Dictionary = Content.balance.deathOverlay
	var progress := (now - flash_at) / float(rules.flashDuration)
	if progress < 0 or progress >= 1:
		return 0.0
	var peak := float(rules.flashPeak)
	var weight := HurtFlashState._ease_out(progress / peak) if progress < peak else 1 - HurtFlashState._ease_out((progress - peak) / (1 - peak))
	return float(rules.flashAlpha) * weight

func clear() -> void:
	active = false
	flash_live = false
