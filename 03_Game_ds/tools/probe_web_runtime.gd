extends SceneTree
## 复现操作者那一幕：**盒子炸出来的网**（运行时生成），拖同款上去必须能解锁 + 升级。
## 之前这类网下面没有棋子（视图却画了一枚），所以拖上去报 SIM_TARGET_EMPTY —— 这就是"不生效"。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var FM = load("res://src/core/free_mode.gd")
	var m = PM.new()
	m.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_project.json")))
	var s = Sim.new(); s.setup(m, 20261111)

	# 第 1 关合一次，把周围的锁盒炸成网
	var r: Dictionary = s.apply({"type": "merge", "payload": {"from": [3, 2], "to": [2, 2]}})
	print("RESULT blast ok=", r.get("ok", false), " unlocks=", s.last_unlocks.size())
	for row in s.last_unlocks:
		var cell := Vector2i(int((row as Dictionary)["cell"][0]), int((row as Dictionary)["cell"][1]))
		if String((row as Dictionary).get("became", "")) != "web":
			continue
		var it: Dictionary = s.board.item(cell)
		print("RESULT new_web=", cell, " item=", it)
		# 找一格空格放同款，拖过去（走 FreeMode 判定）
		var src := Vector2i(-1, -1)
		for y in s.board.height:
			for x in s.board.width:
				var c := Vector2i(x, y)
				if not s.board.is_blocked(c) and not s.board.has_item(c):
					src = c
					break
			if src.x >= 0:
				break
		s.board.put(src, String(it.get("entity", "")), int(it.get("level", 1)))
		var act: Dictionary = FM.drag_action(src, cell, s, m, Vector2i(-1, -1))
		var ev := "drag" if String(act.get("kind", "")) == "merge" else String(act.get("kind", ""))
		var rr: Dictionary = s.apply({"type": ev, "payload": act.get("payload", {})})
		print("RESULT drag->web kind=", act.get("kind", ""), " ok=", rr.get("ok", false),
				" code=", rr.get("code", ""), " after=", s.board.item(cell),
				" obstacle=", s.board.obstacle_types(cell))
		break
	quit()
