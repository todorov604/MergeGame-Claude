extends RefCounted
## Validation result. `to_json()` is what the CLI writes to output/validation_report.json;
## `lines()` is the ASCII console summary (cp936-safe: no CJK on stdout).

var project_path: String = ""
var ok: bool = true
var errors: Array = []
var warnings: Array = []
var stats: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"project": project_path,
		"stats": stats,
		"errors": errors,
		"warnings": warnings,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ", false) + "\n"


func codes() -> Array:
	var out: Array = []
	for e in errors:
		out.append(String(e.get("code", "")))
	return out


func has_code(code: String) -> bool:
	for e in errors:
		if String(e.get("code", "")) == code:
			return true
	return false


func find_code(code: String) -> Dictionary:
	for e in errors:
		if String(e.get("code", "")) == code:
			return e
	return {}


func lines() -> Array:
	var out: Array = []
	out.append("[validate] %s -> ok=%s errors=%d warnings=%d" % [project_path, str(ok), errors.size(), warnings.size()])
	if not stats.is_empty():
		var st := "levels=%d events=%d end=%.2fs entities=%d asset_refs=%d" % [
			int(stats.get("levels", 0)),
			int(stats.get("events", 0)),
			float(stats.get("end_time", 0.0)),
			int(stats.get("entities", 0)),
			int(stats.get("asset_refs", 0)),
		]
		out.append("[validate] " + st)
	for e in errors:
		out.append("  E %-28s %-34s %s" % [String(e.get("code", "")), String(e.get("path", "")), String(e.get("msg", ""))])
	for w in warnings:
		out.append("  W %-28s %-34s %s" % [String(w.get("code", "")), String(w.get("path", "")), String(w.get("msg", ""))])
	return out
