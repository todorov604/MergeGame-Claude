extends RefCounted
## Free mode (F5 default) + take recording: the click->event rules and the recorded
## cursor path that lets a real playthrough become a deterministic 1080x1920 film.
##
## Two pure layers are covered here, because everything else in the feature is UI:
##   src/core/free_mode.gd  page point -> cell -> {"kind", "payload", "selected"}
##   src/core/take_io.gd    cursor sampling / click window / validation / save+load
##
## The screen itself (src/view/game_screen.gd) and the film (src/render/movie_scene.gd)
## are compile-checked by instantiating them headless; their rendering is covered by
## the shot/film acceptance steps, not here.

const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")
const FreeMode = preload("res://src/core/free_mode.gd")
const TakeIo = preload("res://src/core/take_io.gd")
const BoardView = preload("res://src/view/board_view.gd")
const CompletedCells = preload("res://src/core/completed_cells.gd")
const IceCell = preload("res://src/core/ice_cell.gd")
const SimHandlers = preload("res://src/core/sim_handlers.gd")
const Pulse = preload("res://src/core/pulse.gd")

const SAMPLE := "res://data/sample_project.json"
const TAKE_PATH := "res://output/take_unit_test.json"
const SEED := 7


func run(t) -> void:
	_test_take_roundtrip(t)
	_test_cursor_sampling(t)
	_test_click_window(t)
	_test_validate(t)
	_test_normalize_timeline(t)
	_test_cell_at(t)
	_test_board_click_rules(t)
	_test_drag_action(t)
	_test_board_drag_state(t)
	_test_completed_cells(t)
	_test_ice_cell(t)
	_test_swap_command(t)
	_test_pulse_curves(t)
	_test_click_applies_to_sim(t)
	_test_scripts_compile(t)


# ------------------------------------------------------------------ fixtures

func _sim():
	var model = ProjectModel.new()
	if not model.load_file(SAMPLE):
		return null
	var sim = Sim.new()
	sim.setup(model, SEED)
	return {"sim": sim, "model": model}


func _take() -> Dictionary:
	var cursor := [[0.0, 100, 200], [0.5, 140, 220], [1.0, 180, 240]]
	var clicks := [{"t": 0.5, "x": 140, "y": 220, "type": "tap", "cell": [0, 0], "ok": true}]
	var timeline := [{"id": "free_000", "at": 0.5, "type": "tap", "payload": {"target": {"slot": [0, 0]}}}]
	return TakeIo.build(SEED, 60, 1.0, cursor, clicks, timeline, SAMPLE)


# ---------------------------------------------------------------- take_io

func _test_take_roundtrip(t) -> void:
	var take := _take()
	t.eq(int(take.get("schema", -1)), TakeIo.SCHEMA, "take schema is the current one")
	t.eq(int(take.get("seed", 0)), SEED, "take carries the sim seed")
	t.eq((take.get("timeline", []) as Array).size(), 1, "take carries one recorded event")
	t.ok(bool(TakeIo.validate(take).get("ok", false)), "a built take validates")

	DirAccess.make_dir_recursive_absolute("res://output")
	t.ok(TakeIo.save(take, TAKE_PATH), "take writes to output/")
	var loaded: Dictionary = TakeIo.load_file(TAKE_PATH)
	t.eq(int(loaded.get("seed", 0)), SEED, "saved take round-trips through JSON")
	t.eq((loaded.get("cursor", []) as Array).size(), 3, "cursor samples survive the round-trip")
	t.ok(TakeIo.summary(loaded).contains("cursor=3"), "summary names the cursor sample count")
	t.ok(TakeIo.load_file("res://output/__no_such_take__.json").is_empty(),
			"a missing take file loads as an empty dictionary")
	DirAccess.remove_absolute(TAKE_PATH)


