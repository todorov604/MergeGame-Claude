extends RefCounted
## Regression suite for the seven defects found by the independent core review.
## Each test encodes the exact input that used to misbehave, so none of these can
## come back silently:
##
##   D1 a level with `"orders": []` could never be completed or left
##   D2 a tap rejected for a full board still consumed a random draw
##   D3 the sim accepted a level-11 slot / rare output (M0 caps at 10)
##   D4 `board_full_pending` was set once and never cleared
##   D5 the evaluator silently accepted unknown channels and unregistered types
##   D6 `reset()` wiped a failed `load_timeline`, turning it into a green run
##   D7 the clock entered the digest, so a rejected event could change state

const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")
const Evaluator = preload("res://src/core/event_evaluator.gd")
const EventModel = preload("res://src/core/event_model.gd")


func run(t) -> void:
	_test_d1_empty_orders_level(t)
	_test_d2_rejected_tap_keeps_rng(t)
	_test_d3_level_cap(t)
	_test_d4_board_full_clears(t)
	_test_d5_unknown_channel_and_type(t)
	_test_d6_reset_keeps_load_failure(t)
	_test_d7_clock_out_of_digest(t)
	_test_merge_kind_gate(t)
	_test_direct_order_semantics(t)


# ------------------------------------------------------------------ fixtures

func _project(level_extra: Dictionary = {}, entities_extra: Dictionary = {}) -> Dictionary:
	var entities := {
		"A": {"kind": "chip", "family": "Clean", "chain": "a", "maxLevel": 10,
			"visual": {"hue": "#F2A65A", "label": "A"}},
		"B": {"kind": "chip", "family": "Clean", "chain": "b", "maxLevel": 10,
			"visual": {"hue": "#7FB069", "label": "B"}},
		"G": {"kind": "generator", "maxLevel": 3, "visual": {"hue": "#5B8DEF", "label": "G"}},
		"C1": {"kind": "character", "visual": {"hue": "#E9C46A", "label": "C1"}},
	}
	for k in entities_extra.keys():
		entities[k] = entities_extra[k]
	var level := {
		"id": "level_1",
		"board": {"width": 7, "height": 9, "slots": [
			{"x": 0, "y": 0, "entity": "G", "level": 1},
			{"x": 1, "y": 1, "entity": "A", "level": 1},
			{"x": 2, "y": 1, "entity": "A", "level": 1},
		]},
		"obstacles": [],
		"orders": [{"id": "order_1", "character": "C1",
			"mission": [{"entity": "A", "level": 2}], "star": 1, "coin": 5}],
	}
	for k in level_extra.keys():
		level[k] = level_extra[k]
	return {
		"version": 2,
		"meta": {"title": "defects", "resolution": [1080, 1920], "fps": 60, "locale": "zh"},
		"theme": "themes/default",
		"locales": {"zh": {"cta.play": "go"}},
		"hud": {"level": 1, "energy": 10, "energyTickSeconds": 120, "energyTickMode": "decrement",
			"coin": 0, "star": 0, "gem": 0, "exp": 0},
		"entities": entities,
		"generators": {"G": {"charges": 5, "cooldown": 0,
			"outputs": [{"entity": "A", "weight": 1}]}},
		"characters": {"C1": {"display": "c1"}},
		"levels": [level],
		"timeline": [],
	}


func _sim(project: Dictionary) -> Object:
	var m = ProjectModel.new()
	if not m.load_data(project):
		return null
	var s = Sim.new()
	s.setup(m, 7)
	return s


func _tap(s, x: int, y: int, at: float) -> Dictionary:
	return s.apply({"id": "t", "channel": "sim", "type": "tap", "at": at,
		"payload": {"target": {"slot": [x, y]}}})


# ---------------------------------------------------------------------- D1

func _test_d1_empty_orders_level(t) -> void:
	# M0 §2.2 shows a legal level with `"orders": []`; it must be completable.
	var project := _project()
	project["levels"].append({
		"id": "level_2",
		"board": {"width": 7, "height": 9, "slots": []},
		"obstacles": [],
		"orders": [],
	})
	var s = _sim(project)
	t.ok(s != null, "D1: project with an order-less second level loads")
	# clear level 1 (merge A+A -> lv2, then claim)
	s.apply({"id": "m", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [1, 1], "to": [2, 1]}})
	var claim: Dictionary = s.apply({"id": "c", "channel": "sim", "type": "order_claim", "at": 2.0,
		"payload": {"order": "order_1"}})
	t.ok(bool(claim.get("ok", false)), "D1: level_1 order claims", String(claim.get("code", "")))
	var next: Dictionary = s.apply({"id": "n", "channel": "sim", "type": "level_next", "at": 3.0, "payload": {}})
	t.ok(bool(next.get("ok", false)), "D1: level_next is reachable after an order-less level", String(next.get("code", "")))
	t.eq(s.current_level_id(), "level_2", "D1: now on level_2")
	var complete: Dictionary = s.apply({"id": "cc", "channel": "sim", "type": "level_complete", "at": 4.0, "payload": {}})
	t.ok(bool(complete.get("ok", false)), "D1: an order-less level is already complete", String(complete.get("code", "")))


