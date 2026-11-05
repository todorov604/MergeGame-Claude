extends RefCounted
## Asset guard — the only place that decides whether a manifest id may be used.
##
##   REFERENCE_ONLY  -> always blocked (never packaged, never rendered, never shipped)
##   PLACEHOLDER     -> blocked unless allow_placeholders == true (call must be logged)
##   PRODUCTION      -> allowed
##   TODO            -> always blocked (audio etc.)
##   unknown id      -> blocked
##
## Two layers stay distinct on purpose:
##   governance layer  usage + file_present  (check_ref): the *source* file named by the
##                     manifest-generated index exists — "may this id be used at all?"
##   presence layer    local_path(): a copy with that basename really lives under
##                     res://assets/ — "can this project load it right now?"
## A PRODUCTION id that was never copied passes the first and returns "" from the second.
##
## Aliases: the v7 manifest names chain levels 7-10 by raw file id (`icon_10002107`), so
## the snapshot carries an `aliases` table that maps the uniform `chip_clean_*_lvNN` name
## onto those records. Every public method is alias-aware.
##
## The guard reads a *snapshot* (data/manifest_index.json) that carries ids, usage,
## license and a file name only — no absolute paths — so a relocated project still
## enforces the same rules.
##
## Local register (M1 visual fidelity): data/assets_local.json adds the layout art the
## snapshot does not carry yet (`ui_bg_top`, `char_part1`, `ui_board_frame`, ...). It is
## merged into `index` under two rules:
##   * the snapshot always wins — a local record may never override, upgrade or
##     downgrade an id the v7 manifest already declares, nor take an alias name; such a
##     collision is refused and recorded in `local_override_rejected` instead;
##   * a local record is presence-checked at load: `in_project` and `file_present` come
##     from the copy under LOCAL_ASSET_DIRS, because there is no source manifest entry to
##     declare them.
## Everything else (`check_ref`, `local_path`, `allowed_ids`, aliases, `note`) is
## unchanged and treats a local id exactly like a snapshot one.

const USAGE_REFERENCE_ONLY := "REFERENCE_ONLY"
const USAGE_PLACEHOLDER := "PLACEHOLDER"
const USAGE_PRODUCTION := "PRODUCTION"
const USAGE_TODO := "TODO"

## Mirrors tools/build_manifest_index.gd PROJECT_ASSET_DIRS, in resolution order.
const LOCAL_ASSET_DIRS := ["res://assets/ui/", "res://assets/fonts/", "res://assets/chips/"]

const LOCAL_REGISTRY := "res://data/assets_local.json"

var index: Dictionary = {}
var aliases: Dictionary = {}
var allow_placeholders: bool = false
var load_error: String = ""
var log_entries: Array = []

## Local register path. A test may point it at a probe file before load_from(); the
## shipped project always reads LOCAL_REGISTRY.
var local_registry_path: String = LOCAL_REGISTRY
## Non-fatal: a project without a local register is perfectly valid.
var local_load_error: String = ""
## Local ids that survived the merge (Dictionary as a set; local_ids() returns it sorted).
var _local_ids: Dictionary = {}
## Local records refused because the snapshot already owns the id:
## [{ "id": String, "reason": "snapshot" | "alias" }, ...], sorted by id.
var local_override_rejected: Array = []


func load_from(path: String, allow_placeholders_flag: bool = false) -> bool:
	allow_placeholders = allow_placeholders_flag
	index = {}
	aliases = {}
	load_error = ""
	_local_ids = {}
	local_override_rejected = []
	local_load_error = ""
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
	var alias_table = root.get("aliases", null)
	if typeof(alias_table) == TYPE_DICTIONARY:
		aliases = alias_table
	_merge_local()
	return true


