extends RefCounted
## S2 core tests: board rules, generator economy, order/level flow, and the one
## property everything else leans on - same seed + same ordered events must give
## the same digest sequence, whether or not a view sink is attached.

const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")
const Evaluator = preload("res://src/core/event_evaluator.gd")
const Rng = preload("res://src/core/rng.gd")

const SAMPLE := "res://data/sample_project.json"


class CountingSink:
	extends RefCounted

	var calls: int = 0
	var sim_calls: int = 0
	var view_calls: int = 0

	func on_event(ev: Dictionary) -> void:
		calls += 1
		if String(ev.get("channel", "")) == "sim":
			sim_calls += 1
		else:
			view_calls += 1


func run(t) -> void:
	_test_rng(t)
	_test_model(t)
	_test_board(t)
	_test_merge_rules(t)
	_test_generator(t)
	_test_rare_pool(t)
	_test_deliver(t)
	_test_claim(t)
	_test_claim_unsatisfied_is_pure(t)
	_test_level_flow(t)
	_test_sample_run(t)
	_test_determinism(t)
	_test_parity(t)


# ------------------------------------------------------------------ fixtures

func _hud(coin: int = 0, star: int = 0, energy: int = 10) -> Dictionary:
	return {
		"level": 1,
		"energy": energy,
		"energyTickSeconds": 120,
		"energyTickMode": "decrement",
		"coin": coin,
		"star": star,
		"gem": 0,
		"exp": 0,
	}


func _entities() -> Dictionary:
	return {
		"A": {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 3},
		"B": {"kind": "chip", "family": "F", "chain": "b", "maxLevel": 10},
		"CH": {"kind": "character"},
		"GEN": {"kind": "generator", "maxLevel": 1},
	}


func _new_sim(project: Dictionary, seed_value: int):
	var m = ProjectModel.new()
	if not m.load_data(project):
		return null
	var s = Sim.new()
	s.setup(m, seed_value)
	return s


func _merge_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {"GEN": {"charges": 3, "cooldown": 1.0, "outputs": [{"entity": "A", "weight": 1}], "rareOutputs": []}},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "m1",
				"board": {
					"width": 7,
					"height": 2,
					"slots": [
						{"x": 0, "y": 0, "entity": "A", "level": 1},
						{"x": 1, "y": 0, "entity": "A", "level": 1},
						{"x": 2, "y": 0, "entity": "B", "level": 1},
						{"x": 3, "y": 0, "entity": "A", "level": 2},
						{"x": 4, "y": 0, "entity": "A", "level": 3},
						{"x": 5, "y": 0, "entity": "A", "level": 1},
						{"x": 0, "y": 1, "entity": "A", "level": 3},
						{"x": 6, "y": 1, "entity": "A", "level": 1},
					],
				},
				"obstacles": [{"slot": [5, 0], "type": "web"}],
				"orders": [],
			},
		],
		"timeline": [],
	}


func _gen_project(charges: int = 3, cooldown: float = 1.0) -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {"GEN": {"charges": charges, "cooldown": cooldown, "outputs": [{"entity": "A", "weight": 1}], "rareOutputs": []}},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "g1",
				"board": {"width": 5, "height": 1, "slots": [{"x": 0, "y": 0, "entity": "GEN", "level": 1}]},
				"obstacles": [],
				"orders": [],
			},
		],
		"timeline": [],
	}


func _full_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {"GEN": {"charges": 5, "cooldown": 0.0, "outputs": [{"entity": "A", "weight": 1}], "rareOutputs": []}},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "f1",
				"board": {"width": 1, "height": 1, "slots": [{"x": 0, "y": 0, "entity": "GEN", "level": 1}]},
				"obstacles": [],
				"orders": [],
			},
		],
		"timeline": [],
	}


func _rare_project(order_level: int) -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {
			"GEN": {
				"charges": 5,
				"cooldown": 0.0,
				"outputs": [{"entity": "A", "weight": 1}],
				"rareOutputs": [{"entity": "A", "level": 2, "weight": 1, "directOrder": true}],
			},
		},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "r1",
				"board": {
					"width": 3,
					"height": 1,
					"slots": [
						{"x": 0, "y": 0, "entity": "GEN", "level": 1},
						{"x": 2, "y": 0, "entity": "A", "level": 2},
					],
				},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": order_level}], "star": 1, "coin": 1},
				],
			},
		],
		"timeline": [],
	}


