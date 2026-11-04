extends SceneTree
## Command line entry point for 03_Game_ds.
##
##   godot --headless --path . --script res://src/tools/cli.gd -- validate \
##       --project res://data/sample_project.json \
##       --allow-placeholders --strict --dump-order
##
## Exit codes: 0 = ok, 1 = validation errors, 2 = usage / IO problem.
## stdout stays ASCII (Windows consoles are cp936 and mangle CJK).

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")
const EventModel = preload("res://src/core/event_model.gd")

const BOOL_FLAGS := ["--allow-placeholders", "--strict", "--quiet", "--dump-order"]
const DEFAULT_PROJECT := "res://data/sample_project.json"
const DEFAULT_MANIFEST := "res://data/manifest_index.json"
const DEFAULT_OUT := "res://output/validation_report.json"

var _finished := false


func _process(_delta: float) -> bool:
	# safety net: never leave a headless run hanging if _initialize aborted
	if not _finished:
		printerr("[cli] aborted before completion")
		_finish(2)
	return true


func _finish(code: int) -> void:
	_finished = true
	quit(code)


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var cmd := "validate"
	var start := 0
	if argv.size() > 0 and not String(argv[0]).begins_with("--"):
		cmd = String(argv[0])
		start = 1
	var flags := {}
	var opts := {}
	var i := start
	while i < argv.size():
		var a := String(argv[i])
		if a.begins_with("--"):
			if BOOL_FLAGS.has(a):
				flags[a] = true
			elif i + 1 < argv.size():
				opts[a] = String(argv[i + 1])
				i += 1
			else:
				printerr("[cli] flag without value: ", a)
				_finish(2)
				return
		i += 1

	match cmd:
		"validate":
			_finish(_cmd_validate(flags, opts))
		"help", "--help":
			print("usage: -- validate --project <path> [--manifest <path>] [--allow-placeholders] [--strict] [--out <path>] [--dump-order]")
			_finish(0)
		_:
			printerr("[cli] unknown command: ", cmd)
			_finish(2)


func _cmd_validate(flags: Dictionary, opts: Dictionary) -> int:
	var project_path := String(opts.get("--project", DEFAULT_PROJECT))
	var manifest_path := String(opts.get("--manifest", DEFAULT_MANIFEST))
	var out_path := String(opts.get("--out", DEFAULT_OUT))
	var allow_placeholders := flags.has("--allow-placeholders")
	var strict := flags.has("--strict")
	var quiet := flags.has("--quiet")

	var guard = AssetGuard.new()
	if not guard.load_from(manifest_path, allow_placeholders):
		printerr("[validate] " + String(guard.load_error))
		return 2

	var report = ProjectValidator.validate_file(project_path, guard, strict)
	if not quiet:
		for line in report.lines():
			print(line)
		print("[guard] allow_placeholders=%s refs_logged=%d index_ids=%d" % [str(allow_placeholders), guard.log_entries.size(), guard.index.size()])
		for entry in guard.log_entries:
			print("[guard] used id=%s usage=%s allowed=%s" % [String(entry["id"]), String(entry["usage"]), str(entry["allowed"])])

	if flags.has("--dump-order"):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(project_path)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			var r: Dictionary = EventModel.resolve((j.data as Dictionary).get("timeline", []))
			print("[order] resolved=%d end=%.3fs" % [(r["events"] as Array).size(), float(r["end_time"])])
			for ev in r["events"]:
				print("[order] %7.3f  %-5s %-16s %s" % [float(ev["at"]), String(ev["channel"]), String(ev["type"]), String(ev["id"])])

	if not out_path.is_empty():
		var dir := out_path.get_base_dir()
		if not dir.is_empty():
			DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			printerr("[validate] cannot write report to ", out_path)
			return 2
		f.store_string(report.to_json())
		f.close()
		if not quiet:
			print("[validate] report written to ", out_path)

	return 0 if report.ok else 1