## Merges the local register into `index` (see the header rules). A malformed register
## is reported through `local_load_error` and otherwise ignored: the snapshot is still
## authoritative, so a broken side table must not brick the guard.
func _merge_local() -> void:
	if not FileAccess.file_exists(local_registry_path):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(local_registry_path)) != OK:
		local_load_error = "local asset register JSON error at line %d: %s" % [
			j.get_error_line(), j.get_error_message()]
		return
	if typeof(j.data) != TYPE_DICTIONARY:
		local_load_error = "local asset register root is not an object"
		return
	var resources = (j.data as Dictionary).get("resources", null)
	if typeof(resources) != TYPE_DICTIONARY:
		local_load_error = "local asset register has no resources table"
		return
	for id in (resources as Dictionary).keys():
		var key := String(id)
		var record = (resources as Dictionary)[id]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		# the snapshot owns every id it declares, and every alias name too
		if index.has(key):
			local_override_rejected.append({"id": key, "reason": "snapshot"})
			continue
		if aliases.has(key):
			local_override_rejected.append({"id": key, "reason": "alias"})
			continue
		var merged: Dictionary = (record as Dictionary).duplicate(true)
		var present := _file_present(String(merged.get("file_name", "")))
		merged["in_project"] = present
		merged["file_present"] = present
		index[key] = merged
		_local_ids[key] = true
	if not local_override_rejected.is_empty():
		local_override_rejected.sort_custom(_rejected_before)


func _rejected_before(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("id", "")) < String(b.get("id", ""))


func _file_present(fname: String) -> bool:
	if fname.is_empty():
		return false
	for dir in LOCAL_ASSET_DIRS:
		if FileAccess.file_exists(String(dir) + fname):
			return true
	return false


## Canonical ids accepted from the local register, sorted. Snapshot ids and aliases
## never appear here (aliases are names, and an overridden local record was refused).
func local_ids() -> Array:
	var out: Array = _local_ids.keys()
	out.sort()
	return out


## Maps a caller-facing id (an alias such as `chip_clean_ca_lv07`) onto the record id the
## snapshot actually carries. Returns "" when neither the id nor its alias exists.
func resolve_id(id: String) -> String:
	if id.is_empty():
		return ""
	if index.has(id):
		return id
	var target := String(aliases.get(id, ""))
	if not target.is_empty() and index.has(target):
		return target
	return ""


## Round-trips the caller-facing name: an alias returns itself, a canonical id returns the
## alias that names it, and an id without an alias returns "".
func alias_of(id: String) -> String:
	if aliases.has(id):
		return id
	for alias in aliases:
		if String(aliases[alias]) == id:
			return String(alias)
	return ""


func has(id: String) -> bool:
	return not resolve_id(id).is_empty()


## Alias-aware: an alias returns the canonical record unchanged (same file_name, same
## usage, same license), never a copy rewritten to look like the alias.
func entry(id: String) -> Dictionary:
	var canonical := resolve_id(id)
	if canonical.is_empty():
		return {}
	var e = index.get(canonical, {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	return e


func usage(id: String) -> String:
	return String(entry(id).get("usage", ""))


func license_of(id: String) -> String:
	return String(entry(id).get("license", ""))


## Returns "" when the id may be used, otherwise a stable error code.
func check_ref(id: String) -> String:
	if resolve_id(id).is_empty():
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


## Logs the canonical id (never the alias) so a render manifest names the file that was
## actually governed.
func note(id: String, context: String) -> void:
	var canonical := resolve_id(id)
	var e := entry(id)
	log_entries.append({
		"id": canonical if not canonical.is_empty() else id,
		"usage": String(e.get("usage", "")),
		"license": String(e.get("license", "")),
		"context": context,
		"allowed": check_ref(id) == "",
	})


## Resolves a manifest id to a file that actually lives inside this project.
## REFERENCE_ONLY ids resolve to "" by construction, and so do PRODUCTION ids whose copy
## was never made: the presence layer only ever answers with a res://assets/ path.
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


## Canonical ids only: aliases are names, not records, so they never appear here.
func allowed_ids() -> Array:
	var out: Array = []
	for id in index.keys():
		if check_ref(String(id)) == "":
			out.append(id)
	out.sort()
	return out
