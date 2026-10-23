class_name OutlineRules
extends RefCounted

static func unit_width(target: float, rules: Dictionary) -> float:
	var width: Dictionary = rules.unitWidth
	return minf(float(width.maximum), maxf(float(width.minimum), target * float(width.factor)))

static func local_uniforms(basis: Basis, width: float, rules: Dictionary) -> Dictionary:
	var scale := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
	if scale == 0:
		scale = 1
	return {"width": width / scale, "minimum": float(rules.minimumNdc) / scale, "maximum": float(rules.maximumNdc) / scale}

static func displacement(uniforms: Dictionary, depth: float, projection_y: float, style: float, rules: Dictionary) -> float:
	var distance := maxf(float(rules.depthMinimum), depth)
	var projection := maxf(float(rules.projectionMinimum), projection_y)
	var minimum := float(uniforms.minimum) * distance / projection
	var maximum := float(uniforms.maximum) * distance / projection
	return minf(maxf(float(uniforms.width), minimum), maximum) * style
