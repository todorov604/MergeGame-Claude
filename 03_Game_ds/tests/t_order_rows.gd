extends RefCounted
## src/view/order_rows.gd: the one "sim snapshot -> order panel rows" conversion the
## live screen (src/view/game_screen.gd) and the film (src/render/movie_scene.gd) both
## call, so the cards cannot read one thing in the preview and another in the take.
##
## Every expectation below is built from a real Sim on data/sample_project.json, and the
## ready rule is cross-checked against src/core/completed_cells.gd (the other half of
## "this chip pays an order"), so the rows cannot drift from the simulation.
##
## Nothing here renders: no tree, no textures, no window.

const OrderRows = preload("res://src/view/order_rows.gd")
const CompletedCells = preload("res://src/core/completed_cells.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")
const OrderPanel = preload("res://src/view/order_panel.gd")

const SAMPLE := "res://data/sample_project.json"
const SEED := 7
## level_1's only order wants one lv2 chip of this entity.
const ENTITY := "CleanSet_Ca"
const LEVEL := 2
const MISSION_FIELDS := ["entity", "level", "have", "need", "ready", "hue", "label"]


func run(t) -> void:
	_single_order_level(t)
	_ready_follows_the_board(t)
	_obstacle_cell_is_never_ready(t)
	_done_mirrors_the_sim(t)
	_panel_consumes_the_rows(t)


# ------------------------------------------------------------- one order, one level

func _single_order_level(t) -> void:
	var model = _project_model(t)
	if model == null:
		return
	var sim = _fresh_sim(model)
	var rows: Array = OrderRows.build(sim.snapshot(), model)
	t.eq(rows.size(), 1, "level_1 hands the panel exactly one row")

	var row: Dictionary = rows[0]
	t.eq(String(row.get("id", "")), "order_1", "row keeps the sim order id")
	t.eq(String(row.get("character", "")), "char_blonde", "row keeps the sim character")
	t.eq(int(row.get("coin", -1)), 5, "row keeps the sim coin reward")
	t.eq(int(row.get("star", -1)), 0, "row keeps the sim star reward")
	t.eq(bool(row.get("done", true)), false, "a fresh order is not done")

	var mission := _mission(row)
	t.eq(mission.size(), 2, "the row carries two mission entries")
	var item: Dictionary = mission[0]
	for key in MISSION_FIELDS:
		t.ok(item.has(String(key)), "mission row field present: " + String(key))
	t.eq(String(item.get("entity", "")), ENTITY, "mission entity comes from the sim")
	t.eq(int(item.get("level", 0)), LEVEL, "mission level comes from the sim")
	t.eq(int(item.get("have", -1)), 0, "mission have comes from the sim")
	t.eq(int(item.get("need", 0)), 1, "mission need is 1 (paid at have >= 1)")
	t.eq(bool(item.get("ready", true)), false, "the lv1 board holds no lv2 chip yet")
	t.eq(item.get("hue"), Color("#F2A65A"), "mission hue comes from entities.visual.hue")
	t.eq(String(item.get("label", "")), "Ca", "mission label comes from entities.visual.label")


# ------------------------------------------------------------------ ready == board

## `ready` may only be true when the board really holds the chip. Both sides of the
## rule are derived from the same snapshot: the rows' ready flags and
## CompletedCells.from_snapshot() must name exactly the same chips.
func _ready_follows_the_board(t) -> void:
	var model = _project_model(t)
	if model == null:
		return
	var sim = _fresh_sim(model)
	var empty_snap: Dictionary = sim.snapshot()
	# 2026-11-10：第 1 关有 Ca1×2 的任务，开局 4 枚 Ca1 都可付
	t.eq(_ready_keys(OrderRows.build(empty_snap, model)).size(), 1,
			"the fresh board already pays the Ca1 row")
	# 2026-11-10：半途也要变绿 —— 2/4 且棋盘上只剩 1 枚，这一行仍算"能交"。
	# 反向验证：把 ready 改回 `have + 棋盘 >= need`（3 < 4）时这条会红。
	var half_snap := {
		"orders": [{"id": "half", "character": "char_blonde", "mission": [
			["CleanSet_Ca", 1, 2, 4]]}],
		"board": {"cells": [[2, 2, "CleanSet_Ca", 1]], "obstacles": []},
	}
	var half_rows: Array = OrderRows.build(half_snap, model)
	var half_row: Dictionary = (half_rows[0]["mission"] as Array)[0]
	t.eq(int(half_row.get("have", -1)), 2, "半途行 have = 2")
	t.eq(int(half_row.get("need", -1)), 4, "半途行 need = 4")
	t.ok(bool(half_row.get("ready", false)),
			"2/4 且棋盘上还有 1 枚 → 必须绿色（不是'凑够 4 枚才绿'）", str(half_row))

	# 2026-11-10：ready 改成**计数**（要 2 枚的任务得看棋盘上有几枚）
	t.eq(_ready_keys(OrderRows.build(empty_snap, model)), _completed_keys(empty_snap),
			"ready counts match CompletedCells on the fresh board")

	var free: Vector2i = sim.board.first_free_cell()
	t.ok(free.x >= 0, "level_1 still has a free, unblocked cell", str(free))
	sim.board.put(free, ENTITY, LEVEL)
	var held_snap: Dictionary = sim.snapshot()
	var held_rows: Array = OrderRows.build(held_snap, model)
	t.ok(_ready_keys(held_rows).has("%s@%d" % [ENTITY, LEVEL]),
			"placing the mission chip flips its row ready")
	t.eq(_ready_keys(held_rows), _completed_keys(held_snap),
			"ready set matches CompletedCells once the chip is on the board")
	var item: Dictionary = _mission(held_rows[0])[0]
	t.eq(int(item.get("have", -1)), 0, "a chip on the board does not fake mission progress")
	t.eq(int(item.get("need", 0)), 1, "need stays 1 while the chip is waiting")


