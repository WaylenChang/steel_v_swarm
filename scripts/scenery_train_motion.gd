class_name SceneryTrainMotion
extends RefCounted

var spec: Dictionary
var path: Path3D
var follower: PathFollow3D
var visual: Node3D
var distance := 0.0
var direction := 1
var orientation := Basis.IDENTITY

static func create_path(source: Dictionary) -> Path3D:
	var result := Path3D.new()
	result.name = "TrainPath_%d" % int(source.id)
	result.curve = Curve3D.new()
	result.curve.resource_local_to_scene = true
	result.curve.up_vector_enabled = false
	# No spline handles or intermediate bake points: retain the original polyline.
	result.curve.bake_interval = float(source.total)
	var previous := Vector3(INF, INF, INF)
	for point: Array in source.points:
		var position := Vector3(point[0], point[1], point[2])
		if position != previous:
			result.curve.add_point(position)
			previous = position
	var follow := PathFollow3D.new()
	follow.name = "TrainFollower"
	follow.loop = false
	follow.cubic_interp = false
	follow.rotation_mode = PathFollow3D.ROTATION_NONE
	result.add_child(follow)
	var model := Node3D.new()
	model.name = "TrainVisual"
	follow.add_child(model)
	model.transform = _initial_frame(source)
	if result.curve.get_point_count() > 0:
		model.position -= result.curve.get_point_position(0)
	return result

static func _initial_frame(source: Dictionary) -> Transform3D:
	var matrix: Array = source.initialFrame
	return Transform3D(Basis(Vector3(matrix[0], matrix[1], matrix[2]), Vector3(matrix[4], matrix[5], matrix[6]),
		Vector3(matrix[8], matrix[9], matrix[10])), Vector3(matrix[12], matrix[13], matrix[14]))

func configure(root: Node3D, source: Dictionary, phase: Variant = null) -> bool:
	spec = source
	path = root.get_node_or_null("TrainPath_%d" % int(source.id)) as Path3D
	if path == null or path.curve == null or path.curve.get_point_count() < 2 or path.curve.get_baked_length() <= 0:
		push_error("Original train requires its captured native polyline")
		return false
	follower = path.get_node_or_null("TrainFollower") as PathFollow3D
	visual = path.get_node_or_null("TrainFollower/TrainVisual") as Node3D
	if follower == null or visual == null:
		push_error("Missing original train visual/follower binding")
		return false
	distance = float(source.start) if phase == null else float(phase) * float(source.total)
	direction = 1
	var initial := _initial_frame(source)
	orientation = initial.basis
	# The original constructor leaves the train at its bind pose until its first update.
	visual.transform = follower.transform.affine_inverse() * initial
	return true

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0 or not is_instance_valid(visual):
		return
	distance += float(spec.speed) * direction * delta
	if distance > float(spec.total) or distance < 0:
		direction *= -1
		distance = clampf(distance, 0, float(spec.total))
	follower.progress = _native_offset(distance)
	var ahead := path.curve.sample_baked(_native_offset(distance + direction * float(spec.lookahead)), false)
	var offset := ahead - follower.position
	if offset.length_squared() > float(spec.turnSquared):
		orientation = _looking_at(offset, float(spec.parallelPerturbation))
	visual.transform = Transform3D(orientation, Vector3.ZERO)

func _native_offset(value: float) -> float:
	return path.curve.get_baked_length() if value >= float(spec.total) else maxf(0, value)

static func _looking_at(offset: Vector3, perturbation: float) -> Basis:
	var z := offset.normalized()
	var x := Vector3.UP.cross(z)
	if not x.is_zero_approx():
		return Basis.looking_at(offset, Vector3.UP, true)
	# Godot rejects a parallel up axis; preserve the original Matrix4.lookAt seam.
	if x.length_squared() == 0:
		z.z += perturbation
		z = z.normalized()
		x = Vector3.UP.cross(z)
	x = x.normalized()
	return Basis(x, z.cross(x), z)
