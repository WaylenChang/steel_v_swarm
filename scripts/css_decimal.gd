class_name CssDecimal
extends RefCounted

static func fixed(value: float, digits: int) -> float:
	assert(is_finite(value) and absf(value) < 1e12 and digits >= 0 and digits <= 3, "CSS splat serialization requires bounded finite numbers")
	# toFixed rounds the exact binary value; multiplying by 10 first changes half-ties.
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, absf(value))
	var bits := bytes.decode_u64(0)
	var exponent := int((bits >> 52) & 0x7ff)
	var significand := bits & 0xfffffffffffff
	if exponent != 0:
		significand |= 1 << 52
	var power := (-1074 if exponent == 0 else exponent - 1075) + digits
	for index in range(digits):
		significand *= 5
	var integer := 0
	if power >= 0:
		integer = significand << power
	elif -power <= 62:
		var shift := -power
		integer = significand >> shift
		if (significand & ((1 << shift) - 1)) >= (1 << (shift - 1)):
			integer += 1
	var result := float(integer) / pow(10.0, digits)
	return -result if value < 0 else result
