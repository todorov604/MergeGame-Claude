extends RefCounted
## 自造关卡的自验套件：**不再依赖操作者的录屏**。
##
## 每个用例用内存里的合成工程 + 合成 take 跑一遍真实 sim / TakeIo / 视图，
## 断言"改了什么就验什么"：冰只按时间化、爆炸不波及、任务栏偏移回放与空档保持、
## 融化动画参数。新增功能时先在这里加一条，再去出片。
##
## 命名口径：所有用例都写清楚"哪条需求 → 哪条断言"，失败信息直接指出坏在哪。

const Sim = preload("res://src/core/sim.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const TakeIo = preload("res://src/core/take_io.gd")
const BoardView = preload("res://src/view/board_view.gd")


func run(t) -> void:
	_ice_timer_only(t)
	_band_replay_from_take(t)
	_melt_anim_contract(t)
	_stockpile_drops_premium_generator(t)
	_premium_generator_follows_every_mission(t)


## 合成工程：3 枚同系列棋子 + 一块冰，冰在第 1 关配成 `ice_seconds` 秒。
func _project(ice_seconds: int, blast: int) -> Dictionary:
	return {
		"entities": {
			"CleanSet_Ca": {"kind": "chip", "max_level": 7},
			"CleanSet_Cb": {"kind": "chip", "max_level": 7},
			"CleanGen_X": {"kind": "generator", "pool": [{"entity": "CleanSet_Ca", "level": 1}]},
		},
		"generators": {"CleanGen_X": {"pool": [{"entity": "CleanSet_Ca", "level": 1, "weight": 1}]}},
		"hud": {"coin": 0, "gem": 0, "energy": 0},
		"levels": [{
			"id": "probe_ice",
			"level_number": 1,
			"blast": blast,
			"ice_seconds": ice_seconds,
			"board": {"width": 7, "height": 9, "slots": [
				{"slot": [2, 3], "entity": "CleanSet_Ca", "level": 1},
				{"slot": [3, 3], "entity": "CleanSet_Ca", "level": 1},
				{"slot": [4, 4], "entity": "CleanSet_Ca", "level": 1},
			]},
			"obstacles": [{"slot": [3, 4], "type": "ice"}],
			"orders": [],
		}],
	}


func _sim(ice_seconds: int = 4, blast: int = 2):
	var model = ProjectModel.new()
	model.load_data(_project(ice_seconds, blast))
	var sim = Sim.new()
	sim.setup(model, 20261110)
	return sim


## 需求：冰**只能等自己的倒计时**，爆炸不许波及；到点自己化掉并放出里面的棋子。
func _ice_timer_only(t) -> void:
	var sim = _sim(4, 2)
	var ice := Vector2i(3, 4)
	t.eq(sim.ice_remaining(ice), 4, "合成关卡：冰剩 4 秒（读 ice_seconds）")
	var res: Dictionary = sim.apply({"type": "merge", "payload": {"from": [2, 3], "to": [3, 3]}, "at": 1.0})
	t.ok(bool(res.get("ok", false)), "合成关卡：合并成功 " + str(res.get("code", "")))
	t.ok(sim.board.obstacle_types(ice).has("ice"), "合成关卡：blast=2 扫到冰也不炸开")
	t.eq(sim.tick_to(3.9).size(), 0, "合成关卡：3.9 秒还没到点")
	t.eq(sim.ice_remaining(ice), 1, "合成关卡：3.9 秒时剩 1 秒")
	var melts: Array = sim.tick_to(4.05)
	t.eq((melts as Array).size(), 1, "合成关卡：4 秒到点化成一条事件")
	t.ok(not sim.board.obstacle_types(ice).has("ice"), "合成关卡：到点后冰消失")
	t.ok(sim.board.has_item(ice), "合成关卡：化掉后格子里有棋子")
	t.eq(sim.tick_to(9.0).size(), 0, "合成关卡：同一块冰只化一次")


## 需求：成片里的任务栏偏移**只认 take 记录**，空档保持、首采样前归位。
func _band_replay_from_take(t) -> void:
	var take := {
		"band": [
			[1.0, 0.0],
			[1.02, 30.0],
			[1.04, 60.0],
			[1.06, 90.0],
			[3.0, 0.0],
		],
	}
	t.ok(is_equal_approx(TakeIo.band_at(take, 0.5), 0.0), "任务栏：首采样之前必须归位")
	t.ok(is_equal_approx(TakeIo.band_at(take, 1.03), 45.0), "任务栏：拖动段按时间插值")
	t.ok(is_equal_approx(TakeIo.band_at(take, 2.0), 90.0), "任务栏：空档内保持不动（不漂）")
	t.ok(is_equal_approx(TakeIo.band_at(take, 3.0), 0.0), "任务栏：松手后回到 0")
	var empty := {"band": []}
	t.ok(is_equal_approx(TakeIo.band_at(empty, 2.0), 0.0), "任务栏：没有记录就一点都不动")


## 需求：融化效果 = 扩大消失（1.9 倍 + 0.45 秒），画的是冰本身。
func _melt_anim_contract(t) -> void:
	var v = BoardView.new()
	v.melt(Vector2i(1, 1), "ice", 0.0)
	var rows: Array = v.unlock_rows()
	t.eq((rows as Array).size(), 1, "融化动画：进队列")
	var row: Dictionary = rows[0]
	t.ok(bool(row.get("melt", false)), "融化动画：标记 melt")
	t.eq(String(row.get("shown", "")), "ice", "融化动画：画冰")
	v.set_ice_remaining_map({Vector2i(1, 1): 45})
	t.eq(int(v.ice_remaining_for(Vector2i(1, 1))), 45, "融化动画：倒计时读 sim 给的秒数")


## 需求：左上角库存改投**高级生成器**（不是固定棋子）；级别 = 单个子任务 clip 级别 - 1；
## 落点随机、带闪电，点它产出的就是那个级别（比棋盘上的生成器更好）。
func _stockpile_drops_premium_generator(t) -> void:
	var model = ProjectModel.new()
	var project: Dictionary = _project(4, 2)
	project["entities"]["CleanBox_P"] = {
		"kind": "generator", "maxLevel": 3,
		"visual": {"hue": "#7E57C2", "label": "Box+", "icon": "ui_generator_premium"},
	}
	project["generators"] = {
		"CleanBox_P": {"charges": 10, "cooldown": 0.0, "levelFromItem": true,
				"outputs": [{"entity": "CleanSet_Ca", "weight": 100}], "rareOutputs": []},
	}
	# 任务要 lv2 的 Ca → 生成器应为 lv1
	project["levels"][0]["stockpile"] = {"enabled": true, "count": 3, "generator": "CleanBox_P"}
	project["levels"][0]["orders"] = [{
		"id": "o1", "character": "", "coin": 1, "gem": 0, "energy": 0,
		"mission": [{"entity": "CleanSet_Ca", "level": 2, "count": 1}],
	}]
	model.load_data(project)
	var sim = Sim.new()
	sim.setup(model, 20261110)

	var preview: Dictionary = sim.stockpile_preview()
	t.eq(String(preview.get("kind", "")), "generator", "库存预览是生成器")
	t.eq(String(preview.get("entity", "")), "CleanBox_P", "预览实体是高级生成器")
	t.eq(int(preview.get("level", 0)), 1, "级别 = 任务 clip 级别(2) - 1")

	var res: Dictionary = sim.apply({"type": "stockpile_tap", "payload": {}, "at": 1.0})
	t.ok(bool(res.get("ok", false)), "投放成功 " + str(res.get("code", "")))
	t.eq(String(sim.last_spawn.get("kind", "")), "generator", "落下去的是生成器")
	var cell := Vector2i(int(sim.last_spawn["to"][0]), int(sim.last_spawn["to"][1]))
	t.eq(String(sim.board.item(cell).get("entity", "")), "CleanBox_P", "棋盘上真的是高级生成器")
	t.eq(int(sim.board.item(cell).get("level", 0)), 1, "落地生成器带自己的级别")

	sim.hud["energy"] = 5
	var tap: Dictionary = sim.apply({"type": "tap", "payload": {"target": {"slot": [cell.x, cell.y]}}, "at": 2.0})
	t.ok(bool(tap.get("ok", false)), "点生成器成功 " + str(tap.get("code", "")))
	t.eq(int(sim.last_spawn.get("level", 0)), 1, "产出级别 = 生成器自己的级别（levelFromItem）")


## 需求（补充）：「各个小人儿，每个子任务下的次一等级」——
## 高级生成器的产出池 = 每张卡（每个小人儿）的每个子任务，各取"任务级别 - 1"。
func _premium_generator_follows_every_mission(t) -> void:
	var model = ProjectModel.new()
	var project: Dictionary = _project(4, 2)
	project["entities"]["CleanSet_Cb"] = {"kind": "chip", "max_level": 7}
	project["entities"]["CleanSet_Cc"] = {"kind": "chip", "max_level": 7}
	project["entities"]["CleanBox_P"] = {
		"kind": "generator", "maxLevel": 3,
		"visual": {"hue": "#7E57C2", "label": "Box+", "icon": "ui_generator_premium"},
	}
	project["generators"] = {
		"CleanBox_P": {"charges": 10, "cooldown": 0.0, "missionPool": true,
				"outputs": [{"entity": "CleanSet_Ca", "weight": 100}], "rareOutputs": []},
	}
	project["levels"][0]["stockpile"] = {"enabled": true, "count": 9, "generator": "CleanBox_P"}
	# 两张卡（两个小人儿），子任务级别各不相同
	project["levels"][0]["orders"] = [
		{"id": "o1", "character": "char_a", "coin": 1, "gem": 0, "energy": 0, "mission": [
			{"entity": "CleanSet_Ca", "level": 4, "count": 1},
			{"entity": "CleanSet_Cb", "level": 3, "count": 1},
		]},
		{"id": "o2", "character": "char_b", "coin": 1, "gem": 0, "energy": 0, "mission": [
			{"entity": "CleanSet_Cc", "level": 5, "count": 1},
		]},
	]
	model.load_data(project)
	var sim = Sim.new()
	sim.setup(model, 20261110)

	var pool: Array = sim._mission_pool()
	t.eq((pool as Array).size(), 3, "池子覆盖每个子任务（2 + 1）")
	var keys := {}
	for row in pool:
		keys["%s lv%d" % [String((row as Dictionary)["entity"]), int((row as Dictionary)["level"])]] = true
	t.ok(keys.has("CleanSet_Ca lv3"), "小人儿 A 的子任务 Ca4 → 次一级 Ca3")
	t.ok(keys.has("CleanSet_Cb lv2"), "小人儿 A 的子任务 Cb3 → 次一级 Cb2")
	t.ok(keys.has("CleanSet_Cc lv4"), "小人儿 B 的子任务 Cc5 → 次一级 Cc4")

	# 连点 12 次必须出现多种，而不是永远同一种
	sim.hud["energy"] = 99
	sim.apply({"type": "stockpile_tap", "payload": {}, "at": 0.5})
	var cell := Vector2i(int(sim.last_spawn["to"][0]), int(sim.last_spawn["to"][1]))
	var seen := {}
	for i in 12:
		for c in sim.board.cells.keys():
			if c != cell:
				sim.board.take(c)
		var tap: Dictionary = sim.apply({"type": "tap",
				"payload": {"target": {"slot": [cell.x, cell.y]}}, "at": 1.0 + float(i)})
		if not bool(tap.get("ok", false)):
			break
		var key := "%s lv%d" % [String(sim.last_spawn["entity"]), int(sim.last_spawn["level"])]
		seen[key] = true
	t.ok(seen.size() >= 3, "连点 12 次至少出 3 种（现在 " + str(seen.size()) + " 种）")
