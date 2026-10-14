extends RefCounted

class LaunchSimulation extends BattleSimulation:
	var requests := 0
	func request_iframe(_unit: BattleUnit) -> bool:
		requests += 1
		return true

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["movementCosts", "movementSink", "movementLift", "movementLaunch"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original movement references before final verification: " + key)
			return
	for item: Dictionary in fixtures.movementCosts:
		h._near(MovementRules.jump_cost(item.charge, item.morph), item.result, "Original proportional, rounded and bounded jump cost")
	for item: Dictionary in fixtures.movementSink:
		h._near(MovementRules.sink_distance(item.damage, item.wind), item.result, "Original damage-proportional altitude loss and wind factor")
	var frames := 0
	for item: Dictionary in fixtures.movementLift:
		var lift: float = item.initial
		var reference: float = NAN if item.reference == null else item.reference
		h._near(MovementRules.lift_altitude_factor(item.altitude, reference), item.altitude_factor, "Original continuous exponential altitude power factor")
		for step: Dictionary in item.steps:
			var result := MovementRules.step_lift(lift, step.vertical, item.altitude, reference, item.up_speed, item.down_speed,
				step.delta, step.unbalanced, StatusRules.fluid_factor(int(item.wet)))
			h._near(result.lift, step.result.lift, "Original lift depletion, refill, descent and unbalance")
			h._near(result.vertical, step.result.vertical, "Depleted lift cancels ascent only on its next input frame")
			lift = result.lift
			frames += 1
	for item: Dictionary in fixtures.movementLaunch:
		var simulation := LaunchSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.configure({"id": 1, "kind": item.kind, "character": item.character, "side": "STEEL", "position": Vector3(0, 20, 0)})
		await h.get_tree().physics_frame
		unit.charge = item.charge
		unit.lift = Content.constants.FLIGHT.LIFT_MAX
		unit.yaw = item.yaw
		unit.impulse_velocity = Vector2(2, 3)
		unit.buffs = [{"until": 20.0, "mul": {"speed": item.modifier, "jump": item.modifier}}]
		unit._launch_charged_jump(simulation)
		h._check(unit.flying == item.flying and unit.low_gravity == item.low_gravity, "Original charged launch selects the flight or low-gravity state")
		h._near(unit.velocity.y, item.vertical, "Original vertical charged launch speed")
		var actual := Vector2(unit.velocity.x, unit.velocity.z) if unit.flying else unit.impulse_velocity
		h._check(actual.distance_to(Vector2(item.impulse[0], item.impulse[1])) < 0.0001, "Original charged jump preserves and adds horizontal impulse")
		h._check(unit.position.distance_to(Vector3(item.position[0], item.position[1], item.position[2])) < 0.0001, "Original morph launch lifts off before its flight frame")
		h._check(simulation.requests == int(item.iframes) and unit.charge == 0, "Original launch clears charge and requests exactly one authority iframe")
		h._near(unit.lift, Content.constants.FLIGHT.LIFT_MAX - MovementRules.jump_cost(item.charge, item.kind == "morph"), "Launch spends one dedicated lift cost")
		simulation.free()
	print("MOVEMENT_REFERENCE_PASS costs=", fixtures.movementCosts.size(), " sink=", fixtures.movementSink.size(), " lift=", fixtures.movementLift.size(), " frames=", frames,
		" launch=", fixtures.movementLaunch.size())