func _test_cursor_sampling(t) -> void:
	var take := _take()
	t.ok(not bool(TakeIo.cursor_at({}, 0.0).get("visible", true)),
			"a timeline film has no cursor track (visible=false)")
	var head := TakeIo.cursor_at(take, -1.0)
	t.eq(Vector2(float(head["x"]), float(head["y"])), Vector2(100, 200),
			"before the first sample the hand clamps to it")
	var mid := TakeIo.cursor_at(take, 0.25)
	t.eq(Vector2(float(mid["x"]), float(mid["y"])), Vector2(120, 210),
			"between samples the hand is linearly interpolated")
	var tail := TakeIo.cursor_at(take, 99.0)
	t.eq(Vector2(float(tail["x"]), float(tail["y"])), Vector2(180, 240),
			"after the last sample the hand clamps to it")
	var single := TakeIo.build(SEED, 60, 0.0, [[0.0, 7, 9]], [], [], SAMPLE)
	var one := TakeIo.cursor_at(single, 5.0)
	t.eq(Vector2(float(one["x"]), float(one["y"])), Vector2(7, 9),
			"a single-sample track is constant")


func _test_click_window(t) -> void:
	var take := _take()
	var hit: Dictionary = TakeIo.click_at(take, 0.55)
	t.eq(String(hit.get("type", "")), "tap", "a frame 0.05s after a click reads as pressed")
	t.ok(TakeIo.click_at(take, 0.9).is_empty(), "a frame 0.4s later is not pressed")
	t.eq(TakeIo.click_at({}, 0.0), {}, "a take without clicks never reads as pressed")


func _test_validate(t) -> void:
	var bad_schema := _take()
	bad_schema["schema"] = 99
	t.ok(not bool(TakeIo.validate(bad_schema).get("ok", true)), "wrong schema is refused")

	var unsorted := TakeIo.build(SEED, 60, 1.0, [[0.5, 1, 1], [0.1, 2, 2]], [], [], SAMPLE)
	t.ok(not bool(TakeIo.validate(unsorted).get("ok", true)), "out-of-order samples are refused")

	var empty := TakeIo.build(SEED, 60, 1.0, [], [], [], SAMPLE)
	t.ok(not bool(TakeIo.validate(empty).get("ok", true)), "an empty cursor track is refused")

	var broken := _take()
	broken["cursor"] = [[0.0, 1]]
	t.ok(not bool(TakeIo.validate(broken).get("ok", true)), "a [t, x] sample is refused")

	var no_fps := _take()
	no_fps["fps"] = 0
	t.ok(not bool(TakeIo.validate(no_fps).get("ok", true)), "fps=0 is refused")


func _test_normalize_timeline(t) -> void:
	var raw := [
		{"id": "a", "at": 1.0, "type": "merge", "payload": {"from": [1, 1], "to": [2, 2]}},
		{"id": "b", "at": 2.0, "type": "text", "channel": "view", "payload": {}},
		{"id": "c", "at": 3.0, "type": "bogus", "payload": {}},
	]
	var out: Array = TakeIo.normalize_timeline(raw)
	t.eq(String((out[0] as Dictionary).get("channel", "")), "sim",
			"a recorded sim event without channel is normalised to sim")
	t.eq(String((out[1] as Dictionary).get("channel", "")), "view",
			"an explicit channel is kept as written")
	t.eq(String((out[2] as Dictionary).get("channel", "")), "",
			"an unknown type keeps an empty channel so the film can refuse it")
	t.eq((raw[0] as Dictionary).get("channel", null), null,
			"normalising does not mutate the take in memory")
	var events := [{"id": "a", "at": 1.0, "type": "tap", "payload": {"target": {"slot": [0, 0]}}}]
	var no_channel := TakeIo.build(SEED, 60, 2.0, [[0.0, 1, 1], [1.0, 2, 2]], [], events, SAMPLE)
	t.eq(String(((no_channel["timeline"] as Array)[0] as Dictionary).get("channel", "")), "",
			"the builder stores exactly what the recorder gave it")
	var fixed: Array = TakeIo.normalize_timeline(no_channel["timeline"])
	t.ok(String((fixed[0] as Dictionary).get("channel", "")) == "sim",
			"the film's normalisation repairs a legacy take")


