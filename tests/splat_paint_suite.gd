extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["cssDecimal", "splatPaintFrames"]:
		if not fixtures.has(key) or not Content.balance.get("screenSplats", {}).has("paint"):
			h._check(false, "Regenerate original glass DOM/filter/decimal references: " + key)
			return
	for item: Dictionary in fixtures.cssDecimal:
		h._near(CssDecimal.fixed(float(item.value), int(item.digits)), item.result, "Original Number.toFixed rounds the exact binary value, including negative half-ties")
	var overlay := BloodSplatOverlay.new()
	h.add_child(overlay)
	overlay.size = Vector2(800, 600)
	var original: SplatTile
	for frame: Dictionary in fixtures.splatPaintFrames:
		for kind: String in ["blood", "glint"]:
			overlay.sync_layer(kind, frame.list)
			var actual: Array = overlay.paint[kind].live.values()
			var expected: Array = frame.result[kind]
			h._check(actual.size() == expected.size(), "Original HUD reconciles splats by ID and removes disappeared entries")
			for index in range(mini(actual.size(), expected.size())):
				Helper.compare(h, actual[index], expected[index].duplicate().merged({"background": null}, true),
					"Original first-creation percentage coordinates and per-frame decimal opacity")
				var tile: SplatTile = overlay.tiles[kind][int(actual[index].id)]
				h._check(tile.passes.size() == 6, "Native glass paint uses isolated raw, separable blur, shadow and composite targets")
				var rules: Dictionary = Content.balance.screenSplats.paint[kind]
				h._near(tile.extent, float(rules.extent) * 6, "Original vmin canvas extent")
				h._near(float(tile.present.get_shader_parameter("opacity")), actual[index].opacity, "Group opacity applies after source filters")
				if kind == "blood" and int(actual[index].id) == 1:
					if original == null:
						original = tile
					else:
						h._check(tile == original, "Existing splat IDs retain their native texture/filter pipeline")
						h._near(float(tile.layout.drops[0].r), CssDecimal.fixed(1.005, 2), "Existing splat IDs cannot replace their original drop pattern")
				var frozen := tile.layout.duplicate(true)
				tile.resize_canvas(Vector2(600, 800))
				h._check(tile.layout == frozen, "Orientation changes reproject the same frozen glass pattern")
				tile.resize_canvas(overlay.size)
	h._check(overlay.tiles.blood.is_empty() and overlay.tiles.glint.is_empty() and not overlay.free_tiles.is_empty(),
		"Expired glass nodes are hidden and retained for bounded native reuse")
	for tile: SplatTile in overlay.free_tiles:
		h._check(not tile.visible and tile.passes.all(func(viewport): return viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED),
			"Retired glass textures cannot keep issuing render passes")
	overlay.free()
	_receive(h)

static func _receive(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	var character: String = Content.heroes.keys()[0]
	var pilot := Helper.actor(simulation, {"id": 1, "character": character, "side": "STEEL", "position": [0, 0, 0],
		"hp": 700, "max_hp": 700, "shield": 120, "max_shield": 120})
	pilot.camera = Camera3D.new()
	pilot.add_child(pilot.camera)
	var overlay := BloodSplatOverlay.new()
	h.add_child(overlay)
	overlay.size = Vector2(800, 600)
	simulation.screen_hurt.connect(func(event): overlay.receive(event, pilot))
	var resources := [pilot.hp, pilot.shield, pilot.power, pilot.ammo.duplicate(), simulation.rng.state, simulation.projectile_rng.state]
	var report := {"type": "screen_hurt", "peer": pilot.peer_id, "actor": pilot.entity_id, "blood_serial": 1,
		"origin": Vector3(20, 0, -100), "amount": 30.0}
	simulation.present_world_events([report])
	simulation.present_world_events([report])
	h._check(overlay.state.sequence == 1 and overlay.state.blood.size() == 1, "Snapshot replay cannot duplicate a published glass spray")
	overlay.advance(0)
	h._check(overlay.tiles.blood.size() == 1, "A real publication reaches the native glass compositor")
	var rejected := report.duplicate()
	rejected.peer = 999
	rejected.blood_serial = 2
	h._check(not overlay.receive(rejected, pilot) and overlay.last_serial == 1, "Other pilot reports cannot advance the local spray identity")
	pilot.defending = true
	report.blood_serial = 2
	simulation.present_world_events([report])
	overlay.advance(0)
	h._check(overlay.tiles.glint.size() == 1 and overlay.tiles.blood.size() == 1, "Shield catches use their separate source-colour layer while older blood remains")
	pilot.view_reset += 1
	overlay.observe(pilot)
	h._check(overlay.tiles.blood.is_empty() and overlay.tiles.glint.is_empty(), "A new view clears residue without resetting the authority replay guard")
	h._check(not overlay.receive(report, pilot), "A cleared view cannot replay an old publication")
	overlay.reset_room()
	h._check(overlay.receive(report, pilot), "A new room accepts its own authority serial stream")
	h._check(resources == [pilot.hp, pilot.shield, pilot.power, pilot.ammo, simulation.rng.state, simulation.projectile_rng.state],
		"Glass compositing and replay/lifecycle state never spend authority resources or combat RNG")
	overlay.free()
	simulation.free()