func _deliver_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(5, 1),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "d1",
				"board": {
					"width": 3,
					"height": 1,
					"slots": [
						{"x": 0, "y": 0, "entity": "A", "level": 2},
						{"x": 1, "y": 0, "entity": "B", "level": 1},
						{"x": 2, "y": 0, "entity": "A", "level": 1},
					],
				},
				"obstacles": [],
				"orders": [
					{
						"id": "o1",
						"character": "CH",
						"mission": [{"entity": "A", "level": 2}, {"entity": "B", "level": 1}],
						"star": 2,
						"coin": 7,
					},
				],
			},
		],
		"timeline": [],
	}


func _board_claim_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "b1",
				"board": {"width": 3, "height": 1, "slots": [{"x": 2, "y": 0, "entity": "A", "level": 2}]},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 2}], "star": 1, "coin": 4},
				],
			},
		],
		"timeline": [],
	}


func _unsat_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "u1",
				"board": {"width": 3, "height": 1, "slots": [{"x": 0, "y": 0, "entity": "A", "level": 1}]},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 3}], "star": 1, "coin": 9},
				],
			},
		],
		"timeline": [],
	}


func _flow_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {"GEN": {"charges": 2, "cooldown": 0.5, "outputs": [{"entity": "A", "weight": 1}], "rareOutputs": []}},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "level_1",
				"board": {
					"width": 5,
					"height": 1,
					"slots": [
						{"x": 0, "y": 0, "entity": "A", "level": 1},
						{"x": 4, "y": 0, "entity": "GEN", "level": 1},
					],
				},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 1}], "star": 1, "coin": 3},
				],
			},
			{
				"id": "level_2",
				"board": {"width": 4, "height": 2, "slots": [{"x": 1, "y": 1, "entity": "B", "level": 1}]},
				"obstacles": [],
				"orders": [
					{"id": "o2", "character": "CH", "mission": [{"entity": "B", "level": 1}], "star": 2, "coin": 4},
				],
			},
		],
		"timeline": [],
	}


func _gen12_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {
			"GEN": {
				"charges": 12,
				"cooldown": 0.0,
				"outputs": [{"entity": "A", "weight": 1}, {"entity": "B", "weight": 1}],
				"rareOutputs": [],
			},
		},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "s1",
				"board": {"width": 5, "height": 3, "slots": [{"x": 0, "y": 0, "entity": "GEN", "level": 1}]},
				"obstacles": [],
				"orders": [],
			},
		],
		"timeline": [],
	}


# ---------------------------------------------------------------------- tests

func _test_rng(t) -> void:
	var a = Rng.make(7, 0)
	var b = Rng.make(7, 0)
	t.eq(a.state, b.state, "same seed + stream -> same initial state")
	t.eq(a.next_u64(), b.next_u64(), "same seed -> same first draw")
	var c = Rng.make(11, 0)
	t.ne(Rng.make(7, 0).next_u64(), c.next_u64(), "different seed -> different first draw")
	t.ne(Rng.make(7, 0).state, Rng.make(7, 1).state, "different stream -> different state")
	var d = Rng.make(99, 3)
	var in_range := true
	for i in range(200):
		var f: float = d.next_float()
		if f < 0.0 or f >= 1.0:
			in_range = false
		if d.next_int(5) > 4:
			in_range = false
	t.ok(in_range, "next_float stays in [0,1) and next_int(n) in [0,n)")
	t.eq(d.next_int(0), 0, "next_int(0) is 0, not a crash")
	t.eq(d.pick_weighted([]), -1, "empty weighted pool -> -1")
	t.eq(d.pick_weighted([{"weight": 0}, {"weight": 0}]), -1, "all-zero weights -> -1")
	var picks := {}
	for i in range(400):
		picks[d.pick_weighted([{"weight": 1}, {"weight": 3}])] = true
	t.ok(picks.has(0) and picks.has(1), "weighted pick reaches both entries")


