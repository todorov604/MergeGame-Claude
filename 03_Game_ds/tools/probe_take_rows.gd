extends SceneTree
## 回放 take：打印每一行子任务的"棋盘枚数/需求"，并列出棋盘上所有棋子。
##   godot --headless --path . --script res://tools/probe_take_rows.gd -- <take>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var take_path := "res://output/mov/20261110_215708/take_20261110_215708.take.json"
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
	_dump("start", ev.sim)
	while ev.cursor < ev.events.size():
		var e: Dictionary = ev.events[ev.cursor]
		ev.step()
		_dump("t=%.2f %s" % [float(e.get("at", 0.0)), String(e.get("type", ""))], ev.sim)
	quit()


func _dump(tag: String, sim) -> void:
	var counts := {}
	for c in sim.board.cells.keys():
		var it: Dictionary = sim.board.item(c)
		var key := "%s@%d" % [String(it.get("entity", "")), int(it.get("level", 0))]
		counts[key] = int(counts.get(key, 0)) + 1
	var rows: Array = []
	for o in sim.orders:
		if bool((o as Dictionary).get("done", false)):
			continue
		for mm in (o as Dictionary).get("mission", []):
			var key2 := "%s@%d" % [String((mm as Dictionary).get("entity", "")), int((mm as Dictionary).get("level", 0))]
			rows.append("%s %d/%d" % [key2, int(counts.get(key2, 0)), int((mm as Dictionary).get("need", 1))])
	print(tag, " -> ", " | ".join(rows), "   all=", counts)
