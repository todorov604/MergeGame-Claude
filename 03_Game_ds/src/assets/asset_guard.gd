extends RefCounted
## M0 asset guard — the only place that decides whether a manifest id may be used.
##
##   REFERENCE_ONLY  -> always blocked (never packaged, never rendered, never shipped)
##   PLACEHOLDER     -> blocked unless allow_placeholders == true (call must be logged)
##   PRODUCTION      -> allowed
##   TODO            -> always blocked (audio etc.)
##   unknown id      -> blocked
##
## The guard reads a *snapshot* (data/manifest_index.json) that carries ids, usage,
## license and a file name only — no absolute paths — so a relocated project still
## enforces the same rules.

const USAGE_REFERENCE_ONLY := "REFERENCE_ONLY"
const USAGE_PLACEHOLDER := "PLACEHOLDER"
const USAGE_PRODUCTION := "PRODUCTION"
const USAGE_TODO := "TODO"

const LOCAL_ASSET_DIRS := ["res://assets/ui/", "res://assets/fonts/"]

var index: Dictionary = {}
var allow_placeholders: bool = false
var load_error: String = ""
var log_entries: Array = []


func load_from(path: String, allow_placeholders_flag: bool = false) -> bool:
	allow_placeholders = allow_placeholders_flag
	index = {}
	load_error = ""
	if not FileAccess.file_exists(path):
		load_error = "manifest index not found: " + path
		return false
	var j := JSON.new()
	var e := j.parse(FileAccess.get_file_as_string(path))
	if e != OK:
		load_error = "manifest index JSON error at line %d: %s" % [j.get_error_line(), j.get_error_message()]
		return false
	if typeof(j.data) != TYPE_DICTIONARY:
		load_error = "manifest index root is not an object"
		return false
	var root: Dictionary = j.data
	var res = root.get("resources", null)
	if typeof(res) != TYPE_DICTIONARY:
		load_error = "manifest index has no resources table"
		return false
	index = res
	return true


func has(id: String) -> bool:
	return index.has(id)


func entry(id: String) -> Dictionary:
	var e = index.get(id, {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	return e


func usage(id: String) -> String:
	return String(entry(id).get("usage", ""))


func license_of(id: String) -> String:
	return String(entry(id).get("license", ""))


## Returns "" when the id may be used, otherwise a stable error code.
func check_ref(id: String) -> String:
	if id.is_empty():
		return "ASSET_UNKNOWN"
	if not index.has(id):
		return "ASSET_UNKNOWN"
	var e := entry(id)
	var u := String(e.get("usage", ""))
	match u:
		USAGE_REFERENCE_ONLY:
			return "ASSET_REFERENCE_ONLY"
		USAGE_PLACEHOLDER:
			if not allow_placeholders:
				return "ASSET_PLACEHOLDER_BLOCKED"
		USAGE_TODO:
			return "ASSET_TODO"
		USAGE_PRODUCTION:
			pass
		_:
			return "ASSET_UNKNOWN_USAGE"
	if not bool(e.get("file_present", false)):
		return "ASSET_FILE_MISSING"
	return ""


func ref_message(code: String, id: String) -> String:
	match code:
		"ASSET_REFERENCE_ONLY":
			return "REFERENCE_ONLY resource \"%s\" must never be packaged or rendered (reference only)" % id
		"ASSET_PLACEHOLDER_BLOCKED":
			return "PLACEHOLDER resource \"%s\" requires allow_placeholders=true" % id
		"ASSET_TODO":
			return "TODO resource \"%s\" is not filled in yet and blocks rendering" % id
		"ASSET_FILE_MISSING":
			return "resource \"%s\" is declared but its file is missing" % id
		"ASSET_UNKNOWN_USAGE":
			return "resource \"%s\" has an unknown usage level" % id
		_:
			return "resource id \"%s\" is not in the manifest" % id


func note(id: String, context: String) -> void:
	var e := entry(id)
	log_entries.append({
		"id": id,
		"usage": String(e.get("usage", "")),
		"license": String(e.get("license", "")),
		"context": context,
		"allowed": check_ref(id) == "",
	})


## Resolves a manifest id to a file that actually lives inside this project.
## REFERENCE_ONLY ids resolve to "" by construction, because those files are never
## copied into res:// — the guard cannot leak them even if a caller asks.
func local_path(id: String) -> String:
	if check_ref(id) != "":
		return ""
	var fname := String(entry(id).get("file_name", ""))
	if fname.is_empty():
		return ""
	for dir in LOCAL_ASSET_DIRS:
		var p: String = String(dir) + fname
		if FileAccess.file_exists(p):
			return p
	return ""


func allowed_ids() -> Array:
	var out: Array = []
	for id in index.keys():
		if check_ref(String(id)) == "":
			out.append(id)
	out.sort()
	return out
