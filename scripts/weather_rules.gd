class_name WeatherRules
extends RefCounted

static func resolve_environment(environment: Dictionary, next_random: Callable) -> Dictionary:
	var season := _pick_environment(Content.constants.ENV.seasons, environment.get("season"), next_random)
	var lunar = environment.get("lunarDay")
	if not (lunar is int or lunar is float) or not is_finite(float(lunar)) or float(lunar) != floorf(float(lunar)) or float(lunar) < 1 or float(lunar) > 30:
		lunar = int(floorf(float(next_random.call()) * 30)) + 1
	var time := _pick_environment(Content.constants.ENV.times, environment.get("time"), next_random)
	var weather = environment.get("weather")
	if not weather is String or not Content.constants.ENV.weathers.has(weather):
		weather = pick_seasonal_weather(season, float(next_random.call()))
	return {"season": season, "lunarDay": int(lunar), "time": time, "weather": weather}

static func _pick_environment(choices: Dictionary, requested: Variant, next_random: Callable) -> String:
	if requested is String and choices.has(requested):
		return requested
	var keys := choices.keys()
	return keys[int(floorf(float(next_random.call()) * keys.size()))]

static func pick_seasonal_weather(season: String, roll: float) -> String:
	# A supplied source roll and strict boundaries must remain observable to fixtures.
	var all_weights: Dictionary = Content.constants.SEASON_WEATHER_WEIGHTS
	var weights: Dictionary = all_weights.get(season, all_weights.summer)
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	var remaining := roll * total
	for weather: String in weights:
		if remaining < float(weights[weather]):
			return weather
		remaining -= float(weights[weather])
	return weights.keys()[0]

# Climate uses scalar doubles and its own seed; it never advances combat RNG.
static func solar_schedule(season: String = "summer", latitude: float = 25.0, rotation: float = 0.0, lunar_day: int = 15) -> Dictionary:
	var declination := {"spring": 0.0, "summer": 23.44, "autumn": 0.0, "winter": -23.44}
	var lat := clampf(latitude, -65, 65) if is_finite(latitude) else 25.0
	var phi := deg_to_rad(lat)
	var declination_angle := deg_to_rad(float(declination.get(season, 23.44)))
	var half_day := acos(clampf(-tan(phi) * tan(declination_angle), -0.92, 0.92)) / PI * 12
	var rise := 12 - half_day
	var sunset := 12 + half_day
	var twilight := 1 + 0.6 * absf(lat) / 60
	var day := lunar_day if lunar_day >= 1 and lunar_day <= 30 else 15
	return {"season": season, "latDeg": lat, "phi": phi, "delta": declination_angle, "riseH": rise,
		"setH": sunset, "twilightH": twilight, "halfDayH": half_day, "rot": rotation if is_finite(rotation) else 0.0,
		"phaseH": {"dawn": snappedf(rise, 0.01), "day": 12.0, "dusk": snappedf(sunset, 0.01), "night": snappedf(fposmod(sunset + twilight + 1.5, 24), 0.01)},
		"startH": {"dawn": snappedf(fposmod(rise - twilight * 0.75 + 24, 24), 0.01), "day": snappedf(rise + (12 - rise) * 0.4, 0.01),
			"dusk": snappedf(sunset - twilight * 0.5, 0.01), "night": snappedf(sunset + twilight + 0.5, 0.01)},
		"lunarDay": day, "lunarPhaseAngle": (day - 1) / 29.53059 * TAU, "lunarHourOffset": (day - 1) / 29.53059 * 24}

static func clock_hour(start: String, elapsed: float, schedule: Dictionary = {}) -> float:
	var defaults: Dictionary = Content.constants.DAYCLOCK.START_H
	var starts: Dictionary = schedule.get("startH", defaults)
	return fposmod(float(starts.get(start, defaults.get(start, defaults.day))) + elapsed * float(Content.constants.DAYCLOCK.GAME_H) / Content.constants.DAYCLOCK.REAL_S, 24)

