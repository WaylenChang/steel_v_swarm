extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("headMarks") or not HeadMarks.available():
		h._check(false, "Regenerate original head-marker canvas textures and pose references")
		return
	for item: Dictionary in fixtures.headMarks:
		var rules: Dictionary = Content.balance.headMarks.rules[item.kind]
		var state := HeadMarkState.new()
		state.configure(item.height, item.top, rules)
		for frame: Dictionary in item.frames:
			state.advance(frame.dt, frame.now, frame.following, rules)
			h._near(state.size, frame.size, "Original cached head-marker minimum/body-relative scale")
			h._near(state.y, frame.y, "Original top anchor and phase/frequency/amplitude bob")
			h._near(state.opacity, frame.opacity, "Original head-marker fade and immediate following-opacity cap change")
			h._check(not frame.depthTest and not frame.depthWrite, "Detected actors' source markers remain visible through cover without depth writes")
	_native_marks(h)

static func _native_marks(h: Node) -> void:
	var unit := BattleUnit.new()
	h.add_child(unit)
	unit.entity_id = 99871
	unit.kind = "civilian"
	unit.geometry_override = {"height": 2.0, "top": 2.2}
	unit.special = {"role": "civilian", "civil_side": "STEEL", "profession": 0, "following": true}
	var marks := HeadMarks.new()
	unit.add_child(marks)
	marks.advance(unit, "SWARM", .25, 1)
	h._check(marks.marks.has("civilian") and not marks.marks.has("enemy"), "Civilian visual faction uses a separate marker for both viewer factions")
	var original: Dictionary = marks.marks.civilian
	unit.special.spy = true
	marks.advance(unit, "STEEL", 0, 1)
	h._check(marks.marks.size() == 1 and marks.marks.civilian.node == original.node, "Private spy identity cannot create or replace a public faction marker")
	var material: StandardMaterial3D = original.material
	h._check(ViewOcclusion._geometry(original.node) == null, "Native sprite quads stay outside source mesh damage, dissolve and occlusion collectors")
	h._check(material.no_depth_test and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		"Native billboard preserves source cover visibility and depth behavior")
	var priority: int = Content.balance.headMarks.rules.values().map(func(profile): return int(profile.order)).max()
	h._check(material.render_priority == 127 + int(Content.balance.headMarks.rules.civilian.order) - priority,
		"Native transparent ordering preserves the original marker priority differences")
	var spec: Dictionary = Content.balance.headMarks.textures["enemy:STEEL"]
	var image: Dictionary = Content.balance.headMarks.images[int(spec.image)]
	h._check(material.albedo_texture != null and material.albedo_texture.get_width() == int(image.width) and material.albedo_texture.get_height() == int(image.height),
		"Native marker uses the captured original canvas image")
	var combat := HeadMarks.new()
	unit.add_child(combat)
	unit.kind = "soldier"
	unit.special = {}
	unit.side = "SWARM"
	combat.advance(unit, "STEEL", .1, 1)
	h._check(combat.marks.has("enemy") and not combat.marks.has("ally"), "A detected enemy uses the original faction arrow")
	var enemy_mark: Dictionary = combat.marks.enemy
	combat.advance(unit, "SWARM", .1, 2)
	h._check(combat.marks.has("ally") and combat.marks.enemy.node == enemy_mark.node, "Source per-kind marker nodes retain their cached state when the viewer allegiance changes")
	var own := HeadMarks.new()
	unit.add_child(own)
	unit.character = "s01"
	unit.peer_id = Session.player_id()
	own.advance(unit, "SWARM", .1, 2)
	h._check(own.marks.is_empty(), "The local active pilot does not get a friendly marker")
	unit.free()
