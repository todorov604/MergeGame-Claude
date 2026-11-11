extends SceneTree
## 回放一个 take，打印每次 drag 的结果与"网相关"的状态（验证拖同款解锁 + 升级）。
##   godot --headless --path . --script res://tools/probe_take_web.gd -- <take>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var take_path := "res://output/mov/20261111_153811/take_20261111_153811.take.json"
	if args.size() > 0:
		take_path = String(args[0])
	var PM = load("res://src/core/project_model.gd")
	var Eval = load("res://src/core/event_evaluator.gd")
	var TakeIo = load("res://src/core/take_io.gd")
	var take: Dictionary = TakeIo.load_file(take_path)
	var m = PM.new()
	m.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_project.json")))
	var ev = Eval.new()
	ev.setup(m, int(take.get("seed", 1)))
	ev.load_timeline(take.get("timeline", []))
	print("RESULT start webs=", _webs(ev.sim))
	while ev.cursor < ev.events.size():
		var e: Dictionary = ev.events[ev.cursor]
		var report: Dictionary = ev.step()
		var sim = ev.sim
		var p = (e.get("payload", {}) as Dictionary)
		if String(e.get("type", "")) == "drag":
			var to := Vector2i(int((p.get("to", [0,0]) as Array)[0]), int((p.get("to", [0,0]) as Array)[1]))
			var simr = (report.get("sim", {}) as Dictionary)
			print("RESULT t=%.2f drag->%s ok=%s code=%s web_unlocked=%s item=%s" % [
					float(e.get("at", 0.0)), str(to), str(simr.get("ok", false)),
					String(simr.get("code", "")), str(simr.get("web_unlocked", false)),
					str(sim.board.item(to))])
		print("RESULT   webs=", _webs(sim))
	quit()


func _webs(sim) -> String:
	var out: Array = []
	for cell in sim.board.obstacles.keys():
		if sim.board.obstacle_types(cell).has("web"):
			out.append("%s=%s lv%d" % [str(cell),
					String(sim.board.item(cell).get("entity", "?")).right(2),
					int(sim.board.item(cell).get("level", 0))])
	return " | ".join(out)