# --------------------------------------------------------------- free_mode

func _test_cell_at(t) -> void:
	var origin := BoardView.BOARD_ORIGIN
	var size := BoardView.BOARD_SIZE
	var cols := int(BoardView.COLS)
	var rows := int(BoardView.ROWS)
	var cw := size.x / float(cols)
	var ch := size.y / float(rows)
	t.eq(FreeMode.cell_at(origin + Vector2(cw * 0.5, ch * 0.5), origin, size, cols, rows),
			Vector2i(0, 0), "the first cell centre maps to (0,0)")
	t.eq(FreeMode.cell_at(origin + Vector2(cw * 6.5, ch * 8.5), origin, size, cols, rows),
			Vector2i(6, 8), "the last cell centre maps to (cols-1, rows-1)")
	t.eq(FreeMode.cell_at(origin - Vector2(1.0, 1.0), origin, size, cols, rows),
			Vector2i(-1, -1), "a point above/left of the board is outside")
	t.eq(FreeMode.cell_at(origin + size + Vector2(1.0, 0.0), origin, size, cols, rows),
			Vector2i(-1, -1), "the exact right edge is outside (no phantom column)")
	t.eq(FreeMode.cell_at(origin + Vector2(cw + 0.5, ch + 0.5), origin, size, cols, rows),
			Vector2i(1, 1), "a cell boundary belongs to the cell on its right/bottom")


func _test_board_click_rules(t) -> void:
	var env = _sim()
	if env == null:
		t.ok(false, "sample project loads for free-mode tests")
		return
	var sim = env["sim"]
	var model = env["model"]
	var gen := Vector2i(0, 0)
	var chip_a := Vector2i(2, 3)
	var chip_b := Vector2i(3, 3)

	var tap: Dictionary = FreeMode.board_click(gen, sim, model, Vector2i(-1, -1))
	t.eq(String(tap.get("kind", "")), FreeMode.ACTION_TAP, "a generator click becomes a tap")
	t.eq(tap.get("payload", {}), {"target": {"slot": [0, 0]}},
			"the tap payload carries the slot the sim expects")

	var first: Dictionary = FreeMode.board_click(chip_a, sim, model, Vector2i(-1, -1))
	t.eq(String(first.get("kind", "")), FreeMode.ACTION_SELECT, "a chip click selects it")
	t.eq(first.get("selected", Vector2i(-9, -9)), chip_a, "selection moves to the clicked chip")

	var again: Dictionary = FreeMode.board_click(chip_a, sim, model, chip_a)
	t.eq(String(again.get("kind", "")), FreeMode.ACTION_CLEAR, "clicking the selected chip clears it")
	t.eq(again.get("selected", Vector2i(0, 0)), Vector2i(-1, -1), "clear drops the selection")

	var merge: Dictionary = FreeMode.board_click(chip_b, sim, model, chip_a)
	t.eq(String(merge.get("kind", "")), FreeMode.ACTION_MERGE, "same entity+level merges")
	t.eq(merge.get("payload", {}), {"from": [2, 3], "to": [3, 3]},
			"the merge payload is from -> to in cells")
	t.eq(merge.get("selected", chip_a), Vector2i(-1, -1), "a merge drops the selection")

	var empty_cell := Vector2i(-1, -1)
	for y in sim.board.height:
		for x in sim.board.width:
			var pos := Vector2i(x, y)
			if not sim.board.has_item(pos) and not sim.board.is_blocked(pos):
				empty_cell = pos
				break
		if empty_cell.x >= 0:
			break
	if empty_cell.x >= 0:
		var empty: Dictionary = FreeMode.board_click(empty_cell, sim, model, chip_a)
		t.eq(String(empty.get("kind", "")), FreeMode.ACTION_CLEAR,
				"an empty cell clears the selection")
	else:
		t.ok(false, "sample level has no empty cell (fixture changed)")

	var special := Vector2i(-1, -1)
	for pos in sim.board.sorted_cells():
		if String(model.entity(String(sim.board.item(pos).get("entity", ""))).get("kind", "")) == "special":
			special = pos
			break
	if special.x >= 0:
		t.eq(String(FreeMode.board_click(special, sim, model, Vector2i(-1, -1)).get("kind", "")),
				FreeMode.ACTION_NONE, "a special has no click semantics")
	else:
		t.ok(true, "sample level has no special on the board (nothing to check)")

	sim.board.add_obstacle(Vector2i(6, 0), "lock")
	t.eq(String(FreeMode.board_click(Vector2i(6, 0), sim, model, Vector2i(-1, -1)).get("kind", "")),
			FreeMode.ACTION_BLOCKED, "an obstacle cell swallows the click")


