class_name SourceSupportRay
extends RefCounted

# Long downward rays lose height precision when the native hit fraction is
# reconstructed along the full segment. Re-query locally without changing the
# selected collider, shape, face or original segment bounds.
const LOCAL_HALF_SPAN := 1.0

static func intersect(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	return refine(space, query, space.intersect_ray(query))

static func refine(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, first: Dictionary) -> Dictionary:
	if first.is_empty() or query.from.x != query.to.x or query.from.z != query.to.z or query.from.y <= query.to.y:
		return first
	var point: Vector3 = first.position
	var top := minf(query.from.y, point.y + LOCAL_HALF_SPAN)
	var bottom := maxf(query.to.y, point.y - LOCAL_HALF_SPAN)
	if not point.is_finite() or top <= bottom or top == query.from.y and bottom == query.to.y:
		return first
	var local := PhysicsRayQueryParameters3D.create(Vector3(query.from.x, top, query.from.z),
		Vector3(query.to.x, bottom, query.to.z), query.collision_mask, query.exclude)
	local.collide_with_areas = query.collide_with_areas
	local.collide_with_bodies = query.collide_with_bodies
	local.hit_back_faces = query.hit_back_faces
	local.hit_from_inside = query.hit_from_inside
	var refined := space.intersect_ray(local)
	if refined.is_empty() or refined.rid != first.rid or refined.shape != first.shape \
			or refined.get("face_index", -1) != first.get("face_index", -1):
		return first
	var refined_point: Vector3 = refined.position
	if not refined_point.is_finite() or refined_point.y > query.from.y or refined_point.y < query.to.y:
		return first
	# Keep every original identity/normal field and detach the returned buffer.
	var result := first.duplicate()
	result.position = Vector3(point.x, refined_point.y, point.z)
	return result
