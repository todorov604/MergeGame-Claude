extends RefCounted
## Relocatability and asset-boundary audit. Read-only by design.
##
## M1 rule: a payload file may live under res://assets only when a registration
## explains it — either the v7 snapshot (data/manifest_index.json) or the local
## register (data/assets_local.json) that carries the layout art the snapshot does
## not have yet. The allowlist is therefore *computed* from those two tables instead
## of being typed out here, so registering an asset is a data edit and never a test
## edit. The payload count stays an exact equality: a file that appears or disappears
## without a registration still fails this suite.
##
## The M0 name blocklist (`chip_*` / `obstacle_*` / `char_*` ...) is gone on purpose.
## It encoded "these basenames are reference-only originals", which stopped being true
## when the v7 manifest turned every 01_icon material into PRODUCTION: `obstacle_web.png`
## is now a legitimately registered PRODUCTION file name. The rule that replaced it is
## stricter: every shipped basename must be registered, and no shipped basename may
## belong to a REFERENCE_ONLY or TODO record.

const ROOT := "res://"
const PROJECT_CONFIG := "res://project.godot"
const ASSETS_DIR := "res://assets"
const PROVENANCE_PATH := "res://assets/PROVENANCE.md"
const MANIFEST_INDEX := "res://data/manifest_index.json"
const LOCAL_REGISTRY := "res://data/assets_local.json"

const PAYLOAD_USAGES := ["PRODUCTION", "PLACEHOLDER"]

## 28 M0/M1 payload files (20 chips + 2 fonts + 5 placeholders)
## + 21 layout copies (9 files no table carried before + 12 snapshot files that were
##   registered but never copied)
## + 1 CC0 cursor (ui_cursor_hand, 2026-11-05 free mode)
const EXPECTED_PAYLOAD_COUNT := 111

const SNAPSHOT_RESOURCE_COUNT := 180

const TEXT_EXTENSIONS := {
	"gd": true,
	"tscn": true,
	"tres": true,
	"json": true,
	"md": true,
	"cfg": true,
	"godot": true,
	"txt": true,
	"py": true,
	"sh": true,
}

const ABS_DRIVE_PATTERN := "(?<![A-Za-z0-9_])[A-Za-z]:[\\\\/]"
const FILE_SCHEME := "file" + "://"
const MSYS_WORKSPACE := "/e/" + "MergeGame"


const WORKSPACE_TOKEN := "MergeGame-Claude" + "\\0"


func run(t) -> void:
	_test_path_hygiene(t)
	_test_project_config(t)
	_test_asset_allowlist(t)
	_test_resource_redline(t)


func _test_path_hygiene(t) -> void:
	var all_files: Array = []
	_collect_all_files(ROOT, all_files)
	all_files.sort()

	var scanned: Array = []
	var unreadable: Array = []
	for path in all_files:
		if not _is_text_file(String(path)):
			continue
		scanned.append(path)
		var f := FileAccess.open(String(path), FileAccess.READ)
		if f == null:
			unreadable.append(path)

	t.ok(scanned.size() > 0, "text scan found project files", str(scanned.size()))
	t.ok(unreadable.size() == 0, "all scanned text files are readable", _detail_paths(unreadable))

	var drive_re := RegEx.new()
	var compile_err := drive_re.compile(ABS_DRIVE_PATTERN)
	t.ok(compile_err == OK, "absolute-drive regex compiles", str(compile_err))

	var drive_hits: Array = []
	var scheme_hits: Array = []
	var msys_hits: Array = []
	var workspace_hits: Array = []
	for path in scanned:
		var text := FileAccess.get_file_as_string(String(path))
		if compile_err == OK and drive_re.search(text) != null:
			drive_hits.append(path)
		if text.find(FILE_SCHEME) >= 0:
			scheme_hits.append(path)
		if text.find(MSYS_WORKSPACE) >= 0:
			msys_hits.append(path)
		if text.find(WORKSPACE_TOKEN) >= 0:
			workspace_hits.append(path)

	t.ok(drive_hits.size() == 0, "no Windows drive absolute paths in text files", _detail_paths(drive_hits))
	t.ok(scheme_hits.size() == 0, "no file URI paths in text files", _detail_paths(scheme_hits))
	t.ok(msys_hits.size() == 0, "no MSYS workspace absolute paths in text files", _detail_paths(msys_hits))
	t.ok(workspace_hits.size() == 0, "no workspace-root literals in text files", _detail_paths(workspace_hits))


