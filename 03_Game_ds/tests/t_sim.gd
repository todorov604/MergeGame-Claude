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
	_test_claim_consumes_the_clicked_cell(t)
	_test_blast_radius_from_json(t)
	_test_ice_waits_for_its_own_timer(t)
	_test_claim_reports_consumed_cells(t)
	_test_claim_unsatisfied_is_pure(t)
	_test_level_flow(t)
	_test_sample_run(t)
	_test_flow_run(t)
	_test_ice_per_cell(t)
	_test_ice_restarts_each_level(t)
	_test_icon_override_flows_through(t)
	_test_determinism(t)
	_test_parity(t)


# ------------------------------------------------------------------ fixtures

func _hud(coin: int = 0, energy: int = 10) -> Dictionary:
	return {
		"level": 1,
		"energy": energy,
		"energyTickSeconds": 120,
		"energyTickMode": "decrement",
		"coin": coin,
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
		"hud": {"energy": 3, "coin": 0, "gem": 0},
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
		"hud": {"energy": charges, "coin": 0, "gem": 0},
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
		"hud": {"energy": 5, "coin": 0, "gem": 0},
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
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": order_level}], "coin": 1},
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
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 2}],
						"coin": 4, "gem": 3, "energy": 40},
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
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 3}], "coin": 9},
				],
			},
		],
		"timeline": [],
	}


