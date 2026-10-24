class_name CssTransition
extends RefCounted

static func start(owner: Node, property: String, target: float, seconds: float,
		previous: Tween, transition: Dictionary, curve: Callable) -> Tween:
	var current := float(owner.get(property))
	var shortening := 1.0
	var reversing_start := current
	if previous != null and previous.is_valid():
		if target == float(transition.reversing_start):
			var progress := (current - float(transition.start)) / (float(transition.target) - float(transition.start))
			# CSS reversals shorten from eased progress, including earlier reversals.
			shortening = reversal_factor(progress, float(transition.shortening))
			reversing_start = float(transition.target)
		previous.kill()
	transition.assign({"start": current, "target": target, "reversing_start": reversing_start, "shortening": shortening})
	if current == target or shortening == 0:
		owner.set(property, target)
		return null
	var tween := owner.create_tween()
	tween.tween_property(owner, property, target, seconds * shortening).set_custom_interpolator(curve)
	return tween

static func reversal_factor(progress: float, previous: float) -> float:
	return clampf(absf(progress * previous + 1 - previous), 0, 1)
