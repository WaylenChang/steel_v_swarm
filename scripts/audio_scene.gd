class_name AudioScene
extends RefCounted

var rules := AudioSceneRules.new()

func configure(metadata: Dictionary) -> void:
	rules.configure(metadata, Content.heroes)

func reset() -> void:
	rules.density_cache.clear()

func observe(audio: BattleAudio, simulation: BattleSimulation, camera: Camera3D, pilot: BattleUnit) -> void:
	if audio == null or not audio.unlocked or audio.disposed or camera == null or simulation.world == null:
		return
	var entities: Array = []
	for unit: BattleUnit in simulation.units.values():
		var self_source := unit == pilot
		var mesh: Node3D = unit.body if unit.body != null else unit.model
		var point := mesh.global_position if mesh != null else unit.global_position
		var motion: Variant = unit.body.motion.values if unit.body != null and not unit.body.motion.values.is_empty() else null
		entities.append({"kind": unit.kind, "ch": unit.character, "hero": unit.is_hero(),
			"civ": unit.kind == "civilian", "isSelf": self_source, "dead": not unit.alive(),
			"isStatic": unit.kind in ["base", "tower", "bunker"] or unit.special.get("role") in ["slab", "hazard"],
			"flies": unit.flying if self_source else unit.kind in Content.balance.bodyRules.presentation.flyKinds,
			"loco": motion, "mesh": {"position": {"x": point.x, "y": point.y, "z": point.z},
				"visible": mesh != null and mesh.is_visible_in_tree() and unit.presentation_visible}})
	var world := simulation.world
	var position := pilot.global_position if pilot != null else camera.global_position
	var ground := int(pilot.fluid_environment.get("ground", 0)) if pilot != null and pilot.alive() else 0
	world.blocker_query.ensure(world.active_columns)
	var point := Vector2(position.x, position.z)
	# Imported world geometry and native presentation use the source visual coordinates.
	audio.set_ambience(rules.place(point, ground, not world.layers.tunnel_at(point).is_empty(),
		rules.density(world.blocker_query, point), entities))
	var own_weights: Variant = pilot.body.motion.values.get("w") if pilot != null and pilot.body != null else null
	for plan: Dictionary in rules.movement(entities, camera.global_transform, own_weights, world.water_code, ground, false, audio.low_power):
		audio.set_move(plan.category, plan.gain, plan.pan, plan.rate, plan.wet)
