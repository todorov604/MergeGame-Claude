extends SceneTree
## 探针：跑一次真实合并，打印炸开范围内每格的障碍变化（验证 blast 配置与蓝盒子出货）。

func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	var js := FileAccess.get_file_as_string("res://data/sample_project.json")
	m.load_data(JSON.parse_string(js))
	var s = Sim.new()
	s.setup(m, 1)
	var centre := Vector2i(3, 2)
	var before := {}
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c: Vector2i = centre + Vector2i(dx, dy)
			if not s.board.in_bounds(c):
				continue
			before[c] = s.board.obstacle_types(c)
	print("blast=", s.blast_radius())
	var r: Dictionary = s.apply({"type": "merge", "payload": {"from": [2, 2], "to": [3, 2]}})
	print("merge ok=", r.get("ok", false), " code=", r.get("code", ""))
	print("unlocks=", s.last_unlocks)
	for c in before.keys():
		var now: Array = s.board.obstacle_types(c)
		if str(before[c]) != str(now):
			print("  ", c, " ", before[c], " -> ", now)
	quit()
