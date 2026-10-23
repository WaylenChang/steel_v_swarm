class_name NativeWorldData
extends Resource

@export var scene: PackedScene
@export var bounds: Dictionary
@export var minimap_base: Texture2D
@export var source: Dictionary
@export var slabs_captured := false
@export var authority_slabs: Array = []
@export var decks: Array
@export var tunnels: Array
@export var columns: Array
@export var corridors: Array
@export var probes: Array
@export var lane_heights: Array
@export var deck_probes: Array
@export var min_height: float
@export var max_height: float
@export var average_height: float
@export var ceiling: float
@export var terrain_grid: int
@export var terrain_heights: PackedFloat32Array
@export var water_profile: Dictionary
@export var climbs_captured := false
@export var climb_routes: Array = []
@export var supports_captured := false
@export var roof_platforms: Array = []
@export var source_buildings: Array = []
@export var structure_pads: Dictionary = {}
@export var trains_captured := false
@export var source_trains: Array = []
@export var motions_captured := false
@export var source_motions: Array = []
@export var wildlife_captured := false
@export var source_wildlife: Dictionary = {}
@export var petals_captured := false
@export var source_petals: Dictionary = {}
@export var aquatics_captured := false
@export var source_aquatics: Dictionary = {}
@export var marine_captured := false
@export var source_marine: Dictionary = {}
@export var marine_depth_field: Texture2D
@export var marine_programs: Array[ShaderInclude] = []

