extends "res://scripts/main.gd"

var elapsed := 0.0
var bot_elapsed := 0.0
var fixture_bot: BattleUnit
var fixture_target: BattleUnit
var fixture_brain: BotBrain
var bot_id := 0
var initial_pose := Vector3(INF, INF, INF)
var movement_seen := false
var shot_seen := false
var resource_seen := false
var damage_seen := false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 16:
		push_error("NETWORK_BOT_TIMEOUT movement=%s shot=%s resource=%s damage=%s" % [movement_seen, shot_seen, resource_seen, damage_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or simulation.pilots.is_empty():
			return
		if fixture_bot == null:
			var viewer: BattleUnit
			for pilot: BattleUnit in simulation.pilots.values():
				if pilot.peer_id > 1:
					viewer = pilot
			if viewer == null:
				return
			simulation.set_physics_process(false)
			for unit: BattleUnit in simulation.units.values():
				if unit != viewer:
					unit.hp = 0
					unit.refresh_collision()
			viewer.position = Vector3(20, simulation.world.ground_height(20, 0) + 0.1, 0)
			fixture_bot = simulation.spawn({"character": "t04", "kind": Content.heroes.t04.kind,
				"peer": -3001, "side": "STEEL", "bot": true, "position": Vector3(0, simulation.world.ground_height(0, 0) + 0.1, 0)})
			fixture_target = simulation.spawn({"kind": "soldier", "side": "SWARM",
				"position": Vector3(0, simulation.world.ground_height(0, -30) + 0.1, -30)})
			fixture_target.hp = 1000000
			fixture_target.max_hp = fixture_target.hp
			fixture_target.shield = 0
			fixture_bot.yaw = 0
			fixture_brain = BotBrain.new()
			fixture_brain.configure(simulation, fixture_bot, "high")
		simulation.clock += delta
		bot_elapsed += delta
		var tick: float = Content.constants.GAME.TICK_MS / 1000.0
		while bot_elapsed >= tick:
			bot_elapsed -= tick
			fixture_brain.update(tick)
		var packet := simulation.snapshot()
		for unit: Dictionary in packet.units:
			for key: String in ["threat", "bot_alert", "position_trail", "op_at", "op_next"]:
				if unit.has(key):
					push_error("NETWORK_BOT_PRIVATE_POLICY_LEAK " + key)
					get_tree().quit(1)
					return
		return
	super._physics_process(delta)
	if movement_seen and shot_seen and resource_seen and damage_seen:
		print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
		print("NETWORK_BOT_PASS movement=true shot=true resources=true damage=true private=true authority=true")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	for unit: Dictionary in state.units:
		if int(unit.peer) == -3001:
			bot_id = int(unit.id)
			if not initial_pose.is_finite():
				initial_pose = unit.position
			movement_seen = movement_seen or unit.position.distance_to(initial_pose) > 0.1
			var definition := Content.weapon(unit.character, "light", int(unit.upgrades.lw) + 1)
			resource_seen = resource_seen or float(unit.ammo.light) < float(definition.mag) or unit.reload_at.has("light")
			var replica: BattleUnit = simulation.units[bot_id]
			var ammo: Dictionary = replica.ammo.duplicate(true)
			var power := replica.power
			if simulation._bot_fire(replica, replica, "light") or replica.ammo != ammo or replica.power != power or not simulation.bot_brains.is_empty():
				push_error("NETWORK_BOT_REPLICA_AUTHORITY")
				get_tree().quit(1)
				return
		elif unit.kind == "soldier" and unit.side == "SWARM" and float(unit.max_hp) == 1000000:
			damage_seen = damage_seen or float(unit.hp) < float(unit.max_hp)
	for event: Dictionary in state.events:
		shot_seen = shot_seen or event.type == "shot" and int(event.actor) == bot_id
