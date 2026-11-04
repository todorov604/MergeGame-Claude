extends RefCounted

## 第 2 步验收：core sim 规则 + 同 seed 确定性 + 两关模拟。

const BoardState = preload("res://core/sim/board_state.gd")
const MergeEngine = preload("res://core/sim/merge_engine.gd")
const GeneratorEngine = preload("res://core/sim/generator_engine.gd")
const OrderEngine = preload("res://core/sim/order_engine.gd")
const LevelFlow = preload("res://core/sim/level_flow.gd")
const SimState = preload("res://core/sim/sim_state.gd")
const SimRunner = preload("res://core/sim/sim_runner.gd")
const ProjectDoc = preload("res://core/project_doc.gd")


func run(r) -> void:
	_test_board(r)
	_test_merge(r)
	_test_generator(r)
	_test_orders(r)
	_test_level_flow(r)
	_test_runner_determinism(r)
	_test_runner_two_levels(r)
	_test_runner_rules(r)


# ---------------------------------------------------------------- board

func _test_board(r) -> void:
	var board = BoardState.new()
	board.setup(2, 2)
	r.eq(board.first_empty_slot(), [0, 0], "空棋盘首个空位应为 (0,0)")
	board.set_cell(0, 0, "A", 1)
	r.eq(board.first_empty_slot(), [1, 0], "行优先扫描应为 (1,0)")
	board.obstacles[board.key(1, 0)] = "lock"
	r.eq(board.first_empty_slot(), [0, 1], "障碍格应跳过")
	r.check(not board.is_empty_slot(1, 0), "障碍格不是空位")
	board.remove_cell(0, 0)
	r.eq(board.count_cells(), 0, "移除后格子数应为 0")

	var level: Dictionary = _sample_data()["levels"][0]
	var b2 = BoardState.new()
	b2.load_from_level(level)
	r.eq(b2.width, 7, "样例棋盘宽 7")
	r.eq(b2.height, 9, "样例棋盘高 9")
	r.eq(b2.count_cells(), 4, "样例 level_1 应有 4 个格子")
	r.eq(b2.obstacles.size(), 3, "样例 level_1 应有 3 个障碍")
	var cell: Dictionary = b2.get_cell(2, 3)
	r.eq(cell.get("entity", ""), "CleanSet_Ca", "样例格子实体")
	r.eq(int(cell.get("level", 0)), 1, "样例格子等级")
	var snap: Dictionary = b2.snapshot()
	r.eq(int(snap["cells"][0]["y"]), 3, "快照按 y 再 x 排序")


# ---------------------------------------------------------------- merge

func _test_merge(r) -> void:
	var engine = MergeEngine.new()
	var board = BoardState.new()
	board.setup(7, 9)
	board.set_cell(2, 3, "Ca", 1)
	board.set_cell(4, 3, "Ca", 1)

	var ok: Dictionary = engine.merge(board, [2, 3], [4, 3], 10)
	r.check(bool(ok["ok"]), "同实体同等级应可合并（允许不相邻）")
	r.eq(int(ok["level"]), 2, "合并后等级 2")
	r.check(not board.has_cell(2, 3), "来源格应清空")
	r.eq(int(board.get_cell(4, 3)["level"]), 2, "目标格等级 2")

	board.set_cell(2, 3, "Ca", 2)
	board.set_cell(4, 3, "Cb", 2)
	var different: Dictionary = engine.merge(board, [2, 3], [4, 3], 10)
	r.check(not different["ok"], "不同实体应拒绝")
	r.eq(different["message"], "实体不同", "不同实体文案")

	board.set_cell(4, 3, "Ca", 3)
	var level_diff: Dictionary = engine.merge(board, [2, 3], [4, 3], 10)
	r.check(not level_diff["ok"], "不同等级应拒绝")
	r.eq(level_diff["message"], "等级不同", "不同等级文案")

	board.set_cell(2, 3, "Ca", 10)
	board.set_cell(4, 3, "Ca", 10)
	var capped: Dictionary = engine.merge(board, [2, 3], [4, 3], 10)
	r.check(not capped["ok"], "10 级不可再合并")
	r.eq(capped["message"], "达到等级上限", "上限文案")

	board.set_cell(2, 3, "Ca", 1)
	board.obstacles[board.key(4, 3)] = "web"
	var blocked: Dictionary = engine.merge(board, [2, 3], [4, 3], 10)
	r.check(not blocked["ok"], "障碍格应拒绝合并")
	r.eq(blocked["message"], "存在障碍，无法合并", "障碍文案")

	# 同格合并：坐标非法，且失败后棋盘不变
	var same = BoardState.new()
	same.setup(7, 9)
	same.set_cell(2, 3, "Ca", 1)
	var same_res: Dictionary = engine.merge(same, [2, 3], [2, 3], 10)
	r.check(not same_res["ok"], "同格合并应拒绝")
	r.eq(same_res["message"], "坐标非法", "同格合并文案")
	r.check(same.has_cell(2, 3), "同格合并失败后 (2,3) 应仍有物品")
	r.eq(int(same.get_cell(2, 3)["level"]), 1, "同格合并失败后 (2,3) 等级应仍为 Lv1")