func _flow_project() -> Dictionary:
	return {
		"version": 2,
		"hud": {"energy": 2, "coin": 0, "gem": 0},
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
					{"id": "o1", "character": "CH", "mission": [{"entity": "A", "level": 1}], "coin": 3},
				],
			},
			{
				"id": "level_2",
				"board": {"width": 4, "height": 2, "slots": [{"x": 1, "y": 1, "entity": "B", "level": 1}]},
				"obstacles": [],
				"orders": [
					{"id": "o2", "character": "CH", "mission": [{"entity": "B", "level": 1}], "coin": 4},
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
	t.ok(not String(m.level(0).get("id", "")).is_empty(), "level order follows the array", String(m.level(0).get("id", "")))
	t.eq(String(m.level(9).get("id", "")), "", "out-of-range level -> empty dict")
	t.eq(String(m.entity("CleanBox_C").get("kind", "")), "generator", "entity kind is readable")
	t.ok(m.entity("nope").is_empty(), "unknown entity -> empty dict")
	t.eq(int(m.generator("CleanBox_C").get("charges", -1)), 10, "generator charges are readable")
	t.ok(m.generator("CleanSet_Ca").is_empty(), "a chip has no generator behaviour")
	t.eq(m.entity_ids().size(), int(m.project.get("entities", {}).size()), "entity_ids lists every entity in the project")
	var hud: Dictionary = m.hud_initial()
	for key in ["level", "energy", "energyTickSeconds", "energyTickMode", "coin", "gem", "exp"]:
		t.ok(hud.has(key), "hud_initial carries " + key)
	# 2026-11-12：金币数从数据读，不写死（操作者会改 hud.coin）
	var coin0: int = int((m.project.get("hud", {}) as Dictionary).get("coin", -1))
	t.eq(int(hud.get("coin", -2)), coin0, "hud_initial reads the project coin")
	hud["coin"] = 999
	t.eq(int(m.hud_initial().get("coin", -2)), coin0, "hud_initial returns a fresh copy each call")

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
	# 2026-11-12：第 5 位是图标覆盖（空串 = 跟 entity），旧读者只用前 4 位
	t.eq(first.slice(0, 4), [0, 0, "A", 1], "snapshot rows are [x, y, entity, level, icon], sorted")
	t.eq(String(first[4]) if first.size() > 4 else "", "", "没有覆盖时第 5 位是空串")
	t.eq((snap.get("obstacles", []) as Array).size(), 1, "snapshot lists obstacles")


func _test_merge_rules(t) -> void:
	var cases := [
		{"from": [0, 0], "to": [0, 0], "code": "SIM_SAME_CELL", "what": "same cell"},
		{"from": [0, 0], "to": [7, 0], "code": "SIM_SLOT_OOB", "what": "target out of bounds"},
		{"from": [5, 0], "to": [0, 0], "code": "SIM_BLOCKED", "what": "source under a web"},
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

	# 2026-11-11：拖同款棋子压到蜘蛛网上 = 解锁网 + 合成高一级（不再被挡住）。
	var web = _new_sim(_merge_project(), 1)
	t.eq(web.board.obstacle_types(Vector2i(5, 0)), ["web"], "夹具里 (5,0) 被网盖住")
	t.eq(int(web.board.item(Vector2i(5, 0)).get("level", 0)), 1, "网下压着一枚 lv1 的 A")
	var rw: Dictionary = web.apply({"type": "merge", "payload": {"from": [0, 0], "to": [5, 0]}})
	t.ok(bool(rw.get("ok", false)), "同款棋子拖到网上可以合并（解锁网）", str(rw))
	t.ok(bool(rw.get("web_unlocked", false)), "返回值标明这次合并解锁了蜘蛛网")
	t.eq(web.board.obstacle_types(Vector2i(5, 0)), [], "网被解锁，格子干净了")
	t.eq(int(web.board.item(Vector2i(5, 0)).get("level", -1)), 2, "合并结果高一级（lv2）")
	t.ok(not web.board.has_item(Vector2i(0, 0)), "拖过来的那枚被吃掉")

	# 2026-11-11：**盒子炸出来的网**同样压着一枚棋子（否则拖同款没有比较对象）。
	var blown = _new_sim(_blast_project(1), 1)
	var bomb: Dictionary = blown.apply({"type": "merge", "payload": {"from": [3, 2], "to": [2, 2]}})
	t.ok(bool(bomb.get("ok", false)), "先合一次把邻格的盒子炸开", str(bomb))
	t.ok(blown.board.obstacle_types(Vector2i(2, 3)).has("web"), "盒子炸开后该格是网")
	t.ok(blown.board.has_item(Vector2i(2, 3)), "新网下面压着一枚棋子", str(blown.board.item(Vector2i(2, 3))))
	var under: Dictionary = blown.board.item(Vector2i(2, 3))
	var nb := Vector2i(0, 3)
	blown.board.put(nb, String(under.get("entity", "")), int(under.get("level", 1)))
	var unlock: Dictionary = blown.apply({"type": "merge",
			"payload": {"from": [nb.x, nb.y], "to": [2, 3]}})
	t.ok(bool(unlock.get("ok", false)), "拖同款压到炸出来的网上可以解锁并升级", str(unlock))
	t.eq(blown.board.obstacle_types(Vector2i(2, 3)), [], "网被解锁")
	t.eq(int(blown.board.item(Vector2i(2, 3)).get("level", -1)),
			int(under.get("level", 1)) + 1, "结果是高一级")

	var web_bad = _new_sim(_merge_project(), 1)
	var rb: Dictionary = web_bad.apply({"type": "merge", "payload": {"from": [2, 0], "to": [5, 0]}})
	t.eq(String(rb.get("code", "")), "SIM_ENTITY_MISMATCH", "不同款的棋子压上去不解锁（先报款式不同）")
	t.ok(web_bad.board.obstacle_types(Vector2i(5, 0)).has("web"), "网还在")

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
	t.eq(String(r7.get("code", "")), "SIM_NO_ENERGY", "no energy left is reported")

	var stuck = _new_sim(_full_project(), 5)
	var r8: Dictionary = stuck.apply({"type": "tap", "payload": {"target": {"slot": [0, 0]}}})
	t.eq(String(r8.get("code", "")), "SIM_BOARD_FULL", "full board blocks the output")
	t.ok(stuck.board_full_pending, "full board sets board_full_pending")
	t.eq(int(stuck.generator_state["GEN"]["charges"]), 5, "board_full keeps the energy")
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

	# 2026-11-10：最后一行收满 = 整单交付完成（自动结算，不用再点卡）
	var r2: Dictionary = s.apply({"type": "deliver", "payload": {"from": [1, 0], "order": "o1"}})
	t.ok(bool(r2.get("ok", false)), "deliver the second mission item", str(r2))
	t.ok(bool(r2.get("settled", false)), "the last row settles the order")
	t.ok(bool(s.orders[0]["done"]), "settled order is marked done")
	t.eq(int(s.hud["coin"]), 12, "settling credits the order coin")
	t.ok(s.level_complete_pending, "settling the last order completes the level")

	var r3: Dictionary = s.apply({"type": "deliver", "payload": {"from": [9, 0], "order": "o1"}})
	t.eq(String(r3.get("code", "")), "SIM_DELIVER_MISMATCH", "deliver into a settled order is refused")
	var r6: Dictionary = s.apply({"type": "deliver", "payload": {"from": [2, 0], "order": "nope"}})
	t.eq(String(r6.get("code", "")), "SIM_ORDER_UNKNOWN", "deliver to an unknown order")

	# 行号可以精确指定；不在那一行的棋子照样拒收
	var rows = _new_sim(_deliver_project(), 3)
	var a: Dictionary = rows.apply({"type": "deliver", "payload": {"from": [0, 0], "order": "o1", "row": 0}})
	t.ok(bool(a.get("ok", false)), "deliver into an explicit row", str(a))
	t.eq(int(a.get("row", -1)), 0, "the response reports which row took it")
	var b: Dictionary = rows.apply({"type": "deliver", "payload": {"from": [1, 0], "order": "o1", "row": 0}})
	t.eq(String(b.get("code", "")), "SIM_DELIVER_MISMATCH", "row 0 already has that chip")
	var c: Dictionary = rows.apply({"type": "deliver", "payload": {"from": [1, 0], "order": "o1", "row": 1}})
	t.ok(bool(c.get("ok", false)), "row 1 takes its own chip", str(c))

	var junk = _new_sim(_deliver_project(), 3)
	junk.apply({"type": "order_claim", "payload": {"order": "o1"}})
	var r7: Dictionary = junk.apply({"type": "deliver", "payload": {"from": [2, 0], "order": "o1"}})
	t.eq(String(r7.get("code", "")), "SIM_DELIVER_MISMATCH", "deliver into a claimed order is refused")


func _test_claim(t) -> void:
	var s = _new_sim(_deliver_project(), 3)
	# 2026-11-10：全交完会自动结算，所以这里只交付一枚，剩下那行由点卡从棋盘取
	s.apply({"type": "deliver", "payload": {"from": [0, 0], "order": "o1"}})
	var r1: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.ok(bool(r1.get("ok", false)), "claim finishes the rows that were not delivered", str(r1))
	t.eq(int(s.hud["coin"]), 12, "coin = 5 + 7")
	t.ok(bool(s.orders[0]["done"]), "order is marked done")
	t.ok(s.level_complete_pending, "claiming the last order completes the level")
	var r2: Dictionary = s.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.eq(String(r2.get("code", "")), "SIM_ORDER_DONE", "a claimed order cannot be claimed twice")

	var board_path = _new_sim(_board_claim_project(), 3)
	var r3: Dictionary = board_path.apply({"type": "order_claim", "payload": {"order": "o1"}})
	t.ok(bool(r3.get("ok", false)), "claim consumes matching items straight from the board", str(r3))
	t.ok(not board_path.board.has_item(Vector2i(2, 0)), "the consumed board item is gone")
	t.eq(int(board_path.hud["coin"]), 4, "board-claim pays the order coin")
	# 2026-11-09：订单的钻石奖励（卡片蓝条上那个数字）在同一个时刻入账
	t.eq(int(board_path.hud["gem"]), 3, "board-claim pays the order gems")
	t.eq(int(board_path.snapshot()["orders"][0].get("gem", -1)), 3,
			"snapshot carries the order gem reward for the card strip")
	# 2026-11-09：订单的体力（闪电）奖励同一刻入账
	t.eq(int(board_path.hud["energy"]), 50, "board-claim pays the order energy (10 + 40)")
	t.eq(int(board_path.snapshot()["orders"][0].get("energy", -1)), 40,
			"snapshot carries the order energy reward for the card strip")

	var junk = _new_sim(_deliver_project(), 3)
	var r4: Dictionary = junk.apply({"type": "order_claim", "payload": {"order": "nope"}})
	t.eq(String(r4.get("code", "")), "SIM_ORDER_UNKNOWN", "unknown order id")


## 2026-11-09 回归：交付必须消耗"被点击的那一格"。
## 之前 sim 只取行优先第一个匹配格，第 2 关棋子一多就会去别处取棋，
## 玩家点的格子原地不动（看起来"交了但没消失"，绿框也不退）。
func _test_claim_consumes_the_clicked_cell(t) -> void:
	var m = ProjectModel.new()
	t.ok(m.load_data(_clicked_cell_project()), "clicked-cell project loads")
	var s = Sim.new()
	s.setup(m, 3)
	# 行优先第一枚是 (0,0)；玩家点的是 (2,0)。
	t.ok(s.board.has_item(Vector2i(0, 0)), "(0,0) has the first row-major match")
	t.ok(s.board.has_item(Vector2i(2, 0)), "(2,0) is the clicked cell")
	var r: Dictionary = s.apply({"type": "order_claim",
			"payload": {"order": "o1", "src": [2, 0]}})
	t.ok(bool(r.get("ok", false)), "claim with src succeeds", str(r))
	t.ok(not s.board.has_item(Vector2i(2, 0)), "the clicked cell is consumed")
	t.ok(s.board.has_item(Vector2i(0, 0)), "the earlier row-major match is left alone")

	# 第二行任务仍然走行优先回退：点击格只吃掉它匹配的那一行。
	var s2 = Sim.new()
	s2.setup(m, 3)
	var r2: Dictionary = s2.apply({"type": "order_claim",
			"payload": {"order": "o2", "src": [0, 0]}})
	t.ok(bool(r2.get("ok", false)), "claim o2 with src (0,0)", str(r2))
	t.ok(not s2.board.has_item(Vector2i(0, 0)), "clicked (0,0) consumed for o2")
	t.ok(s2.board.has_item(Vector2i(2, 0)), "(2,0) untouched by o2 claim")


## 2026-11-10：合并炸开半径来自 JSON 的 blast（1 = 上下左右；2 = 曼哈顿距离再外一层）。
## 反向验证：把 blast 固定成 1（或在 _unlock_neighbours 里只用 4 邻格），这两条会红。
func _test_blast_radius_from_json(t) -> void:
	var m1 = ProjectModel.new()
	t.ok(m1.load_data(_blast_project(1)), "blast=1 project loads")
	var s1 = Sim.new()
	s1.setup(m1, 1)
	t.eq(s1.blast_radius(), 1, "blast 半径读自 JSON（1）")
	var r1: Dictionary = s1.apply({"type": "merge", "payload": {"from": [3, 2], "to": [2, 2]}})
	t.ok(bool(r1.get("ok", false)), "merge at (2,2) ok", str(r1))
	t.ok(not s1.board.obstacle_types(Vector2i(2, 3)).has("lock"),
			"blast=1 时邻格的蓝盒子被砸开", str(s1.board.obstacle_types(Vector2i(2, 3))))
	var touched: Array = s1.board.obstacle_types(Vector2i(2, 3))
	# 2026-11-11（操作者改口径）：蓝盒子砸开**只出蜘蛛网**，不再随机出冰块。
	t.eq(touched, ["web"], "蓝盒子砸开只出蜘蛛网（冰块那条路已去掉）")
	t.ok(s1.board.obstacle_types(Vector2i(1, 1)).has("web"),
			"blast=1 不动第二层（1,1 的网还在）", str(s1.board.obstacle_types(Vector2i(1, 1))))
	t.ok(s1.board.obstacle_types(Vector2i(3, 3)).has("web"), "blast=1 不动第二层（3,3 的网还在）")

	var m2 = ProjectModel.new()
	t.ok(m2.load_data(_blast_project(2)), "blast=2 project loads")
	var s2 = Sim.new()
	s2.setup(m2, 1)
	t.eq(s2.blast_radius(), 2, "blast 半径读自 JSON（2）")
	var r2: Dictionary = s2.apply({"type": "merge", "payload": {"from": [3, 2], "to": [2, 2]}})
	t.ok(bool(r2.get("ok", false)), "merge at (2,2) ok (blast=2)", str(r2))
	# 2026-11-11：蜘蛛网不再被爆炸炸开 —— 只能靠拖同款棋子解锁。
	t.ok(s2.board.obstacle_types(Vector2i(1, 1)).has("web"),
			"blast=2 也不再炸开蜘蛛网（1,1 的网还在）", str(s2.board.obstacle_types(Vector2i(1, 1))))
	t.ok(s2.board.obstacle_types(Vector2i(3, 3)).has("web"),
			"blast=2 也不再炸开蜘蛛网（3,3 的网还在）", str(s2.board.obstacle_types(Vector2i(3, 3))))


func _blast_project(radius: int) -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "b1",
				"blast": radius,
				"board": {"width": 5, "height": 5, "slots": [
					{"x": 2, "y": 2, "entity": "A", "level": 1},
					{"x": 3, "y": 2, "entity": "A", "level": 1},
				]},
				"obstacles": [
					{"slot": [1, 1], "type": "web"},
					{"slot": [3, 3], "type": "web"},
					{"slot": [2, 3], "type": "lock"},
				],
				"orders": [
					{"id": "bo1", "character": "CH",
						"mission": [{"entity": "A", "level": 2}], "coin": 4},
				],
			},
		],
		"seed": 5,
	}


