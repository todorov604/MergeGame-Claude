extends SceneTree

## 模拟入口（M0 第 1 周第 2 步）：
## godot --headless --path 02_Game --script res://tools/simulate.gd -- [选项]
##   --project X   项目 JSON（默认 res://data/projects/sample_30s.json）
##   --seed N      随机种子（默认取项目 meta.seed 的整数值，否则 0）
##   --runs N      重复运行次数（默认 2，至少 1）
##   --json        只输出一个 JSON 汇总
## 退出码：确定性一致且全部事件成功 -> 0，否则 1。

const ProjectDoc := preload("res://core/project_doc.gd")
const SimRunner := preload("res://core/sim/sim_runner.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var project_path := "res://data/projects/sample_30s.json"
	var seed_arg: Variant = null
	var runs := 2
	var json_output := false

	var i := 0
	while i < args.size():
		var arg := String(args[i])
		if arg == "--project" and i + 1 < args.size():
			i += 1
			project_path = String(args[i])
		elif arg == "--seed" and i + 1 < args.size():
			i += 1
			if String(args[i]).is_valid_int():
				seed_arg = int(String(args[i]))
		elif arg == "--runs" and i + 1 < args.size():
			i += 1
			if String(args[i]).is_valid_int():
				runs = maxi(1, int(String(args[i])))
		elif arg == "--json":
			json_output = true
		i += 1

	var resolved_project := _resolve_path(project_path)
	var project = ProjectDoc.new()
	if not project.load_file(resolved_project):
		print("ERROR 加载项目失败: %s" % project.parse_error)
		quit(1)
		return

	var seed_value := 0
	if seed_arg != null:
		seed_value = int(seed_arg)
	else:
		var meta_v: Variant = project.data.get("meta", {})
		if typeof(meta_v) == TYPE_DICTIONARY:
			seed_value = _int_like_or((meta_v as Dictionary).get("seed"), 0)

	var runner = SimRunner.new()
	var hashes: Array = []
	var events_json: Array = []
	var first_events: Array = []
	var final_level := ""
	var all_ok := true

	for run_index in range(runs):
		var result: Dictionary = runner.run(project, seed_value)
		var run_ok := bool(result.get("ok", false))
		var final_hash := String(result.get("final_hash", ""))
		var events: Array = []
		var events_v: Variant = result.get("events", [])
		if typeof(events_v) == TYPE_ARRAY:
			events = events_v
		var snapshot := _dict_or_empty(result.get("snapshot", {}))

		hashes.append(final_hash)
		events_json.append(JSON.stringify(events, "", true))
		if run_index == 0:
			first_events = events
			var level := _dict_or_empty(snapshot.get("level", {}))
			final_level = String(level.get("id", ""))
		if not run_ok:
			all_ok = false

		if not json_output:
			_print_run(run_index + 1, final_hash, run_ok, events, snapshot)

	# 确定性判定：所有 run 的 final_hash 相同 + 事件日志 JSON 相同 + 每次 ok。
	var hashes_match := true
	for index in range(1, hashes.size()):
		if hashes[index] != hashes[0]:
			hashes_match = false
			break
	var events_match := true
	for index in range(1, events_json.size()):
		if events_json[index] != events_json[0]:
			events_match = false
			break
	var ok := all_ok and hashes_match and events_match

	if json_output:
		print(JSON.stringify({
			"ok": ok,
			"seed": int(seed_value),
			"runs": int(runs),
			"hashes": hashes,
			"final_level": final_level,
			"events": first_events,
		}, "\t"))
	elif ok:
		print("结果: PASS 确定性一致（%d runs, seed=%d）" % [runs, seed_value])
	else:
		var reason := "存在失败事件"
		if not hashes_match:
			reason = "final_hash 不一致"
		elif not events_match:
			reason = "事件日志不一致"
		print("结果: FAIL %s（%d runs, seed=%d）" % [reason, runs, seed_value])

	quit(0 if ok else 1)


func _print_run(run_index: int, final_hash: String, run_ok: bool, events: Array, snapshot: Dictionary) -> void:
	print("run %d: hash=%s ok=%s events=%d" % [run_index, final_hash, str(run_ok), events.size()])
	for event_v in events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		print("  [t=%s] %s %s ok=%s %s" % [
			String.num(float(event.get("at", 0.0)), 3),
			String(event.get("id", "")),
			String(event.get("type", "")),
			str(bool(event.get("ok", false))),
			String(event.get("message", "")),
		])

	var level := _dict_or_empty(snapshot.get("level", {}))
	var order_parts: Array = []
	var orders_v: Variant = snapshot.get("orders", [])
	if typeof(orders_v) == TYPE_ARRAY:
		for order_v in orders_v:
			if typeof(order_v) != TYPE_DICTIONARY:
				continue
			var order: Dictionary = order_v
			order_parts.append("%s:%s" % [String(order.get("id", "")), String(order.get("state", ""))])
	var hud := _dict_or_empty(snapshot.get("hud", {}))
	print("  final: level=%s level_complete=%s orders=%s hud.coin=%d hud.star=%d" % [
		String(level.get("id", "")),
		str(bool(snapshot.get("level_complete", false))),
		",".join(order_parts),
		_int_like_or(hud.get("coin"), 0),
		_int_like_or(hud.get("star"), 0),
	])


func _resolve_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


static func _dict_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return dict
	return {}


static func _int_like_or(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return fallback
