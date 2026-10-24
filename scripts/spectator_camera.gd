class_name SpectatorCamera
extends Camera3D

var state := SpectatorState.new()
var simulation: BattleSimulation
var rows: Dictionary = {}

func configure(battle: BattleSimulation) -> bool:
	if not Content.balance.has("spectator") or battle == null or battle.world == null:
		return false
	simulation = battle
	var ground := simulation.world.source_height(0, 0)
	if not is_finite(ground):
		return false
	var rules: Dictionary = Content.balance.spectator
	state.configure(rules, Vector3(0, ground, 0), simulation.world.ceiling, rules.initialFov)
	fov = state.fov
	near = Content.balance.cameraRules.near
	var bounds: Dictionary = simulation.world.bounds
	far = maxf(float(bounds.maxX) - float(bounds.minX), float(bounds.maxZ) - float(bounds.minZ)) * float(rules.farFactor)
	_apply_pose(state.position)
	make_current()
	refresh()
	return true

func refresh() -> void:
	if not is_instance_valid(simulation):
		return
	var retained := {}
	for unit: BattleUnit in simulation.pilots.values():
		if not is_instance_valid(unit) or unit.peer_id == 0:
			continue
		var row: Dictionary = rows.get(unit.entity_id, {})
		if row.is_empty() or not is_same(row.get("unit"), unit):
			row = {"unit": unit}
		var abilities := ActorSnapshot.abilities(unit, simulation.clock) if simulation.authoritative else unit.public_abilities
		row.merge({"pid": SpectatorState.source_pid(unit.peer_id), "hero": true, "act": unit.presentation_visible,
			"side": unit.side, "ch": unit.character, "dead": not unit.alive(),
			"position": unit.model.global_position if unit.model != null else unit.global_position,
			"ry": unit.body_presentation.report.get("yaw", unit.facing_yaw()) if unit.body_presentation != null else unit.facing_yaw(),
			"heroY": unit.presented_altitude if is_finite(unit.presented_altitude) else 0.0,
			"hp": unit.hp, "max": unit.max_hp, "sp": unit.shield, "maxSp": unit.max_shield,
			"mp": unit.power, "mm": unit.max_power, "money": unit.money, "kn": unit.score,
			"rs": maxf(0, unit.respawn_at - simulation.clock), "up": unit.upgrades.duplicate(),
			"emp": maxf(0, float(unit.status.get("emp_until", 0)) - simulation.clock),
			"ab": abilities.get("levels", {}), "cds": abilities.get("cooldowns", [])}, true)
		retained[unit.entity_id] = row
	rows = retained

func advance(delta: float, angles: Vector2, axis: Dictionary, rising: bool, descending: bool) -> Vector2:
	refresh()
	state.yaw = angles.x
	state.pitch = angles.y
	var world := simulation.world
	var collision := func(start: Vector3, end: Vector3) -> Dictionary: return world.obstruction_hit(start, end, false)
	var pull := func(start: Vector3, end: Vector3) -> Vector3: return CameraPose._pull(start, end, collision, world.visual_surface)
	for command: Dictionary in state.advance(delta, rows.values(), axis, rising, descending, world.visual_surface, world.ceiling, pull):
		_visibility(command.actor, command.visible)
	_apply_pose(state.camera_position)
	fov = state.camera_fov
	return Vector2(state.yaw, state.pitch)

func _apply_pose(point: Vector3) -> void:
	var rotation := SourceQuaternion.multiply(SourceQuaternion.axis_angle(Vector3.UP, state.yaw),
		SourceQuaternion.axis_angle(Vector3.RIGHT, state.pitch))
	global_transform = Transform3D(SourceQuaternion.basis(rotation), point)

func _visibility(row: Dictionary, shown: bool) -> void:
	var unit: Variant = row.get("unit")
	if is_instance_valid(unit) and is_instance_valid(unit.model):
		unit.model.visible = shown

func _exit_tree() -> void:
	if not state.hidden.is_empty():
		var unit: Variant = state.hidden.get("unit")
		if is_instance_valid(unit):
			_visibility(state.hidden, unit.alive())
	state.hidden = {}
	rows.clear()
