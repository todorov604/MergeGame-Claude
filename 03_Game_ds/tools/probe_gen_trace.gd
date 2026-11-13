extends SceneTree
## 打印 6 个 case 的 sim 轨迹（每次点击吐出了什么 / 是否被拒），作为出片之外的文字证据。

const ProjectModel := preload("res://src/core/project_model.gd")
const Sim := preload("res://src/core/sim.gd")
const TakeIo := preload("res://src/core/take_io.gd")

const CASES := ["case1_random", "case2_sequence", "case3_per_cell",
		"case4_stockpile_chip", "case5_stockpile_generator",
		"case6a_level1_random", "case6b_level2_sequence"]


func _init() -> void:
	for name in CASES:
		var proj_path := "res://output/probe/%s.json" % name
		var take_path := "res://output/probe/%s.take.json" % name
		var m = ProjectModel.new()
		if not m.load_file(proj_path):
			print("[trace] %s LOAD_FAIL" % name)
			continue
		var sim = Sim.new()
		sim.setup(m, 7)
		var take = TakeIo.load_file(take_path)
		print("[trace] === %s ===" % name)
		for ev in (take.get("timeline", []) as Array):
			var at := float((ev as Dictionary).get("at", 0.0))
			sim.tick_to(at)
			var r: Dictionary = sim.apply({"type": String((ev as Dictionary).get("type", "")),
					"payload": (ev as Dictionary).get("payload", {})})
			var sp: Dictionary = sim.last_spawn
			var what := "-"
			if not sp.is_empty():
				what = "%s@%s(%s)" % [String(sp.get("entity", "")), str(sp.get("level", 1)),
						String(sp.get("kind", "chip"))]
			print("   t=%.2f %-14s ok=%s %-26s stock=%d %s" % [at,
					String((ev as Dictionary).get("type", "")), str(r.get("ok", false)),
					what, int(sim.stockpile_count), String(r.get("code", ""))])
		print("   board items=%d" % (sim.board.cells as Dictionary).size())
	quit(0)