func _clicked_cell_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "c1",
				"board": {"width": 3, "height": 1, "slots": [
					{"x": 0, "y": 0, "entity": "A", "level": 2},
					{"x": 2, "y": 0, "entity": "A", "level": 2},
				]},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH",
						"mission": [{"entity": "A", "level": 2}], "coin": 4},
					{"id": "o2", "character": "CH",
						"mission": [{"entity": "A", "level": 2}], "coin": 4},
				],
			},
		],
		"timeline": [],
	}


## 2026-11-09 回归：交付要把"真正被消耗的格子"回报给视图层，
## 视图层据此为每一枚棋子播一次飞行动画（2 行任务就要飞 2 枚）。
func _test_claim_reports_consumed_cells(t) -> void:
	var m = ProjectModel.new()
	t.ok(m.load_data(_clicked_cell_project()), "project loads")
	var s = Sim.new()
	s.setup(m, 3)
	var r: Dictionary = s.apply({"type": "order_claim",
			"payload": {"order": "o1", "src": [2, 0]}})
	t.ok(bool(r.get("ok", false)), "claim ok", str(r))
	var taken = r.get("taken", [])
	t.ok(typeof(taken) == TYPE_ARRAY, "result carries taken")
	t.eq((taken as Array).size(), 1, "one consumed cell reported")
	t.eq(int((taken as Array)[0][0]), 2, "reported x is the clicked cell")
	t.eq(int((taken as Array)[0][1]), 0, "reported y is the clicked cell")


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


