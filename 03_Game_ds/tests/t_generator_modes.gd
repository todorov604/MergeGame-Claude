extends RefCounted
## 2026-11-12 生成器产出新口径（操作者拍板）：
##   A 真随机 = 本关**所有订单（含已完成）**每个子任务的系列 lv1..需求等级，等权；
##   B 指定顺序 = 每台生成器自己一条队列，一行 1 枚，吐完转 A；
##   库存 = 飞棋子（受 count）/ 飞生成器（只一次，继承库存的 mode/sequence）。

const Sim := preload("res://src/core/sim.gd")
const ProjectModel := preload("res://src/core/project_model.gd")


func run(t) -> void:
	_test_random_pool_covers_every_level(t)
	_test_random_pool_includes_done_orders(t)
	_test_sequence_then_random(t)
	_test_sequence_is_per_cell(t)
	_test_stockpile_chip_mode(t)
	_test_stockpile_generator_once(t)
	_test_stockpile_chip_ignores_stockpile_icon(t)
	_test_move_carries_generator_config(t)


func _entities() -> Dictionary:
	var out := {}
	for i in range(1, 6):
		out["Ca%d" % i] = {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 10}
		out["Cb%d" % i] = {"kind": "chip", "family": "F", "chain": "b", "maxLevel": 10}
	out["Ca"] = {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 10}
	out["Cb"] = {"kind": "chip", "family": "F", "chain": "b", "maxLevel": 10}
	out["Cc"] = {"kind": "chip", "family": "F", "chain": "c", "maxLevel": 10}
	out["GEN"] = {"kind": "generator", "maxLevel": 1}
	return out


func _project(level_extra: Dictionary = {}) -> Dictionary:
	var lv := {
		"id": "g1",
		"board": {"width": 7, "height": 9, "slots": []},
		"obstacles": [], "safes": [],
		"orders": [
			{"id": "o1", "character": "CH", "coin": 1,
			 "mission": [{"entity": "Ca", "level": 4, "count": 1}]},
			{"id": "o2", "character": "CH", "coin": 1,
			 "mission": [{"entity": "Cb", "level": 3, "count": 1}]},
		],
	}
	for k in level_extra.keys():
		lv[k] = level_extra[k]
	return {
		"version": 2,
		"hud": {"energy": 50, "coin": 0, "gem": 0},
		"entities": _entities(),
		"generators": {"GEN": {"charges": 10, "cooldown": 0.0}},
		"characters": {"CH": {"display": "T"}},
		"levels": [lv],
	}


func _sim(project: Dictionary):
	var m = ProjectModel.new()
	if not m.load_data(project):
		return null
	var s = Sim.new()
	s.setup(m, 7)
	return s


## A：随机池 = Ca1..4 + Cb1..3，共 7 条，每条权重 1。
func _test_random_pool_covers_every_level(t) -> void:
	var sim = _sim(_project())
	t.ok(sim != null, "工程能加载")
	var pool: Array = sim.random_pool()
	var keys: Array = []
	for e in pool:
		keys.append("%s@%d" % [String((e as Dictionary)["entity"]), int((e as Dictionary)["level"])])
	keys.sort()
	t.eq(keys, ["Ca@1", "Ca@2", "Ca@3", "Ca@4", "Cb@1", "Cb@2", "Cb@3"],
			"随机池 = 每个子任务的系列 lv1..需求（Ca4+Cb3 → 7 条）")
	var uniform := true
	for e in pool:
		if not is_equal_approx(float((e as Dictionary)["weight"]), 1.0):
			uniform = false
	t.ok(uniform, "每条权重都是 1（等权）")


## A：已完成的订单仍然留在池子里 —— 难度不降。
func _test_random_pool_includes_done_orders(t) -> void:
	var sim = _sim(_project())
	sim.orders[0]["done"] = true
	var keys: Array = []
	for e in sim.random_pool():
		keys.append("%s@%d" % [String((e as Dictionary)["entity"]), int((e as Dictionary)["level"])])
	t.ok(keys.has("Ca@3"), "已完成订单的子任务照样能在池子里抽到")