# ---------------------------------------------------------------- generator

func _test_generator(r) -> void:
	var data: Dictionary = _sample_data()
	var config: Dictionary = data["generators"]
	var engine = GeneratorEngine.new()
	engine.setup(config)
	var board = BoardState.new()
	board.setup(7, 9)
	board.set_cell(3, 3, "CleanBox_C", 1)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var tap: Dictionary = engine.tap(data, board, [3, 3], 0.0, rng)
	r.check(bool(tap["ok"]), "生成器应产出: " + str(tap["message"]))
	r.check(tap["entity"] in ["CleanSet_Ca", "CleanSet_Cb"], "产出实体应在产出表内")
	r.eq(board.count_cells(), 2, "产出应落在棋盘上")
	r.eq(int(engine.states["CleanBox_C"]["charges"]), 9, "成功产出应扣 1 次")
	var placed: Dictionary = board.get_cell(0, 0)
	r.check(not placed.is_empty(), "产出应落到行优先第一个空位 (0,0)")

	# 相同种子两个独立引擎结果一致
	var e2 = GeneratorEngine.new()
	e2.setup(config)
	var b2 = BoardState.new()
	b2.setup(7, 9)
	b2.set_cell(3, 3, "CleanBox_C", 1)
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 12345
	var tap2: Dictionary = e2.tap(data, b2, [3, 3], 0.0, rng2)
	r.eq(tap2["entity"], tap["entity"], "同种子产出实体一致")
	r.eq(int(tap2["level"]), int(tap["level"]), "同种子产出等级一致")

	# 棋盘已满：不扣次数
	var full = GeneratorEngine.new()
	full.setup({"G": {"charges": 2, "cooldown": 0, "outputs": [{"entity": "Ca", "weight": 1}]}})
	var full_board = BoardState.new()
	full_board.setup(1, 1)
	full_board.set_cell(0, 0, "G", 1)
	var full_data := _tiny_project()
	var full_res: Dictionary = full.tap(full_data, full_board, [0, 0], 0.0, rng)
	r.check(not full_res["ok"] and bool(full_res["board_full"]), "满盘应返回 board_full")
	r.eq(int(full.states["G"]["charges"]), 2, "满盘不扣次数")

	# 冷却
	var cool = GeneratorEngine.new()
	cool.setup({"G": {"charges": 5, "cooldown": 5, "outputs": [{"entity": "Ca", "weight": 1}]}})
	var cb = BoardState.new()
	cb.setup(3, 1)
	cb.set_cell(0, 0, "G", 1)
	var data2 := _tiny_project()
	var first: Dictionary = cool.tap(data2, cb, [0, 0], 10.0, rng)
	r.check(bool(first["ok"]), "首次产出应成功")
	var cooling: Dictionary = cool.tap(data2, cb, [0, 0], 12.0, rng)
	r.check(not cooling["ok"], "冷却中应拒绝")
	r.eq(cooling["message"], "冷却中", "冷却文案")
	var later: Dictionary = cool.tap(data2, cb, [0, 0], 15.0, rng)
	r.check(bool(later["ok"]), "冷却结束应可再次产出")

	# 稀有产出可达（确定性搜索种子）
	var found_rare := false
	for s in range(1000):
		var ge = GeneratorEngine.new()
		ge.setup(config)
		var gb = BoardState.new()
		gb.setup(7, 9)
		gb.set_cell(3, 3, "CleanBox_C", 1)
		var grng = RandomNumberGenerator.new()
		grng.seed = s
		var res: Dictionary = ge.tap(data, gb, [3, 3], 0.0, grng)
		if bool(res["ok"]) and int(res["level"]) == 2:
			found_rare = true
			break
	r.check(found_rare, "稀有直出（2 级）应在 1000 个种子内出现")


