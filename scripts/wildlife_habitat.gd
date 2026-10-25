class_name WildlifeHabitat
extends RefCounted

var profile: Dictionary
var probe: Callable
var code_at: Callable
var dry_at: Callable
var water_height: Callable
var retired := false

func retire() -> void:
	retired = true
	profile = {}
	probe = Callable()
	code_at = Callable()
	dry_at = Callable()
	water_height = Callable()

func _active(scope: Callable) -> bool:
	return not retired and (not scope.is_valid() or bool(scope.call()))

func configure(source: Dictionary, height: Callable, ground_code: Callable, dry_band: Callable, current_water: Callable = Callable()) -> void:
	if retired:
		return
	profile = source
	probe = height
	code_at = ground_code
	dry_at = dry_band
	water_height = current_water

func wet_at(x: float, z: float, scope: Callable = Callable()) -> bool:
	if not _active(scope):
		return false
	var code := int(code_at.call(x, z))
	if not _active(scope) or code != 1:
		return false
	var dry := bool(dry_at.call(x, z))
	return _active(scope) and not dry

func valid_at(x: float, z: float, water_y: Variant, scope: Callable = Callable()) -> bool:
	if not _active(scope):
		return false
	var code := int(code_at.call(x, z))
	if not _active(scope) or code != 0 or occupied(x, z):
		return false
	var surface: Variant = water_height.call() if water_height.is_valid() else water_y
	if not _active(scope):
		return false
	if surface == null or not is_finite(float(surface)):
		return true
	var ground := float(probe.call(x, z))
	if not _active(scope):
		return false
	if ground > float(surface):
		return true
	var dry := bool(dry_at.call(x, z))
	return _active(scope) and dry

func occupied(x: float, z: float) -> bool:
	if retired:
		return false
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