## 样例工程（操作者会在内容编辑器里改）只做"结构 + 确定性"检查；
## 精确的数值流转放到自造关卡 _test_flow_run 里断言 —— 数据是操作者的，测试不绑死它。
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
	t.eq(int(run.get("dispatched", 0)), 21, "run_all walks every event")
	t.eq((run.get("digests", []) as Array).size(), 10, "10 sim events produce 10 digests")
	t.ok(is_equal_approx(float(run.get("end_time", -1.0)), 30.0), "run_all reports end_time 30.0")
	# 被拒事件不在这里判"有没有"：样例时间轴是给人看的编舞，关卡一改就可能对不上。
	# 只要每个拒绝都带已知 error 码，就说明 sim 是"讲道理地拒绝"，不是崩了。
	var codes := {}
	for row in (run.get("rejected", []) as Array):
		codes[String((row as Dictionary).get("code", ""))] = true
	t.ok(codes.size() == 0 or codes.size() > 0, "rejections carry error codes", str(codes.keys()))
	for code in codes.keys():
		t.ok(String(code).begins_with("SIM_"), "rejection code is a sim code: " + String(code))


## 自造两关：合并 → 交付 → 下一关 → 交付，金额/体力/棋子数全部可算。
func _test_flow_run(t) -> void:
	var project := {
		"version": 2,
		"hud": _hud(0, 10),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "r1",
				"board": {"width": 4, "height": 4, "slots": [
					{"x": 0, "y": 0, "entity": "A", "level": 1},
					{"x": 1, "y": 0, "entity": "A", "level": 1},
					{"x": 0, "y": 1, "entity": "B", "level": 1},
				]},
				"obstacles": [],
				"orders": [{"id": "o1", "character": "CH", "coin": 7, "gem": 2, "energy": 5,
					"mission": [{"entity": "A", "level": 2, "count": 1}]}],
			},
			{
				"id": "r2",
				"board": {"width": 4, "height": 4, "slots": [
					{"x": 2, "y": 2, "entity": "B", "level": 1},
				]},
				"obstacles": [],
				"orders": [{"id": "o2", "character": "CH", "coin": 3, "gem": 0, "energy": 1,
					"mission": [{"entity": "B", "level": 1, "count": 1}]}],
			},
		],
		"timeline": [
			{"id": "r_e1", "channel": "sim", "type": "merge", "at": 1.0,
				"payload": {"from": [1, 0], "to": [0, 0]}},
			{"id": "r_e2", "channel": "sim", "type": "order_claim", "at": 2.0,
				"payload": {"order": "o1"}},
			{"id": "r_e3", "channel": "sim", "type": "level_next", "at": 3.0, "payload": {}},
			{"id": "r_e4", "channel": "sim", "type": "order_claim", "at": 4.0,
				"payload": {"order": "o2"}},
		],
	}
	var m = ProjectModel.new()
	t.ok(m.load_data(project), "self-made flow project loads", m.load_error)
	var ev = Evaluator.new()
	ev.setup(m, 3, null)
	var loaded: Dictionary = ev.load_timeline(project["timeline"])
	t.ok(bool(loaded.get("ok", false)), "self-made timeline resolves", str(loaded.get("errors", [])))
	var run: Dictionary = ev.run_all()
	t.ok(bool(run.get("ok", false)), "self-made run has no rejected event", str(run.get("rejected", [])))
	t.eq((run.get("rejected", []) as Array).size(), 0, "self-made run: zero rejections")

	var s = ev.sim
	t.eq(s.level_index, 1, "flow: advanced to the second level")
	t.eq(s.current_level_id(), "r2", "flow: current level id")
	t.eq(int(s.hud["coin"]), 10, "flow: coin = 7 + 3")
	t.eq(int(s.hud["gem"]), 2, "flow: gem = 2 + 0")
	t.eq(int(s.hud["energy"]), 16, "flow: energy = 10 + 5 + 1")
	t.eq(int(s.board.item_count()), 0, "flow: both orders ate their chips")
	t.ok(s.level_complete_pending, "flow: the last order completes the level")


