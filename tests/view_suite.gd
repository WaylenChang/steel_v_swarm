extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Mobile = preload("res://tests/mobile_suite.gd")
const ControlsTests = preload("res://tests/controls_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["viewScope", "viewFov", "viewFog", "viewRosters", "viewLocks", "viewFoes"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original view/scope oracle: " + key)
			return
	for item: Dictionary in fixtures.viewScope:
		h._near(ScopeState.radius_vmin(item.fire, item.weather), item.radius, "Original combined fire/weather scope radius")
		var stops := ScopeState.weather_stops(item.weather)
		h._near(stops.x, item.stops.r0, "Original unscoped weather clear hole")
		h._near(stops.y, item.stops.r1, "Original unscoped weather full-density edge")
	for item: Dictionary in fixtures.viewFov:
		for step: Dictionary in item.steps:
			h._near(ScopeState.fov_step(step.before, step.wanted, step.delta), step.result, "Original zoom FOV easing and snap threshold")
	for item: Dictionary in fixtures.viewFog:
		var state := ScopeState.new()
		for step: Dictionary in item.steps:
			var inside := absf(float(step.get("x", 0))) <= 8
			state.advance(step.delta, inside and not item.flight and not step.get("air", false), step.weather, not step.get("dead", false))
			Helper.compare(h, {"dwell": state.fire_dwell, "fire": state.fire_fog, "weather": state.weather_fog}, step.result,
				"Original fire dwell/air exemption/recovery/death clear")
	for item: Dictionary in fixtures.viewFoes:
		h._check(TargetingMath.foe(item.side, item.target, item.neutral) == item.result, "Original visible-foe and asymmetric Super/third-side view gate")
	for item: Dictionary in fixtures.viewRosters:
		var rows := roster(item)
		Helper.compare(h, rows, item.result, "Original viewport/scope acquisition, NDC order, LOS, range and hysteresis: " + item.name)
		h._check(TargetingMath.view_choice(rows, int(item.keep)) == int(item.choice), "Original sticky current target or nearest angular offset with stable ties")
	for item: Dictionary in fixtures.viewLocks:
		var state := ViewLockState.new()
		var angles := Vector2(item.yaw, item.pitch)
		var paused := false
		var frozen := false
		var dead := false
		var notices: Array = []
		state.cycled.connect(func(index, count):
			notices.append(Content.label("view_lock_count") % [index, count] if count > 0 else Content.label("view_lock_empty_front")))
		var recoil := RecoilState.new()
		recoil.view_pitch = item.recoil[0]
		recoil.view_yaw = item.recoil[1]
		recoil.shake.z = item.recoil[2]
		var recoil_before := [recoil.view_pitch, recoil.view_yaw, recoil.shake.z]
		for step: Dictionary in item.steps:
			notices.clear()
			match step.kind:
				"press": state.press(true)
				"release": state.press(false)
				"paused": paused = true
				"resume": paused = false
				"freeze": frozen = true
				"thaw": frozen = false
				"death":
					state.clear_dead()
					dead = true
				"respawn": dead = false
			var candidates := native_candidates(step.candidates)
			var view_frame := frame(step.frame)
			var projection := matrix(step.projection)
			if not dead:
				var acquire := func(keep, full):
					var rows := TargetingMath.view_roster(Mobile.vector3(item.position), view_frame, projection, Mobile.vector(item.viewport), candidates, item.reach, keep, false, 1)
					return rows if full else TargetingMath.view_choice(rows, keep)
				var point_at := func(id):
					for candidate: Dictionary in candidates:
						if int(candidate.id) == id and candidate.eligible:
							return candidate.point
					return Vector3(INF, INF, INF)
				var change := state.advance(step.delta, step.now, angles, view_frame.origin, item.reach, paused, acquire, point_at)
				angles = InputRules.look(angles.x, angles.y, change, frozen, true, true, true)
			var expected_state: Dictionary = step.result.duplicate()
			expected_state.erase("basis")
			Helper.compare(h, {"hold": state.hold, "cycle": state.cycle, "target": state.target, "previous": state.previous,
				"last_seek": state.last_seek, "lit": state.lit, "angles": [angles.x, angles.y]}, expected_state,
				"Original press/hold/release/cycle/hidden/paused/death view lock")
			Helper.compare(h, notices, step.notices, "Original cycle count and empty-view feedback")
			var basis := recoil.basis(angles.x, angles.y)
			var expected := frame(step.result.basis + [0, 2, 0, 1]).basis
			h._check(basis.x.distance_to(expected.x) < 0.00001 and basis.y.distance_to(expected.y) < 0.00001 and basis.z.distance_to(expected.z) < 0.00001,
				"View lock changes base angles while retaining original recoil and camera roll")
			h._check([recoil.view_pitch, recoil.view_yaw, recoil.shake.z] == recoil_before, "View lock never cancels the recoil account")
	var simulation: BattleSimulation = ControlsTests.context(h)
	var unit: BattleUnit = ControlsTests.actor(simulation, "t01")
	var before := [unit.hp, unit.shield, unit.power, unit.money, unit.ammo.duplicate(true), unit.lock_target, simulation.rng.state]
	var origin := simulation.camera_origin_at(unit, unit.yaw + 0.4)
	h._check(origin.is_finite() and before == [unit.hp, unit.shield, unit.power, unit.money, unit.ammo, unit.lock_target, simulation.rng.state],
		"Owner presentation camera does not settle resources, confirm a weapon lock or consume combat RNG")
	simulation.free()

static func native_candidates(rows: Array) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		result.append({"id": row.id, "eligible": row.eligible, "point": Mobile.vector3(row.point), "obstruction": INF if row.obstruction == null else float(row.obstruction)})
	return result

static func roster(item: Dictionary) -> Array:
	var radius := ScopeState.radius_vmin(item.fire, item.fog) / 100 * minf(item.viewport[0], item.viewport[1])
	return TargetingMath.view_roster(Mobile.vector3(item.position), frame(item.frame), matrix(item.projection), Mobile.vector(item.viewport),
		native_candidates(item.candidates), item.reach, int(item.keep), item.scoped, radius)

static func frame(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])),
		Vector3(values[12], values[13], values[14]))

static func matrix(values: Array) -> Projection:
	return Projection(Vector4(values[0], values[1], values[2], values[3]), Vector4(values[4], values[5], values[6], values[7]),
		Vector4(values[8], values[9], values[10], values[11]), Vector4(values[12], values[13], values[14], values[15]))
