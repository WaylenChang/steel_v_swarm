class_name CockpitPose
extends RefCounted

static func barrel_elevation(velocity: Vector3, direction: Vector3) -> float:
	var speed := velocity.length()
	var elevation := asin(clampf(velocity.y / (speed if speed > 0 else 1.0), -1, 1)) - asin(clampf(direction.y, -1, 1))
	return clampf(elevation, -0.35, Content.constants.BALLISTIC.LOB_SUP_MAX)

# Camera-local source gun-group pose; imported ports remain unchanged under group animation.
static func reload_offset(definition: Dictionary, progress: float) -> Vector3:
	var swing := sin(clampf(progress, 0, 1) * PI)
	if definition.type in ["beam", "rail"]:
		return Vector3(0, 0, swing * 0.4)
	if definition.type in ["launcher", "missile", "plasma"]:
		return Vector3(-swing * 0.5, 0, 0)
	return Vector3(swing * 0.12, -swing * 0.22, 0)

static func transform_for(profile: Dictionary, reload: Vector3, suppression: float, kick: float) -> Transform3D:
	var pivot: Array = profile.pivot
	var lift := clampf(reload.x + suppression, -profile.drop, profile.lift)
	var pull := minf(kick * 0.11 + reload.z, profile.pull)
	var cosine := cos(lift)
	var sine := sin(lift)
	var position := Vector3(0, reload.y + pivot[1] - (pivot[1] * cosine - pivot[2] * sine),
		profile.baseZ + pull + pivot[2] - (pivot[1] * sine + pivot[2] * cosine))
	return Transform3D(Basis(Vector3.RIGHT, lift), position)
