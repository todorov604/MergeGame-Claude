extends SceneTree
## 自造验证关卡 + 合成 take 的生成器（**不碰操作者的录屏**）。
##
## 用法：
##   godot --headless --path . --script res://tools/make_probe.gd
## 产物：
##   output/probe/project.json      合成工程：第 1 关一块 3 秒的冰、blast=2
##   output/probe/probe.take.json   合成 take：1.2s 在冰旁边合并；2.4~3.6s 拖任务栏
##
## 设计约束：
## - 冰必须**扛住 1.2s 的合并爆炸**（blast=2 覆盖到它），又在 3 秒时自己化掉；
##   出片后 `tools/verify_probe.py` 会量像素证明这两条。
## - 任务栏偏移直接写进 `band`（录制端就是这样写的），验证成片回放。

const PROJECT_IN := "res://data/sample_project.json"
const OUT_DIR := "res://output/probe"
const TAKE := "res://output/probe/probe.take.json"

const ICE_CELL := Vector2i(3, 3)
const MERGE_FROM := Vector2i(2, 2)
const MERGE_TO := Vector2i(3, 2)
const ICE_SECONDS := 3


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var project: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROJECT_IN))
	var level: Dictionary = project["levels"][0]
	level["id"] = "probe_ice"
	level["blast"] = 2
	level["ice_seconds"] = ICE_SECONDS
	# 冰放到合并点旁边（曼哈顿距离 1），爆炸必然扫到它。
	var obstacles: Array = []
	for row in level.get("obstacles", []):
		var slot: Array = (row as Dictionary).get("slot", [])
		if slot.size() >= 2 and int(slot[0]) == ICE_CELL.x and int(slot[1]) == ICE_CELL.y:
			continue
		if (row as Dictionary).get("type", "") == "ice":
			continue
		obstacles.append(row)
	obstacles.append({"slot": [ICE_CELL.x, ICE_CELL.y], "type": "ice"})
	level["obstacles"] = obstacles

	var out := ProjectSettings.globalize_path(OUT_DIR) + "/project.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(project, "  "))
	f.close()

	# 合成 take：1.2s 合并；2.4~3.6s 把任务栏往左拖 200px 再回弹。
	var cursor: Array = []
	var band: Array = []
	var t := 0.0
	while t < 6.0:
		cursor.append([snappedf(t, 0.001), 300, 900])
		t += 0.1
	var drag_start := 2.4
	var drag_peak := 3.0
	var drag_end := 3.6
	t = drag_start
	while t <= drag_peak:
		var k := (t - drag_start) / (drag_peak - drag_start)
		band.append([snappedf(t, 0.001), snappedf(-200.0 * k, 0.1)])
		t += 0.02
	t = drag_peak + 0.02
	while t <= drag_end:
		band.append([snappedf(t, 0.001), snappedf(-200.0 * (1.0 - (t - drag_peak) / (drag_end - drag_peak)), 0.1)])
		t += 0.02
	band.append([snappedf(drag_end + 0.02, 0.001), 0.0])

	var timeline: Array = [{
		"id": "probe_merge",
		"type": "merge",
		"channel": "sim",
		"at": 1.2,
		"payload": {"from": [MERGE_FROM.x, MERGE_FROM.y], "to": [MERGE_TO.x, MERGE_TO.y]},
	}]
	var take := {
		"schema": 1,
		"seed": 20261110,
		"fps": 60,
		"duration": 6.0,
		"project": "res://output/probe/project.json",
		"cursor": cursor,
		"clicks": [],
		"drag": [],
		"band": band,
		"timeline": timeline,
	}
	var target := ProjectSettings.globalize_path(TAKE)
	var tf := FileAccess.open(target, FileAccess.WRITE)
	tf.store_string(JSON.stringify(take, "  "))
	tf.close()
	print("[probe] wrote project=%s take=%s band=%d" % [out, target, band.size()])
	quit()