static func phase_blend(hour: float, anchors: Dictionary = {}) -> Dictionary:
	if anchors.is_empty():
		anchors = Content.constants.DAYCLOCK.PHASE_H
	var keys := anchors.keys()
	keys.sort_custom(func(a, b): return float(anchors[a]) < float(anchors[b]))
	var h := fposmod(hour, 24)
	for index in range(keys.size()):
		var a: String = keys[index]
		var b: String = keys[(index + 1) % keys.size()]
		var begin: float = anchors[a]
		var end: float = anchors[b] if float(anchors[b]) > begin else float(anchors[b]) + 24
		var x := h if h >= begin else h + 24
		if x <= end:
			var fraction := (x - begin) / (end - begin)
			return {"a": a, "b": b, "t": fraction * fraction * (3 - 2 * fraction)}
	return {"a": keys[0], "b": keys[0], "t": 0.0}

static func vector_at(season: String, start: String, preset: String, elapsed: float, seed: int, latitude: float) -> Dictionary:
	var biases: Dictionary = Content.constants.SEASON_TIME_BIAS
	var selected := season if biases.has(season) else "summer"
	var presets: Dictionary = Content.constants.WEATHER_PRESETS
	var initial: Dictionary = presets.get(preset, presets.clear).duplicate()
	if preset in ["storm", "windy"]:
		var companions: Dictionary = Content.constants.STORM_SEASON_COMPANION if preset == "storm" else Content.constants.WINDY_SEASON_COMPANION
		var companion: Variant = companions.get(selected)
		if companion is String and presets.has(companion):
			for key: String in ["rain", "snow", "sand"]:
				initial[key] = presets[companion][key] if companion == {"rain": "heavy_rain", "snow": "snow", "sand": "sandstorm"}[key] else 0.0
			if preset == "windy" and companion in ["heavy_rain", "snow"]:
				initial.clouds = 64.0
	var schedule := solar_schedule(selected, latitude)
	# The original authority has no client-global solar schedule: climate bias uses fixed phase anchors.
	var phase := phase_blend(clock_hour(start, elapsed, schedule))
	var a: Dictionary = biases[selected][phase.a]
	var b: Dictionary = biases[selected][phase.b]
	var relax := 1 - exp(-maxf(0, elapsed) / 240)
	var seed_number := float(seed & 0xffffffff)
	var result := {}
	var attributes: Array = Content.constants.WEATHER_ATTRS
	for index in range(attributes.size()):
		var key: String = attributes[index]
		var p1 := fmod(seed_number * 0.137 + index * 7.19, 6.28318)
		var p2 := fmod(seed_number * 0.281 + index * 13.41, 6.28318)
		var p3 := fmod(seed_number * 0.493 + index * 23.77, 6.28318)
		var noise := sin(elapsed * 0.015 + p1) * 7.5 + sin(elapsed * 0.037 + p2) * 4.5 + sin(elapsed * 0.091 + p3) * 2.5
		var mean := float(a[key]) + (float(b[key]) - float(a[key])) * float(phase.t)
		var base := float(initial.get(key, 0)) + (mean - float(initial.get(key, 0))) * relax + noise * minf(1, relax + 0.15)
		var period := 160.0 + index * 26
		var dwell := sin(elapsed * (6.28318 / period) + fmod(seed_number * 0.191 + index * 5.37, 6.28318)) * 0.70
		dwell += sin(elapsed * (6.28318 / (period * 0.47)) + fmod(seed_number * 0.383 + index * 11.23, 6.28318)) * 0.30
		var rebound := 0.0
		if base > 55:
			rebound = -pow((base - 50) / 50, 1.5) * 16 * maxf(0, dwell + 0.35)
		elif base < 45:
			rebound = pow((50 - base) / 50, 1.5) * 16 * maxf(0, -dwell + 0.35)
		result[key] = clampf(snappedf(base + rebound * minf(1, relax + 0.25), 0.01), 0, 100)
	var base_angle := fposmod(seed_number * 47.3, 360)
	var drift := sin(elapsed * 0.008 + fmod(seed_number * 0.31, 6.28)) * 45 + sin(elapsed * 0.021 + fmod(seed_number * 0.73, 6.28)) * 25 + fmod(elapsed * 0.04, 360)
	result.windDirDeg = snappedf(fposmod(base_angle + drift, 360), 0.1)
	return result

