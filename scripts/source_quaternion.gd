class_name SourceQuaternion
extends RefCounted

static func inverse(value: Quaternion) -> Quaternion:
	return Quaternion(-value.x, -value.y, -value.z, value.w)

static func multiply(first: Quaternion, second: Quaternion) -> Quaternion:
	var ax := float(first.x)
	var ay := float(first.y)
	var az := float(first.z)
	var aw := float(first.w)
	var bx := float(second.x)
	var by := float(second.y)
	var bz := float(second.z)
	var bw := float(second.w)
	return Quaternion(ax * bw + aw * bx + ay * bz - az * by, ay * bw + aw * by + az * bx - ax * bz,
		az * bw + aw * bz + ax * by - ay * bx, aw * bw - ax * bx - ay * by - az * bz)

static func normalized(value: Quaternion) -> Quaternion:
	return _normalized(value.x, value.y, value.z, value.w)

static func _normalized(x: float, y: float, z: float, w: float) -> Quaternion:
	var length := sqrt(x * x + y * y + z * z + w * w)
	if length == 0:
		return Quaternion.IDENTITY
	var reciprocal := 1 / length
	return Quaternion(x * reciprocal, y * reciprocal, z * reciprocal, w * reciprocal)

static func axis_angle(axis: Vector3, angle: float) -> Quaternion:
	var sine := sin(angle / 2)
	return Quaternion(float(axis.x) * sine, float(axis.y) * sine, float(axis.z) * sine, cos(angle / 2))

static func from_unit_vectors(first: Vector3, second: Vector3) -> Quaternion:
	var ax := float(first.x)
	var ay := float(first.y)
	var az := float(first.z)
	var bx := float(second.x)
	var by := float(second.y)
	var bz := float(second.z)
	var real := ax * bx + ay * by + az * bz + 1
	if real < float(Content.balance.bodyRules.rotation.numberEpsilon):
		return _normalized(-ay, ax, 0, 0) if absf(ax) > absf(az) else _normalized(0, -az, ay, 0)
	return _normalized(ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx, real)

static func slerp(first: Quaternion, second: Quaternion, weight: float) -> Quaternion:
	if weight == 0:
		return first
	if weight == 1:
		return second
	var x := float(first.x)
	var y := float(first.y)
	var z := float(first.z)
	var w := float(first.w)
	var tx := float(second.x)
	var ty := float(second.y)
	var tz := float(second.z)
	var tw := float(second.w)
	var dot := w * tw + x * tx + y * ty + z * tz
	if dot < 0:
		tx = -tx
		ty = -ty
		tz = -tz
		tw = -tw
		dot = -dot
	if dot >= 1:
		return first
	var sine_squared := 1 - dot * dot
	if sine_squared <= float(Content.balance.bodyRules.rotation.numberEpsilon):
		return _normalized((1 - weight) * x + weight * tx, (1 - weight) * y + weight * ty,
			(1 - weight) * z + weight * tz, (1 - weight) * w + weight * tw)
	var sine := sqrt(sine_squared)
	var angle := atan2(sine, dot)
	var left := sin((1 - weight) * angle) / sine
	var right := sin(weight * angle) / sine
	return Quaternion(x * left + tx * right, y * left + ty * right, z * left + tz * right, w * left + tw * right)

static func rotate(value: Quaternion, point: Vector3) -> Vector3:
	var x := float(point.x)
	var y := float(point.y)
	var z := float(point.z)
	var qx := float(value.x)
	var qy := float(value.y)
	var qz := float(value.z)
	var qw := float(value.w)
	var tx := 2 * (qy * z - qz * y)
	var ty := 2 * (qz * x - qx * z)
	var tz := 2 * (qx * y - qy * x)
	return Vector3(x + qw * tx + qy * tz - qz * ty, y + qw * ty + qz * tx - qx * tz, z + qw * tz + qx * ty - qy * tx)

static func basis(value: Quaternion) -> Basis:
	# Source compose accepts non-unit quaternions; avoid native normalization/decomposition.
	var x := float(value.x)
	var y := float(value.y)
	var z := float(value.z)
	var w := float(value.w)
	var x2 := x + x
	var y2 := y + y
	var z2 := z + z
	var xx := x * x2
	var xy := x * y2
	var xz := x * z2
	var yy := y * y2
	var yz := y * z2
	var zz := z * z2
	var wx := w * x2
	var wy := w * y2
	var wz := w * z2
	return Basis(Vector3(1 - (yy + zz), xy + wz, xz - wy), Vector3(xy - wz, 1 - (xx + zz), yz + wx),
		Vector3(xz + wy, yz - wx, 1 - (xx + yy)))

static func world(node: Node3D) -> Quaternion:
	return from_basis(node.global_transform.basis)

static func from_basis(value: Basis) -> Quaternion:
	var x := vector_length(value.x)
	var y := vector_length(value.y)
	var z := vector_length(value.z)
	var a := float(value.x.x)
	var b := float(value.y.x)
	var c := float(value.z.x)
	var d := float(value.x.y)
	var e := float(value.y.y)
	var f := float(value.z.y)
	var g := float(value.x.z)
	var h := float(value.y.z)
	var i := float(value.z.z)
	var determinant := a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
	if determinant < 0:
		x = -x
	return from_scaled(value, [x, y, z])

static func from_scaled(value: Basis, scale_values: Array) -> Quaternion:
	var x := INF if float(scale_values[0]) == 0 else 1 / float(scale_values[0])
	var y := INF if float(scale_values[1]) == 0 else 1 / float(scale_values[1])
	var z := INF if float(scale_values[2]) == 0 else 1 / float(scale_values[2])
	return from_matrix([float(value.x.x) * x, float(value.y.x) * y, float(value.z.x) * z,
		float(value.x.y) * x, float(value.y.y) * y, float(value.z.y) * z, float(value.x.z) * x, float(value.y.z) * y, float(value.z.z) * z])

static func vector_length(value: Vector3) -> float:
	return sqrt(float(value.x) * float(value.x) + float(value.y) * float(value.y) + float(value.z) * float(value.z))

static func vector_dot(first: Vector3, second: Vector3) -> float:
	return float(first.x) * float(second.x) + float(first.y) * float(second.y) + float(first.z) * float(second.z)

static func vector_normalized(value: Vector3) -> Vector3:
	var length := vector_length(value)
	var reciprocal := 1.0 if length == 0 or is_nan(length) else 1 / length
	return Vector3(float(value.x) * reciprocal, float(value.y) * reciprocal, float(value.z) * reciprocal)

static func from_matrix(matrix: Array) -> Quaternion:
	var a: float = matrix[0]
	var b: float = matrix[1]
	var c: float = matrix[2]
	var d: float = matrix[3]
	var e: float = matrix[4]
	var f: float = matrix[5]
	var g: float = matrix[6]
	var h: float = matrix[7]
	var i: float = matrix[8]
	var trace := a + e + i
	if trace > 0:
		var factor := 0.5 / sqrt(trace + 1)
		return Quaternion((h - f) * factor, (c - g) * factor, (d - b) * factor, 0.25 / factor)
	if a > e and a > i:
		var factor := 2 * sqrt(1 + a - e - i)
		return Quaternion(0.25 * factor, (b + d) / factor, (c + g) / factor, (h - f) / factor)
	if e > i:
		var factor := 2 * sqrt(1 + e - a - i)
		return Quaternion((b + d) / factor, 0.25 * factor, (f + h) / factor, (c - g) / factor)
	var factor := 2 * sqrt(1 + i - a - e)
	return Quaternion((c + g) / factor, (f + h) / factor, 0.25 * factor, (d - b) / factor)