# ---------------------------------------------------------------------- D2

func _test_d2_rejected_tap_keeps_rng(t) -> void:
	# Board full at (0,0)+(1,0): the tap must fail WITHOUT drawing from the RNG.
	# Proof: the next accepted tap has to match a control run whose first tap was
	# also the first draw.
	var full_project := _project()
	full_project["levels"][0]["board"] = {"width": 2, "height": 1, "slots": [
		{"x": 0, "y": 0, "entity": "G", "level": 1},
		{"x": 1, "y": 0, "entity": "A", "level": 1},
	]}
	full_project["levels"][0]["orders"] = [{"id": "order_1", "character": "C1",
		"mission": [{"entity": "A", "level": 1}], "star": 0, "coin": 0}]
	var full = _sim(full_project)
	t.ok(full != null, "D2: 2x1 full board loads")
	var before = full.rng.state
	var res: Dictionary = _tap(full, 0, 0, 1.0)
	t.eq(String(res.get("code", "")), "SIM_BOARD_FULL", "D2: full board rejects the tap")
	t.eq(full.rng.state, before, "D2: a rejected tap does not consume a random draw")
	t.ok(full.board_full_pending, "D2: full board is recorded")

	# control: same seed, an empty cell from the start -> first draw happens here
	var control_project := _project()
	control_project["levels"][0]["board"] = {"width": 2, "height": 1, "slots": [
		{"x": 0, "y": 0, "entity": "G", "level": 1},
	]}
	var control = _sim(control_project)
	var control_tap: Dictionary = _tap(control, 0, 0, 1.0)
	t.ok(bool(control_tap.get("ok", false)), "D2: control tap succeeds", String(control_tap.get("code", "")))
	var control_spawn := _spawned_entity(control, Vector2i(0, 0))
	t.ok(control_spawn != "", "D2: control run spawned an item", control_spawn)

	# free a cell in the "full" sim, then tap: the draw must equal the control's
	var claim: Dictionary = full.apply({"id": "c", "channel": "sim", "type": "order_claim", "at": 2.0,
		"payload": {"order": "order_1"}})
	t.ok(bool(claim.get("ok", false)), "D2: claim frees the blocked cell", String(claim.get("code", "")))
	var second: Dictionary = _tap(full, 0, 0, 3.0)
	t.ok(bool(second.get("ok", false)), "D2: tap succeeds once space exists", String(second.get("code", "")))
	t.eq(_spawned_entity(full, Vector2i(0, 0)), control_spawn,
		"D2: the rejected tap did not shift the RNG stream")


func _spawned_entity(s, generator_cell: Vector2i) -> String:
	for pos in s.board.cells.keys():
		if pos == generator_cell:
			continue
		var it: Dictionary = s.board.cells[pos]
		if String(it.get("kind", "")) == "generator":
			continue
		return String(it.get("entity", ""))
	return ""


# ---------------------------------------------------------------------- D3

func _test_d3_level_cap(t) -> void:
	var project := _project()
	project["levels"][0]["board"]["slots"].append({"x": 3, "y": 3, "entity": "A", "level": 11})
	var s = _sim(project)
	t.ok(s != null, "D3: level-11 slot still loads")
	var it: Dictionary = s.board.item(Vector2i(3, 3))
	t.eq(int(it.get("level", -1)), 10, "D3: slot level is clamped to the M0 cap of 10")

	var rare_project := _project()
	rare_project["generators"] = {"G": {"charges": 5, "cooldown": 0,
		"outputs": [{"entity": "A", "weight": 1}],
		"rareOutputs": [{"entity": "A", "level": 11, "weight": 1, "directOrder": true}]}}
	var rs = _sim(rare_project)
	var r: Dictionary = _tap(rs, 0, 0, 1.0)
	t.ok(bool(r.get("ok", false)), "D3: tap with a rare output succeeds", String(r.get("code", "")))
	var max_level := 0
	for pos in rs.board.cells.keys():
		max_level = maxi(max_level, int(rs.board.cells[pos]["level"]))
	t.ok(max_level <= 10, "D3: rare output never spawns above level 10", str(max_level))


# ---------------------------------------------------------------------- D4