## Drag release: same merge rules as click-click, but a gesture that ends on the same
## cell / an empty cell / an obstacle must cancel without mutating anything.
func _test_drag_action(t) -> void:
	var env = _sim()
	if env == null:
		t.ok(false, "sample project loads for drag tests")
		return
	var sim = env["sim"]
	var model = env["model"]
	var merge: Dictionary = FreeMode.drag_action(Vector2i(2, 3), Vector2i(3, 3), sim, model,
			Vector2i(-1, -1))
	t.eq(String(merge.get("kind", "")), FreeMode.ACTION_MERGE, "drag onto the same chip level merges")
	t.eq(merge.get("payload", {}), {"from": [2, 3], "to": [3, 3]},
			"the drag payload is from -> to")
	t.eq(merge.get("selected", Vector2i(0, 0)), Vector2i(-1, -1), "a drag merge drops the selection")

	t.eq(String(FreeMode.drag_action(Vector2i(2, 3), Vector2i(2, 3), sim, model, Vector2i(-1, -1))
			.get("kind", "")), FreeMode.ACTION_NONE, "dropping on the source cell cancels")

	var empty_cell := Vector2i(-1, -1)
	for y in sim.board.height:
		for x in sim.board.width:
			var pos := Vector2i(x, y)
			if not sim.board.has_item(pos) and not sim.board.is_blocked(pos):
				empty_cell = pos
				break
		if empty_cell.x >= 0:
			break
	var moved: Dictionary = FreeMode.drag_action(Vector2i(2, 3), empty_cell, sim, model, Vector2i(-1, -1))
	t.eq(String(moved.get("kind", "")), FreeMode.ACTION_SWAP, "dropping on an empty cell is a swap (move)")
	t.eq(moved.get("payload", {}), {"from": [2, 3], "to": [empty_cell.x, empty_cell.y]},
			"the swap payload is from -> to")

	sim.board.add_obstacle(Vector2i(6, 0), "lock")
	t.eq(String(FreeMode.drag_action(Vector2i(2, 3), Vector2i(6, 0), sim, model, Vector2i(-1, -1))
			.get("kind", "")), FreeMode.ACTION_BLOCKED, "dropping on an obstacle is refused")

	var mismatch := Vector2i(-1, -1)
	for pos in sim.board.sorted_cells():
		var ent := String(sim.board.item(pos).get("entity", ""))
		if ent == "CleanSet_Cb":
			mismatch = pos
			break
	if mismatch.x >= 0:
		t.eq(String(FreeMode.drag_action(Vector2i(2, 3), mismatch, sim, model, Vector2i(-1, -1))
				.get("kind", "")), FreeMode.ACTION_SWAP, "dropping on another entity swaps places")
	else:
		t.ok(true, "sample level has no Cb chip on the board (nothing to check)")


