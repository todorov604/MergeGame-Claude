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
