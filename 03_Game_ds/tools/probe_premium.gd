extends SceneTree
## 探针：第 2 关高级生成器连点，统计弹出的实体/级别分布（验证"跟着任务出、不单一"）。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	m.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_project.json")))
	var s = Sim.new()
	s.setup(m, 20261110)
	# 直接进第 2 关（探针不依赖操作者进度）
	s._load_level(1)
	s.hud["energy"] = 99
	var r: Dictionary = s.apply({"type": "stockpile_tap", "payload": {}, "at": 0.2})
	var cell := Vector2i(int(s.last_spawn["to"][0]), int(s.last_spawn["to"][1]))
	print("stockpile spawn=", s.last_spawn, " ok=", r.get("ok", false))
	var seen := {}
	for i in 24:
		# 每次把上一条产出清掉，避免棋盘塞满
		for c in s.board.cells.keys():
			if c != cell:
				s.board.take(c)
		var tap: Dictionary = s.apply({"type": "tap", "payload": {"target": {"slot": [cell.x, cell.y]}}, "at": 1.0 + float(i)})
		if not bool(tap.get("ok", false)):
			print("tap rejected: ", tap.get("code", ""))
			break
		var key := "%s lv%d" % [String(s.last_spawn.get("entity", "")), int(s.last_spawn.get("level", 0))]
		seen[key] = int(seen.get(key, 0)) + 1
	print("distinct=", seen.size())
	for k in seen.keys():
		print("  ", k, " x", seen[k])
	quit()
