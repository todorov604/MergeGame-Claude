extends RefCounted
## Shared validator context + tiny type helpers.
##
## No `class_name` on purpose: every entry point runs through `--headless --script`,
## where the editor's global class cache may not exist yet. Cross-file references
## use preload() instead.

var project: Dictionary = {}
var project_path: String = ""
var guard = null  # AssetGuard instance (or null when the snapshot is missing)
var strict: bool = false
var errors: Array = []
var warnings: Array = []
var stats: Dictionary = {}


static func is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func is_int_val(v) -> bool:
	if not is_num(v):
		return false
	return absf(float(v) - roundf(float(v))) < 0.000001


static func as_int(v, fallback: int = -2147483647) -> int:
	if is_int_val(v):
		return int(roundf(float(v)))
	return fallback


static func is_str_val(v) -> bool:
	return typeof(v) == TYPE_STRING and not String(v).is_empty()


static func is_dict(v) -> bool:
	return typeof(v) == TYPE_DICTIONARY


static func is_arr(v) -> bool:
	return typeof(v) == TYPE_ARRAY


func err(code: String, path: String, msg: String, detail: Dictionary = {}) -> void:
	var e := {"level": "error", "code": code, "path": path, "msg": msg}
	if not detail.is_empty():
		e["detail"] = detail
	errors.append(e)


func warn(code: String, path: String, msg: String, detail: Dictionary = {}) -> void:
	var w := {"level": "warning", "code": code, "path": path, "msg": msg}
	if not detail.is_empty():
		w["detail"] = detail
	warnings.append(w)