static func dynamics(vector: Dictionary, previous: Dictionary = {}, delta: float = 0.0) -> Dictionary:
	var v: Dictionary = vector if not vector.is_empty() else Content.constants.WEATHER_PRESETS.clear
	var result := {}
	for key: String in Content.constants.WEATHER_ATTRS:
		result[key] = float(v.get(key, 0))
	result.windDirDeg = float(v.get("windDirDeg", 45))
	result.isDarkCloud = result.clouds > 50
	result.cloudDarkness = minf(1, (float(result.clouds) - 50) / 50) if result.isDarkCloud else 0.0
	result.effectiveRain = (float(result.rain) - 75) / 25 * float(result.cloudDarkness) if result.rain >= 75 and result.isDarkCloud else 0.0
	result.effectiveSnow = (float(result.snow) - 75) / 25 * float(result.cloudDarkness) if result.snow >= 75 and result.isDarkCloud else 0.0
	result.effectiveSand = (float(result.sand) - 75) / 25 if result.sand >= 75 else 0.0
	var target_freeze := clampf(maxf(result.effectiveSnow, (float(result.snow) - 60) / 30), 0, 1)
	var freeze := target_freeze
	var hold := float(previous.get("thawHoldS", 18.0 if target_freeze >= 0.80 else 0.0))
	if previous.has("freezeFactor") and delta > 0:
		var old: float = previous.freezeFactor
		if target_freeze >= old:
			freeze = minf(target_freeze, old + delta * 0.45)
			if freeze >= 0.80:
				hold = 18.0
		elif hold > 0:
			if delta <= hold:
				hold -= delta
				freeze = old
			else:
				freeze = maxf(target_freeze, old - (delta - hold) * 0.12)
				hold = 0.0
		else:
			freeze = maxf(target_freeze, old - delta * 0.12)
	result.freezeFactor = freeze
	result.thawHoldS = hold
	result.isFrozen = freeze >= 0.98
	result.effectiveThunder = (float(result.thunder) - 75) / 25 if result.thunder >= 75 else 0.0
	result.effectiveFog = clampf((float(result.fog) - 75) / 25, 0, 1)
	result.windAmp = 0.5 + float(result.wind) / 100 * 2.2
	result.windFreq = 0.7 + float(result.wind) / 100 * 1.3
	result.waveAmp = 0.0 if result.isFrozen else (0.4 + float(result.wind) / 100 * 2) * (1 - freeze)
	result.waveSpeed = 0.0 if result.isFrozen else (0.5 + float(result.wind) / 100 * 1.6) * (1 - freeze)
	result.fogNear = maxf(0.02, 0.55 - float(result.effectiveFog) * 0.51)
	result.fogFar = maxf(0.25, 1.90 - float(result.effectiveFog) * 1.60)
	result.light = maxf(0.18, 1 - float(result.clouds) / 100 * 0.50 - float(result.effectiveFog) * 0.20 - float(result.effectiveRain) * 0.15 - float(result.effectiveSand) * 0.15)
	var angle := deg_to_rad(float(result.windDirDeg))
	result.windDir = [cos(angle), sin(angle)]
	result.windDirServer = [cos(angle), -sin(angle)]
	result.dominantWeather = "snow" if result.isFrozen or result.effectiveSnow > 0.4 else "sandstorm" if result.effectiveSand > 0.4 else "storm" if result.effectiveThunder > 0.4 else "heavy_rain" if result.effectiveRain > 0.4 else "fog" if result.effectiveFog > 0.4 else "windy" if result.wind > 70 else "cloudy" if result.clouds > 50 else "clear"
	var cfg: Dictionary = Content.constants.WEATHER_DEBUFFS
	for key: String in ["wind", "rain", "sand", "snow", "thunder"]:
		result[key + "Intensity"] = (float(result[key]) - float(cfg.THRESHOLD)) / (100 - float(cfg.THRESHOLD)) if float(result[key]) > float(cfg.THRESHOLD) else 0.0
	result.snowCdMul = 1 + float(cfg.MAX_CHANGE) * float(result.snowIntensity)
	result.sandRateMul = 1 - float(cfg.MAX_CHANGE) * float(result.sandIntensity)
	result.rainAtkMul = 1 - float(cfg.MAX_CHANGE) * float(result.rainIntensity)
	return result