func _test_model(t) -> void:
	var m = ProjectModel.new()
	t.ok(m.load_file(SAMPLE), "sample_project.json loads into the model", m.load_error)
	t.eq(m.level_count(), 2, "sample has 2 levels")
	t.eq(String(m.level(0).get("id", "")), "level_1", "level order follows the array")
	t.eq(String(m.level(9).get("id", "")), "", "out-of-range level -> empty dict")
	t.eq(String(m.entity("CleanBox_C").get("kind", "")), "generator", "entity kind is readable")
	t.ok(m.entity("nope").is_empty(), "unknown entity -> empty dict")
	t.eq(int(m.generator("CleanBox_C").get("charges", -1)), 10, "generator charges are readable")
	t.ok(m.generator("CleanSet_Ca").is_empty(), "a chip has no generator behaviour")
	t.eq(m.entity_ids().size(), 6, "entity_ids lists 6 sample entities")
	var hud: Dictionary = m.hud_initial()
	for key in ["level", "energy", "energyTickSeconds", "energyTickMode", "coin", "star", "gem", "exp"]:
		t.ok(hud.has(key), "hud_initial carries " + key)
	t.eq(int(hud.get("coin", -1)), 9, "hud_initial reads the sample coin")
	hud["coin"] = 999
	t.eq(int(m.hud_initial().get("coin", -1)), 9, "hud_initial returns a fresh copy each call")

	var bad = ProjectModel.new()
	t.ok(not bad.load_file("res://data/does_not_exist.json"), "missing file -> load_file false")
	t.ok(not bad.load_error.is_empty(), "load_error explains a missing file")
	t.ok(not bad.load_data({"levels": []}), "load_data rejects empty levels")
	t.ok(not bad.load_data({"levels": [[]]}), "load_data rejects a project without entities")


func _test_board(t) -> void:
	var s = _new_sim(_merge_project(), 1)
	t.ok(s != null, "merge fixture sim builds")
	if s == null:
		return
	var b = s.board
	t.eq(b.width, 7, "board width from level data")
	t.eq(b.height, 2, "board height from level data")
	t.eq(b.item_count(), 8, "8 occupied cells")
	t.ok(b.has_item(Vector2i(0, 0)), "has_item sees an occupied cell")
	t.ok(not b.has_item(Vector2i(2, 1)), "has_item sees an empty cell")
	t.eq(String(b.item(Vector2i(3, 0)).get("entity", "")), "A", "item() returns the entity")
	t.eq(int(b.item(Vector2i(3, 0)).get("level", -1)), 2, "item() returns the level")
	t.ok(b.item(Vector2i(2, 1)).is_empty(), "item() of an empty cell is {}")
	t.ok(b.in_bounds(Vector2i(6, 1)), "in_bounds accepts the last cell")
	t.ok(not b.in_bounds(Vector2i(7, 1)), "in_bounds rejects x == width")
	t.ok(not b.in_bounds(Vector2i(-1, 0)), "in_bounds rejects negative")
	t.ok(b.is_blocked(Vector2i(5, 0)), "web cell reports blocked")
	t.ok(not b.is_blocked(Vector2i(0, 0)), "free cell is not blocked")
	t.eq(b.obstacle_types(Vector2i(5, 0)), ["web"], "obstacle_types lists the web")
	t.eq(b.first_free_cell(), Vector2i(6, 0), "first_free_cell scans row-major")

	var full = _new_sim(_full_project(), 1)
	t.eq(full.board.first_free_cell(), Vector2i(-1, -1), "full board -> (-1,-1)")

	var snap: Dictionary = b.snapshot()
	t.eq(int(snap.get("width", 0)), 7, "snapshot carries width")
	t.eq((snap.get("cells", []) as Array).size(), 8, "snapshot lists every cell")
	var first: Array = (snap.get("cells", []) as Array)[0]
	t.eq(first, [0, 0, "A", 1], "snapshot rows are [x, y, entity, level], sorted")
	t.eq((snap.get("obstacles", []) as Array).size(), 1, "snapshot lists obstacles")


