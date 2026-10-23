extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("snapshotAbilities") or not fixtures.has("snapshotStatuses") or not fixtures.has("snapshotBuffs") or not fixtures.has("snapshotRoles"):
		h._check(false, "Regenerate original entity serialization and public charge summaries")
		return
	for item: Dictionary in fixtures.snapshotAbilities:
		var unit := BattleUnit.new()
		unit.character = item.character
		unit.kind = item.kind
		unit.side = item.side
		unit.upgrades = item.upgrades.duplicate(true)
		unit.cooldowns = item.cooldowns.duplicate(true)
		unit.ability_charges = item.charges.duplicate(true)
		var before := [unit.cooldowns.duplicate(true), unit.ability_charges.duplicate(true)]
		var actual := ActorSnapshot.abilities(unit, item.now)
		Helper.compare(h, actual, item.result, "Original serialized ability levels, ready charges, earliest recharge, expired queues and allocated max")
		h._check(actual.has("charges") == item.result.has("charges"), "Original conditional public charge roster")
		h._check(before == [unit.cooldowns, unit.ability_charges], "Repeated public snapshot queries do not prune authority charge queues")
		unit.free()
	for item: Dictionary in fixtures.snapshotStatuses:
		var unit := BattleUnit.new()
		unit.character = item.character
		unit.status = item.status.duplicate(true)
		unit.bleed = item.bleed.duplicate(true)
		unit.cast_state = item.cast.duplicate(true)
		unit.status.cast_lock_until = item.cast_lock
		var actual := ActorSnapshot.public_status(unit, item.now)
		Helper.compare(h, actual, item.expected, "Original public hero/NPC CC deadlines, slow zero, suppression precision and bleed")
		h._check(actual.size() == item.expected.size(), "Public CC excludes private cooldown, damage and target fields")
		var cast: Variant = ActorSnapshot.cast_remaining(unit, item.now)
		if item.hero:
			h._check(item.has("icon_expected"), "Regenerate original suppression, stealth and slow-factor status-icon publication")
			if item.has("icon_expected"):
				Helper.compare(h, ActorSnapshot.status_icon_details(unit, item.now), item.icon_expected,
					"Original icon detail publication retains hundredth-second suppression and explicit zero slow factors")
			h._check(item.has("control_expected"), "Regenerate original immutable control-status publications")
			if item.has("control_expected"):
				Helper.compare(h, ActorSnapshot.control_status(unit, item.now), item.control_expected,
					"Original owner control publication includes bleed and cast priority without exposing damage/attacker data")
		if item.cast_remaining == null:
			h._check(cast == null, "Non-hero or inactive casts have no public cast countdown")
		else:
			h._near(cast, item.cast_remaining, "Original public cast countdown prefers an active channel to its lock")
		unit.free()
	for item: Dictionary in fixtures.snapshotBuffs:
		var actual := ActorSnapshot.public_buffs(item.buffs, item.now)
		Helper.compare(h, actual, item.expected, "Original active public modifier/affix timers and integer half-ties")
		for buff: Dictionary in actual:
			h._check(not buff.has("break_on_hit") and not buff.has("private_target"), "Public modifiers omit authority break and targeting data")
	_projection(h)
	h._check(fixtures.has("snapshotIconBuffs"), "Regenerate original separate modifier and affix status-icon timers")
	for item: Dictionary in fixtures.get("snapshotIconBuffs", []):
		var unit := BattleUnit.new()
		unit.buffs = item.buffs.duplicate(true)
		var original := unit.buffs.duplicate(true)
		Helper.compare(h, ActorSnapshot.status_icon_details(unit, item.now), item.result,
			"Original status icons count skill modifiers separately from affixes and preserve active timers that round to zero")
		Helper.compare(h, unit.buffs, original, "Status publication leaves authority modifier state intact")
		unit.free()
	_roles(h, fixtures.snapshotRoles)

