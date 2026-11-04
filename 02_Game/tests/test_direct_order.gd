extends RefCounted

## P1-1 directOrder 语义回归（M0 冻结规格 v0.20 §2.1.10）：
##   true（缺省值）= 稀有产出仅在该 entity+level 被未完成订单需要时才进入抽取池；
##   false = 无条件稀有掉落。
## orders 由调用方传入（订单字典数组，含 mission，可能含 state）；
## state != "claimed"（含缺失）视为未完成。outputs 条目行为不变。

const BoardState = preload("res://core/sim/board_state.gd")
const GeneratorEngine = preload("res://core/sim/generator_engine.gd")
const ProjectDoc = preload("res://core/project_doc.gd")
const SimRunner = preload("res://core/sim/sim_runner.gd")

const MSG_EMPTY := "产出表为空"


func run(r) -> void:
	_test_no_orders_direct_true(r)
	_test_unfinished_order_allows_rare(r)
	_test_direct_false_unconditional(r)
	_test_default_is_true(r)
	_test_claimed_order_filtered(r)
	_test_outputs_unaffected(r)
	_test_sim_runner_passes_orders(r)


# a. 无订单 + directOrder=true → 不进池：失败且零副作用
func _test_no_orders_direct_true(r) -> void:
	var engine = GeneratorEngine.new()
	# cooldown > 0 且 at_time > 0：若实现错误地在空池早退前写入 next_time，值会变成 15.0。
	engine.setup({"G": {"charges": 3, "cooldown": 5, "rareOutputs": [
		{"entity": "Ca", "level": 2, "weight": 1, "directOrder": true},
	]}})
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	var rng_before: int = rng.state

	# 旧 5 参调用兼容：省略 orders 等价于空订单
	var res: Dictionary = engine.tap(_project(), board, [0, 0], 10.0, rng)
	r.check(not bool(res["ok"]), "无订单 + directOrder=true 不应进池")
	r.eq(str(res["message"]), MSG_EMPTY, "无订单时稀有被过滤应返回产出表为空")
	r.eq(int(engine.states["G"]["charges"]), 3, "过滤导致空池不应扣 charges")
	r.eq(float(engine.states["G"]["next_time"]), 0.0, "过滤导致空池不应更新 next_time")
	r.eq(rng.state, rng_before, "过滤导致空池不应推进 RNG")
	r.eq(board.count_cells(), 1, "过滤导致空池不应写棋盘")
	r.check(board.get_cell(1, 0).is_empty(), "空位应保持为空")

	# 显式传空数组与省略第 6 参等价
	var engine2 = GeneratorEngine.new()
	engine2.setup(_rare_config(true))
	var board2 = BoardState.new()
	board2.setup(2, 1)
	board2.set_cell(0, 0, "G", 1)
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 7
	var res2: Dictionary = engine2.tap(_project(), board2, [0, 0], 0.0, rng2, [])
	r.check(not bool(res2["ok"]), "显式空 orders 与省略等价：不应进池")
	r.eq(str(res2["message"]), MSG_EMPTY, "显式空 orders 文案")


# b. 有未完成订单需要该 entity+level + true → 进池
func _test_unfinished_order_allows_rare(r) -> void:
	var engine = GeneratorEngine.new()
	engine.setup(_rare_config(true))
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 99

	var orders: Array = [_order("Ca", 2)]   # state 缺失 → 未完成
	var res: Dictionary = engine.tap(_project(), board, [0, 0], 0.0, rng, orders)
	r.check(bool(res["ok"]), "有未完成订单需要 Ca Lv2 时应进池: " + str(res["message"]))
	r.eq(str(res["entity"]), "Ca", "稀有产出实体")
	r.eq(int(res["level"]), 2, "稀有产出等级")
	r.check(bool(res["direct_order"]), "directOrder=true 抽中时应回填 direct_order=true")
	r.eq(int(engine.states["G"]["charges"]), 2, "成功产出应扣 1 次")
	var placed: Dictionary = board.get_cell(1, 0)
	r.eq(str(placed.get("entity", "")), "Ca", "产出应写入首个空位")
	r.eq(int(placed.get("level", 0)), 2, "首个空位等级")

	# state="ready" 仍算未完成
	var engine2 = GeneratorEngine.new()
	engine2.setup(_rare_config(true))
	var board2 = BoardState.new()
	board2.setup(2, 1)
	board2.set_cell(0, 0, "G", 1)
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 99
	var res2: Dictionary = engine2.tap(_project(), board2, [0, 0], 0.0, rng2, [_order("Ca", 2, "ready")])
	r.check(bool(res2["ok"]), "state=ready 的订单也算未完成: " + str(res2["message"]))
	r.eq(int(res2["level"]), 2, "state=ready 时稀有产出等级")


