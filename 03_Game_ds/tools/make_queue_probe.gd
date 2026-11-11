extends SceneTree
## 自造"交付 + 排序"验证关卡与合成 take（不碰操作者的录屏）。
##
##   godot --headless --path . --script res://tools/make_queue_probe.gd
##
## 产物：
##   output/probe/queue_project.json   4 张卡，棋盘上只有 Cc×2 与 Cd×1
##   output/probe/queue.take.json      1.5s 合并两枚 Cc（让第 3 张卡掉出"全满"）
##                                     3.0s 交付第 4 张卡（点对号的效果）
##
## 看点（按新排序规则）：
##   初始   c3(全满)、c4(全满) → 绿组在前，先满的 c3 在前：[c3, c4, c1, c2]
##   1.5s   c3 的两枚 Cc 被合并成 Cc2 → c3 掉出绿组 → 排到最后一个绿卡后面：[c4, c3, c1, c2]
##   3.0s   c4 交付结算 → 缩卡消失 → 队列补位：[c3, c1, c2]，奖励从 c4 那张卡飞

const IceCell = preload("res://src/core/ice_cell.gd")
const PROJECT_IN := "res://data/sample_project.json"
const OUT_DIR := "res://output/probe"

const MERGE_A := Vector2i(3, 1)
const MERGE_B := Vector2i(4, 1)
const CD_CELL := Vector2i(5, 1)
const WEB_CELL := Vector2i(2, 3)
const WEB_NB := Vector2i(1, 3)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var project: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROJECT_IN))
	var level: Dictionary = project["levels"][0]
	level["id"] = "probe_queue"
	level["safes"] = []
	level["obstacles"] = []
	level["stockpile"] = {"enabled": false}
	# 校验器要求"每张订单都可达"：c1/c2 要 lv2，棋盘给两枚 lv1（可合成出来），
	# 但初始**不算满**（棋盘上没有 lv2），所以只有 c3、c4 是绿的。
	var webbed_chip: Dictionary = IceCell.chip(project, WEB_CELL)
	level["board"] = {
		"width": 7, "height": 9,
		"slots": [
			{"x": 1, "y": 1, "entity": "CleanSet_Ca", "level": 1},
			{"x": 2, "y": 1, "entity": "CleanSet_Ca", "level": 1},
			{"x": 1, "y": 2, "entity": "CleanSet_Cb", "level": 1},
			{"x": 2, "y": 2, "entity": "CleanSet_Cb", "level": 1},
			{"x": MERGE_A.x, "y": MERGE_A.y, "entity": "CleanSet_Cc", "level": 1},
			{"x": MERGE_B.x, "y": MERGE_B.y, "entity": "CleanSet_Cc", "level": 1},
			{"x": CD_CELL.x, "y": CD_CELL.y, "entity": "CleanSet_Cd", "level": 1},
			# 2026-11-11：网下压着的棋子由 `IceCell.chip()` 按格子确定 —— 这里**算同一枚**
			# 放到旁边，3.4s 拖过去 → 解锁网 + 合成 lv2（不能瞎猜款式，否则 SIM_ENTITY_MISMATCH）。
			{"x": WEB_NB.x, "y": WEB_NB.y,
				"entity": String(webbed_chip.get("entity", "CleanSet_Ca")),
				"level": int(webbed_chip.get("level", 1))},
		],
	}
	level["obstacles"] = [{"slot": [WEB_CELL.x, WEB_CELL.y], "type": "web"}]
	level["orders"] = [
		{"id": "c1", "character": "char_blonde",
			"mission": [{"entity": "CleanSet_Ca", "level": 2, "count": 1}],
			"coin": 5, "gem": 2, "energy": 30},
		{"id": "c2", "character": "char_worker",
			"mission": [{"entity": "CleanSet_Cb", "level": 2, "count": 1}],
			"coin": 6, "gem": 1, "energy": 40},
		{"id": "c3", "character": "char_racer",
			"mission": [{"entity": "CleanSet_Cc", "level": 1, "count": 2}],
			"coin": 7, "gem": 3, "energy": 50},
		{"id": "c4", "character": "char_waitress",
			"mission": [{"entity": "CleanSet_Cd", "level": 1, "count": 1}],
			"coin": 8, "gem": 4, "energy": 60},
		# 2026-11-11：部分收集（2/3）必须和 0/1 长得一样（米色底板 + 棕描边）
		{"id": "c5", "character": "char_police",
			"mission": [{"entity": "CleanSet_Ca", "level": 1, "count": 3}],
			"coin": 9, "gem": 2, "energy": 45},
	]
	var out := ProjectSettings.globalize_path(OUT_DIR) + "/queue_project.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(project, "  "))
	f.close()

	var cursor: Array = []
	var t := 0.0
	while t < 5.0:
		cursor.append([snappedf(t, 0.001), 300.0, 600.0])
		t += 0.1

	var timeline: Array = [
		{
			"id": "q_merge", "type": "merge", "channel": "sim", "at": 1.5,
			"payload": {"from": [MERGE_A.x, MERGE_A.y], "to": [MERGE_B.x, MERGE_B.y]},
		},
		{
			# 2026-11-11：拖同款棋子压到蜘蛛网上 → 解锁网 + 合成高一级
			"id": "q_web", "type": "merge", "channel": "sim", "at": 3.4,
			"payload": {"from": [WEB_NB.x, WEB_NB.y], "to": [WEB_CELL.x, WEB_CELL.y]},
		},
		{
			"id": "q_deliver", "type": "deliver", "channel": "sim", "at": 3.0,
			"payload": {"order": "c4", "row": 0, "from": [CD_CELL.x, CD_CELL.y], "via": "check"},
		},
	]
	var take := {
		"schema": 1,
		"seed": 20261111,
		"fps": 60,
		"duration": 5.0,
		"project": "res://output/probe/queue_project.json",
		"cursor": cursor,
		"clicks": [],
		"drag": [],
		# 整排往左推 430px，让第 3/4 张卡（含"部分收集 2/3"那张）进画面
		"band": [[0.0, -430.0]],
		"timeline": timeline,
	}
	var target := ProjectSettings.globalize_path(OUT_DIR) + "/queue.take.json"
	var tf := FileAccess.open(target, FileAccess.WRITE)
	tf.store_string(JSON.stringify(take, "  "))
	tf.close()
	print("[queue-probe] wrote ", out, " and ", target)
	quit()