func _test_d4_board_full_clears(t) -> void:
	var project := _project()
	project["levels"][0]["board"] = {"width": 2, "height": 1, "slots": [
		{"x": 0, "y": 0, "entity": "G", "level": 1},
		{"x": 1, "y": 0, "entity": "A", "level": 1},
	]}
	project["levels"][0]["orders"] = [{"id": "order_1", "character": "C1",
		"mission": [{"entity": "A", "level": 1}], "star": 0, "coin": 0}]
	var s = _sim(project)
	var blocked: Dictionary = _tap(s, 0, 0, 1.0)
	t.eq(String(blocked.get("code", "")), "SIM_BOARD_FULL", "D4: 2x1 board is full")
	t.ok(s.board_full_pending, "D4: flag set while full")
	var claim: Dictionary = s.apply({"id": "c", "channel": "sim", "type": "order_claim", "at": 2.0,
		"payload": {"order": "order_1"}})
	t.ok(bool(claim.get("ok", false)), "D4: claim consumes the item and frees a cell", String(claim.get("code", "")))
	t.ok(not s.board_full_pending, "D4: a freed cell clears board_full_pending")
	var ok_tap: Dictionary = _tap(s, 0, 0, 3.0)
	t.ok(bool(ok_tap.get("ok", false)), "D4: tap works again once space exists", String(ok_tap.get("code", "")))


# ---------------------------------------------------------------------- D5

func _test_d5_unknown_channel_and_type(t) -> void:
	var project := _project()
	var m = ProjectModel.new()
	m.load_data(project)
	var ev = Evaluator.new()
	ev.setup(m, 7, null)

	var load: Dictionary = ev.load_timeline([
		{"id": "u1", "channel": "view", "type": "not_a_real_type", "at": 1.0, "payload": {}},
	])
	t.ok(bool(load.get("ok", false)), "D5: resolve itself still succeeds (shape is valid)")
	var r1: Dictionary = ev.step()
	t.ok(not bool(r1.get("ok", true)), "D5: unregistered view type is rejected", str(r1.get("code", "")))
	t.eq(String(r1.get("code", "")), "EV_UNKNOWN_TYPE", "D5: code is EV_UNKNOWN_TYPE")

	ev.load_timeline([{"id": "u2", "channel": "nope", "type": "cta", "at": 1.0, "payload": {}}])
	var r2: Dictionary = ev.step()
	t.eq(String(r2.get("code", "")), "EV_CHANNEL", "D5: unknown channel is rejected")

	ev.load_timeline([
		{"id": "u3", "channel": "view", "type": "bogus", "at": 1.0, "payload": {}},
		{"id": "u4", "channel": "sim", "type": "tap", "at": 2.0, "payload": {"target": {"slot": [0, 0]}}},
	])
	var run: Dictionary = ev.run_all()
	var ids: Array = []
	for item in run.get("rejected", []):
		ids.append(String(item.get("id", "")))
	t.ok(ids.has("u3"), "D5: run_all reports the unregistered event", str(ids))
	t.ok(not bool(run.get("ok", true)), "D5: run_all is not ok when an event was rejected")


# ---------------------------------------------------------------------- D6

func _test_d6_reset_keeps_load_failure(t) -> void:
	var project := _project()
	var m = ProjectModel.new()
	m.load_data(project)
	var ev = Evaluator.new()
	ev.setup(m, 7, null)
	var bad: Dictionary = ev.load_timeline([
		{"id": "e1", "channel": "sim", "type": "tap", "at": {"after": "missing", "offset": 0.1}, "payload": {}},
	])
	t.ok(not bool(bad.get("ok", true)), "D6: a broken anchor fails to load")
	ev.reset()
	var run: Dictionary = ev.run_all()
	t.ok(not bool(run.get("ok", true)), "D6: reset does not turn a failed load into a green run")
	t.eq(bool(run.get("load_ok", true)), false, "D6: load_ok stays false after reset")


# ---------------------------------------------------------------------- D7

func _test_d7_clock_out_of_digest(t) -> void:
	var project := _project()
	var a = _sim(project)
	var b = _sim(project)
	# identical sim commands, but b sees a presentation event at t=10 in between
	a.apply({"id": "m1", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [1, 1], "to": [2, 1]}})
	b.apply({"id": "m1", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [1, 1], "to": [2, 1]}})
	b.set_time(10.0)  # as if a view event at 10s had been dispatched
	t.eq(a.digest(), b.digest(), "D7: the clock alone does not change the sim digest")

	var c = _sim(project)
	var before: String = c.digest()
	var rejected: Dictionary = c.apply({"id": "r", "channel": "sim", "type": "merge", "at": 99.0,
		"payload": {"from": [0, 0], "to": [1, 1]}})
	t.ok(not bool(rejected.get("ok", true)), "D7: the control merge is rejected", str(rejected.get("code", "")))
	t.eq(c.digest(), before, "D7: a rejected event carrying a late timestamp leaves the digest untouched")