func _test_merge_rules(t) -> void:
	var cases := [
		{"from": [0, 0], "to": [0, 0], "code": "SIM_SAME_CELL", "what": "same cell"},
		{"from": [0, 0], "to": [7, 0], "code": "SIM_SLOT_OOB", "what": "target out of bounds"},
		{"from": [5, 0], "to": [0, 0], "code": "SIM_BLOCKED", "what": "source under a web"},
		{"from": [0, 0], "to": [5, 0], "code": "SIM_BLOCKED", "what": "target under a web"},
		{"from": [1, 1], "to": [0, 0], "code": "SIM_SOURCE_EMPTY", "what": "empty source"},
		{"from": [0, 0], "to": [1, 1], "code": "SIM_TARGET_EMPTY", "what": "empty target"},
		{"from": [0, 0], "to": [2, 0], "code": "SIM_ENTITY_MISMATCH", "what": "different entity"},
		{"from": [0, 0], "to": [3, 0], "code": "SIM_LEVEL_MISMATCH", "what": "different level"},
		{"from": [4, 0], "to": [0, 1], "code": "SIM_MAX_LEVEL", "what": "level cap (3+1 > min(10, maxLevel 3))"},
		{"from": [0, 0], "to": [], "code": "SIM_SLOT_OOB", "what": "malformed target"},
	]
	for c in cases:
		var s = _new_sim(_merge_project(), 1)
		var before: String = s.digest()
		var r: Dictionary = s.apply({"type": "merge", "payload": {"from": c["from"], "to": c["to"]}})
		t.eq(String(r.get("code", "")), String(c["code"]), "merge rejects: " + String(c["what"]))
		t.eq(s.digest(), before, "rejected merge leaves the digest untouched (" + String(c["what"]) + ")")

	var adj = _new_sim(_merge_project(), 1)
	var r1: Dictionary = adj.apply({"type": "merge", "payload": {"from": [0, 0], "to": [1, 0]}})
	t.ok(bool(r1.get("ok", false)), "adjacent equal chips merge", str(r1))
	t.eq(int(adj.board.item(Vector2i(1, 0)).get("level", -1)), 2, "target levels up")
	t.ok(not adj.board.has_item(Vector2i(0, 0)), "source is cleared")

	var far = _new_sim(_merge_project(), 1)
	var r2: Dictionary = far.apply({"type": "merge", "payload": {"from": [6, 1], "to": [1, 0]}})
	t.ok(bool(r2.get("ok", false)), "non-adjacent chips still merge (M0 rule)", str(r2))
	t.eq(int(far.board.item(Vector2i(1, 0)).get("level", -1)), 2, "non-adjacent target levels up")
	t.ok(not far.board.has_item(Vector2i(6, 1)), "non-adjacent source is cleared")

	var drag = _new_sim(_merge_project(), 1)
	var r3: Dictionary = drag.apply({"type": "drag", "payload": {"from": [0, 0], "to": [1, 0]}})
	t.ok(bool(r3.get("ok", false)), "drag uses the same merge rules", str(r3))

	var junk = _new_sim(_merge_project(), 1)
	var r4: Dictionary = junk.apply({"type": "teleport", "payload": {}})
	t.eq(String(r4.get("code", "")), "SIM_UNKNOWN_TYPE", "unregistered sim type is rejected")


func _test_generator(t) -> void:
	var s = _new_sim(_gen_project(3, 1.0), 5)
	t.ok(s != null, "generator fixture sim builds")
	if s == null:
		return
	s.set_time(0.0)
	var r1: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.ok(bool(r1.get("ok", false)), "tap on a generator produces", str(r1))
	# 2026-11-05: the drop cell is now a seeded random free slot, not the first one.
	var spawned: Dictionary = s.last_spawn
	t.ok(not spawned.is_empty(), "a successful tap reports where the chip went")
	var spawn_to = spawned.get("to", [])
	t.ok(int(spawn_to[1]) != 0 or int(spawn_to[0]) != 0, "the chip does not stay on the generator")
	t.ok(s.board.has_item(Vector2i(int(spawn_to[0]), int(spawn_to[1]))),
			"the dropped chip sits on the reported cell")
	t.ok(not s.board.is_blocked(Vector2i(int(spawn_to[0]), int(spawn_to[1]))),
			"the drop cell is never an obstacle")
	t.eq(int(s.generator_state["GEN"]["charges"]), 2, "charge is consumed")
	t.ok(is_equal_approx(float(s.generator_state["GEN"]["ready_at"]), 1.0), "ready_at = time + cooldown")

	var before: String = s.digest()
	var r2: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.eq(String(r2.get("code", "")), "SIM_COOLDOWN", "tap inside cooldown is rejected")
	t.eq(s.digest(), before, "cooldown rejection changes nothing")

	s.set_time(1.0)
	var r3: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.ok(bool(r3.get("ok", false)), "tap after the cooldown works", str(r3))
	t.eq(int(s.generator_state["GEN"]["charges"]), 1, "second charge consumed")

	var r4: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [1, 1]}}})
	t.eq(String(r4.get("code", "")), "SIM_SLOT_OOB", "tap outside the board is rejected")
	var r5: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [1, 0]}}})
	t.eq(String(r5.get("code", "")), "SIM_TAP_NO_GENERATOR", "tapping a chip is not a generator tap")
	var r6: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [4, 0]}}})
	t.eq(String(r6.get("code", "")), "SIM_TAP_NO_GENERATOR", "tapping an empty cell is not a generator tap")

	var dry = _new_sim(_gen_project(1, 0.0), 5)
	dry.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	var r7: Dictionary = dry.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.eq(String(r7.get("code", "")), "SIM_NO_CHARGES", "no charges left is reported")

	var stuck = _new_sim(_full_project(), 5)
	var r8: Dictionary = stuck.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.eq(String(r8.get("code", "")), "SIM_BOARD_FULL", "full board blocks the output")
	t.ok(stuck.board_full_pending, "full board sets board_full_pending")
	t.eq(int(stuck.generator_state["GEN"]["charges"]), 5, "board_full keeps the charge")
	t.eq(int(stuck.board.item_count()), 1, "board_full adds nothing")


