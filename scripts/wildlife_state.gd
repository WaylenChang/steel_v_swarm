class_name WildlifeState
extends RefCounted

var spec: Dictionary
var route: Dictionary
var points: PackedFloat32Array
var positions: PackedFloat32Array
var velocities: PackedFloat32Array
var speeds: PackedFloat32Array
var offsets: PackedFloat32Array
var wings: PackedFloat32Array
var time := 0.0
var elapsed := 0.0

func configure(source: Dictionary) -> void:
	route = source
	spec = source.spec
	points = PackedFloat32Array(source.pts)
	positions = PackedFloat32Array(source.pos)
	velocities = PackedFloat32Array(source.vel)
	speeds = PackedFloat32Array(source.spd)
	offsets = PackedFloat32Array(source.off)
	wings = PackedFloat32Array(source.wing)
	time = float(source.t)
	elapsed = 0

func curve_at(value: float) -> Array[float]:
	var fraction := fmod(fmod(value, 1.0) + 1.0, 1.0) * int(route.n)
	var first := int(floor(fraction)) % int(route.n)
	var second := (first + 1) % int(route.n)
	var weight: float = fraction - floor(fraction)
	var result: Array[float] = []
	for axis in range(3):
		var a := float(points[first * 3 + axis])
		result.append(a + (float(points[second * 3 + axis]) - a) * weight)
	return result

func _progress(index: int, now: float) -> float:
	return now * float(spec.SPEED) * float(speeds[index]) / float(route.len) + float(offsets[index])

func target(index: int, now: float) -> Array[float]:
	var result := curve_at(_progress(index, now))
	for axis in range(3):
		var a := sin((int(route.seed) % 9973) * 0.0007 + index * 12.9898 + axis * 78.233) * 43758.5453
		var phase: float = a - floor(a)
		var clock := now * float(spec.NOISE_TS[axis]) * 10
		var noise := sin((clock + phase) * TAU) * 0.6 + sin((clock * 1.618 + phase * 3.1) * TAU) * 0.4
		result[axis] += float(spec.NOISE_AMP[axis]) * noise
	return result

func advance(now: float, delta: float) -> void:
	var step := 0.0 if is_nan(delta) else clampf(delta, 0, float(spec.DT_MAX))
	time = now
	var spring := float(route.spring) * step
	var friction := BodyMotionState.friction(float(spec.FRICTION_K), step)
	for index in range(int(route.count)):
		var destination := target(index, now)
		for axis in range(3):
			var j := index * 3 + axis
			# Preserve each source Float32Array compound-assignment rounding boundary.
			velocities[j] = float(velocities[j]) + (destination[axis] - float(positions[j])) * spring
			velocities[j] = float(velocities[j]) * friction
			positions[j] = float(positions[j]) + float(velocities[j]) * step

func snap() -> void:
	for index in range(int(route.count)):
		var destination := target(index, time)
		for axis in range(3):
			positions[index * 3 + axis] = destination[axis]
			velocities[index * 3 + axis] = 0

func heading(index: int) -> Vector3:
	var j := index * 3
	var vx := float(velocities[j])
	var vz := float(velocities[j + 2])
	if vx * vx + vz * vz > 1e-8:
		return Vector3(vx, velocities[j + 1], vz)
	var progress := _progress(index, time)
	var first := curve_at(progress)
	var second := curve_at(progress + 0.01)
	return Vector3(second[0] - first[0], second[1] - first[1], second[2] - first[2])

func wing_angle(index: int, now: float) -> float:
	return sin((now * _truthy_number("WING_HZ", 3.4) + float(wings[index])) * TAU) * _truthy_number("WING_MAX", 0.85)

func tail_angle(index: int, now: float) -> float:
	return sin((now * _truthy_number("TAIL_HZ", 3.0) + float(wings[index])) * TAU) * _truthy_number("TAIL_MAX", 0.5)

func _truthy_number(key: String, fallback: float) -> float:
	return float(spec[key]) if ControlPreferences.truthy(spec.get(key)) else fallback
