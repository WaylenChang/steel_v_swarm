class_name EnvironmentRules
extends RefCounted

# Original terrain samples follow mesh triangles, rather than bilinear interpolation.
static func height_at(heights: PackedFloat32Array, grid: int, bounds: Dictionary, x: float, z: float) -> float:
	if grid < 2 or heights.size() != grid * grid or not is_finite(x) or not is_finite(z):
		return NAN
	var column := (x - float(bounds.minX)) / (float(bounds.maxX) - float(bounds.minX)) * (grid - 1)
	var row := (z - float(bounds.minZ)) / (float(bounds.maxZ) - float(bounds.minZ)) * (grid - 1)
	var i := clampi(floori(row), 0, grid - 2)
	var j := clampi(floori(column), 0, grid - 2)
	var fi := clampf(row - i, 0, 1)
	var fj := clampf(column - j, 0, 1)
	var a := float(heights[i * grid + j])
	var b := float(heights[i * grid + j + 1])
	var c := float(heights[(i + 1) * grid + j])
	var d := float(heights[(i + 1) * grid + j + 1])
	return a + (b - a) * fj + (c - a) * fi if fi + fj <= 1 else d + (c - d) * (1 - fj) + (b - d) * (1 - fi)

static func in_dry_band(x: float, z: float, profile: Dictionary) -> bool:
	var radius: float = profile.get("radius", 0)
	for segment: Array in profile.get("segments", []):
		var dx := float(segment[2]) - float(segment[0])
		var dz := float(segment[3]) - float(segment[1])
		var square := dx * dx + dz * dz
		var fraction := clampf(((x - float(segment[0])) * dx + (z - float(segment[1])) * dz) / square, 0, 1) if square > 0 else 0.0
		var ox := x - (float(segment[0]) + dx * fraction)
		var oz := z - (float(segment[1]) + dz * fraction)
		if sqrt(ox * ox + oz * oz) <= radius:
			return true
	return false

static func ground_code(height: float, water_y: Variant, color: Array = [], dry: bool = false, border: bool = false) -> int:
	if dry or border:
		return 0
	var blue := color.size() >= 3 and float(color[2]) > float(color[0]) + 14 and float(color[2]) > float(color[1]) + 6
	if (water_y != null and height < float(water_y) + float(Content.constants.WATER.SHORE)) or blue:
		return 1
	var green := color.is_empty() or (float(color[1]) >= float(color[0]) - 4 and float(color[1]) >= float(color[2]) - 4)
	if water_y != null and height < float(water_y) + float(Content.constants.WATER.SWAMP_BAND) and green:
		return 2
	return 0

static func wet_at(grid: Dictionary, x: float, native_z: float) -> int:
	if grid.is_empty() or not is_finite(x) or not is_finite(native_z):
		return 0
	var cell: float = grid.get("cell", 0)
	var columns := int(grid.get("cols", 0))
	var rows := int(grid.get("rows", 0))
	var data: Variant = grid.get("data")
	if cell <= 0 or not is_finite(cell) or columns <= 0 or rows <= 0 or columns * rows > 90000 or not data is String or data.length() < columns * rows:
		return 0
	var column := floori((x - float(grid.minX)) / float(grid.cell))
	var row := floori((-native_z - float(grid.minZ)) / float(grid.cell))
	if row < 0 or column < 0 or row >= int(grid.rows) or column >= int(grid.cols):
		return 0
	var value: int = data.unicode_at(row * columns + column) - 48
	return value if value in [1, 2] else 0

static func trigger(ground: int, water_y: Variant, foot: float, body_height: float, frozen: bool) -> int:
	if ground == 0 or water_y == null:
		return 0
	var plane := float(water_y) + (float(Content.constants.WATER.SWAMP_BAND) if ground != 1 else 0.0)
	if frozen:
		return 3 if foot < plane else 0
	return ground if foot + body_height < plane else 0

static func environment(ground: int, water_y: Variant, foot: float, body_height: float, frozen: bool,
		flying: bool, surface: float, bare: float) -> Dictionary:
	var dry := {"code": 0, "depth": 0.0, "ground": 0, "air": false}
	var plane: Variant = float(water_y) + (float(Content.constants.WATER.SWAMP_BAND) if ground == 2 else 0.0) if water_y != null and ground > 0 else null
	var depth := maxf(0, float(plane) - foot) if plane != null else 0.0
	var code := trigger(ground, water_y, foot, body_height, frozen)
	var wet := {"code": code, "depth": depth, "ground": ground, "air": false}
	if flying:
		return wet if code > 0 else dry
	if foot - surface > float(Content.constants.AIR.OFF_GROUND):
		if code > 0:
			return wet
		dry.air = true
		return dry
	if surface - bare > 1.2:
		return dry
	return wet

