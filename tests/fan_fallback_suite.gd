extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class SpyEffects extends CombatEffects:
	var calls: Array = []
	var admission := false

	func point(value: Vector3) -> Array:
		return [value.x, value.y, value.z]

	func fan(origin: Vector3, direction: Vector3, definition: Dictionary, reach: float, _clip: Callable, _ttl: float = .45) -> bool:
		calls.append({"type": "fan", "origin": point(origin), "direction": point(direction), "reach": reach,
			"ch": definition.ch, "slot": definition.slot})
		return admission

	func muzzle(origin: Vector3, heavy: bool, side: String) -> void:
		calls.append({"type": "muzzle", "point": point(origin), "heavy": heavy, "side": side})

	func ion(origin: Vector3, target: Vector3, color: int, radius: float = 2.2, ttl: float = .45,
			coil: float = 3, core: int = 0xffffff, definition: Dictionary = {}) -> void:
		calls.append({"type": "ion", "origin": point(origin), "target": point(target), "color": color,
			"radius": radius, "ttl": ttl, "coil": coil, "core": core, "ch": definition.get("ch"), "slot": definition.get("slot")})

	func beam(origin: Vector3, target: Vector3, color: int, ttl: float = .4, width: float = .08, opacity: float = .85) -> void:
		calls.append({"type": "beam", "origin": point(origin), "target": point(target), "color": color, "ttl": ttl, "width": width, "opacity": opacity})

	func lance(origin: Vector3, target: Vector3, _definition: Dictionary, color: int) -> void:
		calls.append({"type": "lance", "origin": point(origin), "target": point(target), "color": color})

	func energy_beam(origin: Vector3, target: Vector3, color: int, radius: float, ttl: float, rings: float, core: int, _definition: Dictionary = {}) -> void:
		calls.append({"type": "energy", "origin": point(origin), "target": point(target), "color": color,
			"radius": radius, "ttl": ttl, "rings": rings, "core": core})

	func spark(origin: Vector3, radius: float, color: int, _delay: float = 0) -> void:
		calls.append({"type": "spark", "point": point(origin), "radius": radius, "color": color})

	func shock(origin: Vector3, radius: float, color: int) -> void:
		calls.append({"type": "shock", "point": point(origin), "radius": radius, "color": color})

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("fanFallbacks"):
		h._check(false, "Regenerate original local/remote fan fallback dispatch references")
		return
	var effects := SpyEffects.new()
	effects.random_sample = func(): return .25
	for item: Dictionary in fixtures.fanFallbacks:
		effects.calls.clear()
		effects.admission = item.admission
		var clip := func(origin: Vector3, target: Vector3):
			var obstruction := func(start: Vector3, end: Vector3):
				if item.scenario != "wall" or start.z == end.z:
					return {}
				var fraction := (30.0 - start.z) / (end.z - start.z)
				return {"position": start.lerp(end, fraction)} if fraction >= 0 and fraction <= 1 else {}
			var result := NpcShotMotion.clip(origin, target, obstruction)
			effects.calls.append({"type": "clip", "origin": effects.point(origin), "target": effects.point(target), "result": effects.point(result.to)})
			return result
		if item.mode == "local":
			effects.fan_blast(BodyPose.vector(item.origin), BodyPose.vector(item.direction), item.definition, item.reach, item.side, item.hue, clip)
		else:
			effects.remote_plasma(BodyPose.vector(item.origin), BodyPose.vector(item.direction), item.definition, item.reach, item.arc,
				item.slot, item.side, item.hue, item.scenario.ends_with("barrel"), clip)
		Helper.compare(h, effects.calls, item.calls, "Original fan fallback primitive/query order, central-bin reach, zero/vertical directions and barrel variants")
	if not fixtures.has("lanceVisualFallbacks"):
		h._check(false, "Regenerate original authored/procedural lance dispatch references")
	else:
		for item: Dictionary in fixtures.lanceVisualFallbacks:
			effects.calls.clear()
			effects.lance_visual(BodyPose.vector(item.origin), BodyPose.vector(item.target), item.definition, item.side, item.hue)
			Helper.compare(h, effects.calls, item.calls, "Original lance asset preference, side colours, full-width kinetic channel and endpoint primitives")
	effects.free()