# ---------------------------------------------------------------- orders

func _test_orders(r) -> void:
	var level: Dictionary = _sample_data()["levels"][0]
	var board = BoardState.new()
	board.load_from_level(level)
	var orders = OrderEngine.new()
	orders.setup(level)
	var hud := {"coin": 9, "star": 0}

	var early: Dictionary = orders.deliver(board, "order_1")
	r.check(not early["ok"], "物品不在棋盘时不可交付")

	board.set_cell(4, 3, "CleanSet_Ca", 2)
	var ready: Dictionary = orders.deliver(board, "order_1")
	r.check(bool(ready["ok"]), "物品齐备应可交付")
	r.eq(orders.state_of("order_1"), "ready", "交付后状态 ready")

	var claim_early = OrderEngine.new()
	claim_early.setup(level)
	var not_ready: Dictionary = claim_early.claim(board, "order_1", hud)
	r.check(not not_ready["ok"], "未交付不可领取")

	var claimed: Dictionary = orders.claim(board, "order_1", hud)
	r.check(bool(claimed["ok"]), "ready 状态应可领取")
	r.eq(int(hud["coin"]), 14, "金币 +5")
	r.eq(int(hud["star"]), 1, "星星 +1")
	r.check(not board.has_cell(4, 3), "领取应消耗订单物品")
	r.eq(orders.state_of("order_1"), "claimed", "领取后状态 claimed")
	r.check(bool(claimed["level_complete"]), "全部订单完成应标记关卡完成")

	# 多件同物品的 multiset 消耗
	var lv2 := {
		"id": "lv",
		"orders": [{"id": "o2", "character": "char_01", "mission": [
			{"entity": "Ca", "level": 1}, {"entity": "Ca", "level": 1}], "star": 0, "coin": 0}],
	}
	var b2 = BoardState.new()
	b2.setup(2, 1)
	b2.set_cell(0, 0, "Ca", 1)
	var o2 = OrderEngine.new()
	o2.setup(lv2)
	r.check(not bool(o2.deliver(b2, "o2")["ok"]), "只有一件时双件订单不可交付")
	b2.set_cell(1, 0, "Ca", 1)
	r.check(bool(o2.deliver(b2, "o2")["ok"]), "两件齐备应可交付")
	var hud2 := {"coin": 0, "star": 0}
	r.check(bool(o2.claim(b2, "o2", hud2)["ok"]), "双件订单应可领取")
	r.eq(b2.count_cells(), 0, "双件订单应消耗两格")

	# 空订单：视为全部完成，不阻塞切关
	var empty_orders = OrderEngine.new()
	empty_orders.setup({"id": "x", "orders": []})
	r.check(empty_orders.all_claimed(), "空订单应视为全部完成")

	var empty_data: Dictionary = _sample_data()
	var empty_levels: Array = empty_data["levels"]
	for level_v in empty_levels:
		var empty_level: Dictionary = level_v
		empty_level["orders"] = []
	var empty_state = SimState.new()
	empty_state.setup(empty_data, 1)
	r.check(empty_state.level_complete, "空订单关卡 setup 后应标记 level_complete")
	r.check(empty_state.advance_level(), "空订单关卡不应卡死，advance_level 应成功")

	# mission 非整值：交付与领取都应报“订单数据非法”
	var bad_mission = OrderEngine.new()
	bad_mission.setup({
		"id": "lv_bad",
		"orders": [{
			"id": "o",
			"character": "char_01",
			"mission": [{"entity": "Ca", "level": 1.5}],
			"star": 0,
			"coin": 0,
		}],
	})
	var bad_board = BoardState.new()
	bad_board.setup(2, 1)
	bad_board.set_cell(0, 0, "Ca", 1)
	var bad_deliver: Dictionary = bad_mission.deliver(bad_board, "o")
	r.check(not bool(bad_deliver["ok"]), "非整值 mission 的交付应被拒绝")
	r.eq(str(bad_deliver["message"]), "订单数据非法", "非整值 mission 交付文案")
	var bad_hud: Dictionary = {"coin": 0, "star": 0}
	var bad_claim: Dictionary = bad_mission.claim(bad_board, "o", bad_hud)
	r.check(not bool(bad_claim["ok"]), "非整值 mission 的领取应被拒绝")
	r.eq(str(bad_claim["message"]), "订单数据非法", "非整值 mission 领取文案")