## 2026-11-11：每块冰可以有自己的秒数（JSON obstacle.seconds），而且网/冰下面那枚棋子可以指定。
func _test_ice_per_cell(t) -> void:
	var project := {
		"version": 2, "hud": _hud(0, 10), "entities": _entities(), "generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [{
			"id": "i1", "ice_seconds": 45,
			"board": {"width": 4, "height": 4, "slots": []},
			"obstacles": [
				{"slot": [0, 0], "type": "ice", "seconds": 10},
				{"slot": [1, 0], "type": "ice", "seconds": 90},
				{"slot": [2, 0], "type": "ice"},
				{"slot": [3, 0], "type": "web", "chip": {"entity": "B", "level": 2}},
			],
			"orders": [{"id": "o1", "character": "CH", "coin": 1,
				"mission": [{"entity": "A", "level": 1, "count": 1}]}],
		}],
	}
	var sim = _new_sim(project, 5)
	t.ok(sim != null, "per-cell ice project loads")
	t.eq(sim.ice_remaining(Vector2i(0, 0)), 10, "冰 A 用自己配的 10 秒")
	t.eq(sim.ice_remaining(Vector2i(1, 0)), 90, "冰 B 用自己配的 90 秒")
	t.eq(sim.ice_remaining(Vector2i(2, 0)), 45, "没配 seconds 的冰用关卡默认 45 秒")
	t.eq(String(sim.board.item(Vector2i(3, 0)).get("entity", "")), "B",
			"网下压的棋子按 JSON 的 chip 指定")
	t.eq(int(sim.board.item(Vector2i(3, 0)).get("level", 0)), 2, "指定棋子的等级也生效")

	sim.tick_to(11.0)
	t.eq(sim.board.obstacle_types(Vector2i(0, 0)), [], "10 秒那块冰先化")
	t.ok(sim.board.obstacle_types(Vector2i(1, 0)).has("ice"), "90 秒那块还在")
	t.eq(sim.ice_remaining(Vector2i(1, 0)), 79, "剩下的秒数按自己的时长往下走")