## Assert the *effective* settings, not the file text: the engine rewrites
## project.godot on exit and drops keys whose value equals the default
## (`window/stretch/aspect="keep"`), which used to turn a clean tree red on the
## next run. Values are the contract here; the F5 preview size lives in
## game_screen.gd and never touches project.godot.
func _test_project_config(t) -> void:
	var config := FileAccess.get_file_as_string(PROJECT_CONFIG)
	t.ok(not config.is_empty(), "project.godot is readable")
	t.eq(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)), 1080,
			"viewport width is 1080")
	t.eq(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), 1920,
			"viewport height is 1920")
	# 2026-11-09：改成 viewport —— 窗口 540x960 玩，但根视口固定 1080x1920，
	# 这样 Movie Maker 录出来的是真 1080 像素，而不是把 540 的画面放大。
	t.eq(String(ProjectSettings.get_setting("display/window/stretch/mode", "")), "viewport",
			"stretch mode is viewport (crisp 1080x1920 film)")
	t.eq(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")), "keep",
			"stretch aspect is keep")


## The allowlist is the union of the two registration tables. Everything that ships
## must be inside it, and the shipped count is asserted exactly, so nothing can be
## added or dropped silently.
func _test_asset_allowlist(t) -> void:
	var reg := _registrations()
	var by_basename: Dictionary = reg["by_basename"]
	var local_basenames: Array = reg["local_basenames"]

	t.ok(int(reg["snapshot_count"]) == SNAPSHOT_RESOURCE_COUNT,
			"the snapshot still carries 180 records", str(reg["snapshot_count"]))
	t.ok(local_basenames.size() > 0, "the local register contributes layout files",
			str(local_basenames.size()))

	var all_files: Array = []
	_collect_all_files(ASSETS_DIR, all_files)
	all_files.sort()

	var payload_files: Array = []
	var unexpected: Array = []
	for path in all_files:
		if String(path) == PROVENANCE_PATH:
			continue
		payload_files.append(path)
		if not by_basename.has(String(path).get_file().to_lower()):
			unexpected.append(path)

	var missing_local: Array = []
	for base in local_basenames:
		var found := false
		for path in payload_files:
			if String(path).get_file().to_lower() == String(base):
				found = true
		if not found:
			missing_local.append(String(base))

	t.ok(all_files.has(PROVENANCE_PATH), "PROVENANCE.md governance document is present")
	t.eq(payload_files.size(), EXPECTED_PAYLOAD_COUNT,
			"assets contains exactly one-hundred-eleven payload files")
	t.ok(unexpected.size() == 0,
			"every payload file under res://assets is registered in the snapshot or in data/assets_local.json",
			_detail_paths(unexpected))
	t.ok(missing_local.size() == 0,
			"every file the local register declares was really copied under res://assets",
			_detail_paths(missing_local))


## The M1 red line is a registration rule: every file that lives under res://assets
## must be explained by a PRODUCTION or PLACEHOLDER record of one of the two tables,
## and no shipped basename may belong to a REFERENCE_ONLY or TODO record.
func _test_resource_redline(t) -> void:
	var reg := _registrations()
	t.eq(reg["ref_only_ids"], [], "snapshot has zero REFERENCE_ONLY records")
	t.ok((reg["local_bad_usage"] as Array).is_empty(),
			"the local register is a PRODUCTION-only table",
			_detail_paths(reg["local_bad_usage"]))

	var by_basename: Dictionary = reg["by_basename"]

	var all_files: Array = []
	_collect_all_files(ASSETS_DIR, all_files)
	all_files.sort()

	var unregistered: Array = []
	var wrong_usage: Array = []
	var todo_hits: Array = []
	for path in all_files:
		if String(path) == PROVENANCE_PATH:
			continue
		var base := String(path).get_file().to_lower()
		if not by_basename.has(base):
			unregistered.append(path)
			continue
		var usable := false
		for record in by_basename[base]:
			var usage := String(record["usage"])
			if PAYLOAD_USAGES.has(usage):
				usable = true
			if usage == "TODO":
				todo_hits.append(path + "=" + String(record["id"]))
		if not usable:
			wrong_usage.append(path)

	t.ok(unregistered.size() == 0,
			"every payload file under res://assets is registered by basename",
			_detail_paths(unregistered))
	t.ok(wrong_usage.size() == 0,
			"every payload file is registered as a PRODUCTION or PLACEHOLDER record",
			_detail_paths(wrong_usage))
	t.ok(todo_hits.size() == 0, "no payload basename belongs to a TODO record", _detail_paths(todo_hits))


