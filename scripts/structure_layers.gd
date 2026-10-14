class_name StructureLayers
extends RefCounted

var slabs: Array = []
var slab_grid: Dictionary = {}
var decks: Array = []
var tunnels: Array = []
var deck_grid: Dictionary = {}
var tunnel_grid: Dictionary = {}

func configure(accepted_slabs: Array, deck_data: Array = [], tunnel_data: Array = []) -> void:
	slabs = accepted_slabs
	decks = deck_data
	tunnels = tunnel_data
	slab_grid.clear()
	deck_grid.clear()
	tunnel_grid.clear()
	for slab: Array in slabs:
		_index(slab_grid, slab, slab[0], slab[1], slab[2], slab[3], slab[4], Content.constants.LOS.CELL_M)
	for deck: Dictionary in decks:
		_index(deck_grid, deck, deck.x1, deck.z1, deck.x2, deck.z2, deck.hw + Content.balance.structure.deckPad, Content.balance.structure.deckCell)
	for tunnel: Dictionary in tunnels:
		_index(tunnel_grid, tunnel, tunnel.x1, tunnel.z1, tunnel.x2, tunnel.z2, tunnel.hw + Content.balance.structure.tunnelPad, Content.balance.structure.tunnelCell)

func _index(grid: Dictionary, entry: Variant, x1: float, z1: float, x2: float, z2: float, pad: float, cell: float) -> void:
	for i in range(floori((minf(x1, x2) - pad) / cell), floori((maxf(x1, x2) + pad) / cell) + 1):
		for j in range(floori((minf(z1, z2) - pad) / cell), floori((maxf(z1, z2) + pad) / cell) + 1):
			var key := Vector2i(i, j)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(entry)

func _slabs_at(point: Vector2) -> Array:
	# The authority's uploaded ribbons use north-positive coordinates.
	var cell: float = Content.constants.LOS.CELL_M
	return slab_grid.get(Vector2i(floori(point.x / cell), floori(-point.y / cell)), [])

static func on_ribbon(point: Vector2, slab: Array) -> bool:
	var x := float(point.x)
	var z := -float(point.y)
	var ex: float = slab[2] - slab[0]
	var ez: float = slab[3] - slab[1]
	var square := ex * ex + ez * ez
	if square == 0:
		square = 1.0
	var t: float = clampf(((x - slab[0]) * ex + (z - slab[1]) * ez) / square, 0, 1)
	var dx: float = x - (slab[0] + ex * t)
	var dz: float = z - (slab[1] + ez * t)
	return dx * dx + dz * dz <= slab[4] * slab[4]

static func tunnel_exit(inner: Vector2, outer: Vector2, slab: Array) -> int:
	var ux: float = slab[2] - slab[0]
	var uz: float = slab[3] - slab[1]
	var length := sqrt(ux * ux + uz * uz)
	if length == 0:
		length = 1.0
	var nx := ux / length
	var nz := uz / length
	var ix: float = inner.x - slab[0]
	var iz: float = -inner.y - slab[1]
	var ox: float = outer.x - slab[0]
	var oz: float = -outer.y - slab[1]
	var along := ix * nx + iz * nz
	var lateral := -ix * nz + iz * nx
	var ds := ox * nx + oz * nz - along
	var dd := -ox * nz + oz * nx - lateral
	var axis_exit := (length - along) / ds if ds > 0 else -along / ds if ds < 0 else INF
	var side_exit: float = (slab[4] - lateral) / dd if dd > 0 else (-slab[4] - lateral) / dd if dd < 0 else INF
	if not side_exit < axis_exit:
		return 0
	return 2 if int(slab[6]) & (1 if dd > 0 else 2) else 1

func inferred_level(point: Vector2) -> int:
	for slab: Array in _slabs_at(point):
		if on_ribbon(point, slab):
			return int(slab[5])
	return 0

func unit_level(spec: Dictionary, point: Vector2) -> int:
	if spec.kind in ["tower", "base"]:
		return 0
	if spec.get("hero", false) and spec.get("level") != null:
		return int(spec.level)
	var fly: bool = Content.constants.UNITS.get(spec.kind, {}).get("fly", false) or spec.kind == "heli" or spec.get("kami", false) or spec.get("decoy", false) or spec.get("hyper", false)
	if fly and spec.get("altitude", 0.0) >= Content.constants.LOS.TUN_CLEAR_M:
		return 0
	if not fly and not spec.get("hero", false) and not spec.get("has_lane", false):
		return 0
	return inferred_level(point)

