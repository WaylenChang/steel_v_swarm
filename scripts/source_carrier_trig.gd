extends RefCounted

# Bounded launch-angle adaptation of V8's fdlibm kernels and argument reduction.
# https://github.com/nodejs/node/blob/v24.19.0/deps/v8/src/base/ieee754.cc
# Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
# Developed at SunSoft, a Sun Microsystems, Inc. business.
# Permission to use, copy, modify, and distribute this software is freely
# granted, provided that this notice is preserved.
# Modified significantly by Google Inc. Copyright 2016 the V8 project authors.

# Exact source words avoid GDScript decimal-literal rounding before evaluation.
static var P1 := from_words(0x3ff921fb, 0x54400000)
static var T1 := from_words(0x3dd0b461, 0x1a626331)
static var P2 := from_words(0x3dd0b461, 0x1a600000)
static var T2 := from_words(0x3ba3198a, 0x2e037073)
static var P3 := from_words(0x3ba3198a, 0x2e000000)
static var T3 := from_words(0x397b839a, 0x252049c1)
static var INV_PI_2 := from_words(0x3fe45f30, 0x6dc9c883)
static var S1 := from_words(0xbfc55555, 0x55555549)
static var S2 := from_words(0x3f811111, 0x1110f8a6)
static var S3 := from_words(0xbf2a01a0, 0x19c161d5)
static var S4 := from_words(0x3ec71de3, 0x57b1fe7d)
static var S5 := from_words(0xbe5ae5e6, 0x8a2b9ceb)
static var S6 := from_words(0x3de5d93a, 0x5acfd57c)
static var C1 := from_words(0x3fa55555, 0x5555554c)
static var C2 := from_words(0xbf56c16c, 0x16c15177)
static var C3 := from_words(0x3efa01a0, 0x19cb1590)
static var C4 := from_words(0xbe927e4f, 0x809c52ad)
static var C5 := from_words(0x3e21ee9e, 0xbdb4b1c4)
static var C6 := from_words(0xbda8fae9, 0xbe8838d4)

static func from_words(upper: int, lower: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(0, lower)
	bytes.encode_u32(4, upper)
	return bytes.decode_double(0)

static func high(value: float) -> int:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.decode_u32(4) & 0x7fffffff

static func from_high(word: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(4, word)
	return bytes.decode_double(0)

static func reduce(angle: float) -> Dictionary:
	# All active carrier scatter producers supply a finite angle within one turn.
	if not is_finite(angle) or absf(angle) > TAU + .5:
		push_error("Carrier scatter angle is outside the source launch domain")
		return {"n": 0, "x": NAN, "y": NAN}
	var ix := high(angle)
	if ix <= 0x3fe921fb:
		return {"n": 0, "x": angle, "y": 0.0}
	var negative := angle < 0
	var t := absf(angle)
	if ix < 0x4002d97c:
		var z := t - P1
		var tail := T1
		if ix == 0x3ff921fb:
			z -= P2
			tail = T2
		var x := z - tail
		var y := (z - x) - tail
		return {"n": -1 if negative else 1, "x": -x if negative else x, "y": -y if negative else y}
	var n := int(t * INV_PI_2 + .5)
	var fn := float(n)
	var r := t - fn * P1
	var w := fn * T1
	var x := r - w
	var multiples := [0x3ff921fb, 0x400921fb, 0x4012d97c, 0x401921fb]
	if ix == multiples[n - 1] and (ix >> 20) - ((high(x) >> 20) & 0x7ff) > 16:
		t = r
		w = fn * P2
		r = t - w
		w = fn * T2 - ((t - r) - w)
		x = r - w
		if (ix >> 20) - ((high(x) >> 20) & 0x7ff) > 49:
			t = r
			w = fn * P3
			r = t - w
			w = fn * T3 - ((t - r) - w)
			x = r - w
	var y := (r - x) - w
	return {"n": -n if negative else n, "x": -x if negative else x, "y": -y if negative else y}

static func kernel_sin(x: float, y: float, reduced: bool) -> float:
	if high(x) < 0x3e400000:
		return x
	var z := x * x
	var v := z * x
	var r := S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
	if not reduced:
		return x + v * (S1 + z * r)
	return x - ((z * (.5 * y - v * r) - y) - v * S1)

static func kernel_cos(x: float, y: float) -> float:
	var ix := high(x)
	if ix < 0x3e400000:
		return 1.0
	var z := x * x
	var r := z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
	if ix < 0x3fd33333:
		return 1.0 - (.5 * z - (z * r - x * y))
	var qx := .28125 if ix > 0x3fe90000 else from_high(ix - 0x00200000)
	var iz := .5 * z - qx
	var a := 1.0 - qx
	return a - (iz - (z * r - x * y))

static func sine(angle: float) -> float:
	var value := reduce(angle)
	match int(value.n) & 3:
		0: return kernel_sin(value.x, value.y, value.n != 0)
		1: return kernel_cos(value.x, value.y)
		2: return -kernel_sin(value.x, value.y, true)
		_: return -kernel_cos(value.x, value.y)

static func cosine(angle: float) -> float:
	var value := reduce(angle)
	match int(value.n) & 3:
		0: return kernel_cos(value.x, value.y)
		1: return -kernel_sin(value.x, value.y, true)
		2: return -kernel_cos(value.x, value.y)
		_: return kernel_sin(value.x, value.y, true)
