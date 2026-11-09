extends SceneTree
## 一次性探针：回放 take，把每次 order_claim 的 taken / 起点格 / 前后棋盘打出来。
## 只读，不写任何文件。
##   godot --headless --path . --script res://tools/probe_claim_taken.gd -- --take=<path>

const ProjectModel := preload("res://src/core/project_model.gd")
const EventEvaluator := preload("res://src/core/event_evaluator.gd")
const TakeIo := preload("res://src/core/take_io.gd")


func _initialize() -> void:
	var take_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--take="):
			take_path = arg.substr(7)
	if take_path.is_empty():
		print("[probe] need --take=<path>")
		quit(2)
		return
	var text := FileAccess.get_file_as_string(take_path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("[probe] take is not json object")
		quit(2)
		return
	var take: Dictionary = parsed
	var project := String(take.get("project", "res://data/sample_project.json"))
	var model := ProjectModel.new()
	if not model.load_file(project):
		print("[probe] cannot load project ", project)
		quit(2)
		return
	var ev := EventEvaluator.new()
	ev.setup(model, int(take.get("seed", 0)), null)
	ev.load_timeline(take.get("timeline", []))
	print("[probe] project=", project, " seed=", take.get("seed"), " events=", ev.events.size())
	var events: Array = ev.events
	while ev.cursor < events.size():
		var e: Dictionary = events[ev.cursor]
		var typ := String(e.get("type", ""))
		var payload = e.get("payload", {})
		var before := ""
		if typ == "order_claim" and typeof(payload) == TYPE_DICTIONARY:
			var src = (payload as Dictionary).get("src", [])
			if typeof(src) == TYPE_ARRAY and (src as Array).size() >= 2:
				before = _cell_desc(ev.sim.snapshot(), int((src as Array)[0]), int((src as Array)[1]))
		var r: Dictionary = ev.step()
		if typ == "order_claim":
			print("--- claim at %.3f order=%s src=%s" % [float(r.get("at", 0.0)),
					String((payload as Dictionary).get("order", "?")), str((payload as Dictionary).get("src", []))])
			var sim_res = r.get("sim", {})
			print("    ok=%s code=%s TOP_taken=%s SIM_taken=%s" % [str(r.get("ok")), String(r.get("code", "")), str(r.get("taken", [])), str((sim_res as Dictionary).get("taken", []))])
			print("    src cell BEFORE = ", before)
			print("    board BEFORE/AT = ", _board_cells_around(ev.sim.snapshot(), payload))
			print("    coin=%d level_index=%d" % [int(ev.sim.hud.get("coin", -1)), int(ev.sim.level_index)])
	quit(0)


func _cell_desc(snap: Dictionary, x: int, y: int) -> String:
	var cells = (snap.get("board", {}) as Dictionary).get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		return "no-cells"
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
			continue
		if int((raw as Array)[0]) == x and int((raw as Array)[1]) == y:
			return "%s lv%d" % [String((raw as Array)[2]), int((raw as Array)[3])]
	return "(empty)"


func _board_cells_around(snap: Dictionary, payload) -> String:
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	var out: Array = []
	var cells = (snap.get("board", {}) as Dictionary).get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		return ""
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
			continue
		out.append("%d,%d=%s%d" % [int((raw as Array)[0]), int((raw as Array)[1]),
				String((raw as Array)[2]), int((raw as Array)[3])])
	return " ".join(out)