# c. directOrder=false + 无订单 → 无条件进池
func _test_direct_false_unconditional(r) -> void:
	var engine = GeneratorEngine.new()
	engine.setup(_rare_config(false))
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 99

	var res: Dictionary = engine.tap(_project(), board, [0, 0], 0.0, rng)
	r.check(bool(res["ok"]), "directOrder=false 无订单也应无条件进池: " + str(res["message"]))
	r.eq(int(res["level"]), 2, "无条件稀有产出等级")
	r.check(not bool(res["direct_order"]), "directOrder=false 时 direct_order 应为 false")


# d. 字段缺省 + 无订单 → 等价 true；字段缺省 + 有需要的订单 → 进池
func _test_default_is_true(r) -> void:
	var engine = GeneratorEngine.new()
	engine.setup(_rare_config_missing())
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var res: Dictionary = engine.tap(_project(), board, [0, 0], 0.0, rng)
	r.check(not bool(res["ok"]), "directOrder 缺省应按 true 处理：无订单时不进池")
	r.eq(str(res["message"]), MSG_EMPTY, "directOrder 缺省 + 无订单文案")
	r.eq(int(engine.states["G"]["charges"]), 3, "缺省过滤不应扣 charges")

	var engine2 = GeneratorEngine.new()
	engine2.setup(_rare_config_missing())
	var board2 = BoardState.new()
	board2.setup(2, 1)
	board2.set_cell(0, 0, "G", 1)
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 99
	var res2: Dictionary = engine2.tap(_project(), board2, [0, 0], 0.0, rng2, [_order("Ca", 2)])
	r.check(bool(res2["ok"]), "directOrder 缺省 + 有订单需要时应进池: " + str(res2["message"]))
	r.eq(int(res2["level"]), 2, "缺省 + 有订单时稀有产出等级")
	r.check(bool(res2["direct_order"]), "缺省等价 true：direct_order 应为 true")


# e. state="claimed" 的订单不算需要；entity/level 不完全匹配也不算
func _test_claimed_order_filtered(r) -> void:
	var engine = GeneratorEngine.new()
	engine.setup(_rare_config(true))
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var res: Dictionary = engine.tap(_project(), board, [0, 0], 0.0, rng, [_order("Ca", 2, "claimed")])
	r.check(not bool(res["ok"]), "state=claimed 的订单不算需要，稀有应被过滤")
	r.eq(str(res["message"]), MSG_EMPTY, "claimed 订单被过滤文案")
	r.eq(int(engine.states["G"]["charges"]), 3, "claimed 过滤不应扣 charges")

	var engine2 = GeneratorEngine.new()
	engine2.setup(_rare_config(true))
	var board2 = BoardState.new()
	board2.setup(2, 1)
	board2.set_cell(0, 0, "G", 1)
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 12345
	var res2: Dictionary = engine2.tap(_project(), board2, [0, 0], 0.0, rng2, [
		_order("Ca", 3), _order("Cb", 2),
	])
	r.check(not bool(res2["ok"]), "entity 或 level 不完全匹配的订单不算需要")
	r.eq(str(res2["message"]), MSG_EMPTY, "不完全匹配时稀有应被过滤文案")


