class_name WildlifeHabitat
extends RefCounted

var profile: Dictionary
var probe: Callable
var code_at: Callable
var dry_at: Callable
var water_height: Callable

func configure(source: Dictionary, height: Callable, ground_code: Callable, dry_band: Callable, current_water: Callable = Callable()) -> void:
	profile = source
	probe = height
	code_at = ground_code
	dry_at = dry_band
	water_height = current_water

func wet_at(x: float, z: float) -> bool:
	return int(code_at.call(x, z)) == 1 and not bool(dry_at.call(x, z))

func valid_at(x: float, z: float, water_y: Variant) -> bool:
	if int(code_at.call(x, z)) != 0 or occupied(x, z):
		return false
	var surface: Variant = water_height.call() if water_height.is_valid() else water_y
	return surface == null or not is_finite(float(surface)) or float(probe.call(x, z)) > float(surface) or bool(dry_at.call(x, z))

func occupied(x: float, z: float) -> bool:
	# The source freezes this footprint index when constructing the flocks.
	var cell := float(profile.cell)
	var seen := {}
	for row in range(floori((z - 0.5) / cell), floori((z + 0.5) / cell) + 1):
		for column in range(floori((x - 0.5) / cell), floori((x + 0.5) / cell) + 1):
			for id: Variant in profile.grid.get("%d,%d" % [column, row], []):
				var index := int(id)
				if seen.has(index):
					continue
				seen[index] = true
				var foot: Dictionary = profile.feet[index]
				var dx := x - float(foot.x)
				var dz := z - float(foot.z)
				if ControlPreferences.truthy(foot.get("hd")):
					var ca := cos(float(foot.ry))
					var sa := sin(float(foot.ry))
					var ex := maxf(0, absf(dx * ca + dz * sa) - float(foot.hw))
					var ez := maxf(0, absf(-dx * sa + dz * ca) - float(foot.hd))
					if sqrt(ex * ex + ez * ez) < 0.5:
						return true
				elif sqrt(dx * dx + dz * dz) < float(foot.r) + 0.5:
					return true
	return false
