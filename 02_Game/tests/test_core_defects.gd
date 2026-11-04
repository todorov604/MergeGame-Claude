extends RefCounted

## 交叉审查回归（对照 03_Game_ds/docs/REVIEW-CORE.md 的 D1–D7）。
## 覆盖 02_Game 中确认存在的同类缺陷：
##   D3 core 不执行等级上限（载入 / 生成器产出）
##   D5 求值器把未知 channel / 未注册 type 当成功
## 以及 D2 的防回归证据（满盘 tap 不推进 RNG）。
## D1/D4/D6/D7 在 02_Game 结构下已由既有实现/测试覆盖，见审查报告。

const EventEvaluator = preload("res://core/event_evaluator.gd")
const BoardState = preload("res://core/sim/board_state.gd")
const GeneratorEngine = preload("res://core/sim/generator_engine.gd")
const SimState = preload("res://core/sim/sim_state.gd")


func run(r) -> void:
	_test_d5_unknown_channel(r)
	_test_d5_unregistered_type(r)
	_test_d3_loaded_slot_levels(r)
	_test_d3_generator_levels(r)
	_test_d2_board_full_rng(r)


# ---------------------------------------------------------------- D5

func _test_d5_unknown_channel(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "x1", "channel": "vieww", "type": "text", "at": 1.0, "payload": {}},
	])
	r.check(not ok, "未知 channel 应求值失败")
	r.contains(_messages(evaluator.errors), "channel", "未知 channel 错误信息: " + _messages(evaluator.errors))
	r.eq(evaluator.events.size(), 0, "未知 channel 的事件不应进入执行列表")


func _test_d5_unregistered_type(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "x1", "channel": "sim", "type": "explode", "at": 1.0, "payload": {}},
		{"id": "x2", "channel": "view", "type": "explode", "at": 2.0, "payload": {}},
	])
	r.check(not ok, "未注册事件类型应求值失败")
	r.contains(_messages(evaluator.errors), "未注册", "未注册类型错误信息: " + _messages(evaluator.errors))
	r.eq(evaluator.events.size(), 0, "未注册类型的事件不应进入执行列表")

	# 对照组：已注册的 sim/view 事件仍应通过
	var good = EventEvaluator.new()
	var good_ok := good.evaluate([
		{"id": "s1", "channel": "sim", "type": "tap", "at": 0.0, "payload": {}},
		{"id": "v1", "channel": "view", "type": "text", "at": 1.0, "payload": {}},
	])
	r.check(good_ok, "已注册的 sim/view 事件应通过: " + _messages(good.errors))
	r.eq(good.events.size(), 2, "合法事件应全部进入执行列表")


# ---------------------------------------------------------------- D3

func _test_d3_loaded_slot_levels(r) -> void:
	var state = SimState.new()
	state.setup({
		"entities": {
			"Ca": {"kind": "chip", "maxLevel": 10},
			"G": {"kind": "generator", "maxLevel": 3},
		},
		"levels": [{
			"id": "l1",
			"board": {"width": 3, "height": 1, "slots": [
				{"x": 0, "y": 0, "entity": "Ca", "level": 11},
				{"x": 1, "y": 0, "entity": "G", "level": 11},
				{"x": 2, "y": 0, "entity": "Ca", "level": 2},
			]},
			"orders": [],
		}],
	}, 1)
	r.eq(int(state.board.get_cell(0, 0)["level"]), 10, "M0 等级上限 10 应在载入时生效")
	r.eq(int(state.board.get_cell(1, 0)["level"]), 3, "实体 maxLevel 上限应在载入时生效")
	r.eq(int(state.board.get_cell(2, 0)["level"]), 2, "合法等级不应被改动")


func _test_d3_generator_levels(r) -> void:
	var data := {
		"entities": {
			"G": {"kind": "generator", "maxLevel": 3},
			"Ca": {"kind": "chip", "maxLevel": 10},
			"B": {"kind": "chip", "maxLevel": 3},
		},
	}

	var engine = GeneratorEngine.new()
	engine.setup({"G": {"charges": 3, "cooldown": 0, "rareOutputs": [
		{"entity": "Ca", "level": 11, "weight": 1, "directOrder": true},
	]}})
	var board = BoardState.new()
	board.setup(1, 2)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var res: Dictionary = engine.tap(data, board, [0, 0], 0.0, rng)
	r.check(bool(res["ok"]), "稀有产出应成功: " + str(res.get("message", "")))
	r.eq(int(res["level"]), 10, "产出 11 级应夹到 M0 上限 10")

	var engine_b = GeneratorEngine.new()
	engine_b.setup({"G": {"charges": 3, "cooldown": 0, "rareOutputs": [
		{"entity": "B", "level": 5, "weight": 1},
	]}})
	var board_b = BoardState.new()
	board_b.setup(1, 2)
	board_b.set_cell(0, 0, "G", 1)
	var res_b: Dictionary = engine_b.tap(data, board_b, [0, 0], 0.0, rng)
	r.check(bool(res_b["ok"]), "稀有产出应成功: " + str(res_b.get("message", "")))
	r.eq(int(res_b["level"]), 3, "产出应夹到实体 maxLevel 3")


# ---------------------------------------------------------------- D2

func _test_d2_board_full_rng(r) -> void:
	var data := {
		"entities": {
			"G": {"kind": "generator", "maxLevel": 3},
			"Ca": {"kind": "chip", "maxLevel": 10},
		},
	}
	var engine = GeneratorEngine.new()
	engine.setup({"G": {"charges": 2, "cooldown": 0, "outputs": [{"entity": "Ca", "weight": 1}]}})
	var board = BoardState.new()
	board.setup(1, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	var before: int = rng.state
	var res: Dictionary = engine.tap(data, board, [0, 0], 0.0, rng)
	r.check(not bool(res["ok"]) and bool(res["board_full"]), "满盘应返回 board_full")
	r.eq(rng.state, before, "满盘失败不应推进 RNG")


# ---------------------------------------------------------------- helpers

func _messages(errors: Array) -> String:
	var parts: Array = []
	for e in errors:
		parts.append(str(e.get("message", "")))
	return " | ".join(parts)
