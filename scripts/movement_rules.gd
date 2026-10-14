class_name MovementRules
extends RefCounted

static func jump_cost(charge: float, morph: bool) -> float:
	var fraction: float = Content.constants.FLIGHT.MORPH_COST_F if morph else Content.constants.FLIGHT.CJUMP_F
	return ceilf(Content.constants.FLIGHT.LIFT_MAX * fraction * clampf(charge, 0, 1))

static func lift_altitude_factor(altitude: float, reference: float) -> float:
	if not is_finite(reference) or not is_finite(altitude):
		return 1.0
	var towers: float = (altitude - reference) / Content.constants.TARGET_H.tower
	return pow(2, minf(towers, Content.constants.FLIGHT.ALT_TOP_F)) if towers > 0 else 1.0

static func step_lift(lift: float, vertical: float, altitude: float, reference: float, up_speed: float,
		down_speed: float, delta: float, unbalanced: bool, fluid: float = 1.0, weather: float = 1.0) -> Dictionary:
	var flight: Dictionary = Content.constants.FLIGHT
	if lift < 0 or lift > flight.LIFT_MAX:
		lift = flight.LIFT_MAX
	var factor := lift_altitude_factor(altitude, reference)
	var drain: float = flight.LIFT_MAX / flight.DRAIN_S
	if vertical > 0:
		if lift <= 0:
			vertical = 0.0
		else:
			lift = maxf(0, lift - drain * factor * minf(1, vertical / maxf(0.000001, up_speed)) * delta)
	elif not unbalanced:
		var descent := minf(1, -vertical / maxf(0.000001, down_speed)) if vertical < 0 else 0.0
		lift = minf(flight.LIFT_MAX, lift + (flight.REGEN_PS + drain * flight.DESCENT_RECHARGE_F * factor * descent) * fluid * weather * delta)
	return {"lift": lift, "vertical": vertical}

static func sink_distance(damage: float, wind: float = 0.0) -> float:
	var factor := 1 + 0.25 * minf(1, (wind - 75) / 25) if wind > 75 else 1.0
	return maxf(0, damage) / Content.constants.SQUAD.DRONE_AVG_HP * Content.constants.FLIGHT.SINK_TOWERS * Content.constants.TARGET_H.tower * factor
