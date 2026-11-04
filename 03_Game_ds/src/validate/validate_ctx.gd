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

## Name of the rule family executing right now. A GDScript runtime error aborts
## only the innermost function: the caller keeps running, so without this marker
## an aborted rule would look like a clean rule. A rule must end with rule_done();
## a marker that is still set afterwards means the rule never reached its last line.
var rule: String = ""


static func is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## String / StringName only. JSON gives us neither for a number or an object, and
## `String(5)` is a runtime error (not a conversion), so every identifier that
## reaches String() has to pass through here first.
static func is_string(v) -> bool:
	return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME


static func as_str(v, fallback: String = "") -> String:
	if is_string(v):
		return String(v)
	return fallback


static func type_name_of(v) -> String:
	return type_string(typeof(v))


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


## The engine-level backstop: a rule function that was interrupted by a runtime
## script error never returns to the validator, but it also never reports its
## findings. Recording this keeps the run red instead of silently green.
func err_internal(name: String, detail: String) -> void:
	err("INTERNAL_SCRIPT_ERROR", "rule:" + name,
		"rule \"%s\" was interrupted by a runtime script error; its remaining findings are missing (%s)" % [name, detail])


## Called by a rule as its very last statement.
func rule_done() -> void:
	rule = ""


func rule_running() -> bool:
	return not rule.is_empty()


## Runs one rule family and reports an interrupted run. The rule must call
## rule_done() on its last line; see validator.run_rule for the static facade.
func run_rule(name: String, fn: Callable) -> bool:
	var outer := rule
	rule = name
	fn.call()
	var finished := rule.is_empty()
	rule = outer
	if not finished:
		err_internal(name, "the rule stopped before its last line")
	return finished


func warn(code: String, path: String, msg: String, detail: Dictionary = {}) -> void:
	var w := {"level": "warning", "code": code, "path": path, "msg": msg}
	if not detail.is_empty():
		w["detail"] = detail
	warnings.append(w)
