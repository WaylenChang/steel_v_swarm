class_name SourceEuler
extends RefCounted

const ORDERS := {EULER_ORDER_XYZ: "XYZ", EULER_ORDER_XZY: "XZY", EULER_ORDER_YXZ: "YXZ",
	EULER_ORDER_YZX: "YZX", EULER_ORDER_ZXY: "ZXY", EULER_ORDER_ZYX: "ZYX"}

static func from_quaternion(value: Quaternion, order: String) -> Array:
	# Match the source callback's unscaled matrix, without canonicalizing Euler writes.
	var x := float(value.x)
	var y := float(value.y)
	var z := float(value.z)
	var w := float(value.w)
	var m11 := 1 - 2 * (y * y + z * z)
	var m12 := 2 * (x * y - w * z)
	var m13 := 2 * (x * z + w * y)
	var m21 := 2 * (x * y + w * z)
	var m22 := 1 - 2 * (x * x + z * z)
	var m23 := 2 * (y * z - w * x)
	var m31 := 2 * (x * z - w * y)
	var m32 := 2 * (y * z + w * x)
	var m33 := 1 - 2 * (x * x + y * y)
	var epsilon: float = Content.balance.bodyRules.rotation.gimbal
	var result := [0.0, 0.0, 0.0]
	match order:
		"XYZ":
			result[1] = asin(clampf(m13, -1, 1))
			if absf(m13) < epsilon:
				result[0] = atan2(-m23, m33)
				result[2] = atan2(-m12, m11)
			else:
				result[0] = atan2(m32, m22)
		"YXZ":
			result[0] = asin(-clampf(m23, -1, 1))
			if absf(m23) < epsilon:
				result[1] = atan2(m13, m33)
				result[2] = atan2(m21, m22)
			else:
				result[1] = atan2(-m31, m11)
		"ZXY":
			result[0] = asin(clampf(m32, -1, 1))
			if absf(m32) < epsilon:
				result[1] = atan2(-m31, m33)
				result[2] = atan2(-m12, m22)
			else:
				result[2] = atan2(m21, m11)
		"ZYX":
			result[1] = asin(-clampf(m31, -1, 1))
			if absf(m31) < epsilon:
				result[0] = atan2(m32, m33)
				result[2] = atan2(m21, m11)
			else:
				result[2] = atan2(-m12, m22)
		"YZX":
			result[2] = asin(clampf(m21, -1, 1))
			if absf(m21) < epsilon:
				result[0] = atan2(-m23, m22)
				result[1] = atan2(-m31, m11)
			else:
				result[1] = atan2(m13, m33)
		"XZY":
			result[2] = asin(-clampf(m12, -1, 1))
			if absf(m12) < epsilon:
				result[0] = atan2(m32, m22)
				result[1] = atan2(m13, m11)
			else:
				result[0] = atan2(-m23, m33)
		_:
			assert(false, "Unsupported original Euler rotation order")
	return result