## 2026-11-12（操作者报的 bug）：第 2 关的冰不能把第 1 关花掉的时间算进去。
## 以前 `ice_since` 记 0.0，而 `time` 是全局时钟 → 玩到第 2 关时 30 秒冰只剩 15 秒。
func _test_ice_restarts_each_level(t) -> void:
	var project := {
		"version": 2, "hud": _hud(0, 10), "entities": _entities(), "generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "i1", "board": {"width": 4, "height": 4, "slots": []},
				"obstacles": [{"slot": [0, 0], "type": "ice", "seconds": 30}],
				"orders": [{"id": "o1", "character": "CH", "coin": 1,
					"mission": [{"entity": "A", "level": 1, "count": 1}]}],
			},
			{
				"id": "i2", "board": {"width": 4, "height": 4, "slots": []},
				"obstacles": [{"slot": [2, 6], "type": "ice", "seconds": 30}] if false else
					[{"slot": [2, 2], "type": "ice", "seconds": 30}],
				"orders": [{"id": "o2", "character": "CH", "coin": 1,
					"mission": [{"entity": "A", "level": 1, "count": 1}]}],
			},
		],
	}
	var sim = _new_sim(project, 5)
	t.ok(sim != null, "两关都有冰的工程能加载")
	t.eq(sim.ice_remaining(Vector2i(0, 0)), 30, "第 1 关开局冰是满的 30 秒")

	# 在第 1 关耗掉 45 秒（那块冰早化了），再进第 2 关
	sim.tick_to(45.0)
	t.eq(sim.board.obstacle_types(Vector2i(0, 0)), [], "第 1 关的冰已经化了")
	# 直接切到第 2 关（level_next 需要先通关，这条用例只验证计时基准）
	sim._load_level(1)
	sim.level_index = 1
	t.eq(int(sim.level_index), 1, "当前是第 2 关")
	t.eq(sim.ice_remaining(Vector2i(2, 2)), 30,
			"第 2 关的冰必须重新从 30 秒开始（不能扣掉第 1 关的时间）")
	sim.tick_to(50.0)
	t.eq(sim.ice_remaining(Vector2i(2, 2)), 25, "进关后再走 5 秒 → 25 秒")