# --------------------------------------------------------------- obstacle coverage

## The sample level_1 has a web obstacle. A chip of the wanted entity+level parked
## under it is not deliverable, so it must not light the mission row up — the live
## green cell and the card badge have to agree with the sim.
func _obstacle_cell_is_never_ready(t) -> void:
	var model = _project_model(t)
	if model == null:
		return
	var sim = _fresh_sim(model)
	var web := _obstacle_cell(sim.board, "web")
	t.ok(web.x >= 0, "sample level_1 declares a web obstacle", str(web))
	if web.x < 0:
		return

	sim.board.put(web, ENTITY, LEVEL)
	var covered_snap: Dictionary = sim.snapshot()
	t.ok(not _cells_include(CompletedCells.from_snapshot(covered_snap), web),
			"CompletedCells drops the chip hidden under the web")
	var covered_rows: Array = OrderRows.build(covered_snap, model)
	t.ok(not _any_ready(covered_rows, ENTITY, LEVEL),
			"a chip under the web never reports ready=true")
	t.eq(_ready_keys(covered_rows), _completed_keys(covered_snap),
			"ready set still matches CompletedCells with the obstacle in the way")

	# Positive control: the same chip on the same cell is ready the moment the web is
	# gone, so the obstacle (not the chip) is what blocked it.
	sim.board.remove_obstacle(web, "web")
	var freed_snap: Dictionary = sim.snapshot()
	t.ok(_any_ready(OrderRows.build(freed_snap, model), ENTITY, LEVEL),
			"the same chip reports ready once the web is removed")


# ------------------------------------------------------------------- done from sim

func _done_mirrors_the_sim(t) -> void:
	var model = _project_model(t)
	if model == null:
		return
	var sim = _fresh_sim(model)
	var free: Vector2i = sim.board.first_free_cell()
	sim.board.put(free, ENTITY, LEVEL)
	var claim: Dictionary = sim.apply({"type": "order_claim", "payload": {"order": "order_1"}})
	t.ok(bool(claim.get("ok", false)), "the real sim claims order_1", str(claim))
	var snap: Dictionary = sim.snapshot()
	var rows: Array = OrderRows.build(snap, model)
	var sim_orders: Array = _as_array(snap.get("orders", []))
	t.eq(bool(((sim_orders[0] as Dictionary).get("done", false))), true,
			"the sim marks order_1 done")
	t.eq(bool((rows[0] as Dictionary).get("done", false)), true, "row.done mirrors the sim")
	var item: Dictionary = _mission(rows[0])[0]
	t.eq(int(item.get("have", -1)), 0, "row.have mirrors the sim's zeroed have after a claim")
	t.eq(bool(item.get("ready", true)), false, "a claimed order has no ready row")

	# A five-order queue passes through untouched (level_2 of the sample project).
	var advanced: Dictionary = sim.apply({"type": "level_next", "payload": {}})
	t.ok(bool(advanced.get("ok", false)), "the real sim advances to level_2", str(advanced))
	var queue: Array = OrderRows.build(sim.snapshot(), model)
	t.eq(queue.size(), 5, "level_2 hands the panel a five-card queue")
	t.eq(_mission_count(queue), 11, "level_2 totals eleven mission rows")
	t.eq(_done_count(queue), 0, "a fresh queue has no claimed card")


# --------------------------------------------------------------- panel round trip

