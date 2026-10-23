class_name SourceCelData
extends Resource

const MATERIAL_META := ["source_cel", "source_cel_data"]
const IMAGE_FORMATS := {
	"unorm8": [Image.FORMAT_R8, Image.FORMAT_RG8, Image.FORMAT_RGB8, Image.FORMAT_RGBA8],
	"float16": [Image.FORMAT_RH, Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH],
	"float32": [Image.FORMAT_RF, Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF],
}
const SAMPLE_STORAGE := {"unorm8": ["Uint8Array", "Uint8ClampedArray"], "float16": ["Uint16Array"], "float32": ["Float32Array"]}
const SAMPLE_BYTES := {"unorm8": 1, "float16": 2, "float32": 4}

@export var programs: Array = []
@export var samplers: Array = []
@export var material_sources: Array[Dictionary] = []
@export var sampler_images: Array[Image] = []
@export_storage var sampler_textures: Array[Texture2D] = []
@export_storage var configured := false
var _material_ids: Dictionary = {}

func configure(data: Dictionary, textures: SourceTextureImages) -> bool:
	if configured:
		push_error("Original cel data bundles cannot be reconfigured after publication")
		return false
	configured = true
	programs = data.get("celPrograms", [])
	samplers = data.get("celSamplers", [])
	sampler_images = []
	sampler_textures = []
	sampler_textures.resize(samplers.size())
	for program: Dictionary in programs:
		if not program.get("vertex") is String or not program.get("fragment") is String or not program.get("chunks") is Dictionary:
			push_error("Missing original cel shader program/chunks")
			return false
	for sampler: Dictionary in samplers:
		if sampler.get("kind") == "image":
			var index := int(sampler.get("texture", {}).get("image", -1))
			if index < 0 or index >= textures.images.size():
				push_error("Original cel sampler references a missing image")
				return false
			var manual := bool(sampler.texture.get("manualMipmaps", false))
			if manual != bool(textures.images[index].get_meta("source_manual_mipmaps", false)) or manual and sampler.texture.get("mipmaps", false):
				push_error("Original cel sampler manual mip declaration does not match its image")
				return false
			# Retain raw pixels; shader samplers must not inherit albedo UV/mirror baking.
			sampler_images.append(textures.images[index])
		elif sampler.get("kind") == "data":
			var image := data_image(sampler)
			if image == null:
				return false
			sampler_images.append(image)
		else:
			push_error("Unsupported original cel sampler kind")
			return false
	return true

static func data_image(source: Dictionary) -> Image:
	var width := int(source.get("width", 0))
	var height := int(source.get("height", 0))
	var channels := int(source.get("channels", 0))
	var sample_type := str(source.get("sampleType", ""))
	if width <= 0 or height <= 0 or width > Image.MAX_WIDTH or height > Image.MAX_HEIGHT or channels < 1 or channels > 4:
		push_error("Invalid original cel data sampler dimensions")
		return null
	if not IMAGE_FORMATS.has(sample_type) or source.get("storage") not in SAMPLE_STORAGE[sample_type] or int(source.get("elementSize", 0)) != int(SAMPLE_BYTES[sample_type]):
		push_error("Unsupported original cel data sampler storage/type")
		return null
	var bytes := Marshalls.base64_to_raw(str(source.get("bytes", "")))
	if bytes.size() != width * height * channels * int(SAMPLE_BYTES[sample_type]):
		push_error("Original cel data sampler byte count does not match its extent")
		return null
	var image := Image.create_from_data(width, height, false, IMAGE_FORMATS[sample_type][channels - 1], bytes)
	if image == null or image.is_empty():
		push_error("Cannot create the original cel data sampler image")
		return null
	return image

func sampling(index: int) -> Dictionary:
	if index < 0 or index >= samplers.size():
		push_error("Original cel sampler index is missing")
		return {}
	var source: Dictionary = samplers[index]
	return source.get("sampling", {}) if source.kind == "data" else source.get("texture", {})

func texture(index: int) -> Texture2D:
	if index < 0 or index >= sampler_images.size() or index >= sampler_textures.size() or sampler_images[index] == null:
		push_error("Original cel sampler image is missing")
		return null
	if sampler_textures[index] != null:
		return sampler_textures[index]
	var settings := sampling(index)
	if settings.is_empty():
		push_error("Original cel sampler configuration is missing")
		return null
	var image: Image = sampler_images[index]
	if settings.get("mipmaps", false):
		image = image.duplicate()
		if image.generate_mipmaps() != OK:
			push_error("Cannot generate native mipmaps for the original cel sampler")
			return null
	# UV orientation, colour space and filter modes belong to the generated sampler.
	# Keep the immutable source pixels and channel precision unchanged here.
	sampler_textures[index] = ImageTexture.create_from_image(image)
	return sampler_textures[index]

func attach(material: Material, source: Dictionary) -> bool:
	var index := int(source.get("program", -1))
	if index < 0 or index >= programs.size() or not source.get("uniforms") is Dictionary or not source.get("defines") is Dictionary:
		push_error("Original cel material has no captured program/uniform declarations")
		return false
	if _material_ids.is_empty():
		for material_id in range(material_sources.size()):
			_material_ids[material_sources[material_id]] = material_id
	if not _material_ids.has(source):
		_material_ids[source] = material_sources.size()
		material_sources.append(source)
	# Native Resource references keep one immutable source table per captured bundle.
	material.set_meta("source_cel", _material_ids[source])
	material.set_meta("source_cel_data", self)
	return true

static func material_source(material: Material) -> Dictionary:
	if material == null:
		return {}
	var reference: Variant = material.get_meta("source_cel", null)
	if reference is Dictionary:
		return reference
	var bundle := material.get_meta("source_cel_data", null) as SourceCelData
	if reference is int and bundle != null and reference >= 0 and reference < bundle.material_sources.size():
		return bundle.material_sources[reference]
	push_error("Missing original shared cel material reference")
	return {}

static func retain_from(source: Material, destination: Material) -> void:
	for key: String in MATERIAL_META:
		if source.has_meta(key):
			destination.set_meta(key, source.get_meta(key))