static func movement_factor(state: Dictionary, frozen: bool) -> float:
	if int(state.get("ground", 0)) == 0:
		return 1.0
	if int(state.get("code", 0)) > 0:
		return StatusRules.fluid_factor(int(state.code))
	if frozen:
		return 1.0
	var depth: float = state.get("depth", 0)
	if int(state.ground) == 2:
		return minf(1, 1 - (1 - float(Content.constants.TERRAIN_FX.SWAMP_SLOW)) * minf(1, depth / float(Content.constants.WATER.SWAMP_BAND)))
	return minf(Content.constants.WATER.SLOW, 1 - (1 - float(Content.constants.WATER.SLOW_MIN)) * minf(1, depth / float(Content.constants.WATER.FULL_D)))

static func jump_velocity(state: Dictionary, frozen: bool, flying: bool = false, flooded: bool = false) -> float:
	if flying or state.get("air", false):
		return 1.0
	if flooded:
		return sqrt(float(Content.constants.WATER.SLOW))
	return sqrt(movement_factor(state, frozen))

static func ice_surface(surface: float, foot: float, plane: Variant, frozen: bool) -> float:
	if not frozen or plane == null or float(plane) <= surface:
		return surface
	return float(plane) if foot >= float(plane) - float(Content.balance.structure.deckStep) else maxf(surface, foot)

static func ice_ceiling(ceiling: Variant, foot: float, plane: Variant, frozen: bool) -> Variant:
	if frozen and plane != null and foot + 2.0 < float(plane) and (ceiling == null or float(plane) < float(ceiling)):
		return float(plane)
	return ceiling

static func tide(hour: float, lunar_day: float, marine: bool) -> float:
	if not marine:
		return 0.0
	var day := clampf(lunar_day, 1, 30) if is_finite(lunar_day) else 15.0
	var phase := (day - 1) / 29.53059 * TAU
	var modifier := 1 + float(Content.constants.TIDE.SPRING_NEAP_F) * cos(2 * phase)
	var moon_hour := fposmod(hour - (day - 1) / 29.53059 * 24, 24)
	return float(Content.constants.TIDE.BASE_AMP) * modifier * cos((moon_hour - 12) * TAU / 12)

static func fire_multiplier(dynamics: Dictionary) -> float:
	if dynamics.is_empty():
		return 1.0
	var cfg: Dictionary = Content.constants.FIRE_WEATHER
	var rain: float = dynamics.get("rain", 0)
	var snow: float = dynamics.get("snow", 0)
	var wind: float = dynamics.get("wind", 0)
	var rain_quench := (rain - float(cfg.RAIN_QUENCH_T)) / (100 - float(cfg.RAIN_QUENCH_T)) if rain > float(cfg.RAIN_QUENCH_T) else 0.0
	var snow_quench := (snow - float(cfg.SNOW_QUENCH_T)) / (100 - float(cfg.SNOW_QUENCH_T)) if snow > float(cfg.SNOW_QUENCH_T) else 0.0
	var quench := minf(1, maxf(rain_quench, snow_quench))
	if quench >= 1:
		return 0.0
	var boost := (wind - float(cfg.WIND_BOOST_T)) / (100 - float(cfg.WIND_BOOST_T)) if wind > float(cfg.WIND_BOOST_T) else 0.0
	return (1 - quench) * (1 + (float(cfg.WIND_MAX_MUL) - 1) * boost)

static func burn_split(hp: float, shield: float, maximum_hp: float, maximum_shield: float, amount: float, multiplier: float = 1.0) -> Dictionary:
	var total := maximum_hp + maximum_shield
	if total <= 0:
		return {"hp": hp, "shield": shield}
	return {"hp": maxf(0, hp - amount * multiplier * maximum_hp / total), "shield": maxf(0, shield - amount * multiplier * maximum_shield / total)}

