extends SceneTree
## Headless test runner with auto-discovery, so parallel work never has to edit a
## shared list.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --suite res://tests/t_guard.gd
##
## Every res://tests/t_*.gd is loaded; a suite is an object with `run(t)`.
## Exit code 0 = pass, 1 = failures or a suite failed to compile, 2 = no suites.
## `_process` is a safety net: if `_initialize` aborts on a script error, the loop
## still terminates instead of hanging headless forever.

const TestCtx = preload("res://tests/t.gd")

var _finished := false


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var total_checks := 0
	var total_failures := 0
	var load_errors := 0

	var suites := _discover()
	print("[tests] engine=", Engine.get_version_info().get("string", "?"), " suites=", suites.size())
	if suites.is_empty():
		print("[tests] RESULT FAIL no suites found")
		_finish(2)
		return

	for path in suites:
		var script = load(path)
		if script == null or not (script is GDScript):
			print("[suite] " + String(path).get_file() + " LOAD_FAILED (null)")
			load_errors += 1
			continue
		var compile = script.reload()
		if compile != OK:
			print("[suite] " + String(path).get_file() + " COMPILE_FAILED code=" + str(compile))
			load_errors += 1
			continue
		var suite = script.new()
		if suite == null:
			print("[suite] " + String(path).get_file() + " INSTANTIATE_FAILED")
			load_errors += 1
			continue
		var t = TestCtx.new(String(path).get_file())
		suite.run(t)
		total_checks += t.checks
		total_failures += t.failures.size()
		if t.checks == 0:
			# a suite that asserts nothing is a silent no-op, not a pass
			print("[suite] " + String(path).get_file() + " EMPTY_FAILED checks=0")
			load_errors += 1
			continue
		print("[suite] " + String(path).get_file() + " checks=" + str(t.checks) + " failures=" + str(t.failures.size()))
		for f in t.failures:
			print("   FAIL " + String(f))

	var elapsed := Time.get_ticks_msec() - started
	print("[tests] TOTAL checks=" + str(total_checks) + " failures=" + str(total_failures) + " elapsed=" + str(elapsed) + "ms")
	if total_failures == 0 and load_errors == 0:
		print("[tests] RESULT PASS")
		_finish(0)
	else:
		print("[tests] RESULT FAIL load_errors=" + str(load_errors))
		_finish(1)


func _process(_delta: float) -> bool:
	if not _finished:
		print("[tests] RESULT FAIL runner aborted before completion")
		_finish(1)
	return true


func _discover() -> Array:
	var only := ""
	var args := OS.get_cmdline_user_args()
	var i := args.find("--suite")
	if i >= 0 and i + 1 < args.size():
		only = String(args[i + 1])
	if not only.is_empty():
		return [only]
	var files: Array = []
	var d := DirAccess.open("res://tests")
	if d == null:
		return files
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.begins_with("t_") and name.ends_with(".gd"):
			files.append("res://tests/" + name)
		name = d.get_next()
	d.list_dir_end()
	files.sort()
	return files


func _finish(code: int) -> void:
	_finished = true
	quit(code)
