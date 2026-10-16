class_name BodyViewMotion
extends RefCounted

var position := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var configured := false
var ground: Variant = null

func place(point: Vector3) -> void:
	position = point
	configured = true

func advance(delta: float, now: float, frame: int, camera: Vector3, state: Dictionary, snap: bool,
		queries: Dictionary, nearest: Callable, carrier: CarrierBodyMotion, low_power: bool = false) -> Dictionary:
	if not configured or not is_finite(delta) or delta < 0 or not is_finite(now):
		return {}
	var previous := position
	var previous_yaw := yaw
	var target: Vector3 = state.target
	if not target.is_finite():
		return {}
	if state.get("static", false):
		position = Vector3(target.x, float(state.padY) if state.get("padY") != null else float(queries.ground.call(target.x, target.z)), target.z)
		return {"due": BodyPresentation.update_due(frame, str(state.id), BodyPresentation.update_stride(
			Vector2(position.x - camera.x, position.z - camera.z).length_squared(), low_power)), "previous": previous, "previous_yaw": previous_yaw}
	var rules: Dictionary = Content.balance.bodyRules.presentation.remote
	var gain := 1.0 - exp(-float(rules.positionResponse) * delta)
	var x := target.x if snap else position.x + (target.x - position.x) * gain
	var z := target.z if snap else position.z + (target.z - position.z) * gain
	var due := snap or BodyPresentation.update_due(frame, str(state.id), BodyPresentation.update_stride(
		Vector2(position.x - camera.x, position.z - camera.z).length_squared(), low_power))
	if snap:
		ground = null
	var lift := float(state.heroY) if state.hero or state.flies else 0.0
	if due or ground == null:
		if state.flies:
			ground = queries.flight.call(x, z)
		else:
			var seed := position.y - lift
			if not state.hero and state.side in ["STEEL", "SWARM"]:
				var lane: Variant = queries.lane.call(x, z)
				if lane != null:
					seed = float(lane) + float(rules.laneSeed)
			ground = queries.surface.call(Vector3(x, seed, z))
	if not (ground is int or ground is float) or not is_finite(float(ground)):
		return {}
	var y := float(ground) + lift
	if state.get("waterY") != null and not state.hero and not state.flies and y < float(state.waterY):
		var deck: Variant = queries.deck.call(x, z)
		y = float(deck) if deck != null and float(deck) > float(state.waterY) else float(state.waterY)
	if state.get("carrier", false):
		if not carrier.sampled:
			carrier.place(previous)
		carrier.advance(Vector3(x, y, z), state.reported_yaw, delta, state.kind == "hyper", snap)
		yaw = carrier.yaw
		pitch = carrier.pitch
	else:
		var wanted: Variant = null
		var dx := float(target.x) - float(position.x)
		var dz := float(target.z) - float(position.z)
		var aim: Variant = state.get("aim")
		var aiming := aim is Dictionary and now < float(aim.until)
		if state.hero:
			wanted = float(state.reported_yaw) + PI
			if dx * dx + dz * dz <= float(rules.stoppedSquared) and aiming:
				wanted = atan2(float(aim.x) - position.x, float(aim.z) - position.z)
		elif dx * dx + dz * dz > float(rules.stoppedSquared):
			wanted = atan2(dx, dz)
		elif aiming:
			wanted = atan2(float(aim.x) - position.x, float(aim.z) - position.z)
		else:
			var enemy: Variant = nearest.call(now, previous)
			if enemy is Vector3:
				wanted = atan2(enemy.x - position.x, enemy.z - position.z)
		if wanted != null:
			yaw = float(wanted) if snap else yaw + BodyMountAim.wrap_angle(float(wanted) - yaw) * (1.0 - exp(-float(rules.headingResponse) * delta))
	position = Vector3(x, y, z)
	return {"due": due, "previous": previous, "previous_yaw": previous_yaw}