## One pass over both registration tables. `origin` records where a basename came
## from so a failure message can say which table has to grow.
func _registrations() -> Dictionary:
	var by_basename := {}
	var ref_only_ids: Array = []
	var local_basenames: Array = []
	var local_bad_usage: Array = []

	var snapshot := _load_json(MANIFEST_INDEX)
	var snapshot_count := 0
	var resources = snapshot.get("resources", null)
	if typeof(resources) == TYPE_DICTIONARY:
		snapshot_count = (resources as Dictionary).size()
		for id in (resources as Dictionary).keys():
			var record = (resources as Dictionary)[id]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var usage := String((record as Dictionary).get("usage", ""))
			if usage == "REFERENCE_ONLY":
				ref_only_ids.append(String(id))
			var file_name := String((record as Dictionary).get("file_name", "")).to_lower()
			if file_name.is_empty():
				continue
			if not by_basename.has(file_name):
				by_basename[file_name] = []
			(by_basename[file_name] as Array).append({
				"id": String(id),
				"usage": usage,
				"origin": "snapshot",
			})

	var local := _load_json(LOCAL_REGISTRY)
	var local_resources = local.get("resources", null)
	if typeof(local_resources) == TYPE_DICTIONARY:
		for id in (local_resources as Dictionary).keys():
			var record = (local_resources as Dictionary)[id]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var usage := String((record as Dictionary).get("usage", ""))
			if usage != "PRODUCTION":
				local_bad_usage.append(String(id) + "=" + usage)
			var file_name := String((record as Dictionary).get("file_name", "")).to_lower()
			if file_name.is_empty():
				continue
			if not local_basenames.has(file_name):
				local_basenames.append(file_name)
			if not by_basename.has(file_name):
				by_basename[file_name] = []
			(by_basename[file_name] as Array).append({
				"id": String(id),
				"usage": usage,
				"origin": "local",
			})
	local_basenames.sort()

	return {
		"by_basename": by_basename,
		"ref_only_ids": ref_only_ids,
		"local_basenames": local_basenames,
		"local_bad_usage": local_bad_usage,
		"snapshot_count": snapshot_count,
	}


func _is_text_file(path: String) -> bool:
	if path.ends_with(".log"):
		return false
	var ext := path.get_extension().to_lower()
	return TEXT_EXTENSIONS.has(ext)


## Engine sidecars (`.import` next to every imported texture, `.uid` next to every
## script) are generated on any real-window run — including the F5 test loop — and
## are never payload. Skipping them here keeps "assets holds exactly 48 payload
## files" true both before and after a run; `.gitignore` hides them from git.
func _collect_all_files(dir_path: String, files: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := dir_path.path_join(entry)
			if dir.current_is_dir():
				if entry != ".godot" and entry != "output":
					_collect_all_files(child, files)
			elif not _is_engine_sidecar(entry):
				files.append(child)
		entry = dir.get_next()
	dir.list_dir_end()


func _is_engine_sidecar(file_name: String) -> bool:
	return file_name.ends_with(".import") or file_name.ends_with(".uid")


func _load_json(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


func _detail_paths(paths: Array) -> String:
	if paths.is_empty():
		return "<none>"
	var limit := mini(paths.size(), 12)
	var out: Array = []
	for i in limit:
		out.append(String(paths[i]))
	var detail := ", ".join(out)
	if paths.size() > limit:
		detail += ", ..."
	return detail
