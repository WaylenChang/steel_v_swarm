class_name ShotHistory
extends RefCounted

static func flight_seconds(definition: Dictionary, distance: float, height: float = 0.0) -> float:
	var horizontal := maxf(0, distance)
	return sqrt(2 * maxf(0, horizontal - height) / float(Content.constants.BALLISTIC.G)) if definition.trajectory == "lob" else sqrt(horizontal * horizontal + height * height) / float(definition.projectile.speed)

static func record(trail: Array, now: float, x: float, z: float) -> void:
	trail.append({"at": now, "x": x, "z": z})
	var cutoff := now - float(Content.balance.bot.shotTrailSeconds)
	var count := 0
	while count + 1 < trail.size() and float(trail[count + 1].at) <= cutoff:
		count += 1
	if count > 0:
		for index in range(count):
			trail.pop_front()

static func origin(trail: Array, now: float, current: Vector2, target: Vector2, definition: Dictionary, cap: float) -> Dictionary:
	for index in range(trail.size() - 1, -1, -1):
		var sample: Dictionary = trail[index]
		var elapsed := now - float(sample.at)
		if elapsed > cap:
			break
		var dx := float(sample.x) - float(target.x)
		var dz := float(sample.z) - float(target.y)
		var flight := flight_seconds(definition, sqrt(dx * dx + dz * dz))
		if elapsed >= flight:
			return {"point": Vector2(sample.x, sample.z), "back": minf(flight, cap)}
	return {"point": current, "back": minf(flight_seconds(definition, current.distance_to(target)), cap)}
