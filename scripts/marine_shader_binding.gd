class_name MarineShaderBinding
extends RefCounted

var material: ShaderMaterial
var wind_rules: Dictionary
var heading := Vector2.ZERO
var retired := false

func retire() -> void:
	retired = true
	material = null
	wind_rules = {}

func sync_visuals(preferences: VisualPreferences, appearance: Dictionary) -> void:
	if retired:
		return
	var surface: Dictionary = preferences.selected_preset().surface
	if appearance.school == "b":
		material.set_shader_parameter("uCelCutWidth", float(surface.cutWidth))
		material.set_shader_parameter("uCelShadowV", maxf(float(appearance.shadowFloor), float(appearance.shadowValue) * float(surface.shadowValue)))
	material.set_shader_parameter("uCelRimScale", float(surface.rim))
	var amount := float(preferences.value("shadowEnv"))
	if appearance.school == "b":
		amount = maxf(amount, float(appearance.hueMinimum))
	amount = clampf(amount, 0, appearance.tintMaximum)
	var hue: Array = appearance.shadowHueNormalized
	var tint := Vector3.ONE + (Vector3(hue[0], hue[1], hue[2]) - Vector3.ONE) * amount
	material.set_shader_parameter("uCelRampTint", tint)
	material.set_shader_parameter("uCelWSpread", float(appearance.weatherSpread) * float(preferences.value("weather")))
	material.set_shader_parameter("uFoamA", float(preferences.value("foam")))
	material.set_shader_parameter("uRenderStyle", float(appearance.renderStyles.get(preferences.value("renderStyle"), 0)))

func configure_geometry(values: Array, receive_shadow: bool) -> bool:
	if retired:
		return false
	if values.size() != 16:
		push_error("Missing original marine model matrix")
		return false
	var frame := Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]),
		Vector3(values[8], values[9], values[10])), Vector3(values[12], values[13], values[14]))
	if not frame.is_finite() or is_zero_approx(frame.basis.determinant()):
		push_error("Invalid original marine model matrix")
		return false
	material.set_shader_parameter("uNativeSourceFrame", frame)
	material.set_shader_parameter("uNativeSourceNormal", frame.basis.inverse().transposed())
	material.set_shader_parameter("uNativeReceiveShadow", receive_shadow)
	return true

func sync_lighting(presentation: WeatherPresentation) -> void:
	if retired or presentation == null or presentation.light == null or presentation.environment == null:
		return
	var environment := presentation.environment
	var strength := environment.ambient_light_energy + presentation.flash * 3.5
	var sky := environment.ambient_light_color.srgb_to_linear() * strength
	var ground := presentation.sky_material.ground_bottom_color.srgb_to_linear() * strength
	var key := presentation.light.light_color.srgb_to_linear() * presentation.light.light_energy
	material.set_shader_parameter("uNativeHemiSky", Vector3(sky.r, sky.g, sky.b))
	material.set_shader_parameter("uNativeHemiGround", Vector3(ground.r, ground.g, ground.b))
	material.set_shader_parameter("uNativeKeyColor", Vector3(key.r, key.g, key.b))
	material.set_shader_parameter("uNativeKeyDirection", presentation.light.global_basis.z)

func configure(original: ShaderMaterial, parameters: Dictionary, source: Dictionary, depth_field: Texture2D, initial_ripples := PackedVector4Array()) -> bool:
	if retired:
		return false
	if original == null or original.shader == null or depth_field == null or not parameters.get("uniforms") is Dictionary or not parameters.get("vectors") is Dictionary:
		push_error("Missing original native marine shader/material binding")
		return false
	if not source.get("wind") is Dictionary or not source.get("rect") is Array or source.rect.size() != 4:
		push_error("Missing original marine field rectangle or wind declarations")
		return false
	wind_rules = source.wind
	var direction: Array = parameters.vectors.get("uWindDir", [])
	if direction.size() != 2 or float(wind_rules.get("WAVE_M", 0)) <= 0 or float(wind_rules.get("GUST_M", 0)) <= 0:
		push_error("Invalid original marine wind heading/wavelength")
		return false
	# Shader code/field remain shared; live parameters belong to this scene instance.
	material = original.duplicate()
	var bundle := original.get_meta("source_cel_data", null) as SourceCelData
	var captured := SourceCelData.material_source(original)
	if bundle == null or not captured.get("uniforms") is Dictionary:
		push_error("Missing original typed marine uniforms; regenerate source world materials")
		return false
	var names: Array = parameters.uniforms.keys()
	names.append_array(parameters.vectors.keys())
	if not SourceCelUniforms.bind(material, bundle, captured.uniforms, names):
		return false
	heading = material.get_shader_parameter("uWindDir")
	material.set_shader_parameter("uSeaField", depth_field)
	material.set_shader_parameter("uSeaRect", Vector4(source.rect[0], source.rect[1], source.rect[2], source.rect[3]))
	var waves := MarineWaveSources.new()
	if not waves.configure(int(wind_rules.get("SEA_SOURCE_N", 0)), source.get("sources", []), source.get("shapes", [])):
		return false
	material.set_shader_parameter("uSeaSources", waves.sources)
	material.set_shader_parameter("uSeaSourceShape", waves.shapes)
	var packets := initial_ripples.duplicate()
	if packets.is_empty():
		packets.resize(int(wind_rules.get("SWAMP_RIPPLE_N", 0)))
		packets.fill(Vector4(0, 0, -999, 0))
	material.set_shader_parameter("uRipple", packets)
	return true

func advance(weather: Dictionary, waves: MarineWaveSources, ripples: MarineRippleState) -> void:
	if retired:
		return
	var direction: Variant = weather.get("windDir")
	if direction is Array and direction.size() >= 2:
		heading = Vector2(direction[0], direction[1])
	elif weather.get("windDirDeg") is float or weather.get("windDirDeg") is int:
		var radians := deg_to_rad(float(weather.windDirDeg))
		heading = Vector2(cos(radians), sin(radians))
	material.set_shader_parameter("uWindDir", heading)
	material.set_shader_parameter("uWindK", heading * (TAU / float(wind_rules.WAVE_M)))
	material.set_shader_parameter("uGustK", heading * (TAU / float(wind_rules.GUST_M)))
	for pair in [["uWeatherWindAmp", "windAmp"], ["uWeatherWindFreq", "windFreq"], ["uWeatherWaveAmp", "waveAmp"], ["uWeatherWaveSpeed", "waveSpeed"]]:
		var value: Variant = weather.get(pair[1])
		material.set_shader_parameter(pair[0], 1.0 if value == null else float(value))
	material.set_shader_parameter("uWindT", SceneryPresentation.wind_time)
	material.set_shader_parameter("uWeatherWindT", SceneryPresentation.wind_phase)
	material.set_shader_parameter("uWeatherWaveT", SceneryPresentation.wave_phase)
	material.set_shader_parameter("uWeatherGustT", SceneryPresentation.gust_phase)
	material.set_shader_parameter("uWeatherWindShape", WeatherRules.wind_profile(weather))
	material.set_shader_parameter("uWeatherWaterShape", WeatherRules.water_profile(weather))
	material.set_shader_parameter("uSeaSources", waves.sources)
	material.set_shader_parameter("uSeaSourceShape", waves.shapes)
	material.set_shader_parameter("uRipple", ripples.packets)
