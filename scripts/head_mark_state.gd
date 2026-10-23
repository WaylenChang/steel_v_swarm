class_name HeadMarkState
extends RefCounted

var size := 0.0
var base_y := 0.0
var y := 0.0
var opacity := 0.0

func configure(height: float, top: Variant, rules: Dictionary) -> void:
	var h := maxf(float(rules.minimum), height)
	size = maxf(float(rules.sizeMin), h * float(rules.sizeFactor))
	base_y = (float(top) if top != null else h) + float(rules.margin) + size * float(rules.half)

func advance(delta: float, now: float, following: bool, rules: Dictionary) -> void:
	if not is_finite(delta) or delta < 0 or not is_finite(now):
		return
	var maximum: float = rules.followOpacity if following and rules.has("followOpacity") else rules.opacity
	opacity = minf(maximum, opacity + delta * float(rules.fade))
	y = base_y + sin(now * float(rules.frequency) + float(rules.phase)) * float(rules.amplitude)