# ---------------------------------------------------------------- level flow

func _test_level_flow(r) -> void:
	var flow = LevelFlow.new()
	flow.setup(_sample_data()["levels"])
	r.eq(flow.level_id(), "level_1", "初始关卡 level_1")
	r.check(flow.has_next(), "level_1 应有下一关")
	r.check(flow.next(), "应能切到 level_2")
	r.eq(flow.level_id(), "level_2", "切关后 level_2")
	r.check(not flow.has_next(), "最后一关没有下一关")
	r.check(not flow.next(), "最后一关 next 应失败")
	r.eq(int(flow.snapshot()["index"]), 1, "index 不应越界")


# ---------------------------------------------------------------- runner

func _test_runner_determinism(r) -> void:
	var doc = _sample_doc()
	var runner = SimRunner.new()
	var first: Dictionary = runner.run(doc, 12345)
	var second: Dictionary = runner.run(doc, 12345)
	r.check(bool(first["ok"]), "样例模拟应全部事件成功: " + _log_text(first["events"]))
	r.eq(first["final_hash"], second["final_hash"], "同 seed 双跑 final_hash 一致")
	r.eq(JSON.stringify(first["events"], "", true), JSON.stringify(second["events"], "", true), "同 seed 双跑事件日志一致")
	r.check(not str(first["final_hash"]).is_empty(), "final_hash 不应为空")


func _test_runner_two_levels(r) -> void:
	var runner = SimRunner.new()
	var result: Dictionary = runner.run(_sample_doc(), 12345)
	r.check(bool(result["ok"]), "两关模拟应成功: " + _log_text(result["events"]))
	var snap: Dictionary = result["snapshot"]
	r.eq(str(snap["level"]["id"]), "level_2", "模拟结束应停在 level_2")
	r.check(bool(snap["level_complete"]), "level_2 订单完成后应标记关卡完成")
	r.eq(int(snap["hud"]["coin"]), 19, "HUD 金币应为 9+5+5")
	r.eq(int(snap["hud"]["star"]), 2, "HUD 星星应为 2")
	var orders_snap: Array = snap["orders"]
	r.eq(orders_snap.size(), 1, "level_2 只有 order_2")
	r.eq(orders_snap[0]["id"], "order_2", "当前订单为 order_2")
	r.eq(orders_snap[0]["state"], "claimed", "order_2 已领取")
	r.eq(int(snap["board"]["cells"].size()), 1, "level_2 结束后只剩生成器格")
	r.eq(str(snap["board"]["cells"][0]["entity"]), "CleanBox_C", "剩余格是生成器")

	var e6 := _find_event(result["events"], "e6")
	r.check(bool(e6.get("ok", false)), "level_next 应成功")
	r.check(str(e6.get("message", "")).find("level_2") != -1, "level_next 应进入 level_2")
	var e5 := _find_event(result["events"], "e5")
	r.check(str(e5.get("message", "")).find("关卡完成") != -1, "第一次领奖应标记关卡完成")
	var e9 := _find_event(result["events"], "e9")
	r.check(bool(e9.get("ok", false)), "第二次领奖应成功")