static func surface_step(previous: Dictionary = {}, dyn: Dictionary = {}, delta: float = 0.0) -> Dictionary:
	var seconds := maxf(0, delta) if is_finite(delta) else 0.0
	var cfg: Dictionary = Content.balance.weather.surface
	var wind := _cover_clamp(float(dyn.get("wind", 0)) / 100)
	var result := {}
	for key: String in ["water", "snow", "sand"]:
		var attribute := "Rain" if key == "water" else key.capitalize()
		var intensity := _cover_clamp(float(dyn.get("effective" + attribute, 0)))
		var fill: float = cfg.rainS if key == "water" else cfg.snowS if key == "snow" else cfg.sandS
		var dry: float = cfg.drainS if key == "water" else cfg.meltS if key == "snow" else float(cfg.disperseS) / (1 + wind * 4)
		var capacity := 1.0 if key == "snow" and intensity > 0 else intensity
		var rate := intensity / fill if intensity > 0 else 1 / dry
		result[key] = _cover_clamp(capacity + (_cover_clamp(float(previous.get(key, 0))) - capacity) * exp(-seconds * rate))
	return result

static func _cover_clamp(value: float) -> float:
	return clampf(value, 0, 1) if is_finite(value) else 0.0

static func surface_cover(value: float) -> float:
	var delay: float = Content.balance.weather.surface.delay
	return _cover_clamp((_cover_clamp(value) - delay) / (1 - delay))

static func ground_speed(surface: Dictionary) -> float:
	return 1 - 0.125 * maxf(surface_cover(float(surface.get("water", surface.get("puddle", 0)))), maxf(surface_cover(float(surface.get("snow", 0))), surface_cover(float(surface.get("sand", surface.get("dune", 0))))))

static func jump_velocity(surface: Dictionary) -> float:
	return sqrt(ground_speed(surface))

static func ground_rate(surface: Dictionary) -> float:
	return 1 - 0.125 * surface_cover(float(surface.get("sand", surface.get("dune", 0))))

static func _air_intensity(dyn: Dictionary, key: String) -> float:
	var title := key.capitalize()
	var raw := (float(dyn.get(key, 0)) - 75) / 25 if float(dyn.get(key, 0)) > 75 else 0.0
	return float(dyn.get(key + "Slow", dyn.get(key + "Intensity", dyn.get("effective" + title, raw))))

static func air_lift(dyn: Dictionary) -> float:
	return 1 - float(Content.constants.WEATHER_DEBUFFS.AIR_LIFT_SLOW_MAX) * clampf(maxf(_air_intensity(dyn, "rain"), maxf(_air_intensity(dyn, "snow"), _air_intensity(dyn, "sand"))), 0, 1)

static func air_rate(dyn: Dictionary) -> float:
	return 1 - float(Content.constants.WEATHER_DEBUFFS.MAX_CHANGE) * clampf(_air_intensity(dyn, "sand"), 0, 1)

static func wind_speed(x: float, z: float, direction: Array, wind: float) -> float:
	var cfg: Dictionary = Content.constants.WEATHER_DEBUFFS
	var distance := sqrt(x * x + z * z)
	if wind <= float(cfg.THRESHOLD) or distance < 0.001:
		return 1.0
	var wx: float = direction[0] if direction.size() > 0 else 1.0
	var wz: float = direction[1] if direction.size() > 1 else 0.0
	var length := sqrt(wx * wx + wz * wz)
	if length == 0:
		length = 1.0
	return 1 + float(cfg.MAX_CHANGE) * clampf((wind - float(cfg.THRESHOLD)) / (100 - float(cfg.THRESHOLD)), 0, 1) * (x * wx + z * wz) / (distance * length)

static func unbalance_threshold(wind: float) -> float:
	return float(Content.constants.TARGET_H.tower) * (1 - 0.5 * clampf((wind - 75) / 25, 0, 1))

static func sun_direction(hour: float, schedule: Dictionary = {}) -> Dictionary:
	var phi := float(schedule.get("phi", deg_to_rad(90 - float(Content.constants.DAYCLOCK.MAX_ELEV_DEG))))
	var declination := float(schedule.get("delta", 0))
	var half_day := 6.0 if schedule.is_empty() else (float(schedule.setH) - float(schedule.riseH)) / 2
	if half_day == 0:
		half_day = 6.0
	var angle := PI / 2 * (hour - 12) / half_day
	var x := -cos(declination) * sin(angle)
	var y := sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(angle)
	var z := sin(phi) * cos(declination) * cos(angle) - cos(phi) * sin(declination)
	var length := sqrt(x * x + y * y + z * z)
	if length == 0:
		length = 1.0
	var rotation: float = schedule.get("rot", 0)
	return {"x": (x * cos(rotation) - z * sin(rotation)) / length, "y": y / length, "z": (x * sin(rotation) + z * cos(rotation)) / length}