func separated(level: int, impact: Vector2, target: Vector2, target_level: int) -> bool:
	if level < 0 or slabs.is_empty() or level == target_level:
		return false
	if level == 2 or target_level == 2:
		var inner := impact if level == 2 else target
		var outer := target if level == 2 else impact
		var open := false
		for slab: Array in _slabs_at(inner):
			if int(slab[5]) != 2 or not on_ribbon(inner, slab):
				continue
			# Portals allow LOS, but only gallery-side exits allow cross-layer blast.
			if tunnel_exit(inner, outer, slab) != 2:
				return true
			open = true
		if not open:
			return true
	for slab: Array in _slabs_at(impact):
		if int(slab[5]) == 1 and on_ribbon(impact, slab) and on_ribbon(target, slab):
			return true
	return false

func deck_height(point: Vector2, margin: float = 0.0, min_y: float = -INF, max_y: float = INF, nearest_above: bool = false) -> Variant:
	var cell: float = Content.balance.structure.deckCell
	var best: Variant = null
	for deck: Dictionary in deck_grid.get(Vector2i(floori(point.x / cell), floori(point.y / cell)), []):
		var ex: float = deck.x2 - deck.x1
		var ez: float = deck.z2 - deck.z1
		var square := ex * ex + ez * ez
		if square == 0:
			square = 1.0
		var length := sqrt(square)
		var dx: float = float(point.x) - deck.x1
		var dz: float = float(point.y) - deck.z1
		var raw := (dx * ex + dz * ez) / square
		var overflow := (-raw if raw < 0 else raw - 1 if raw > 1 else 0.0) * length
		if overflow > Content.balance.structure.deckLongTolerance or absf(dx * ez - dz * ex) / length > deck.hw + margin:
			continue
		var y: float = deck.y1 + (deck.y2 - deck.y1) * clampf(raw, 0, 1)
		if y < min_y or y > max_y:
			continue
		if best == null or (y < best if nearest_above else y > best):
			best = y
	return best

func tunnel_at(point: Vector2) -> Dictionary:
	var cell: float = Content.balance.structure.tunnelCell
	var best := {}
	for tunnel: Dictionary in tunnel_grid.get(Vector2i(floori(point.x / cell), floori(point.y / cell)), []):
		var ex: float = tunnel.x2 - tunnel.x1
		var ez: float = tunnel.z2 - tunnel.z1
		var square := ex * ex + ez * ez
		if square == 0:
			square = 1.0
		var dx: float = float(point.x) - tunnel.x1
		var dz: float = float(point.y) - tunnel.z1
		var raw := (dx * ex + dz * ez) / square
		var fraction := clampf(raw, 0, 1)
		if absf(raw - fraction) * sqrt(square) > Content.balance.structure.tunnelLongTolerance:
			continue
		if sqrt(pow(dx - ex * fraction, 2) + pow(dz - ez * fraction, 2)) > tunnel.hw:
			continue
		var floor_y: float = tunnel.fy1 + (tunnel.fy2 - tunnel.fy1) * fraction
		if best.is_empty() or floor_y < best.floor:
			best = {"floor": floor_y, "ceil": tunnel.cy1 + (tunnel.cy2 - tunnel.cy1) * fraction, "open": tunnel.get("open", false)}
	return best

func player_level(point: Vector3, surface: float, ground: float) -> int:
	var planar := Vector2(point.x, point.z)
	var tunnel := tunnel_at(planar)
	if not tunnel.is_empty() and not tunnel.open and point.y < tunnel.ceil:
		return 2
	if surface > ground + Content.balance.structure.bridgeThreshold:
		var deck: Variant = deck_height(planar, Content.balance.structure.deckMargin)
		if deck != null and absf(surface - deck) < Content.balance.structure.bridgeHeightTolerance:
			return 1
	return 0

func projectile_surface(point: Vector3, ground: float) -> float:
	var rules: Dictionary = Content.balance.structure
	var planar := Vector2(point.x, point.z)
	var tunnel := tunnel_at(planar)
	if not tunnel.is_empty() and point.y < tunnel.ceil:
		return tunnel.floor
	var maximum: float = maxf(point.y + rules.deckStep, ground + rules.deckUnder + rules.maximumMechHeight - 0.000001)
	var deck: Variant = deck_height(planar, rules.deckMargin, -INF, maximum)
	var surface := ground
	if deck != null and deck > ground and (point.y >= deck - rules.deckStep or deck - rules.deckUnder - ground < rules.maximumMechHeight):
		surface = deck
	if not tunnel.is_empty() and not tunnel.open:
		surface = maxf(surface, tunnel.ceil + rules.tunnelRoofThickness)
	return surface

func player_reference(point: Vector3, surface: float, ground: float) -> float:
	var level := player_level(point, surface, ground)
	return ground if level == 0 and surface > ground + Content.balance.structure.bridgeThreshold else surface

func impact_level(point: Vector3) -> int:
	var tunnel := tunnel_at(Vector2(point.x, point.z))
	return 2 if not tunnel.is_empty() and not tunnel.open and point.y < tunnel.ceil else 0
