class_name PetalMotion
extends RefCounted

var rules: Dictionary

func advance(part: Dictionary, delta: float, now: float, dynamics: Variant = null) -> void:
	var step := minf(delta, float(rules.DT_MAX)) if delta > 0 else 0.0
	var strength: Variant = dynamics.get("windAmp") if dynamics is Dictionary else null
	var wind := clampf(float(strength), 0.4, 2.5) if BodyMotionState._finite(strength) else 1.0
	var direction := [1.0, 0.0]
	var heading: Variant = dynamics.get("windDir") if dynamics is Dictionary else null
	if heading is Array and heading.size() >= 2 and BodyMotionState._finite(heading[0]) and BodyMotionState._finite(heading[1]):
		direction = heading
	if not is_finite(now):
		return
	if float(part.get("groundTime", 0)) > 0:
		part.groundTime = maxf(0, float(part.groundTime) - step)
		part.fade = minf(1, float(part.groundTime) / 0.35)
		part.oy = 0.025
		if wind > 1.6 and not ControlPreferences.truthy(part.get("lifted")):
			part.y = minf(float(part.h), 0.4 + wind * 0.35)
			part.groundTime = 0
			part.lifted = true
			part.fade = 1
		elif float(part.groundTime) == 0:
			part.y = part.h
			part.lifted = false
		else:
			return
	part.y = float(part.y) - float(part.vy) * step * (0.85 + wind * 0.15)
	if float(part.y) < 0:
		part.y = 0
		part.groundTime = 1.2 + 0.8 * (1 + sin(float(part.p1)))
		part.oy = 0.025
		part.fade = 1
		return
	part.fade = minf(1, (float(part.h) - float(part.y)) / 0.35)
	part.a = float(part.a) + float(part.w) * step * wind
	part.ang = float(part.ang) + float(part.sp) * step * wind
	part.slowPhase = (float(part.slowPhase) if ControlPreferences.truthy(part.get("slowPhase")) else 0.0) + step * float(rules.F_SLOW) * wind
	part.fastPhase = (float(part.fastPhase) if ControlPreferences.truthy(part.get("fastPhase")) else 0.0) + step * float(rules.F_FAST) * wind
	var slow := sin(float(part.slowPhase) + float(part.p1))
	var fast := sin(float(part.fastPhase) + float(part.p2))
	var radius := float(part.r) * (1 + float(rules.SWAY_SLOW) * slow + float(rules.SWAY_FAST) * fast)
	part.ox = cos(float(part.a)) * radius
	part.oz = sin(float(part.a)) * radius
	if dynamics != null and (wind > 1.05 or wind < 0.95):
		var drift := (wind - 1.0) * 1.8
		part.ox = float(part.ox) + float(direction[0]) * drift * (1 + slow * 0.25)
		part.oz = float(part.oz) + float(direction[1]) * drift * (1 + slow * 0.25)
	part.oy = float(part.y) + float(rules.BOB) * (1 + fast)