## The board keeps the dragged chip and its white frame at the pointer, so the piece
## visually travels with the hand instead of snapping cell to cell.
func _test_board_drag_state(t) -> void:
	var view = BoardView.new()
	t.eq(view.drag_source(), Vector2i(-1, -1), "no drag by default")
	view.set_drag_state({"from": [2, 3], "pos": Vector2(700, 1200)})
	t.eq(view.drag_source(), Vector2i(2, 3), "set_drag_state keeps the source cell")
	view.set_drag_state({})
	t.eq(view.drag_source(), Vector2i(-1, -1), "an empty state ends the drag")
	if view != null:
		view.free()


## 所见即所得: the live board and the film read the same rule. A chip counts when an
## unfinished order still needs exactly that entity+level.
func _test_completed_cells(t) -> void:
	var snap := {
		"orders": [
			{"id": "o1", "done": false, "mission": [["CleanSet_Ca", 2, 0]]},
		],
		"board": {"cells": [
			[2, 3, "CleanSet_Ca", 2],
			[3, 3, "CleanSet_Ca", 1],
			[4, 4, "CleanSet_Cb", 2],
		]},
	}
	t.eq(CompletedCells.from_snapshot(snap), [[2, 3]],
			"only the entity+level the order still needs is marked")

	var satisfied := snap.duplicate(true)
	(satisfied["orders"] as Array)[0]["mission"][0][2] = 1
	t.eq(CompletedCells.from_snapshot(satisfied), [],
			"a mission entry that already has its item marks nothing")

	var claimed := snap.duplicate(true)
	(claimed["orders"] as Array)[0]["done"] = true
	t.eq(CompletedCells.from_snapshot(claimed), [],
			"a claimed order marks nothing")

	t.eq(CompletedCells.from_snapshot({}), [], "an empty snapshot marks nothing")
	t.eq(CompletedCells.from_snapshot({"orders": [], "board": {"cells": []}}), [],
			"no orders -> no marks")


## 所见即所得: the frozen chip is a pure function of (project, cell), so the live
## board and the film cannot disagree and it never flickers between frames.
func _test_ice_cell(t) -> void:
	var project := {"entities": {
		"CleanSet_Ca": {"kind": "chip"},
		"CleanSet_Cb": {"kind": "chip"},
		"CleanBox_C": {"kind": "generator"},
	}}
	var a := IceCell.chip(project, Vector2i(6, 6))
	var b := IceCell.chip(project, Vector2i(6, 6))
	t.eq(a, b, "the same cell always freezes the same chip")
	t.ok(String(a.get("entity", "")) in ["CleanSet_Ca", "CleanSet_Cb"],
			"only chip entities are frozen inside the ice")
	t.ok(int(a.get("level", 0)) >= 1, "the frozen chip carries a level >= 1")
	t.eq(IceCell.chip({}, Vector2i(6, 6)), {}, "a project without entities freezes nothing")

	var cell := Vector2i(6, 6)
	var start := IceCell.start_seconds(cell)
	t.ok(start >= 600 and start <= 1199, "the ice countdown starts between 10:00 and 19:59")
	t.eq(IceCell.start_seconds(Vector2i(6, 6)), start, "the start value is fixed per cell")
	t.eq(IceCell.format_clock(754), "12:34", "seconds format as mm:ss")
	t.eq(IceCell.remaining_seconds(cell, 0.0), start, "at level time 0 nothing has ticked")
	t.eq(IceCell.remaining_seconds(cell, 1.0), start - 1, "exactly one tick per second")
	t.eq(IceCell.remaining_seconds(cell, 1.9), start - 1, "a partial second does not tick")
	t.eq(IceCell.remaining_seconds(cell, 99999.0), 0, "the countdown never goes negative")


