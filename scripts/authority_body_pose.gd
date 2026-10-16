class_name AuthorityBodyPose
extends Node3D

var body: BodyRig
var presentation := BodyPresentation.new()
var frame_number := 0
var character := ""
var side := ""
var root_scale := Vector3.ONE

func configure(pilot: String, faction: String, source_id: String, phase: Callable = Callable()) -> bool:
	assert(body == null, "Configure an authority body only once")
	character = pilot
	side = faction
	# The private graph must not inherit a rendered/interpolated actor transform.
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = false
	body = BodyRig.new()
	add_child(body)
	if not body.configure("%s_%s" % [faction.to_lower(), pilot], phase):
		return false
	root_scale = body.poses.read(body.source_root).s
	presentation.configure(body, source_id)
	presentation.pending_snap = false
	return true

func accept(event: Dictionary, now: float, position: Vector3) -> bool:
	return presentation.accept(event, now, position, true, true)

func advance(delta: float, now: float, position: Vector3, yaw: float, scale_factor: float, state: Dictionary, first_person: bool) -> bool:
	if body == null or body.source_root == null:
		return false
	place(position, yaw, scale_factor, first_person, state.get("dead", false))
	frame_number = (frame_number + 1) & 0xffffffff
	var fields := state.duplicate()
	fields.isSelf = true
	var stepped := presentation.frame(delta, now, frame_number, position, body.poses.axis(body.source_root, "y"), position, fields, first_person)
	body.spin(delta)
	return stepped

func place(position: Vector3, yaw: float, scale_factor: float, first_person: bool, dead: bool = false) -> void:
	body.poses.set_position(body.source_root, position)
	body.poses.set_scale(body.source_root, root_scale * scale_factor)
	body.source_root.visible = not first_person and not dead
	if not first_person:
		body.poses.set_axis(body.source_root, "y", yaw + PI)

func muzzle(slot: String, position: Vector3, eye: float, yaw: float, camera: Vector3, reach: float, direction: Variant = null) -> Dictionary:
	return BodyLaunchPose.resolve(body, slot, position, eye, yaw, camera, reach, direction)

func request_snap() -> void:
	presentation.request_snap()
