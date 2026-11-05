extends SceneTree
## Builds res://data/manifest_index.json from 00_design/resource_manifest.json.
## The snapshot keeps only ids + governance fields (no absolute paths), so the
## validator can run inside a relocated copy of this project.
##
##   godot --headless --path . --script res://src/tools/build_manifest_index.gd -- \
##       --manifest <workspace>/00_design/resource_manifest.json \
##       --out res://data/manifest_index.json
##
## Two layers are recorded and must stay distinct:
##   file_present  governance layer: the *source* file named by the manifest exists
##   in_project    presence layer:   a file with that basename lives under res://assets/

const DEFAULT_OUT := "res://data/manifest_index.json"

## Every usage level is emitted even when its count is zero, so a consumer can read
## `usage_counts[level]` without a fallback and see the drop to 0 explicitly.
const USAGE_LEVELS := ["REFERENCE_ONLY", "PLACEHOLDER", "PRODUCTION", "TODO"]

## Where a copied payload may live. Mirrors AssetGuard.LOCAL_ASSET_DIRS.
const PROJECT_ASSET_DIRS := ["res://assets/ui", "res://assets/fonts", "res://assets/chips"]

## The v7 manifest names chain levels 7-10 by raw file id (`icon_10002107` ...) while
## levels 1-6 keep the `chip_clean_*_lvNN` form. These aliases restore the uniform
## naming for callers without inventing records the source manifest does not have.
const ALIASES := {
	"chip_clean_ca_lv07": "icon_10002107",
	"chip_clean_ca_lv08": "icon_10002108",
	"chip_clean_ca_lv09": "icon_10002109",
	"chip_clean_ca_lv10": "icon_10002110",
	"chip_clean_cb_lv07": "icon_10002207",
	"chip_clean_cb_lv08": "icon_10002208",
	"chip_clean_cb_lv09": "icon_10002209",
	"chip_clean_cb_lv10": "icon_10002210",
}


class ArgReader:
	var _args: PackedStringArray

	func _init(args: PackedStringArray) -> void:
		_args = args

	func value(flag: String, fallback: String) -> String:
		var i := _args.find(flag)
		if i >= 0 and i + 1 < _args.size():
			return _args[i + 1]
		return fallback

	func has(flag: String) -> bool:
		return _args.has(flag)


func _initialize() -> void:
	var a := ArgReader.new(OS.get_cmdline_user_args())
	var manifest_path := a.value("--manifest", "")
	var out_path := a.value("--out", DEFAULT_OUT)
	if manifest_path.is_empty():
		printerr("[manifest-index] missing --manifest <path to resource_manifest.json>")
		quit(2)
		return
	if not FileAccess.file_exists(manifest_path):
		printerr("[manifest-index] manifest not found: ", manifest_path)
		quit(2)
		return

	var j := JSON.new()
	var parse_err := j.parse(FileAccess.get_file_as_string(manifest_path))
	if parse_err != OK:
		printerr("[manifest-index] JSON error line ", j.get_error_line(), ": ", j.get_error_message())
		quit(2)
		return
	if typeof(j.data) != TYPE_DICTIONARY:
		printerr("[manifest-index] manifest root is not an object")
		quit(2)
		return

	var manifest: Dictionary = j.data
	var resources: Array = manifest.get("resources", [])
	var out := {
		"schema": 1,
		"note": "read-only snapshot of 00_design/resource_manifest.json; regenerate with src/tools/build_manifest_index.gd",
		"manifest_version": int(manifest.get("version", 0)),
		"manifest_generated": String(manifest.get("generated", "")),
		"snapshot_date": Time.get_date_string_from_system(),
		"count": resources.size(),
		"usage_levels": manifest.get("usage_levels", {}),
		"aliases": ALIASES.duplicate(),
		"resources": {},
	}
	var by_usage := {}
	for level in USAGE_LEVELS:
		by_usage[level] = 0
	var missing := []
	var in_project_names := _project_basenames()
	var in_project_count := 0
	var resources_out: Dictionary = out["resources"]
	for raw in resources:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = raw
		var id := String(r.get("id", ""))
		if id.is_empty():
			continue
		var file := String(r.get("file", ""))
		var present := not file.is_empty() and FileAccess.file_exists(file)
		var usage := String(r.get("usage", ""))
		var file_name := file.get_file()
		var copied := not file_name.is_empty() and in_project_names.has(file_name)
		resources_out[id] = {
			"usage": usage,
			"status": String(r.get("status", "")),
			"priority": String(r.get("priority", "")),
			"category": String(r.get("category", "")),
			"use": String(r.get("use", "")),
			"license": String(r.get("license", "")),
			"file_name": file_name,
			"file_present": present,
			"target_size": String(r.get("target_size", "")),
			"actual_size": String(r.get("actual_size", "")),
			"fit": String(r.get("fit", "")),
			"animation": String(r.get("animation", "")),
			"in_project": copied,
		}
		by_usage[usage] = int(by_usage.get(usage, 0)) + 1
		if copied:
			in_project_count += 1
		if not present:
			missing.append(id)
	out["usage_counts"] = by_usage
	out["missing_files"] = missing
	out["count"] = resources_out.size()

	var dangling: Array = []
	for alias in ALIASES:
		if not resources_out.has(String(ALIASES[alias])):
			dangling.append(String(alias))

	var fw := FileAccess.open(out_path, FileAccess.WRITE)
	if fw == null:
		printerr("[manifest-index] cannot write ", out_path)
		quit(2)
		return
	fw.store_string(JSON.stringify(out, "  ", false) + "\n")
	fw.close()

	print("[manifest-index] wrote ", out_path)
	print("[manifest-index] count=", out["count"], " usage=", by_usage)
	print("[manifest-index] missing_files=", missing)
	print("[manifest-index] in_project=", in_project_count, " aliases=", ALIASES.size())
	if not dangling.is_empty():
		printerr("[manifest-index] aliases point at ids the manifest does not define: ", dangling)
	quit(0)


## Basenames of every file that really lives in the project's asset dirs. `in_project`
## is derived from this scan, never from the manifest's own path column.
func _project_basenames() -> Dictionary:
	var out := {}
	for dir_path in PROJECT_ASSET_DIRS:
		var dir := DirAccess.open(String(dir_path))
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir() and not name.begins_with("."):
				out[name] = true
			name = dir.get_next()
		dir.list_dir_end()
	return out