func _test_rare_pool(t) -> void:
	var wanted = _new_sim(_rare_project(2), 5)
	t.eq(wanted.tap_pool("GEN").size(), 2, "rare joins the pool when an order wants A lv2")
	var has_rare := false
	for entry in wanted.tap_pool("GEN"):
		if bool(entry.get("rare", false)) and int(entry.get("level", 0)) == 2:
			has_rare = true
	t.ok(has_rare, "the pool entry is the rare A lv2")
	t.ok(bool(wanted.apply({"type": "order_claim", "payload": {"order": "o1"}}).get("ok", false)), "order satisfied by the board chip")
	t.eq(wanted.tap_pool("GEN").size(), 1, "rare leaves the pool once the order is done")

	var wrong_level = _new_sim(_rare_project(3), 5)
	t.eq(wrong_level.tap_pool("GEN").size(), 1, "rare stays out when the order wants lv3, not lv2")

	var no_order = _new_sim(_gen_project(3, 0.0), 5)
	t.eq(no_order.tap_pool("GEN").size(), 1, "no orders -> no rare in the pool")
	var before: String = no_order.digest()
	no_order.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	var no_order_to = no_order.last_spawn.get("to", [0, 0])
	t.eq(int(no_order.board.item(Vector2i(int(no_order_to[0]), int(no_order_to[1]))).get("level", -1)), 1,
			"plain output stays at lv1")
	t.ne(no_order.digest(), before, "a successful tap does change the state")


func _test_deliver(t) -> void:
	var s = _new_sim(_deliver_project(), 3)
	var r1: Dictionary = s.apply({"type": "deliver", "payload": {"from": [0, 0], "order": "o1"}})
	t.ok(bool(r1.get("ok", false)), "deliver the first mission item", str(r1))
	t.eq(int(s.orders[0]["mission"][0]["have"]), 1, "mission[0] have becomes 1")
	t.ok(not s.board.has_item(Vector2i(0, 0)), "delivered item leaves the board")
	t.ok(not bool(s.orders[0]["done"]), "deliver alone does not complete the order")

	var r2: Dictionary = s.apply({"type": "deliver", "payload": {"from": [1, 0], "order": "o1"}})
	t.ok(bool(r2.get("ok", false)), "deliver the second mission item", str(r2))
	t.eq(int(s.orders[0]["mission"][1]["have"]), 1, "mission[1] have becomes 1")

	var r3: Dictionary = s.apply({"type": "deliver", "payload": {"from": [9, 0], "order": "o1"}})
	t.eq(String(r3.get("code", "")), "SIM_SLOT_OOB", "deliver from outside the board")
	var r4: Dictionary = s.apply({"type": "deliver", "payload": {"from": [0, 0], "order": "o1"}})
	t.eq(String(r4.get("code", "")), "SIM_DELIVER_MISMATCH", "deliver from an empty cell")
	var r5: Dictionary = s.apply({"type": "deliver", "payload": {"from": [2, 0], "order": "o1"}})
	t.eq(String(r5.get("code", "")), "SIM_DELIVER_MISMATCH", "wrong entity/level is a mismatch")
	var r6: Dictionary = s.apply({"type": "deliver", "payload": {"from": [2, 0], "order": "nope"}})
	t.eq(String(r6.get("code", "")), "SIM_ORDER_UNKNOWN", "deliver to an unknown order")

	var junk = _new_sim(_deliver_project(), 3)
	junk.apply({"type": "order_claim", "payload": {"order": "o1"}})
	var r7: Dictionary = junk.apply({"type": "deliver", "payload": {"from": [2, 0], "order": "o1"}})
	t.eq(String(r7.get("code", "")), "SIM_DELIVER_MISMATCH", "deliver into a claimed order is refused")