# ------------------------------------------------- merge only for chips (A)

func _test_merge_kind_gate(t) -> void:
	# two identical specials sit side by side: they must NOT level up
	var special_project := _project({}, {"S": {"kind": "special",
		"visual": {"hue": "#C0C8D8", "label": "S"}}})
	special_project["levels"][0]["board"] = {"width": 3, "height": 1, "slots": [
		{"x": 0, "y": 0, "entity": "S", "level": 1},
		{"x": 1, "y": 0, "entity": "S", "level": 1},
	]}
	var s1 = _sim(special_project)
	var before: String = s1.digest()
	var r1: Dictionary = s1.apply({"id": "m", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [0, 0], "to": [1, 0]}})
	t.eq(String(r1.get("code", "")), "SIM_NOT_MERGEABLE", "special + special is not mergeable")
	t.eq(s1.digest(), before, "rejected special merge leaves the board untouched")
	t.eq(int(s1.board.item(Vector2i(1, 0)).get("level", -1)), 1, "special stays at level 1")

	# two identical generators: same rejection (per-entity charge pool)
	var gen_project := _project()
	gen_project["levels"][0]["board"] = {"width": 3, "height": 1, "slots": [
		{"x": 0, "y": 0, "entity": "G", "level": 1},
		{"x": 1, "y": 0, "entity": "G", "level": 1},
	]}
	var s2 = _sim(gen_project)
	var r2: Dictionary = s2.apply({"id": "m", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [0, 0], "to": [1, 0]}})
	t.eq(String(r2.get("code", "")), "SIM_NOT_MERGEABLE", "generator + generator is not mergeable")

	# chips still merge (the rule did not change for them)
	var s3 = _sim(_project())
	var r3: Dictionary = s3.apply({"id": "m", "channel": "sim", "type": "merge", "at": 1.0,
		"payload": {"from": [1, 1], "to": [2, 1]}})
	t.ok(bool(r3.get("ok", false)), "chip + chip still merges", String(r3.get("code", "")))
	t.eq(int(s3.board.item(Vector2i(2, 1)).get("level", -1)), 2, "merged chip reached level 2")


# ------------------------------------------- directOrder: true = order-gated

func _test_direct_order_semantics(t) -> void:
	# no order needs A@2 in this fixture: only the flag decides pool membership
	var project := _project()
	project["levels"][0]["orders"] = []
	project["generators"] = {"G": {"charges": 5, "cooldown": 0,
		"outputs": [{"entity": "A", "weight": 1}],
		"rareOutputs": [{"entity": "A", "level": 2, "weight": 1, "directOrder": true}]}}
	var gated = _sim(project)
	t.eq(_pool_sizes(gated.tap_pool("G")), 1, "directOrder=true: rare stays out with no open order")
	t.ok(not _pool_has_rare(gated.tap_pool("G")), "directOrder=true: pool has no rare entry")

	project["generators"]["G"]["rareOutputs"][0]["directOrder"] = false
	var jackpot = _sim(project)
	t.eq(_pool_sizes(jackpot.tap_pool("G")), 2, "directOrder=false: rare joins the pool unconditionally")
	t.ok(_pool_has_rare(jackpot.tap_pool("G")), "directOrder=false: pool carries the rare entry")

	# missing flag keeps today's behaviour (order-gated), never an accidental jackpot
	project["generators"]["G"]["rareOutputs"][0].erase("directOrder")
	var legacy = _sim(project)
	t.eq(_pool_sizes(legacy.tap_pool("G")), 1, "missing directOrder defaults to order-gated")
	t.ok(not _pool_has_rare(legacy.tap_pool("G")), "missing directOrder does not create a jackpot")

	# and the gate still opens when an unfinished order actually needs it
	var wanted := _project()
	wanted["generators"] = {"G": {"charges": 5, "cooldown": 0,
		"outputs": [{"entity": "A", "weight": 1}],
		"rareOutputs": [{"entity": "A", "level": 2, "weight": 1, "directOrder": true}]}}
	var s2 = _sim(wanted)
	t.ok(_pool_has_rare(s2.tap_pool("G")), "directOrder=true: rare enters once an order needs it")


func _pool_sizes(pool: Array) -> int:
	return pool.size()


func _pool_has_rare(pool: Array) -> bool:
	for item in pool:
		if typeof(item) == TYPE_DICTIONARY and bool(item.get("rare", false)):
			return true
	return false