## The consumer reads the shared shape: have/need/ready/hue/label all land on the card
## the panel already built from the level data.
func _panel_consumes_the_rows(t) -> void:
	var model = _project_model(t)
	if model == null:
		return
	var panel = OrderPanel.new()
	panel.set_project(model.project)
	var built: Dictionary = panel.build_from_level(model.level(0))
	t.ok(bool(built.get("ok", false)), "level_1 builds into a card")
	t.eq(int(built.get("cards", 0)), 1, "level_1 has one card to feed")

	var sim = _fresh_sim(model)
	var free: Vector2i = sim.board.first_free_cell()
	sim.board.put(free, ENTITY, LEVEL)
	panel.sync_orders(OrderRows.build(sim.snapshot(), model))
	var card: Dictionary = panel.cards[0]
	var item: Dictionary = (card["mission"] as Array)[0]
	t.eq(int(item.get("have", -1)), 0, "the card reads have from the row")
	t.eq(int(item.get("need", 0)), 1, "the card reads need from the row")
	t.eq(bool(item.get("ready", false)), true, "the card picks up the ready flag")
	t.eq(item.get("hue"), Color("#F2A65A"), "the card picks up the entity hue")
	t.eq(String(item.get("label", "")), "Ca", "the card picks up the entity label")
	t.ok(panel.debug_summary().contains("CleanSet_Ca@2 0/1"),
			"the card still reads 0/1 before the claim", panel.debug_summary())

	var claim: Dictionary = sim.apply({"type": "order_claim", "payload": {"order": "order_1"}})
	t.ok(bool(claim.get("ok", false)), "the real sim claims the order for the panel", str(claim))
	panel.sync_orders(OrderRows.build(sim.snapshot(), model))
	t.ok(panel.debug_summary().contains("done=1"), "the claimed row flips the card to done",
			panel.debug_summary())
	t.ok(panel.debug_summary().contains("CleanSet_Ca@2 1/1"),
			"a claimed card reads as satisfied", panel.debug_summary())
	panel.free()


# ------------------------------------------------------------------------ helpers

func _project_model(t):
	var model = ProjectModel.new()
	if not model.load_file(SAMPLE):
		t.ok(false, "sample project loads for the shared order rows")
		return null
	return model


func _fresh_sim(model):
	var sim = Sim.new()
	sim.setup(model, SEED)
	return sim


func _mission(row: Dictionary) -> Array:
	return _as_array(row.get("mission", []))


## "entity@level" for every mission row the rows report as ready.
func _ready_keys(rows: Array) -> Dictionary:
	var keys := {}
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		for raw_item in _mission(raw):
			if typeof(raw_item) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = raw_item
			if bool(item.get("ready", false)):
				keys["%s@%d" % [String(item.get("entity", "")), int(item.get("level", 1))]] = true
	return keys


## The same set derived from CompletedCells + the snapshot's own board rows, i.e. the
## independent half of the rule.
func _completed_keys(snap: Dictionary) -> Dictionary:
	var by_pos := {}
	var board = snap.get("board", {})
	if typeof(board) == TYPE_DICTIONARY:
		for raw in _as_array((board as Dictionary).get("cells", [])):
			if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
				continue
			by_pos["%d@%d" % [int((raw as Array)[0]), int((raw as Array)[1])]] = \
					"%s@%d" % [String((raw as Array)[2]), int((raw as Array)[3])]
	var keys := {}
	for raw_cell in CompletedCells.from_snapshot(snap):
		if typeof(raw_cell) != TYPE_ARRAY or (raw_cell as Array).size() < 2:
			continue
		var key := String(by_pos.get("%d@%d" % [int((raw_cell as Array)[0]),
				int((raw_cell as Array)[1])], ""))
		if not key.is_empty():
			keys[key] = true
	return keys


func _any_ready(rows: Array, entity_id: String, level: int) -> bool:
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		for raw_item in _mission(raw):
			if typeof(raw_item) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = raw_item
			if String(item.get("entity", "")) != entity_id:
				continue
			if int(item.get("level", 1)) != level:
				continue
			if bool(item.get("ready", false)):
				return true
	return false


func _mission_count(rows: Array) -> int:
	var total := 0
	for raw in rows:
		if typeof(raw) == TYPE_DICTIONARY:
			total += _mission(raw).size()
	return total


func _done_count(rows: Array) -> int:
	var total := 0
	for raw in rows:
		if typeof(raw) == TYPE_DICTIONARY and bool((raw as Dictionary).get("done", false)):
			total += 1
	return total


## First cell carrying `kind`, in row-major order (the sample level_1 has one web).
func _obstacle_cell(board, kind: String) -> Vector2i:
	if board == null:
		return Vector2i(-1, -1)
	var keys: Array = board.obstacles.keys()
	keys.sort_custom(func(a, b):
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for pos in keys:
		if (board.obstacle_types(pos) as Array).has(kind):
			return pos
	return Vector2i(-1, -1)


func _cells_include(cells: Array, pos: Vector2i) -> bool:
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
			continue
		if int((raw as Array)[0]) == pos.x and int((raw as Array)[1]) == pos.y:
			return true
	return false


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