## The swap command itself: chips trade places, a chip slides into an empty cell,
## obstacles and non-chip items refuse — and the "completed" markers follow the board
## because CompletedCells reads the snapshot, not a separate flag.
func _test_swap_command(t) -> void:
	var env = _sim()
	if env == null:
		t.ok(false, "sample project loads for swap tests")
		return
	var sim = env["sim"]
	var model = env["model"]
	var before: Dictionary = sim.snapshot()

	var a := Vector2i(2, 3)
	var b := Vector2i(1, 4)
	var src_entity := String(sim.board.item(a).get("entity", ""))
	var dst_entity := String(sim.board.item(b).get("entity", ""))
	var r: Dictionary = SimHandlers.apply(sim, {"type": "swap", "payload": {"from": [a.x, a.y], "to": [b.x, b.y]}})
	t.ok(bool(r.get("ok", false)), "swap between two chips is accepted")
	t.eq(String(sim.board.item(a).get("entity", "")), dst_entity, "the target chip landed on the source cell")
	t.eq(String(sim.board.item(b).get("entity", "")), src_entity, "the source chip landed on the target cell")

	var empty_cell := Vector2i(-1, -1)
	for y in sim.board.height:
		for x in sim.board.width:
			var pos := Vector2i(x, y)
			if not sim.board.has_item(pos) and not sim.board.is_blocked(pos):
				empty_cell = pos
				break
		if empty_cell.x >= 0:
			break
	var moving := String(sim.board.item(b).get("entity", ""))
	var mv: Dictionary = SimHandlers.apply(sim, {"type": "swap",
			"payload": {"from": [b.x, b.y], "to": [empty_cell.x, empty_cell.y]}})
	t.ok(bool(mv.get("ok", false)), "a chip slides into an empty cell")
	t.ok(not sim.board.has_item(b), "the source cell is empty after the slide")
	t.eq(String(sim.board.item(empty_cell).get("entity", "")), moving, "the chip now sits in the empty cell")

	var blocked := Vector2i(-1, -1)
	for y in sim.board.height:
		for x in sim.board.width:
			if sim.board.is_blocked(Vector2i(x, y)):
				blocked = Vector2i(x, y)
				break
		if blocked.x >= 0:
			break
	var on_obstacle: Dictionary = SimHandlers.apply(sim, {"type": "swap",
			"payload": {"from": [empty_cell.x, empty_cell.y], "to": [blocked.x, blocked.y]}})
	t.eq(String(on_obstacle.get("code", "")), "SIM_BLOCKED", "an obstacle cell refuses a swap")

	var generator := Vector2i(0, 0)
	var non_chip: Dictionary = SimHandlers.apply(sim, {"type": "swap",
			"payload": {"from": [generator.x, generator.y], "to": [empty_cell.x, empty_cell.y]}})
	t.eq(String(non_chip.get("code", "")), "SIM_NOT_SWAPPABLE", "a generator cannot be swapped")

	# 所见即所得: the green cell + finish badge are derived from the snapshot, so the
	# completed marker travels with the chip after a swap.
	var done_before: Array = CompletedCells.from_snapshot(sim.snapshot())
	t.ok(done_before.size() >= 1, "the sample level still has a mission-matching chip")
	if done_before.size() >= 1:
		var done_cell := Vector2i(int(done_before[0][0]), int(done_before[0][1]))
		var free2 := Vector2i(-1, -1)
		for y in sim.board.height:
			for x in sim.board.width:
				var pos := Vector2i(x, y)
				if not sim.board.has_item(pos) and not sim.board.is_blocked(pos):
					free2 = pos
					break
			if free2.x >= 0:
				break
		SimHandlers.apply(sim, {"type": "swap",
				"payload": {"from": [done_cell.x, done_cell.y], "to": [free2.x, free2.y]}})
		var done_after: Array = CompletedCells.from_snapshot(sim.snapshot())
		t.eq(done_after, [[free2.x, free2.y]], "the completed marker follows the chip to the new cell")

	t.eq((sim.snapshot().get("board", {}).get("cells", []) as Array).size(),
			(before.get("board", {}).get("cells", []) as Array).size(),
			"swapping never changes how many cells are occupied")


