extends RefCounted

## 极简测试收集器：subagent 写实现，验收统一走这里。

var checks := 0
var failures: Array = []


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s（实际=%s，期望=%s）" % [msg, str(actual), str(expected)])


func contains(text: String, needle: String, msg: String) -> void:
	checks += 1
	if text.find(needle) == -1:
		failures.append("%s（未找到 \"%s\"，实际=%s）" % [msg, needle, text])


func has_error_with_path(errors: Array, path_prefix: String) -> bool:
	for e in errors:
		if str(e.get("path", "")).begins_with(path_prefix):
			return true
	return false


func has_error_containing(errors: Array, needle: String) -> bool:
	for e in errors:
		if str(e.get("message", "")).find(needle) != -1:
			return true
	return false