func _test_claim(t) -> void:
	var s = _new_sim(_deliver_project(), 3)
	s.apply({"type": "deliver", "payload": {"from": [0, 0], "order": "o1"}})
	s.apply({"type": "deliver", "payload": {"from": [1, 0], "order": "o1"}})
	var r1: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.ok(bool(r1.get("ok", false)), "claim with both items delivered", str(r1))
	t.eq(int(s.hud["coin"]), 12, "coin = 5 + 7")
	t.eq(int(s.hud["star"]), 3, "star = 1 + 2")
	t.ok(bool(s.orders[0]["done"]), "order is marked done")
	t.ok(s.level_complete_pending, "claiming the last order completes the level")
	var r2: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.eq(String(r2.get("code", "")), "SIM_ORDER_DONE", "a claimed order cannot be claimed twice")

	var board_path = _new_sim(_board_claim_project(), 3)
	var r3: Dictionary = board_path.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.ok(bool(r3.get("ok", false)), "claim consumes matching items straight from the board", str(r3))
	t.ok(not board_path.board.has_item(Vector2i(2, 0)), "the consumed board item is gone")
	t.eq(int(board_path.hud["coin"]), 4, "board-claim pays the order coin")
	t.eq(int(board_path.hud["star"]), 1, "board-claim pays the order star")

	var junk = _new_sim(_deliver_project(), 3)
	var r4: Dictionary = junk.apply({"type": "order_claim", "payload": {"order": "nope"}})
	t.eq(String(r4.get("code", "")), "SIM_ORDER_UNKNOWN", "unknown order id")


func _test_claim_unsatisfied_is_pure(t) -> void:
	var s = _new_sim(_unsat_project(), 3)
	var before: String = s.digest()
	var coin_before := int(s.hud["coin"])
	var r: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.eq(String(r.get("code", "")), "SIM_ORDER_UNSATISFIED", "unsatisfied claim is rejected")
	t.eq(s.hud["coin"], coin_before, "unsatisfied claim pays nothing")
	t.ok(not bool(s.orders[0]["done"]), "unsatisfied claim does not mark the order done")
	t.eq(s.digest(), before, "unsatisfied claim leaves the digest untouched")
	t.ok(not s.level_complete_pending, "unsatisfied claim does not complete the level")


func _test_level_flow(t) -> void:
	var s = _new_sim(_flow_project(), 9)
	var r0: Dictionary = s.apply({"type": "level_next", "payload": {}})
	t.eq(String(r0.get("code", "")), "SIM_LEVEL_NOT_COMPLETE", "level_next before completion is rejected")
	var r1: Dictionary = s.apply({"type": "level_complete", "payload": {}})
	t.eq(String(r1.get("code", "")), "SIM_LEVEL_NOT_COMPLETE", "level_complete before completion is rejected")

	var r2: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.ok(bool(r2.get("ok", false)), "claim level_1 order", str(r2))
	t.eq(int(s.hud["coin"]), 3, "level_1 pays 3 coins")
	var r3: Dictionary = s.apply({"type": "level_complete", "payload": {}})
	t.ok(bool(r3.get("ok", false)), "level_complete after the claim")
	var r4: Dictionary = s.apply({"type": "level_complete", "payload": {}})
	t.ok(bool(r4.get("ok", false)), "level_complete is idempotent")

	var r5: Dictionary = s.apply({"type": "level_next", "payload": {}})
	t.ok(bool(r5.get("ok", false)), "level_next enters level 2", str(r5))
	t.eq(s.level_index, 1, "level_index advanced")
	t.eq(s.current_level_id(), "level_2", "current_level_id is level_2")
	t.eq(String(s.orders[0].get("id", "")), "o2", "orders reload with the new level")
	t.ok(not s.level_complete_pending, "pending flag is cleared on level change")
	t.ok(not s.board.has_item(Vector2i(0, 0)), "level_1 board is gone")
	t.ok(s.board.has_item(Vector2i(1, 1)), "level_2 board is loaded")
	t.eq(int(s.generator_state["GEN"]["charges"]), 2, "generator charges reset on level change")
	t.eq(int(s.hud["coin"]), 3, "hud survives the level change")

	var r6: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o2"}})
	t.ok(bool(r6.get("ok", false)), "claim level_2 order", str(r6))
	t.eq(int(s.hud["coin"]), 7, "coin accumulates across levels")
	t.eq(int(s.hud["star"]), 3, "star accumulates across levels")
	t.ok(s.level_complete_pending, "level_2 is complete")
	var r7: Dictionary = s.apply({"type": "level_next", "payload": {}})
	t.eq(String(r7.get("code", "")), "SIM_NO_MORE_LEVELS", "no level after the last one")
	t.eq(s.level_index, 1, "failed level_next does not move the index")

	var energy = _new_sim(_flow_project(), 9)
	energy.apply({"type": "energy_tick", "payload": {"delta": -50}})
	t.eq(int(energy.hud["energy"]), 0, "energy floors at 0")
	energy.apply({"type": "energy_tick", "payload": {"delta": 4}})
	t.eq(int(energy.hud["energy"]), 4, "energy_tick applies the delta")

	var marker = _new_sim(_flow_project(), 9)
	var before: String = marker.digest()
	var r8: Dictionary = marker.apply({"type": "board_full", "payload": {}})
	t.ok(bool(r8.get("ok", false)), "board_full is an ok marker")
	t.eq(marker.digest(), before, "board_full changes nothing")