# 额外：outputs 条目行为不变（rare 被过滤时 outputs 仍可产出）
func _test_outputs_unaffected(r) -> void:
	var config := {"G": {"charges": 2, "cooldown": 0,
		"outputs": [{"entity": "Ca", "weight": 1}],
		"rareOutputs": [{"entity": "Ca", "level": 2, "weight": 1, "directOrder": true}],
	}}
	var engine = GeneratorEngine.new()
	engine.setup(config)
	var board = BoardState.new()
	board.setup(2, 1)
	board.set_cell(0, 0, "G", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var res: Dictionary = engine.tap(_project(), board, [0, 0], 0.0, rng)
	r.check(bool(res["ok"]), "outputs 不受 rare 过滤影响: " + str(res["message"]))
	r.eq(int(res["level"]), 1, "rare 被过滤时只应产出 outputs（Lv1）")
	r.check(not bool(res["direct_order"]), "outputs 产出 direct_order 应为 false")


# 主会话集成回归：SimRunner 必须把当前关卡未完成订单传给 tap（不读全局状态）。
# rare-only 权重表 + 订单需要 Ca Lv2 → tap 产 Ca Lv2；无订单 → 池空、tap 失败。
func _test_sim_runner_passes_orders(r) -> void:
	var with_order: Dictionary = SimRunner.new().run(_sim_doc(true), 1)
	var event: Dictionary = _find_event(with_order.get("events", []), "t1")
	r.check(bool(event.get("ok", false)), "SimRunner 应传递未完成订单，rare 进池: " + str(event.get("message", "")))
	r.eq(int(_cell_at(with_order["snapshot"]["board"], 1, 0).get("level", 0)), 2, "rare-only 池应产出 Ca Lv2")

	var without_order: Dictionary = SimRunner.new().run(_sim_doc(false), 1)
	var event2: Dictionary = _find_event(without_order.get("events", []), "t1")
	r.check(not bool(event2.get("ok", true)), "无订单时 SimRunner 的 rare-only tap 应失败")
	r.contains(str(event2.get("message", "")), MSG_EMPTY, "无订单时失败文案")


func _sim_doc(with_order: bool) -> RefCounted:
	var orders: Array = []
	if with_order:
		orders.append({
			"id": "o1",
			"character": "char_01",
			"mission": [{"entity": "Ca", "level": 2}],
			"star": 1,
			"coin": 5,
		})
	var doc = ProjectDoc.new()
	doc.from_dict({
		"entities": {
			"G": {"kind": "generator", "maxLevel": 3},
			"Ca": {"kind": "chip", "maxLevel": 10},
		},
		"generators": {"G": {"charges": 3, "cooldown": 0, "rareOutputs": [
			{"entity": "Ca", "level": 2, "weight": 1, "directOrder": true},
		]}},
		"hud": {},
		"levels": [{
			"id": "l1",
			"board": {"width": 2, "height": 1, "slots": [
				{"x": 0, "y": 0, "entity": "G", "level": 1},
			]},
			"orders": orders,
		}],
		"timeline": [
			{"id": "t1", "channel": "sim", "type": "tap", "at": 1.0, "payload": {"target": {"slot": [0, 0]}}},
		],
	}, "<direct-order-sim-test>")
	return doc


# ---------------------------------------------------------------- helpers

func _project() -> Dictionary:
	return {
		"entities": {
			"G": {"kind": "generator", "maxLevel": 3},
			"Ca": {"kind": "chip", "maxLevel": 10},
			"Cb": {"kind": "chip", "maxLevel": 10},
		},
	}


func _rare_config(direct_order: bool) -> Dictionary:
	return {"G": {"charges": 3, "cooldown": 0, "rareOutputs": [
		{"entity": "Ca", "level": 2, "weight": 1, "directOrder": direct_order},
	]}}


func _rare_config_missing() -> Dictionary:
	return {"G": {"charges": 3, "cooldown": 0, "rareOutputs": [
		{"entity": "Ca", "level": 2, "weight": 1},
	]}}


func _order(entity: String, level: int, state = null) -> Dictionary:
	var order := {
		"id": "order_test",
		"character": "char_01",
		"mission": [{"entity": entity, "level": level}],
		"star": 1,
		"coin": 5,
	}
	if typeof(state) == TYPE_STRING:
		order["state"] = state
	return order


func _find_event(events: Array, event_id: String) -> Dictionary:
	for event in events:
		if str(event.get("id", "")) == event_id:
			return event
	return {}


func _cell_at(board_snapshot: Dictionary, x: int, y: int) -> Dictionary:
	for cell in board_snapshot.get("cells", []):
		if int(cell.get("x", -1)) == x and int(cell.get("y", -1)) == y:
			return cell
	return {}