static func decode_height_grid(encoded: Dictionary) -> Dictionary:
	var text: Variant = encoded.get("data")
	if not text is String:
		return {}
	var limit := int(Content.constants.LOS.HGT_MAX)
	var columns := clampi(int(floorf(float(encoded.get("cols", 0)) + 0.5)), 1, limit)
	var rows := clampi(int(floorf(float(encoded.get("rows", 0)) + 0.5)), 1, limit)
	var cell: float = encoded.get("cell", 0)
	var min_x: float = encoded.get("minX", NAN)
	var min_z: float = encoded.get("minZ", NAN)
	if not is_finite(cell) or cell <= 0 or not is_finite(min_x) or not is_finite(min_z) or text.length() < columns * rows * 2:
		return {}
	var heights := PackedFloat32Array()
	var alphabet: String = Content.constants.HGT_CHARS
	var minimum: float = encoded.get("minH", 0)
	for index in range(columns * rows):
		var a := alphabet.find(String.chr(text.unicode_at(index * 2) & 127))
		var b := alphabet.find(String.chr(text.unicode_at(index * 2 + 1) & 127))
		if a < 0 or b < 0:
			return {}
		heights.append(minimum + ((a << 6) | b) * float(Content.constants.HGT_STEP))
	return {"minX": min_x, "minZ": min_z, "cell": cell, "cols": columns, "rows": rows, "heights": heights}

static func authority_height(grid: Dictionary, x: float, native_z: float) -> Variant:
	if grid.is_empty():
		return null
	var fx := clampf((x - float(grid.minX)) / float(grid.cell) - 0.5, 0, float(grid.cols) - 1)
	var fz := clampf((-native_z - float(grid.minZ)) / float(grid.cell) - 0.5, 0, float(grid.rows) - 1)
	var i0 := floori(fx)
	var j0 := floori(fz)
	var i1 := mini(int(grid.cols) - 1, i0 + 1)
	var j1 := mini(int(grid.rows) - 1, j0 + 1)
	var tx := fx - i0
	var tz := fz - j0
	var a := float(grid.heights[j0 * int(grid.cols) + i0])
	var b := float(grid.heights[j0 * int(grid.cols) + i1])
	var c := float(grid.heights[j1 * int(grid.cols) + i0])
	var d := float(grid.heights[j1 * int(grid.cols) + i1])
	return (a + (b - a) * tx) * (1 - tz) + (c + (d - c) * tx) * tz

static func surface_strike(random: SourceRng, bounds: Dictionary, height_at: Callable, wet_at: Callable,
		level_at: Callable, obstacles: Array, dynamics: Dictionary, fire_count: int) -> Dictionary:
	var x := float(bounds.minX) + random.next() * (float(bounds.maxX) - float(bounds.minX))
	var z := float(bounds.maxZ) - random.next() * (float(bounds.maxZ) - float(bounds.minZ))
	var ground: Variant = height_at.call(x, z)
	if ground == null or not is_finite(float(ground)) or int(wet_at.call(x, z)) > 0 or int(level_at.call(x, z)) > 0:
		return {}
	var y := float(ground)
	var object := false
	for obstacle: Dictionary in obstacles:
		var data: Array = obstacle.shape
		var dx := x - float(data[0])
		var dz := -z - float(data[1])
		if sqrt(dx * dx + dz * dz) > float(data[2]):
			continue
		if data.size() >= 8 and (absf(dx * float(data[6]) + dz * float(data[7])) > float(data[4]) or absf(-dx * float(data[7]) + dz * float(data[6])) > float(data[5])):
			continue
		var base: Variant = obstacle.get("baseY")
		if base == null:
			base = height_at.call(float(data[0]), -float(data[1]))
		if base == null:
			base = 0.0
		var top := float(base) + float(data[3])
		if top > y:
			y = top
			object = true
	var radius: float = Content.balance.weather.surface.strikeR
	var result := {"x": x, "y": y, "z": z, "radius": radius, "fire": false}
	if object or lightning_fire_wet(dynamics) or fire_count >= 40:
		return result
	for point: Array in [[x - radius, z], [x + radius, z], [x, z - radius], [x, z + radius]]:
		if float(point[0]) < float(bounds.minX) or float(point[0]) > float(bounds.maxX) or float(point[1]) < float(bounds.minZ) or float(point[1]) > float(bounds.maxZ) or int(wet_at.call(point[0], point[1])) > 0 or int(level_at.call(point[0], point[1])) > 0:
			return result
		var sample: Variant = height_at.call(point[0], point[1])
		if sample == null or not is_finite(float(sample)) or absf(float(sample) - float(ground)) / radius > float(Content.balance.weather.surface.flatGrade):
			return result
	result.fire = true
	return result

static func lightning_fire_wet(dynamics: Dictionary) -> bool:
	return float(dynamics.get("effectiveRain", 0)) > 0 or float(dynamics.get("effectiveSnow", 0)) > 0