func _test_runner_rules(r) -> void:
	var runner = SimRunner.new()
	var data := _sample_data()

	# drag 移动
	var drag_data := _with_timeline(data, [
		{"id": "d1", "channel": "sim", "type": "drag", "at": 1.0, "payload": {"from": [2, 3], "to": [1, 0]}},
	])
	var drag_res: Dictionary = runner.run(_doc_from(drag_data), 1)
	r.check(bool(_find_event(drag_res["events"], "d1")["ok"]), "drag 应成功")
	r.eq(int(drag_res["snapshot"]["board"]["cells"].size()), 4, "drag 后格子数不变")
	r.check(_cell_at(drag_res["snapshot"]["board"], 1, 0) != {}, "drag 目标格应有物品")
	r.check(_cell_at(drag_res["snapshot"]["board"], 2, 3) == {}, "drag 来源格应清空")

	# energy_tick 扣/加
	var dec_data := _with_timeline(data, [
		{"id": "n1", "channel": "sim", "type": "energy_tick", "at": 1.0, "payload": {}},
	])
	var dec: Dictionary = runner.run(_doc_from(dec_data), 1)
	r.eq(int(dec["snapshot"]["hud"]["energy"]), 87, "能量应扣 1")
	var inc_data := _with_timeline(data, [
		{"id": "n2", "channel": "sim", "type": "energy_tick", "at": 1.0, "payload": {}},
	])
	inc_data["hud"]["energyTickMode"] = "increment"
	var inc: Dictionary = runner.run(_doc_from(inc_data), 1)
	r.eq(int(inc["snapshot"]["hud"]["energy"]), 89, "能量应加 1")

	# 关卡未完成时 level_next 拒绝
	var early_next := _with_timeline(data, [
		{"id": "n3", "channel": "sim", "type": "level_next", "at": 1.0, "payload": {}},
	])
	var early_res: Dictionary = runner.run(_doc_from(early_next), 1)
	r.check(not bool(_find_event(early_res["events"], "n3")["ok"]), "未完成时 level_next 应失败")

	# 非法合并拒绝
	var bad_merge := _with_timeline(data, [
		{"id": "n4", "channel": "sim", "type": "merge", "at": 1.0, "payload": {"from": [2, 3], "to": [5, 5]}},
	])
	var bad_res: Dictionary = runner.run(_doc_from(bad_merge), 1)
	var n4: Dictionary = _find_event(bad_res["events"], "n4")
	r.check(not bool(n4["ok"]), "不同实体合并不应成功")
	r.eq(str(n4["message"]), "实体不同", "非法合并文案")

	# board_full 作为外部命令不阻断
	var bf := _with_timeline(data, [
		{"id": "n5", "channel": "sim", "type": "board_full", "at": 1.0, "payload": {}},
	])
	var bf_res: Dictionary = runner.run(_doc_from(bf), 1)
	r.check(bool(_find_event(bf_res["events"], "n5")["ok"]), "board_full 命令应记成功")


# ---------------------------------------------------------------- helpers

func _sample_data() -> Dictionary:
	var doc = ProjectDoc.new()
	doc.load_file("res://data/projects/sample_30s.json")
	return doc.data.duplicate(true)


func _sample_doc():
	var doc = ProjectDoc.new()
	doc.load_file("res://data/projects/sample_30s.json")
	return doc


func _doc_from(data: Dictionary):
	var doc = ProjectDoc.new()
	doc.from_dict(data, "<sim-test>")
	return doc


func _with_timeline(data: Dictionary, timeline: Array) -> Dictionary:
	var copy := data.duplicate(true)
	copy["timeline"] = timeline
	return copy


func _tiny_project() -> Dictionary:
	return {
		"entities": {
			"G": {"kind": "generator", "maxLevel": 3},
			"Ca": {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 10},
		},
		"generators": {"G": {"charges": 2, "cooldown": 0, "outputs": [{"entity": "Ca", "weight": 1}]}},
	}


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


func _log_text(events: Array) -> String:
	var parts: Array = []
	for event in events:
		parts.append("%s:%s:%s" % [event.get("id", ""), str(event.get("ok", false)), event.get("message", "")])
	return " | ".join(parts)