static func moon_direction(hour: float, lunar_day: float, schedule: Dictionary = {}) -> Dictionary:
	var day := clampf(lunar_day, 1, 30) if is_finite(lunar_day) else 15.0
	return sun_direction(hour + 12 if day == 15 else fposmod(hour - (day - 1) / 29.53059 * 24, 24), schedule)

static func accuracy_penalty(fog: float, hour: float, schedule: Dictionary = {}) -> float:
	var maximum: float = Content.constants.WEATHER_ACCURACY.MAX_PENALTY
	# The source server's sun helper uses its offline orbit even with explicit rise/set arguments.
	var sun := sun_direction(hour)
	var night := 0.0
	if sun.y <= 0:
		var day: float = schedule.get("lunarDay", 15)
		var moon := moon_direction(hour, day)
		var illumination := (1 - cos((day - 1) / 29.53059 * TAU)) / 2
		var light := minf(1, float(moon.y) / 0.5) * illumination if moon.y > 0 else 0.0
		night = maximum * maxf(0, minf(1, maxf(0, -float(sun.y)) / 0.7) * (1 - light))
	return minf(maximum, maximum * clampf(fog, 0, 1) + night)

static func _ramp(begin: float, end: float, value: float) -> float:
	var t := _cover_clamp((value - begin) / (end - begin))
	return t * t * (3 - 2 * t)

static func wind_profile(dyn: Dictionary) -> Vector4:
	var wind := _cover_clamp(float(dyn.get("wind", 0)) / 100)
	return Vector4(_ramp(0.25, 0.9, wind) * 0.85, _ramp(0.45, 1, wind) * 0.16,
		lerpf(0.18, 1, wind), lerpf(0.55, 1.7, wind))

static func water_profile(dyn: Dictionary) -> Vector4:
	var wind := _cover_clamp(float(dyn.get("wind", 0)) / 100)
	return Vector4(_ramp(0.3, 1, wind) * 0.65, lerpf(0.08, 0.3, wind),
		_ramp(0.35, 0.95, wind), _ramp(0.5, 1, wind) * 0.55)

static func particle_profiles(dyn: Dictionary) -> Dictionary:
	var wind := _cover_clamp(float(dyn.get("wind", 0)) / 100)
	var profiles := {}
	for kind: String in ["rain", "snow", "sand"]:
		var strength := _cover_clamp(float(dyn.get("effective" + kind.capitalize(), 0)))
		var gust := _ramp(0.35, 1, strength) * wind
		var p := {"strength": strength, "density": pow(strength, 0.8), "opacity": lerpf(0.18, 0.78, sqrt(strength)) if strength > 0 else 0.0, "gust": gust}
		if kind == "rain":
			p.merge({"speed": lerpf(38, 95, strength), "width": lerpf(0.025, 0.065, strength), "size": lerpf(0.5, 2.8, strength),
				"drift": lerpf(3, 30, wind), "turbulence": gust * 1.8, "veil": _ramp(0.4, 1, strength) * 0.23})
		elif kind == "snow":
			p.merge({"speed": lerpf(2.5, 8, strength), "width": 1.0, "size": lerpf(0.22, 0.65, strength) * (1 - gust * 0.45),
				"drift": lerpf(0.5, 18, wind) * lerpf(0.5, 1.4, strength), "turbulence": lerpf(1, 5, strength) + gust * 4,
				"veil": _ramp(0.45, 1, strength) * 0.3, "fine": _ramp(0.35, 1, strength)})
		else:
			p.merge({"speed": lerpf(1.5, 4, strength), "width": lerpf(1, 2.8, gust), "size": lerpf(0.09, 0.28, strength),
				"drift": lerpf(5, 35, strength) * lerpf(0.6, 1.4, wind), "turbulence": lerpf(1, 8, strength), "veil": _ramp(0.2, 1, strength) * 0.22})
		profiles[kind] = p
	return profiles

static func wildlife_activity(dyn: Dictionary) -> float:
	var strength := _cover_clamp(float(dyn.get("wind", 0)) / 100) * 0.8
	for key: String in ["effectiveRain", "effectiveSnow", "effectiveSand"]:
		strength = maxf(strength, _cover_clamp(float(dyn.get(key, 0))))
	return maxf(0.15, 1 - strength)