func _test_sample_run(t) -> void:
	var m = ProjectModel.new()
	t.ok(m.load_file(SAMPLE), "sample loads for the integration run", m.load_error)
	var ev = Evaluator.new()
	ev.setup(m, 20261104, null)
	var loaded: Dictionary = ev.load_timeline(m.project.get("timeline", []))
	t.ok(bool(loaded.get("ok", false)), "sample timeline resolves", str(loaded.get("errors", [])))
	t.eq(int(loaded.get("count", 0)), 21, "21 events dispatched")
	t.ok(is_equal_approx(float(loaded.get("end_time", -1.0)), 30.0), "end_time is 30.0s")

	var run: Dictionary = ev.run_all()
	t.ok(bool(run.get("ok", false)), "sample run has no rejected sim event", str(run.get("rejected", [])))
	t.eq(int(run.get("dispatched", 0)), 21, "run_all walks every event")
	t.eq((run.get("rejected", []) as Array).size(), 0, "no rejected events")
	t.eq((run.get("digests", []) as Array).size(), 10, "10 sim events produce 10 digests")
	t.ok(is_equal_approx(float(run.get("end_time", -1.0)), 30.0), "run_all reports end_time 30.0")

	var s = ev.sim
	t.eq(s.level_index, 1, "final level_index is 1")
	t.eq(s.current_level_id(), "level_2", "final level is level_2")
	t.eq(int(s.hud["coin"]), 22, "coin = 9 + 5 + 8")
	t.eq(int(s.hud["star"]), 3, "star = 0 + 1 + 2")
	t.eq(int(s.hud["energy"]), 87, "energy = 88 - 1")
	t.ok(s.level_complete_pending, "order_2 leaves level_2 complete")
	t.ok(not s.board_full_pending, "the sample never fills the board")
	t.eq(int(s.generator_state["CleanBox_C"]["charges"]), 9, "level_2 generator reset to 10 then tapped once")
	t.eq(int(s.board.item_count()), 3, "3 items left on the level_2 board")
	t.ok(s.board.has_item(Vector2i(5, 0)) == false, "claimed mission items were consumed")

	var before: String = s.digest()
	var r: Dictionary = s.apply({"type": "level_next", "payload": {}})
	t.eq(String(r.get("code", "")), "SIM_NO_MORE_LEVELS", "sample ends at the last level")
	t.eq(s.digest(), before, "the rejected level_next leaves the state untouched")

	# Opt-in evidence line for cross-process comparison (S3 / render stage):
	# `... --suite res://tests/t_sim.gd --digest`
	if OS.get_cmdline_user_args().has("--digest"):
		print("[sim] sample_final_digest=" + before)
		print("[sim] sample_event_digests=" + str((run.get("digests", []) as Array).size()))


