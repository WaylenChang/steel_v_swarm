extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not metadata.has("scene") or not fixtures.has("audioSceneMovement"):
		h._check(false, "Regenerate original movement-source selection and location density references")
		return
	var scene := AudioSceneRules.new()
	scene.configure(metadata, Content.heroes)
	for fixture: Dictionary in fixtures.audioMoveCategories:
		h._check(scene.move_category(fixture.entity) == (str(fixture.result) if fixture.result != null else ""), "Original movement category shares flight animation thresholds and preserves NPC/civilian precedence")
	for fixture: Dictionary in fixtures.audioSceneMovement:
		var queries: Array = []
		var ground := func(x: float, z: float) -> int:
			queries.append([x, z])
			return 1 if x >= 0 and z <= 0 else 2
		var camera := Transform3D.IDENTITY
		camera.origin = Vector3(fixture.camera.position[0], fixture.camera.position[1], fixture.camera.position[2])
		camera.basis.x = Vector3(fixture.camera.right[0], fixture.camera.right[1], fixture.camera.right[2])
		var plans := scene.movement(fixture.entities, camera, fixture.ownWeights, ground, 1, fixture.selfBed, fixture.low)
		Helper.compare(h, plans, fixture.result, "Original movement audio retains nearest-source ties, full 3D audibility, density, idle floors, self inclusion and animation-weight rate")
		Helper.compare(h, queries, fixture.queries, "Only the winning remote stomp source queries wetness; low power does not scan movement sources")
	_density(h, scene, fixtures.audioSceneDensity, metadata)
	for fixture: Dictionary in fixtures.audioScenePlaces:
		var actual := scene.place(Vector2(fixture.position[0], fixture.position[1]), fixture.ground, fixture.tunnel, fixture.densities, fixture.entities)
		var expected: Dictionary = fixture.result.duplicate(true)
		if expected.camp == null:
			h._check(is_inf(float(actual.camp)), "No living static source leaves the camp distance unbounded")
		else:
			h._near(actual.camp, expected.camp, "Location camp distance ignores altitude and excludes dead static entities")
		actual.erase("camp")
		expected.erase("camp")
		Helper.compare(h, actual, expected, "Location queries reuse ground, tunnels and interpolated collision-grid density")

static func _density(h: Node, scene: AudioSceneRules, fixture: Dictionary, metadata: Dictionary) -> void:
	Helper.compare(h, scene.density(null, Vector2.ZERO), {"bld": 0.0, "tree": 0.0}, "Missing source collision grid has zero building/tree density")
	h._near(metadata.scene.cell, Content.balance.minimap.fog.cell, "Location audio reuses the existing source collision-grid cell size")
	var query := SourceBlockerQuery.new()
	for cell: Dictionary in fixture.cells:
		var indices: Array[int] = []
		for row: Dictionary in cell.rows:
			indices.append(query.entries.size())
			query.entries.append(row)
		query.grid[Vector2i(cell.cell[0], cell.cell[1])] = indices
	for sample: Dictionary in fixture.cases:
		Helper.compare(h, scene.density(query, Vector2(sample.position[0], sample.position[1])), sample.result, "Original four-cell interpolation is continuous at source cell centers and negative coordinates")
	query.grid.clear()
	Helper.compare(h, scene.density(query, Vector2(32, 32)), fixture.retained, "Original location density cache remains unchanged when the collision grid later mutates")
