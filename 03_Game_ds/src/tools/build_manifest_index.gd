extends SceneTree
## Builds res://data/manifest_index.json from 00_design/resource_manifest.json.
## The snapshot keeps only ids + governance fields (no absolute paths), so the
## validator can run inside a relocated copy of this project.
##
##   godot --headless --path . --script res://src/tools/build_manifest_index.gd -- \
##       --manifest <workspace>/00_design/resource_manifest.json \
##       --out res://data/manifest_index.json

const DEFAULT_OUT := "res://data/manifest_index.json"


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
		"resources": {},
	}
	var by_usage := {}
	var missing := []
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
		resources_out[id] = {
			"usage": usage,
			"status": String(r.get("status", "")),
			"priority": String(r.get("priority", "")),
			"category": String(r.get("category", "")),
			"use": String(r.get("use", "")),
			"license": String(r.get("license", "")),
			"file_name": file.get_file(),
			"file_present": present,
			"target_size": String(r.get("target_size", "")),
			"actual_size": String(r.get("actual_size", "")),
			"fit": String(r.get("fit", "")),
			"animation": String(r.get("animation", "")),
		}
		by_usage[usage] = int(by_usage.get(usage, 0)) + 1
		if not present:
			missing.append(id)
	out["usage_counts"] = by_usage
	out["missing_files"] = missing
	out["count"] = resources_out.size()

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
	quit(0)
