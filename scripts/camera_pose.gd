class_name CameraPose
extends RefCounted

static func angle_step(current: float, target: float, rate: float, delta: float) -> float:
	# The source camera seam maps both half-turn endpoints to -PI.
	var difference := fposmod(target - current + PI, TAU) - PI
	return current + difference * (1 - exp(-rate * delta))

static func body_height(character: String, flying: bool, scale_factor: float = 1.0) -> float:
	return float(Content.balance.cameraProfiles[character]["air" if flying else "ground"].height) * scale_factor

static func entity_collider(kind: String, scale_factor: float, collapsed: bool) -> Dictionary:
	var profile: Dictionary = Content.balance.playerView.colliders[kind]
	var radius: float = profile.radius * ((scale_factor if scale_factor != 0 else 1.0) if profile.scaleRadius else 1.0)
	var height: float = profile.height
	if collapsed:
		radius *= float(Content.balance.playerView.collapseRadius)
		height *= float(Content.balance.playerView.collapseHeight)
	return {"colR": radius, "colH": height}

static func third_person_anchor(position: Vector3, height: float, yaw: float, pitch: float, surface: Callable) -> Vector3:
	var rules: Dictionary = Content.constants.PLAYER_TPS
	var distance := maxf(float(rules.MIN_DIST), height * float(rules.DIST_F))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(-forward.z, 0, forward.x)
	var camera := position - forward * distance * cos(pitch) + right * height * float(rules.SHOULDER_F)
	camera.y += height * float(rules.HEIGHT_F) - sin(pitch) * distance
	var floor_height: float = surface.call(camera)
	if camera.y < floor_height + float(rules.FLOOR_M):
		camera.y = floor_height + float(rules.FLOOR_M)
	return camera

static func frame_ring(frame: Transform3D, projection: Projection, ring: Vector3) -> Transform3D:
	var view := frame.affine_inverse()
	var point := view * ring
	var target: float = Content.constants.PLAYER_TPS.RING_NDC_Y
	var denominator := target * view.basis.z.y + projection.y.y * view.basis.y.y
	if absf(denominator) <= float(Content.balance.playerView.ringDenominator):
		return frame
	var offset := (target * point.z + projection.y.y * point.y) / denominator
	if is_finite(offset):
		frame.origin.y += offset
	return frame

static func eye_height(character: String, flying: bool, charge: float = 0.0, scale_factor: float = 1.0) -> float:
	var view: Dictionary = Content.balance.cameraProfiles[character]["air" if flying else "ground"]
	return view.eye * scale_factor - charge * view.crouch

static func anchor(character: String, position: Vector3, yaw: float, flying: bool, charge: float = 0.0, scale_factor: float = 1.0) -> Vector3:
	var view: Dictionary = Content.balance.cameraProfiles[character]["air" if flying else "ground"]
	return position + Vector3(-sin(yaw) * view.forward * scale_factor, eye_height(character, flying, charge, scale_factor), -cos(yaw) * view.forward * scale_factor)

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
	var result := _pull_components([float(anchor_point.x), float(anchor_point.y), float(anchor_point.z)],
		[float(camera.x), float(camera.y), float(camera.z)], collision, surface)
	return Vector3(result[0], result[1], result[2])

static func _pull_components(anchor: Array, camera: Array, collision: Callable, surface: Callable) -> Array:
	var ax := float(anchor[0])
	var ay := float(anchor[1])
	var az := float(anchor[2])
	var dx := float(camera[0]) - ax
	var dy := float(camera[1]) - ay
	var dz := float(camera[2]) - az
	var length := sqrt(dx * dx + dy * dy + dz * dz)
	if length < 0.001:
		return camera
	var fraction := 1.0
	var hit: Dictionary = collision.call(Vector3(ax, ay, az), Vector3(camera[0], camera[1], camera[2]))
	var rules: Dictionary = Content.balance.cameraRules
	if not hit.is_empty():
		var point: Vector3 = hit.position
		var hx := float(point.x) - ax
		var hy := float(point.y) - ay
		var hz := float(point.z) - az
		var hit_distance := sqrt(hx * hx + hy * hy + hz * hz)
		fraction = minf(fraction, maxf(0, (hit_distance - rules.pullClearance) / length))
	var count := clampi(ceili(length / 4), 2, 12)
	for i in range(1, count + 1):
		var t := float(i) / count
		var x := ax + dx * t
		var y := ay + dy * t
		var z := az + dz * t
		var floor_height: float = surface.call(Vector3(x, y, z))
		if is_finite(floor_height) and y < floor_height + rules.surfaceClearance:
			fraction = minf(fraction, maxf(0, float(i - 1) / count - rules.surfaceRetreat))
			break
	return [ax + dx * fraction, ay + dy * fraction, az + dz * fraction] if fraction < 1 else camera
