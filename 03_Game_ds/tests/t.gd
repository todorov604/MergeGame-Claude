extends RefCounted
## Minimal assertion context for the headless test runner.

var suite: String = ""
var checks: int = 0
var failures: Array = []


func _init(suite_name: String) -> void:
	suite = suite_name


func ok(cond: bool, what: String, detail: String = "") -> bool:
	checks += 1
	if cond:
		return true
	failures.append("%s :: %s%s" % [suite, what, (" [" + detail + "]") if not detail.is_empty() else ""])
	return false


func eq(actual, expected, what: String) -> bool:
	return ok(actual == expected, what, "expected=%s actual=%s" % [str(expected), str(actual)])


func ne(actual, unexpected, what: String) -> bool:
	return ok(actual != unexpected, what, "unexpected=%s" % str(unexpected))


func has_code(errors: Array, code: String, what: String) -> bool:
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("code", "")) == code:
			return ok(true, what)
	return ok(false, what, "codes=" + str(codes_of(errors)))


func codes_of(errors: Array) -> Array:
	var out: Array = []
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(String(e.get("code", "")))
	return out