## B：按顺序吐，一行 1 枚；吐完转随机池。
func _test_sequence_then_random(t) -> void:
	var slot := {"x": 1, "y": 1, "entity": "GEN", "level": 1, "mode": "sequence",
			"sequence": [{"entity": "Ca", "level": 1}, {"entity": "Cb", "level": 2}]}
	var lv := {"board": {"width": 7, "height": 9, "slots": [slot]}}
	var sim = _sim(_project(lv))
	var got: Array = []
	for i in range(3):
		var r: Dictionary = sim.apply({"type": "tap", "payload": {"target": {"slot": [1, 1]}}})
		t.ok(bool(r.get("ok", false)), "第 %d 次点击成功" % (i + 1), str(r))
		var sp: Dictionary = sim.last_spawn
		got.append("%s@%d" % [String(sp.get("entity", "")), int(sp.get("level", 1))])
	t.eq(got.slice(0, 2), ["Ca@1", "Cb@2"], "前两枚严格按队列")
	var third_key := "N/A"
	var k := String(got[2]).split("@")
	if k.size() == 2:
		var lvl := int(k[1])
		var ok_random := (k[0] == "Ca" and lvl >= 1 and lvl <= 4) or (k[0] == "Cb" and lvl >= 1 and lvl <= 3)
		third_key = "random" if ok_random else "bad"
	t.eq(third_key, "random", "队列吐完后落在随机池里（Ca1..4 / Cb1..3）")


## B：两台生成器各自一条队列，互不影响。
func _test_sequence_is_per_cell(t) -> void:
	var a := {"x": 1, "y": 1, "entity": "GEN", "level": 1, "mode": "sequence",
			"sequence": [{"entity": "Ca", "level": 3}]}
	var b := {"x": 3, "y": 1, "entity": "GEN", "level": 1, "mode": "sequence",
			"sequence": [{"entity": "Cb", "level": 2}]}
	var lv := {"board": {"width": 7, "height": 9, "slots": [a, b]}}
	var sim = _sim(_project(lv))
	sim.apply({"type": "tap", "payload": {"target": {"slot": [3, 1]}}})
	t.eq(String(sim.last_spawn.get("entity", "")), "Cb", "先点右边那台 → 出它自己的 Cb")
	sim.apply({"type": "tap", "payload": {"target": {"slot": [1, 1]}}})
	t.eq(int(sim.last_spawn.get("level", 0)), 3, "再点左边那台 → 还是它自己的第 1 条（Ca lv3）")


## 库存 ① 飞棋子：受 count 限制，吐完转随机池。
func _test_stockpile_chip_mode(t) -> void:
	var lv := {
		"board": {"width": 7, "height": 9, "slots": []},
		"stockpile": {"enabled": true, "count": 2, "drop": "chip", "generator": "GEN",
			"mode": "sequence", "sequence": [{"entity": "Cb", "level": 2}]},
	}
	var sim = _sim(_project(lv))
	var r1: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}})
	t.ok(bool(r1.get("ok", false)), "第 1 次飞棋子成功", str(r1))
	t.eq(String(sim.last_spawn.get("entity", "")), "Cb", "按队列先飞 Cb")
	t.eq(String(sim.last_spawn.get("kind", "")), "chip", "飞的是棋子不是生成器")
	var r2: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}})
	t.ok(bool(r2.get("ok", false)), "第 2 次仍然成功（count=2）")
	var r3: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}})
	t.eq(String(r3.get("code", "")), "SIM_STOCKPILE_EMPTY", "count 用完拒绝")