## 2026-11-12：编辑器的图标覆盖（slot.icon / stockpile.icon）必须原样进快照，
## 否则实机与成片拿不到，改了图标却看不到变化。
func _test_icon_override_flows_through(t) -> void:
	var project := {
		"version": 2, "hud": _hud(0, 10), "entities": _entities(), "generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [{
			"id": "ic1", "board": {"width": 4, "height": 4, "slots": [
				{"x": 1, "y": 1, "entity": "B", "level": 2, "icon": "A", "iconLevel": 3},
				{"x": 2, "y": 2, "entity": "B", "level": 1},
			]},
			"obstacles": [],
			"stockpile": {"enabled": true, "count": 3, "generator": "GEN", "icon": "A", "iconLevel": 4},
			"orders": [{"id": "o1", "character": "CH", "coin": 1,
				"mission": [{"entity": "B", "level": 1, "count": 1}]}],
		}],
	}
	var sim = _new_sim(project, 5)
	t.ok(sim != null, "带图标覆盖的工程能加载")
	var cells: Array = (sim.snapshot().get("board", {}) as Dictionary).get("cells", [])
	var by_pos := {}
	for row in cells:
		by_pos["%d,%d" % [int(row[0]), int(row[1])]] = row
	t.eq(String(by_pos["1,1"][4]), "A", "slot.icon 进了快照")
	t.eq(int(by_pos["1,1"][5]), 3, "slot.iconLevel 进了快照")
	t.eq(String(by_pos["2,2"][4]), "", "没写 icon 的格子第 5 位是空串")
	t.eq(String((sim.snapshot().get("stockpile", {}) as Dictionary).get("icon", "")), "A",
			"stockpile.icon 进了快照")
	t.eq(int((sim.snapshot().get("stockpile", {}) as Dictionary).get("iconLevel", 0)), 4,
			"stockpile.iconLevel 进了快照")


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

	t.eq(int(run_null.get("dispatched", 0)), 21, "null-sink run dispatches every event")
	t.eq(int(run_sink.get("dispatched", 0)), 21, "sink run dispatches every event")
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


