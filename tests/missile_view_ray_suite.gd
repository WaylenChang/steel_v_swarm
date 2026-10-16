extends RefCounted

const PresentationTests = preload("res://tests/missile_presentation_suite.gd")

class RecordedEffects extends CombatEffects:
	func _ready() -> void:
		pass
	func missile_smoke(_point: Vector3) -> void:
		pass
	func scene_damage_burst(_id: int, _kind: String, _point: Vector3, _height: float, _radius: float, _stage: int) -> void:
		pass

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("missileViewRays") or not MissilePresentation.available():
		h._check(false, "Regenerate source interpolated missile ray geometry and original candidate/triangle fixtures")
		return
	for authority: bool in [false, true]:
		for row: Dictionary in fixtures.missileViewRays:
			_case(h, row, authority)
	_shells(h)
	print("MISSILE_VIEW_RAY_REFERENCE_PASS cases=", fixtures.missileViewRays.size())

static func _case(h: Node, row: Dictionary, authority: bool) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = authority
	simulation.world = PresentationTests.FlatWorld.new()
	simulation.add_child(simulation.world)
	var effects := RecordedEffects.new()
	effects.random_sample = func(): return .5
	simulation.world.combat_effects = effects
	simulation.world.add_child(effects)
	var collision := MissileBody.new()
	collision.position = Vector3(100, 200, 300)
	simulation.add_child(collision)
	simulation.missile_bodies[999] = collision
	simulation.missiles.append({"id": 999, "hp": 10.0})
	var resources := [simulation.rng.state, simulation.projectile_rng.state, simulation.clock,
		simulation.next_id, simulation.missiles.duplicate(true), collision.transform, collision.collision_layer]
	for frame: Dictionary in row.frames:
		var states: Array = []
		for source: Dictionary in frame.states:
			var state := source.duplicate(true)
			state.position = BodyPose.vector(source.position)
			states.append(state)
		simulation.sync_missile_presentations(states, [])
		simulation.step_missile_presentations(float(frame.delta))
		(simulation.missile_presentations[7] as MissilePresentation).visible = not frame.hidden
		for ray: Dictionary in frame.rays:
			var origin := BodyPose.vector(ray.origin)
			var direction := BodyPose.vector(ray.direction)
			var candidates: Array = []
			for view: MissilePresentation in simulation.missile_presentations.values():
				if MissileViewRay.candidate(origin, direction, float(ray.far), view.global_position):
					candidates.append(view.missile_id)
			h._check(candidates == ray.candidates, "Original inclusive six-metre missile broad phase and insertion order")
			var hit := simulation.missile_view_collision(origin, origin + direction * float(ray.far))
			h._check(hit.is_empty() == (ray.point == null), "Original source mesh sidedness, hidden parts and finite ray length")
			if not hit.is_empty() and ray.point is Array:
				h._check(int(hit.missile) == int(ray.missile) and (hit.position as Vector3).distance_to(BodyPose.vector(ray.point)) < .0005,
					"Original interpolated/animated body, outline and persistent-damage mesh intersection")
		h._check(resources == [simulation.rng.state, simulation.projectile_rng.state, simulation.clock,
			simulation.next_id, simulation.missiles, collision.transform, collision.collision_layer],
			"Visual missile selection cannot move physical missiles, settle hits or consume combat RNG")
	simulation.sync_missile_presentations([], [])
	h._check(simulation.missile_view_collision(Vector3.ZERO, Vector3(0, 0, 100)).is_empty(), "Retired view IDs cannot remain ray candidates")
	simulation.free()

static func _shells(h: Node) -> void:
	for pierce: bool in [false, true]:
		for stop: float in [-1.0, .25, .5, .75]:
			var view := ProjectilePresentation.new()
			h.add_child(view)
			var calls := {"missile": 0, "impact": Vector3.INF}
			view.missile_collision = func(start: Vector3, end: Vector3) -> Dictionary:
				calls.missile += 1
				return {"position": start.lerp(end, .5), "missile": 7, "visual": true}
			var state := {"position": Vector3.ZERO, "origin": Vector3.ZERO, "target": Vector3(0, 0, -100),
				"velocity": Vector3(0, 0, -10), "guided": false, "age": 0.0, "range": 100.0, "pierce": pierce}
			view.spawn_shell(state, "sam-source")
			var terrain := func(start: Vector3, end: Vector3) -> Dictionary:
				return {"position": start.lerp(end, stop)} if stop >= 0 else {}
			view.advance(.1, terrain, func(point: Vector3, _radius: float, _color: int): calls.impact = point)
			h._check(calls.missile == (0 if pierce else 1), "Penetrating echo shells skip visual missile meshes")
			h._check(view.shells.is_empty() == (not pierce or stop >= 0), "Only ordinary missiles or environmental stops retire an echo shell")
			if not pierce or stop >= 0:
				var fraction := stop
				if not pierce:
					fraction = minf(stop, .5) if stop >= 0 else .5
				h._near(float(calls.impact.z), -fraction, "Nearest visual/environment hit wins and terrain retains exact ties")
			view.free()