## 库存 ② 飞生成器：只允许一次；落地那台继承库存的 mode/sequence。
func _test_stockpile_generator_once(t) -> void:
	var lv := {
		"board": {"width": 7, "height": 9, "slots": []},
		"stockpile": {"enabled": true, "count": 5, "drop": "generator", "generator": "GEN",
			"mode": "sequence", "sequence": [{"entity": "Ca", "level": 2}]},
	}
	var sim = _sim(_project(lv))
	var r1: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}})
	t.ok(bool(r1.get("ok", false)), "第一次飞出生成器", str(r1))
	t.eq(String(sim.last_spawn.get("kind", "")), "generator", "飞的是生成器")
	var cell: Array = sim.last_spawn.get("to", [])
	t.ok(typeof(cell) == TYPE_ARRAY and (cell as Array).size() == 2, "拿到了落点")
	if typeof(cell) == TYPE_ARRAY and (cell as Array).size() == 2:
		var item: Dictionary = sim.board.item(Vector2i(int(cell[0]), int(cell[1])))
		t.eq(String(item.get("mode", "")), "sequence", "落地生成器继承 mode")
		t.eq((item.get("sequence", []) as Array).size(), 1, "落地生成器继承队列")
		var t2: Dictionary = sim.apply({"type": "tap", "payload": {"target": {"slot": [int(cell[0]), int(cell[1])]}}})
		t.ok(bool(t2.get("ok", false)), "点落地生成器能出货", str(t2))
		t.eq(String(sim.last_spawn.get("entity", "")), "Ca", "出的是库存队列里那条")
	var r2: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}})
	t.eq(String(r2.get("code", "")), "SIM_STOCKPILE_SPENT", "库存只允许飞一次")


## 飞棋子模式：库存的 icon 是给生成器用的，不能盖到棋子上（操作者 2026-11-13 报的 bug）。
func _test_stockpile_chip_ignores_stockpile_icon(t) -> void:
	var lv := {
		"board": {"width": 7, "height": 9, "slots": []},
		"stockpile": {"enabled": true, "count": 4, "drop": "chip", "generator": "GEN",
			"mode": "sequence",
			"sequence": [{"entity": "Ca", "level": 1}, {"entity": "Cb", "level": 1}],
			"icon": "Cc", "iconLevel": 9},
	}
	var sim = _sim(_project(lv))
	sim.apply({"type": "stockpile_tap", "payload": {}})
	var to: Array = sim.last_spawn.get("to", [])
	t.ok(typeof(to) == TYPE_ARRAY and (to as Array).size() == 2, "拿到了落点")
	if typeof(to) == TYPE_ARRAY and (to as Array).size() == 2:
		var item: Dictionary = sim.board.item(Vector2i(int(to[0]), int(to[1])))
		t.eq(String(item.get("entity", "")), "Ca", "棋子还是队列里那枚 Ca")
		t.eq(String(item.get("icon", "")), "", "棋子不能被库存的 icon 覆盖")
		t.eq(int(item.get("icon_level", 0)), 0, "棋子也不能带库存的 iconLevel")
	# 面板外观必须固定：配了 icon 就一直是它，不能跟着下一枚棋子在变
	var snap: Dictionary = sim.snapshot()
	var stock: Dictionary = snap.get("stockpile", {})
	t.eq(String(stock.get("icon", "")), "Cc", "面板图标固定用配置的 icon")
	t.eq(int(stock.get("iconLevel", 0)), 9, "面板图标等级也固定")
	sim.apply({"type": "stockpile_tap", "payload": {}})
	var snap2: Dictionary = sim.snapshot()
	t.eq(String((snap2.get("stockpile", {}) as Dictionary).get("icon", "")), "Cc",
			"点过之后面板图标仍然不变")


## 移动生成器：配方与游标一起走（含图标覆盖）。
func _test_move_carries_generator_config(t) -> void:
	var slot := {"x": 1, "y": 1, "entity": "GEN", "level": 1, "mode": "sequence",
			"sequence": [{"entity": "Ca", "level": 2}, {"entity": "Cb", "level": 1}],
			"icon": "Ca", "iconLevel": 3}
	var lv := {"board": {"width": 7, "height": 9, "slots": [slot]}}
	var sim = _sim(_project(lv))
	sim.apply({"type": "tap", "payload": {"target": {"slot": [1, 1]}}})
	var r: Dictionary = sim.apply({"type": "move", "payload": {"from": [1, 1], "to": [5, 5]}})
	t.ok(bool(r.get("ok", false)), "移动成功", str(r))
	var item: Dictionary = sim.board.item(Vector2i(5, 5))
	t.eq(String(item.get("mode", "")), "sequence", "移动后 mode 还在")
	t.eq(String(item.get("icon", "")), "Ca", "移动后图标覆盖还在")
	sim.apply({"type": "tap", "payload": {"target": {"slot": [5, 5]}}})
	t.eq(int(sim.last_spawn.get("level", 0)), 1, "游标跟着走：第 2 次出队列第 2 条（Cb lv1）")