func _test_determinism(t) -> void:
	var a: Array = _tap_digests(_gen12_project(), 7)
	var b: Array = _tap_digests(_gen12_project(), 7)
	var c: Array = _tap_digests(_gen12_project(), 11)
	t.eq(a.size(), 12, "12 taps -> 12 digests")
	t.eq(a, b, "same seed -> identical digest sequence")
	t.ne(str(a), str(c), "different seed -> a different sequence")

	var runs: Array = []
	for i in range(3):
		var m = ProjectModel.new()
		m.load_file(SAMPLE)
		var ev = Evaluator.new()
		ev.setup(m, 20261104, null)
		ev.load_timeline(m.project.get("timeline", []))
		var r: Dictionary = ev.run_all()
		runs.append(r.get("digests", []))
	t.eq(runs[0], runs[1], "sample run 2 matches run 1 digest-for-digest")
	t.eq(runs[1], runs[2], "sample run 3 matches run 2 digest-for-digest")

	var m2 = ProjectModel.new()
	m2.load_file(SAMPLE)
	var ev2 = Evaluator.new()
	ev2.setup(m2, 20261104, null)
	ev2.load_timeline(m2.project.get("timeline", []))
	var first: Dictionary = ev2.run_all()
	ev2.reset()
	var second: Dictionary = ev2.run_all()
	t.eq(first.get("digests", []), second.get("digests", []), "reset() replays to the same digests")
	t.eq(ev2.sim.digest(), StateDigestProbe.of(ev2.sim.snapshot()), "digest is the hash of the snapshot")


func _tap_digests(project: Dictionary, seed_value: int) -> Array:
	var s = _new_sim(project, seed_value)
	var out: Array = []
	for i in range(12):
		s.set_time(float(i))
		s.apply({"type": "tap", "at": float(i), "payload": {"target": {"slot": [0, 0]}}})
		out.append(s.digest())
	return out


func _test_parity(t) -> void:
	var m = ProjectModel.new()
	m.load_file(SAMPLE)
	var plain = Evaluator.new()
	plain.setup(m, 20261104, null)
	plain.load_timeline(m.project.get("timeline", []))
	var run_null: Dictionary = plain.run_all()

	var sink = CountingSink.new()
	var m2 = ProjectModel.new()
	m2.load_file(SAMPLE)
	var watched = Evaluator.new()
	watched.setup(m2, 20261104, sink)
	watched.load_timeline(m2.project.get("timeline", []))
	var run_sink: Dictionary = watched.run_all()

	t.ok(bool(run_null.get("ok", false)) and bool(run_sink.get("ok", false)), "both runs pass")
	t.eq(run_null.get("digests", []), run_sink.get("digests", []), "view sink does not perturb the sim")
	t.eq(plain.sim.digest(), watched.sim.digest(), "final state is identical with and without a sink")
	t.eq(sink.calls, 21, "the sink sees every event, view included")
	t.eq(sink.sim_calls, 10, "the sink sees all 10 sim events")
	t.eq(sink.view_calls, 11, "the sink sees all 11 view events")

	var ev = Evaluator.new()
	ev.setup(m, 1, null)
	var bad: Dictionary = ev.load_timeline([
		{"id": "x", "channel": "view", "type": "text", "at": {"after": "missing", "offset": 0.1}, "payload": {}},
	])
	t.ok(not bool(bad.get("ok", false)), "a broken timeline refuses to load")
	t.ok(not (bad.get("errors", []) as Array).is_empty(), "load_timeline surfaces the resolver errors")
	t.eq(String(ev.step().get("code", "")), "EVAL_END", "nothing to step after a failed load")

	var walk = Evaluator.new()
	var m3 = ProjectModel.new()
	m3.load_file(SAMPLE)
	walk.setup(m3, 20261104, null)
	walk.load_timeline(m3.project.get("timeline", []))
	var first_step: Dictionary = walk.step()
	t.eq(String(first_step.get("id", "")), "e01", "step() walks the sorted order")
	t.eq(walk.cursor, 1, "cursor advances one event at a time")
	while walk.cursor < walk.events.size():
		walk.step()
	t.eq(String(walk.step().get("code", "")), "EVAL_END", "single stepping ends with EVAL_END")


## Tiny probe object so the test can hash the snapshot with the same canonical
## encoder the sim uses, without exposing state_digest as part of the sim API.
class StateDigestProbe:
	extends RefCounted

	static func of(value) -> String:
		var StateDigest := load("res://src/core/state_digest.gd")
		return StateDigest.of(value)
