class_name SiegeRules
extends RefCounted

static func open_stage(counts: Array) -> int:
	for stage in range(Content.constants.SIEGE.STAGES.size()):
		if stage < counts.size() and int(counts[stage]) > 0:
			return stage
	return int(Content.constants.SIEGE.BASE)

static func segment_of(fraction: float) -> int:
	var count: int = Content.constants.BOSS.SEG_W.size()
	for segment in range(count):
		if fraction > StatusRules.boss_hp_cap(segment + 1) + 0.000000001:
			return segment
	return count - 1

static func segment_fraction(fraction: float, segment: int) -> float:
	var high := StatusRules.boss_hp_cap(segment)
	var low := StatusRules.boss_hp_cap(segment + 1)
	return clampf((fraction - low) / maxf(0.000000001, high - low), 0, 1)

static func body_scale(segment: int) -> float:
	var values: Array = Content.constants.BOSS.SCALE_F
	return float(values[clampi(segment, 0, values.size() - 1)])

static func invulnerability(segment: int) -> float:
	var values: Array = Content.constants.BOSS.INVULN_S
	return float(values[clampi(segment, 0, values.size() - 1)])

static func talk_seconds(stage: int) -> float:
	return float(Content.constants.SIEGE.TALK_S) if stage < int(Content.constants.SIEGE.BASE) else 0.0

static func slot_offset(index: int) -> float:
	if index == 0:
		return 0.0
	return (1.0 if index % 2 else -1.0) * ceili(index / 2.0) * float(Content.constants.GAME.TOWER_SIDE_OFF) * float(Content.constants.BOSS.SLOT_OFF_F)

static func slot_plan(count: int) -> Array:
	if count <= 0:
		return []
	var stages: int = Content.constants.SIEGE.STAGES.size()
	var slots: Array = Content.constants.BOSS.SLOTS.get(str(count), [])
	if slots.is_empty():
		for stage in range(stages):
			slots.append(floori(count / float(stages)) + (1 if count % stages > stage else 0))
	var plan: Array = []
	for stage in range(stages):
		for index in range(int(slots[stage]) if stage < slots.size() else 0):
			plan.append(stage)
	return plan.slice(0, count)

static func anchor(side: String, stage: int, index: int, sites: Array, lane: Array, base: Vector2) -> Vector2:
	var offset := slot_offset(index)
	var site_index := sites.size() - 1 - stage
	if stage < int(Content.constants.SIEGE.BASE) and site_index >= 0 and sites[site_index].has(side):
		var site: Dictionary = sites[site_index]
		if not site.get("normals", {}).has(side):
			return Vector2(INF, INF)
		return Vector2(site[side][0], site[side][1]) + Vector2(site.normals[side][0], site.normals[side][1]) * offset
	if lane.size() < 2:
		return base + Vector2(0, -offset)
	var first: Array = lane[0] if side == "SWARM" else lane[-1]
	var second: Array = lane[1] if side == "SWARM" else lane[-2]
	var dx := float(second[0]) - float(first[0])
	var dz := float(second[1]) - float(first[1])
	var distance := sqrt(dx * dx + dz * dz)
	if distance == 0:
		distance = 1.0
	return base + Vector2(-dz, dx) / distance * offset
