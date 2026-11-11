extends SceneTree
## 打印两关每一格蜘蛛网下面压着的那枚棋子（实机要拖"同款同级"才解锁）。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	m.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_project.json")))
	for li in 2:
		var s = Sim.new(); s.setup(m, 20261111)
		s._load_level(li)
		var rows: Array = []
		for cell in s.board.obstacles.keys():
			if s.board.obstacle_types(cell).has("web"):
				var it: Dictionary = s.board.item(cell)
				rows.append("%s=%s lv%d" % [str(cell), String(it.get("entity", "?")).right(2),
						int(it.get("level", 0))])
		print("RESULT level=", li + 1, " webs=", rows)
	quit()
