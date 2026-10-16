class_name BodyGaitVehicle
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, forward: float, yaw_rate: float) -> void:
	assert(rig.kind in ["wheeled", "tracked"], "Vehicle motion requires the original wheel/track rig")
	travel(poses, state, rig, delta, now, speed, forward, yaw_rate)
	var tracked: bool = rig.kind == "tracked"
	var roll := clampf(yaw_rate * forward * (0.004 if tracked else 0.009), -0.1, 0.1)
	var pitch := clampf(-float(state.accel) * (0.014 if tracked else 0.01), -0.09, 0.13)
	state.roll = BodyMotionState.damp(state.roll, roll, 4, delta)
	state.pitch = BodyMotionState.damp(state.pitch, pitch, 4, delta)
	poses.set_axis(rig.hull, "z", state.roll)
	poses.set_axis(rig.hull, "x", float(state.pitch) - Joint.or_number(rig, "_kickB", 0) * 0.045)
	var jiggle := clampf(speed / Joint.or_number(rig, "top", 10), 0, 1)
	poses.set_position_axis(rig.hull, "y", Joint.or_number(rig, "hullY0", 0) + sin(now * 12.5 + float(state.ph) * 7) * 0.012 * jiggle)

static func travel(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, forward: float, yaw_rate: float) -> void:
	var wheels: Array = rig.wheels if rig.get("wheels") is Array else []
	if wheels.is_empty() or delta < 0 or not is_finite(delta) or not is_finite(now) or not is_finite(speed) or not is_finite(forward) or not is_finite(yaw_rate):
		return
	var scale_factor := Joint.or_number(rig, "s", 1)
	var suspension: Array = rig.suspension if rig.get("suspension") is Array else []
	for index in range(wheels.size()):
		var wheel: Dictionary = wheels[index]
		var axle: Variant = suspension[index] if index < suspension.size() else null
		var velocity := forward - (yaw_rate * float(axle.x) * scale_factor if rig.kind == "tracked" and axle != null else 0.0)
		poses.set_axis(wheel.m, "x", fmod(poses.axis(wheel.m, "x") + velocity / maxf(0.05, float(wheel.r) * scale_factor) * delta, TAU))
		if axle == null:
			continue
		var drive := minf(1, speed / Joint.or_number(rig, "top", 10))
		poses.set_position_axis(axle.mount, "y", float(axle.y) + sin(now * 12.5 + Joint.or_number(state, "ph", 0) - float(axle.z) * 1.7) * float(axle.radius) * 0.06 * drive)
		poses.set_axis(axle.mount, "y", clampf(yaw_rate / maxf(2, speed) * 0.6, -0.32, 0.32) if Joint.flag(axle, "steer") else 0.0)
	var tracks: Array = rig.tracks if rig.get("tracks") is Array else []
	for track: Dictionary in tracks:
		track.travel = fmod(float(track.travel) + (forward / scale_factor - yaw_rate * float(track.x)) * delta, float(track.length))
		var mesh := track.mesh as MultiMeshInstance3D
		assert(mesh != null and mesh.multimesh.instance_count == int(track.count), "Source track shoes require their complete native MultiMesh")
		for index in range(int(track.count)):
			var distance := fmod(fmod(index * float(track.length) / float(track.count) + float(track.travel), float(track.length)) + float(track.length), float(track.length))
			var longitudinal: float
			var vertical: float
			var angle: float
			var radius: float = track.r
			var span: float = track.span
			if distance < span:
				longitudinal = float(track.rear) + distance
				vertical = -radius
				angle = 0
			elif distance < span + PI * radius:
				var arc := (distance - span) / radius
				longitudinal = float(track.front) + sin(arc) * radius
				vertical = -cos(arc) * radius
				angle = -arc
			elif distance < span * 2 + PI * radius:
				longitudinal = float(track.front) - (distance - span - PI * radius)
				vertical = radius
				angle = PI
			else:
				var arc := (distance - span * 2 - PI * radius) / radius
				longitudinal = float(track.rear) - sin(arc) * radius
				vertical = cos(arc) * radius
				angle = PI - arc
			poses.set_position(track.pose, Vector3(track.x, float(track.y) + vertical, longitudinal))
			poses.set_axis(track.pose, "x", angle)
			mesh.multimesh.set_instance_transform(index, track.pose.transform)
