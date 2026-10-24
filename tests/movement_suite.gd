extends RefCounted

class MovementUnit extends BattleUnit:
	# The source launch seam has no rendered model. Retain native physics shapes.
	func _build_model() -> void:
		pass

class LaunchSimulation extends BattleSimulation:
	var requests := 0
	func request_iframe(_unit: BattleUnit) -> bool:
		requests += 1
		return true

class BalanceSimulation extends BattleSimulation:
	var balance: Dictionary = {}
	func flight_balance_state(_unit: BattleUnit) -> Dictionary:
		return balance

class SinkSimulation extends BattleSimulation:
	var altitude := 0.0
	func _missile_target_altitude(_unit: BattleUnit) -> float:
		return altitude

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["movementCosts", "movementSink", "movementLift", "movementLaunch", "movementUnbalance", "movementSinkHits"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original movement references before final verification: " + key)
			return
	for item: Dictionary in fixtures.movementCosts:
		h._near(MovementRules.jump_cost(item.charge, item.morph), item.result, "Original proportional, rounded and bounded jump cost")
	for item: Dictionary in fixtures.movementSink:
		h._near(MovementRules.sink_distance(item.damage, item.wind), item.result, "Original damage-proportional altitude loss and wind factor")
	var balance_simulation := BalanceSimulation.new()
	var balance_unit := BattleUnit.new()
	for item: Dictionary in fixtures.movementUnbalance:
		h._check(MovementRules.flight_unbalanced(item.state, item.now) == item.result,
			"Original flight-unbalance predicate honors death, non-flight, low-drone exemption, weather threshold and strict lock deadline")
		balance_simulation.balance = item.state
		balance_simulation.clock = item.now
		balance_simulation.weather_dynamics = {"wind": item.state.wind}
		balance_unit.kind = "drone" if item.state.drone else "morph"
		balance_unit.lift = 25
		balance_unit.wet = 0
		balance_unit._step_lift(balance_simulation, 0, .1)
		h._near(balance_unit.lift, item.lift, "Native flight power consumes the original complete unbalance predicate, including low-drone recovery")
	balance_unit.free()
	balance_simulation.free()
	for item: Dictionary in fixtures.movementSinkHits:
		var state: Dictionary = item.state.duplicate(true)
		var sink_simulation := SinkSimulation.new()
		sink_simulation.altitude = state.altitude
		sink_simulation.weather_dynamics = {"wind": state.wind}
		var sink_unit := BattleUnit.new()
		sink_unit.character = "fixture"
		sink_unit.kind = "drone" if state.drone else "morph"
		sink_unit.flying = state.flying
		sink_unit.hp = 100
		sink_unit.shield = state.shield
		sink_unit.defending = state.defending
		sink_unit.air_sink = state.sink
		sink_unit.air_sink_speed = state.sink_speed
		sink_unit.lift_lock_until = state.lock_until
		for step: Dictionary in item.steps:
			var actual := MovementRules.sink_hit(state, step.damage, step.now)
			sink_simulation.clock = step.now
			sink_simulation._record_air_sink(sink_unit, step.damage)
			for key: String in step.result:
				h._near(actual[key], step.result[key], "Original successive hit sink/velocity/defensive lock accumulation: " + key)
			h._near(sink_unit.air_sink, step.result.sink, "Authority damage uses the original accumulated sink distance")
			h._near(sink_unit.air_sink_speed, step.result.speed, "Authority damage resets pending sink speed after each accepted loss")
			h._near(sink_unit.lift_lock_until, step.result.lock_until, "Authority damage preserves stronger existing locks and shield-depletion ordering")
			h._check(sink_unit.hp == 100 and sink_unit.shield == state.shield, "Flight reaction cannot settle or duplicate health and shield loss")
			state.sink = actual.sink
			state.sink_speed = actual.speed
			state.lock_until = actual.lock_until
		sink_unit.free()
		sink_simulation.free()
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
		h._near(MovementRules.charged_launch_speed(item.charge, item.kind == "morph", item.modifier, 1.0),
			item.vertical, "Original scalar charged launch speed before native vector storage")
		var simulation := LaunchSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var unit := MovementUnit.new()
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
		h._check(unit.velocity.y == Vector3(0, item.vertical, 0).y,
			"Native vertical charged launch is exactly the source scalar converted to Vector3 storage")
		var actual := Vector2(unit.velocity.x, unit.velocity.z) if unit.flying else unit.impulse_velocity
		h._check(actual.distance_to(Vector2(item.impulse[0], item.impulse[1])) < 0.0001, "Original charged jump preserves and adds horizontal impulse")
		h._check(unit.position.distance_to(Vector3(item.position[0], item.position[1], item.position[2])) < 0.0001, "Original morph launch lifts off before its flight frame")
		h._check(simulation.requests == int(item.iframes) and unit.charge == 0, "Original launch clears charge and requests exactly one authority iframe")
		h._near(unit.lift, Content.constants.FLIGHT.LIFT_MAX - MovementRules.jump_cost(item.charge, item.kind == "morph"), "Launch spends one dedicated lift cost")
		simulation.free()
	print("MOVEMENT_REFERENCE_PASS costs=", fixtures.movementCosts.size(), " sink=", fixtures.movementSink.size(), " lift=", fixtures.movementLift.size(), " frames=", frames,
		" launch=", fixtures.movementLaunch.size())
