extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("localFire") or not Content.balance.controls.has("localFeedback") or not Content.balance.controls.has("weaponHud"):
		h._check(false, "Regenerate original local fire presentation references")
		return
	for fixture: Dictionary in fixtures.localFire:
		var state := LocalFireState.new()
		state.configure(Content.balance.controls.weaponHud)
		state.feedback = LocalCombatFeedback.new()
		state.feedback.configure(Content.balance.controls.localFeedback)
		var notices: Array = []
		state.feedback.message.connect(func(value): notices.append(value))
		state.set_weapons(fixture.definitions)
		state.power = 100000
		state.reload_factor = 1.7
		for weapon: Dictionary in state.weapons.values():
			weapon.ammo = 3.0
		var fallbacks: Array = []
		state.empty_heavy.connect(func(): fallbacks.append(true))
		for step: Dictionary in fixture.steps:
			if not step.has("nowBits") or String(step.nowBits).hex_decode().size() != 8:
				h._check(false, "Regenerate exact original local-fire clock bits")
				return
			# JSON decimal parsing can move a strict reload boundary by one ULP.
			var now := String(step.nowBits).hex_decode().decode_double(0)
			var context := "%s/%s/%s/%s@%s" % [fixture.character, fixture.initialSlot, fixture.program, step.slot, now]
			fallbacks.clear()
			notices.clear()
			if step.has("power"):
				state.power = float(step.power)
			state.tick(now)
			if not step.frame.firing:
				state.recoil.release_fire()
			if step.reload:
				state.reload(step.slot, now)
			h._check(state.attempt(step.slot, now, step.frame) == bool(step.ready), "Immediate local fire follows original cadence, defense/weather, reload, power, settle and charge gates " + context)
			h._check(fallbacks.size() == int(step.fallbacks), "Empty heavy presentation leaves aiming at the original gate boundary")
			Helper.compare(h, notices, step.notices, "Original fire feedback retains silent gates, warning throttles, charge starts and reload notices")
			for slot: String in ["light", "heavy"]:
				Helper.compare(h, state.hud(slot, 1, now), step.hud[slot], "Original weapon HUD uses local magazines and retained snow-scaled reload duration")
			Helper.compare(h, {"power": state.power, "lastFire": state.last_fire, "weapons": state.weapons,
				"burst": state.recoil.burst_count, "settle": state.recoil.settle_until,
				"rail": state.recoil.rail_at, "steady": state.recoil.steady_at}, step.result,
				"Original client presentation accounts retain independent resource predictions and source gate ordering " + context)
		state.set_weapons(fixture.definitions, true)
		for slot: String in state.weapons:
			h._near(state.weapons[slot].ammo, fixture.definitions[slot].mag, "Tier refresh and respawn refill the presentation magazine")
			h._near(state.weapons[slot].reload_end, 0, "Presentation refill cancels local cooldown")
