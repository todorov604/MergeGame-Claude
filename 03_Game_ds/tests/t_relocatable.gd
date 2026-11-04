extends RefCounted
## Relocatability and asset-boundary audit. Read-only by design.

const ROOT := "res://"
const PROJECT_CONFIG := "res://project.godot"
const ASSETS_DIR := "res://assets"
const PROVENANCE_PATH := "res://assets/PROVENANCE.md"
const MANIFEST_INDEX := "res://data/manifest_index.json"

const EXPECTED_ASSETS := [
	"res://assets/fonts/font_zh.otf",
	"res://assets/fonts/font_en.ttf",
	"res://assets/ui/board_frame.png",
	"res://assets/ui/ui_icon_star.png",
	"res://assets/ui/box_safe_x.png",
	"res://assets/ui/box_energe_w.png",
	"res://assets/ui/box_treasure_y.png",
]

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


func _test_project_config(t) -> void:
	var config := FileAccess.get_file_as_string(PROJECT_CONFIG)
	t.ok(not config.is_empty(), "project.godot is readable")
	t.ok(config.contains("window/size/viewport_width=1080"), "viewport width is 1080")
	t.ok(config.contains("window/size/viewport_height=1920"), "viewport height is 1920")
	t.ok(config.contains("window/stretch/mode=\"canvas_items\""), "stretch mode is canvas_items")
	t.ok(config.contains("window/stretch/aspect=\"keep\""), "stretch aspect is keep")


func _test_asset_allowlist(t) -> void:
	var all_files: Array = []
	_collect_all_files(ASSETS_DIR, all_files)
	all_files.sort()

	var payload_files: Array = []
	var unexpected: Array = []
	for path in all_files:
		if String(path) == PROVENANCE_PATH:
			continue
		payload_files.append(path)
		if not EXPECTED_ASSETS.has(String(path)):
			unexpected.append(path)

	var missing: Array = []
	for expected in EXPECTED_ASSETS:
		if not all_files.has(expected):
			missing.append(expected)

	t.ok(all_files.has(PROVENANCE_PATH), "PROVENANCE.md governance document is present")
	t.ok(payload_files.size() == 7, "assets contains exactly seven payload files", _detail_paths(payload_files))
	t.ok(unexpected.size() == 0, "assets has no extra payload files", _detail_paths(unexpected))
	t.ok(missing.size() == 0, "all seven allowed payload files are present", _detail_paths(missing))

	var forbidden := RegEx.create_from_string("^(chip_|obstacle_|char_|board_bg|slot_|ui_topbar)")
	t.ok(forbidden != null, "forbidden asset-name regex compiles")
	var forbidden_hits: Array = []
	for path in all_files:
		if forbidden != null and forbidden.search(String(path).get_file().to_lower()) != null:
			forbidden_hits.append(path)
	t.ok(forbidden_hits.size() == 0, "no reference-only filename families under assets", _detail_paths(forbidden_hits))


func _test_resource_redline(t) -> void:
	var manifest := _load_json(MANIFEST_INDEX)
	t.ok(not manifest.is_empty(), "manifest snapshot loads for redline cross-check")
	if manifest.is_empty():
		return

	var resources = manifest.get("resources", null)
	if typeof(resources) != TYPE_DICTIONARY:
		t.ok(false, "manifest resources is a dictionary", str(typeof(resources)))
		return

	var ref_names := {}
	for id in resources:
		var record = resources[id]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if String(record.get("usage", "")) == "REFERENCE_ONLY":
			var file_name := String(record.get("file_name", "")).to_lower()
			if not file_name.is_empty():
				ref_names[file_name] = true

	var all_files: Array = []
	_collect_all_files(ASSETS_DIR, all_files)
	all_files.sort()
	var leaked: Array = []
	for path in all_files:
		var base := String(path).get_file().to_lower()
		if ref_names.has(base):
			leaked.append(path)

	t.ok(leaked.size() == 0, "zero REFERENCE_ONLY files under res://assets", _detail_paths(leaked))


func _is_text_file(path: String) -> bool:
	if path.ends_with(".log"):
		return false
	var ext := path.get_extension().to_lower()
	return TEXT_EXTENSIONS.has(ext)


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
			else:
				files.append(child)
		entry = dir.get_next()
	dir.list_dir_end()


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



