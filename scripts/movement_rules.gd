class_name MovementRules
extends RefCounted

static func camera_roll(current: float, lateral: float, speed: float, flying: bool, delta: float) -> float:
	var rules: Dictionary = Content.balance.movement.climb
	var target := -lateral / speed * float(rules.bankAmount) if flying and speed > 0 else 0.0
	var response: float = rules.bankResponse if flying else rules.groundRollResponse
	return current + (target - current) * (1 - exp(-response * maxf(0, delta)))

static func slope_degrees(rise: float, run: float) -> float:
	return rad_to_deg(atan2(rise, run))

static func slope_factor(degrees: float) -> float:
	var rules: Dictionary = Content.constants.SLOPE
	var over := absf(degrees) - float(rules.EASE_DEG)
	if over <= 0:
		return 1.0
	var fraction := minf(1, over / (float(rules.BLOCK_DEG) - float(rules.EASE_DEG)))
	return 1 + ((float(rules.UP_MIN_F) if degrees > 0 else float(rules.DOWN_MAX_F)) - 1) * fraction

static func slope_blocked(degrees: float) -> bool:
	return degrees > float(Content.constants.SLOPE.BLOCK_DEG)

static func slope_snap_distance(run: float) -> float:
	return tan(deg_to_rad(float(Content.constants.SLOPE.SNAP_DEG))) * maxf(0, run)

static func slope_along(x: float, z: float, y: float, dx: float, dz: float, flying: bool,
		airborne: bool, vertical: float, queries: Dictionary) -> float:
	var rules: Dictionary = Content.balance.movement.slope
	var margin: float = queries.get("deck_margin", rules.deckMargin)
	if margin == 0:
		margin = float(rules.deckMargin)
	var run := sqrt(dx * dx + dz * dz)
	if run < float(rules.epsilon) or flying or airborne or vertical > 0:
		return 0.0
	for point: Array in [[x, z], [x + dx, z + dz]]:
		var tunnel: Dictionary = queries.tunnel.call(point[0], point[1])
		if not tunnel.is_empty() and y < float(tunnel.ceil):
			return 0.0
		var deck: Variant = queries.deck.call(point[0], point[1], margin)
		if deck != null:
			var deck_surface: float = queries.surface.call(point[0], point[1], y)
			if not is_finite(deck_surface):
				return NAN
			if absf(deck_surface - float(deck)) < float(rules.deckTolerance):
				return 0.0
		var surface: float = queries.surface.call(point[0], point[1], y)
		var ground: float = queries.height.call(point[0], point[1])
		if not is_finite(surface) or not is_finite(ground):
			return NAN
		if absf(surface - ground) > float(Content.constants.SLOPE.STRUCT_M):
			return 0.0
	var end_height: float = queries.height.call(x + dx, z + dz)
	var start_height: float = queries.height.call(x, z)
	return slope_degrees(end_height - start_height, run) if is_finite(end_height) and is_finite(start_height) else NAN

static func slope_speed(x: float, z: float, y: float, dx: float, dz: float, flying: bool,
		airborne: bool, vertical: float, queries: Dictionary) -> float:
	var magnitude := sqrt(dx * dx + dz * dz)
	if magnitude < float(Content.balance.movement.slope.speedEpsilon):
		return 1.0
	var scale: float = float(Content.constants.SLOPE.PROBE_M) / magnitude
	var degrees := slope_along(x, z, y, dx * scale, dz * scale, flying, airborne, vertical, queries)
	return slope_factor(degrees) if is_finite(degrees) else NAN

static func slope_step(dx: float, dz: float, degrees: Callable) -> Dictionary:
	var angle: float = degrees.call(dx, dz)
	if not is_finite(angle):
		return {"valid": false}
	if not slope_blocked(angle):
		return {"valid": true, "x": dx, "z": dz, "blocked": false}
	# Original axis order is observable: X is attempted before Z.
	for offset: Array in [[dx, 0.0], [0.0, dz]]:
		var candidate: float = degrees.call(offset[0], offset[1])
		if not is_finite(candidate):
			return {"valid": false}
		if not slope_blocked(candidate):
			return {"valid": true, "x": float(offset[0]), "z": float(offset[1]), "blocked": true}
	return {"valid": true, "x": 0.0, "z": 0.0, "blocked": true}

static func slope_ground(foot: float, previous_surface: float, surface: float, run: float, vertical: float, low_gravity: bool) -> Dictionary:
	var tolerance: float = Content.balance.movement.slope.groundTolerance
	var drop := maxf(0, previous_surface - surface)
	var grounded := foot <= surface + tolerance or vertical <= 0 and foot <= surface + drop + tolerance
	var snap := grounded and not low_gravity and vertical <= 0 and foot > surface and foot - surface <= slope_snap_distance(run)
	return {"grounded": grounded, "snap": snap}

static func slope_warn(now: float, last: float, blocked: bool, dx: float, dz: float) -> bool:
	return blocked and dx == 0 and dz == 0 and now - last > float(Content.balance.movement.slope.warningInterval)

static func jump_cost(charge: float, morph: bool) -> float:
	var fraction: float = Content.constants.FLIGHT.MORPH_COST_F if morph else Content.constants.FLIGHT.CJUMP_F
	return ceilf(Content.constants.FLIGHT.LIFT_MAX * fraction * clampf(charge, 0, 1))

static func charged_launch_speed(charge: float, morph: bool, modifier: float, jump_factor: float) -> float:
	# Keep the original scalar arithmetic before CharacterBody3D's Vector3 storage.
	if morph:
		return float(Content.constants.MORPH.JUMP_V) * charge * jump_factor
	return float(Content.constants.CJUMP.V) * charge * modifier * jump_factor

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

static func flight_unbalanced(state: Dictionary, now: float) -> bool:
	if not state.flying or state.dead:
		return false
	if state.drone and float(state.altitude) < WeatherRules.unbalance_threshold(float(state.wind)):
		return false
	return float(state.sink) > 0 or now < float(state.lock_until) or float(state.unbalance_left) > 0

static func sink_hit(state: Dictionary, damage: float, now: float) -> Dictionary:
	var result := {"sink": state.sink, "speed": state.sink_speed, "lock_until": state.lock_until}
	if not state.flying or not damage > 0:
		return result
	if state.drone and float(state.altitude) < WeatherRules.unbalance_threshold(float(state.wind)):
		return result
	result.sink = float(state.sink) + sink_distance(damage, float(state.wind))
	result.speed = float(result.sink) / float(Content.constants.FLIGHT.SINK_S)
	var factor := float(Content.constants.SHIELD_DEFENSE.FLIGHT_UNBAL_DIRECT_F) if state.defending and float(state.shield) > 0 else 1.0
	result.lock_until = maxf(float(state.lock_until), now + float(Content.constants.FLIGHT.HIT_LOCK_S) * factor)
	return result