static func _roles(h: Node, fixtures: Array) -> void:
	var other := BattleUnit.new()
	for item: Dictionary in fixtures:
		var unit := BattleUnit.new()
		h.add_child(unit)
		unit.entity_id = 99171
		unit.peer_id = int(item.peer)
		unit.kind = item.kind
		unit.side = item.side
		unit.character = item.character
		unit.hp = item.hp
		unit.max_hp = item.max_hp
		unit.upgrades = item.upgrades.duplicate(true)
		unit.special = item.special.duplicate(true)
		unit.status = item.status.duplicate(true)
		var original := unit.special.duplicate(true)
		for viewer: BattleUnit in [other, null]:
			var packet := ActorSnapshot.project(unit, viewer, item.now)
			Helper.compare(h, packet.special, item.expected, "Original special-role public identity: " + str(item.name))
			h._check(packet.special.size() == item.expected.size(), "Special roles omit owner entities, targets, definitions, offsets and AI timers: " + str(item.name))
			for key: String in ["money", "power", "score", "upgrades", "public_abilities"]:
				h._check(packet.has(key) == item.economy, "Only the original active hero publishes economy/ability state: " + key)
			if item.super_level != null:
				h._check(int(packet.super_level) == int(item.super_level), "Inactive SUPER bodies retain the source public scale level")
			h._check(bool(packet.get("charred", false)) == item.charred, "Public lightning scorch exposes only its marker")
			var replica := BattleUnit.new()
			h.add_child(replica)
			replica.configure(packet, true)
			replica.apply_snapshot(packet, true)
			h._check(replica.model != null and replica.special == packet.special and replica.hp == unit.hp and replica.max_hp == unit.max_hp,
				"Build the actual replica from public role/model tags and public HP, without combat construction plans")
			h._check(replica.charred == item.charred, "Replica retains public scorch state without authority damage history")
			if item.super_level != null:
				h._check(int(replica.upgrades["super"]) == int(item.super_level), "Replica scale does not require private clone upgrades")
			replica.free()
		h._check(unit.special == original, "Role projection never edits authority construction or AI state")
		unit.free()
	other.free()

static func _projection(h: Node) -> void:
	var actor := BattleUnit.new()
	h.add_child(actor)
	actor.configure({"id": 99071, "peer": 17, "kind": Content.heroes.t01.kind,
		"side": "STEEL", "character": "t01", "position": Vector3.ZERO})
	var other := BattleUnit.new()
	actor.ammo = {"light": 9876, "heavy": 5432}
	actor.reload_at = {"light": 1234}
	actor.lift = 987
	actor.charge = .81
	actor.pitch = .73
	actor.authority_fov = 33
	actor.view_mode = "tps"
	actor.cooldowns = {"def": 12.5}
	actor.ability_charges = {"def": {"max": 3, "recharge_at": [10, 12.5, 14]}}
	var original := actor.snapshot()
	for viewer: BattleUnit in [actor, other, null]:
		var packet := ActorSnapshot.project(actor, viewer, 12)
		for key: String in ActorSnapshot.OWNER_FIELDS:
			h._check(packet.has(key) == (viewer == actor), "Only actor ownership retains transport field: " + key)
		if viewer == actor:
			for key: String in ActorSnapshot.OWNER_FIELDS:
				Helper.compare(h, packet[key], original[key], "Owner reconciliation retains authority state: " + key)
		else:
			h._check(packet.has("public_abilities") and packet.max_power == actor.max_power, "Observers retain public ability summaries and resource capacity")
		var replica := BattleUnit.new()
		h.add_child(replica)
		replica.configure({"id": 99073, "peer": 99, "kind": actor.kind, "side": actor.side, "character": actor.character, "position": Vector3.ZERO})
		replica.apply_snapshot(original, true)
		replica.apply_snapshot(packet, true)
		if viewer != actor:
			h._check(replica.ammo.is_empty() and replica.reload_at.is_empty() and replica.cooldowns.is_empty() and replica.ability_charges.is_empty(), "Public replicas erase previously held private resources")
			h._check(replica.lift == -1 and not replica.view_offset_ready and replica.pitch == 0 and replica.view_mode == "fpv" and replica.authority_fov != 33,
				"Public replicas cannot reuse stale private lift, scope FOV, view mode or camera anchors")
			Helper.compare(h, replica.public_abilities, packet.public_abilities, "Replica retains public charge summary without fabricating a private queue")
		replica.free()
	h._check(actor.ammo == original.ammo and actor.ability_charges == original.ability_charges, "Publication does not mutate authority resources")
	var event := {"type": "weapon_fire", "actor": actor.entity_id, "empty_heavy": true, "aim_request": 29, "slot": "heavy", "serial": 3}
	var private_event := ActorSnapshot.event(event, true)
	var public_event := ActorSnapshot.event(event, false)
	h._check(private_event == event and event.has("empty_heavy") and not public_event.has("empty_heavy") and not public_event.has("aim_request"), "Public event projection keeps serial/slot while preserving private owner feedback")
	private_event.serial = 4
	h._check(event.serial == 3 and public_event.serial == 3, "Event recipients cannot mutate authority events or another recipient's copy")
	actor.free()
	other.free()
