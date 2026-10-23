extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("localStatus") or not Content.balance.controls.has("casting"):
		h._check(false, "Regenerate original private status publication and client hold-until-snapshot references")
		return
	var state := LocalCastState.new()
	state.configure(Content.balance.controls.casting)
	var unit := BattleUnit.new()
	unit.character = "t01"
	for step: Dictionary in fixtures.localStatus:
		match str(step.kind):
			"snapshot":
				unit.status = {"emp_until": float(step.get("emp", 0)), "cast_lock_until": float(step.get("lock", 0))}
				unit.cast_state = {"start": 0.0, "duration": float(step.cast)} if step.has("cast") else {}
				var cast: Variant = ActorSnapshot.cast_remaining(unit, step.now)
				var emp := ActorSnapshot.deadline_remaining(unit.status.emp_until, step.now)
				state.sync({}, float(cast) if cast != null else 0.0, emp)
				Helper.compare(h, {"emp": emp, "cast": float(cast) if cast != null else 0.0},
					{"emp": step.publication.get("emp", 0), "cast": step.publication.get("cst", 0)},
					"Source private status serializer retains cast priority, decisecond rounding and omitted zero fields")
			"start": state.started(step.duration, step.now)
			"cancel": state.cancel()
		Helper.compare(h, {"emp": state.emp_left, "cast": state.cast_left, "until": state.until, "casting": state.is_casting(step.now)}, step.result,
			"Local EMP and cast remainders stay published between snapshots while optimistic deadlines and completion events retain their own clocks")
	unit.free()
