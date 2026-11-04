extends RefCounted

## 事件求值器验收：锚点解析、确定性排序、错误检测。

const EventEvaluator = preload("res://core/event_evaluator.gd")


func run(r) -> void:
	_test_sort_order(r)
	_test_anchors(r)
	_test_missing_anchor(r)
	_test_cycle(r)
	_test_duplicate_id(r)
	_test_bad_entry(r)


func _test_sort_order(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "v1", "channel": "view", "type": "text", "at": 5.0, "payload": {}},
		{"id": "s1", "channel": "sim", "type": "tap", "at": 5.0, "payload": {}},
		{"id": "s2", "channel": "sim", "type": "tap", "at": 5.0, "order": 1, "payload": {}},
		{"id": "s0", "channel": "sim", "type": "tap", "at": 5.0, "track": 1, "payload": {}},
		{"id": "s00", "channel": "sim", "type": "tap", "at": 5.0, "payload": {}},
	])
	r.check(ok, "合法事件应求值成功: " + _join(evaluator.errors))
	r.eq(_ids(evaluator.events), ["s00", "s1", "s2", "s0", "v1"], "排序应为 at→channel→track→order→id")
	# audio 通道当前没有注册类型，优先级只能直接验证
	r.eq(EventEvaluator.channel_priority("sim"), 0, "sim 通道优先级 0")
	r.eq(EventEvaluator.channel_priority("view"), 1, "view 通道优先级 1")
	r.eq(EventEvaluator.channel_priority("audio"), 2, "audio 通道优先级 2")


func _test_anchors(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "e1", "channel": "sim", "type": "tap", "at": 2.0, "payload": {}},
		{"id": "e2", "channel": "sim", "type": "tap", "at": {"after": "e1", "offset": 0.5}, "payload": {}},
		{"id": "e3", "channel": "sim", "type": "tap", "at": {"after": "e2", "offset": 1.0}, "duration": 1.5, "payload": {}},
	])
	r.check(ok, "锚点链应求值成功: " + _join(evaluator.errors))
	var by_id := {}
	for event in evaluator.events:
		by_id[event["id"]] = event
	r.check(by_id.has("e2") and is_equal_approx(by_id["e2"].get("at_resolved", -1.0), 2.5), "after+offset 应解析为 2.5")
	r.check(by_id.has("e3") and is_equal_approx(by_id["e3"].get("at_resolved", -1.0), 3.5), "链式锚点应解析为 3.5")
	r.check(is_equal_approx(evaluator.end_time(), 5.0), "end_time 应为 3.5+1.5=5.0")
	r.check(by_id.has("e3") and by_id["e3"].has("payload"), "事件副本应保留原字段")


func _test_missing_anchor(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "e1", "channel": "sim", "type": "tap", "at": {"after": "ghost", "offset": 1.0}, "payload": {}},
	])
	r.check(not ok, "缺失锚点应失败")
	r.check(_messages(evaluator.errors).find("锚点") != -1, "缺失锚点错误信息: " + _join(evaluator.errors))


func _test_cycle(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "a", "channel": "sim", "type": "tap", "at": {"after": "b", "offset": 0.0}, "payload": {}},
		{"id": "b", "channel": "sim", "type": "tap", "at": {"after": "a", "offset": 0.0}, "payload": {}},
	])
	r.check(not ok, "锚点循环应失败")
	r.check(_messages(evaluator.errors).find("循环") != -1, "循环错误信息: " + _join(evaluator.errors))


func _test_duplicate_id(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([
		{"id": "dup", "channel": "sim", "type": "tap", "at": 1.0, "payload": {}},
		{"id": "dup", "channel": "sim", "type": "tap", "at": 2.0, "payload": {}},
	])
	r.check(not ok, "重复事件 id 应失败")
	r.check(_messages(evaluator.errors).find("重复") != -1, "重复 id 错误信息: " + _join(evaluator.errors))


func _test_bad_entry(r) -> void:
	var evaluator = EventEvaluator.new()
	var ok := evaluator.evaluate([42])
	r.check(not ok, "非对象事件应失败")
	r.check(_messages(evaluator.errors).find("对象") != -1, "非对象错误信息: " + _join(evaluator.errors))


func _ids(events: Array) -> Array:
	var ids: Array = []
	for event in events:
		ids.append(event.get("id", ""))
	return ids


func _messages(errors: Array) -> String:
	var parts: Array = []
	for e in errors:
		parts.append(str(e.get("message", "")))
	return " | ".join(parts)


func _join(errors: Array) -> String:
	return _messages(errors)
