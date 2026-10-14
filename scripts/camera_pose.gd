class_name CameraPose
extends RefCounted

static func eye_height(character: String, flying: bool, charge: float = 0.0) -> float:
	var view: Dictionary = Content.balance.cameraProfiles[character]["air" if flying else "ground"]
	return view.eye - charge * view.crouch

static func anchor(character: String, position: Vector3, yaw: float, flying: bool, charge: float = 0.0) -> Vector3:
	var view: Dictionary = Content.balance.cameraProfiles[character]["air" if flying else "ground"]
	return position + Vector3(-sin(yaw) * view.forward, eye_height(character, flying, charge), -cos(yaw) * view.forward)

static func clip(position: Vector3, camera: Vector3, eye: float, blockers: Array, entities: Array,
		on_deck: bool, standing_surface: float, collision: Callable, surface: Callable) -> Vector3:
	var dx := float(camera.x) - position.x
	var dz := float(camera.z) - position.z
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.001:
		return camera
	var ux := dx / length
	var uz := dz / length
	var maximum := length
	var skin: float = Content.balance.cameraRules.skin
	for blocker: Dictionary in blockers:
		if on_deck and blocker.y < standing_surface - 3:
			continue
		if camera.y < blocker.y or camera.y > blocker.y + blocker.h:
			continue
		var radius: float = sqrt(float(blocker.hw2) * blocker.hw2 + float(blocker.hd2) * blocker.hd2) if blocker.has("hw2") else blocker.r
		var reach := length + radius + skin + 1
		var bx: float = float(position.x) - blocker.x
		var bz: float = float(position.z) - blocker.z
		if absf(bx) > reach or absf(bz) > reach or sqrt(bx * bx + bz * bz) > reach:
			continue
		var entry := _box_entry(blocker, bx, bz, ux, uz, skin) if blocker.has("hw2") else _circle_entry(bx, bz, ux, uz, blocker.r + skin)
		maximum = minf(maximum, entry)
		if maximum <= 0:
			break
	if maximum > 0:
		for entity: Dictionary in entities:
			if entity.get("colR", 0) == 0 or entity.get("isSelf", false):
				continue
			var p: Vector3 = entity.position
			var entity_height: float = entity.get("colH", 6)
			if entity_height == 0:
				entity_height = 6
			if camera.y < p.y or camera.y > p.y + entity_height:
				continue
			var bx := float(position.x) - p.x
			var bz := float(position.z) - p.z
			if sqrt(bx * bx + bz * bz) > length + entity.colR + skin + 1:
				continue
			maximum = minf(maximum, _circle_entry(bx, bz, ux, uz, entity.colR + skin))
			if maximum <= 0:
				break
	if maximum < length:
		camera.x = position.x + ux * maximum
		camera.z = position.z + uz * maximum
	return _pull(Vector3(position.x, position.y + eye, position.z), camera, collision, surface)

static func _circle_entry(x: float, z: float, ux: float, uz: float, radius: float) -> float:
	var c := x * x + z * z - radius * radius
	if c <= 0:
		return 0.0
	var projection := x * ux + z * uz
	var discriminant := projection * projection - c
	if discriminant <= 0:
		return INF
	var entry := -projection - sqrt(discriminant)
	return entry if entry > 0 else INF

static func _box_entry(box: Dictionary, x: float, z: float, ux: float, uz: float, skin: float) -> float:
	var cosine: float = box._cs if box.has("_cs") else cos(box.ry)
	var sine: float = box._sn if box.has("_sn") else -sin(box.ry)
	var px := x * cosine + z * sine
	var pz := -x * sine + z * cosine
	var vx := ux * cosine + uz * sine
	var vz := -ux * sine + uz * cosine
	var width: float = box.hw2 + skin
	var depth: float = box.hd2 + skin
	if absf(px) < width and absf(pz) < depth:
		return 0.0
	var minimum := -INF
	var maximum := INF
	for axis: Array in [[px, vx, width], [pz, vz, depth]]:
		if absf(axis[1]) < 0.000000001:
			if axis[0] < -axis[2] or axis[0] > axis[2]:
				return INF
		else:
			var a: float = (-axis[2] - axis[0]) / axis[1]
			var b: float = (axis[2] - axis[0]) / axis[1]
			minimum = maxf(minimum, minf(a, b))
			maximum = minf(maximum, maxf(a, b))
	if maximum < minimum or maximum < 0:
		return INF
	return maxf(0, minimum)

static func _pull(anchor_point: Vector3, camera: Vector3, collision: Callable, surface: Callable) -> Vector3:
	var offset := camera - anchor_point
	var length := sqrt(float(offset.x) * offset.x + float(offset.y) * offset.y + float(offset.z) * offset.z)
	if length < 0.001:
		return camera
	var fraction := 1.0
	var hit: Dictionary = collision.call(anchor_point, camera)
	var rules: Dictionary = Content.balance.cameraRules
	if not hit.is_empty():
		fraction = minf(fraction, maxf(0, (anchor_point.distance_to(hit.position) - rules.pullClearance) / length))
	var count := clampi(ceili(length / 4), 2, 12)
	for i in range(1, count + 1):
		var point := anchor_point + offset * (float(i) / count)
		var floor_height: float = surface.call(point)
		if is_finite(floor_height) and point.y < floor_height + rules.surfaceClearance:
			fraction = minf(fraction, maxf(0, float(i - 1) / count - rules.surfaceRetreat))
			break
	return anchor_point + offset * fraction if fraction < 1 else camera