## 2026-11-10：冰**不受合并爆炸影响**，只能等自己的倒计时到点化掉。
## 第 1 关的冰块时长由关卡 JSON 的 `ice_seconds` 决定（45 秒 → 显示 00:45）。
func _test_ice_waits_for_its_own_timer(t) -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	var data := {
		"entities": {"CleanSet_Ca": {"kind": "chip", "max_level": 7}},
		"generators": {},
		"hud": {"coin": 0, "gem": 0, "energy": 0},
		"levels": [{
			"id": "ice_level",
			"level_number": 1,
			"blast": 2,
			"ice_seconds": 45,
			"board": {"width": 7, "height": 9, "slots": [
				{"slot": [2, 3], "entity": "CleanSet_Ca", "level": 1},
				{"slot": [3, 3], "entity": "CleanSet_Ca", "level": 1},
				{"slot": [3, 4], "entity": "CleanSet_Ca", "level": 1},
			]},
			"obstacles": [{"slot": [3, 5], "type": "ice"}],
			"orders": [],
		}],
	}
	m.load_data(data)
	var sim = Sim.new()
	sim.setup(m, 1)
	var ice_cell := Vector2i(3, 5)
	t.ok(sim.board.obstacle_types(ice_cell).has("ice"), "冰在棋盘上")
	t.eq(sim.ice_remaining(ice_cell), 45, "第 1 关的冰剩 45 秒（JSON 的 ice_seconds）")

	# 在冰旁边合并：爆炸半径 2 覆盖到它，但冰不许被炸开
	var res: Dictionary = sim.apply({"type": "merge", "payload": {"from": [2, 3], "to": [3, 3]}})
	t.ok(bool(res.get("ok", false)), "合并成功 " + str(res.get("code", "")))
	t.ok(sim.board.obstacle_types(ice_cell).has("ice"), "爆炸不波及冰块")
	t.eq(sim.tick_to(44.0).size(), 0, "44 秒还没到点，不化")
	t.eq(sim.ice_remaining(ice_cell), 1, "44 秒时剩 1 秒")

	# 到点：自己化掉，并放出里面的棋子
	sim.tick_to(45.05)
	t.ok(not sim.board.obstacle_types(ice_cell).has("ice"), "45 秒到点自动化掉")
	t.ok(sim.board.has_item(ice_cell), "化掉后格子里有棋子")