## 拖起放大 / 放下缩小 / 合成弹一下：都是纯时间函数，峰值不白框。
func _test_pulse_curves(t) -> void:
	t.ok(is_equal_approx(Pulse.drag_scale(0.0, 0.0), 1.0), "pickup starts at normal size")
	t.ok(is_equal_approx(Pulse.drag_scale(0.0, 0.12), Pulse.PEAK), "held chip grows to the peak")
	t.ok(is_equal_approx(Pulse.drag_scale(0.0, 5.0), Pulse.PEAK), "held chip stays big")
	t.ok(is_equal_approx(Pulse.settle_scale(0.0, 0.0), Pulse.PEAK), "drop starts at the peak")
	t.ok(is_equal_approx(Pulse.settle_scale(0.0, 0.2), 1.0), "drop settles back to normal")
	t.ok(is_equal_approx(Pulse.merge_scale(0.0, 0.0), 1.0), "merge pop starts normal")
	t.ok(is_equal_approx(Pulse.merge_scale(0.0, 0.2), Pulse.PEAK), "merge pop peaks at half time")
	t.ok(is_equal_approx(Pulse.merge_scale(0.0, 0.4), 1.0), "merge pop ends normal after 0.4 s")
	t.ok(Pulse.PEAK <= (160.0 * 1.14) / 132.0, "the peak fits inside the drawn drag frame")
	t.eq(Pulse.duration_of("merge"), Pulse.MERGE_DURATION, "merge pulse lasts 0.4 s")


func _test_click_applies_to_sim(t) -> void:
	var env = _sim()
	if env == null:
		t.ok(false, "sample project loads for free-mode sim tests")
		return
	var sim = env["sim"]
	var model = env["model"]
	var tap: Dictionary = FreeMode.board_click(Vector2i(0, 0), sim, model, Vector2i(-1, -1))
	var before := int(sim.board.item_count())
	var tap_result: Dictionary = sim.apply({"id": "free_000", "type": "tap", "at": 0.5,
			"payload": tap.get("payload", {})})
	t.ok(bool(tap_result.get("ok", false)), "the free-mode tap payload is accepted by the sim",
			String(tap_result.get("code", "")))
	t.eq(int(sim.board.item_count()), before + 1, "the tap spawned exactly one chip")

	var merge_action: Dictionary = FreeMode.board_click(Vector2i(3, 3), sim, model, Vector2i(2, 3))
	var merge_result: Dictionary = sim.apply({"id": "free_001", "type": "merge", "at": 0.6,
			"payload": merge_action.get("payload", {})})
	t.ok(bool(merge_result.get("ok", false)), "the free-mode merge payload is accepted by the sim",
			String(merge_result.get("code", "")))
	t.eq(int(sim.board.item(Vector2i(3, 3)).get("level", 0)), 2, "the merge produced level 2")
	t.ok(not sim.board.has_item(Vector2i(2, 3)), "the merge consumed the source cell")


# --------------------------------------------------------------- compile

func _test_scripts_compile(t) -> void:
	var screen_script = load("res://src/view/game_screen.gd")
	t.ok(screen_script != null, "game_screen.gd loads")
	if screen_script != null:
		var screen = screen_script.new()
		t.ok(screen is Control, "game_screen instantiates as a Control")
		t.ok(screen.has_method("_fit_preview_window"), "game_screen keeps the F5 window helper")
		t.ok(screen.has_method("_free_click"), "game_screen exposes the free-mode click path")
		t.ok(screen.has_method("_free_click_at"), "game_screen exposes the testable click point")
		t.ok(screen.has_method("_start_recording"), "game_screen exposes take recording")
		if screen != null:
			screen.free()
	var film_script = load("res://src/render/movie_scene.gd")
	t.ok(film_script != null, "movie_scene.gd loads")
	if film_script != null:
		var film = film_script.new()
		t.ok(film is Control, "movie_scene instantiates as a Control")
		t.ok(film.has_method("_draw_cursor"), "movie_scene can draw the recorded cursor")
		t.ok(film.has_method("_load_take"), "movie_scene can load a take")
		if film != null:
			film.free()
