extends RefCounted

## 第 5 步验收：TimelinePlayer（setup / step / seek / 快照 / 求值失败）。

const TimelinePlayer = preload("res://game/timeline_player.gd")
const ProjectDoc = preload("res://core/project_doc.gd")

const SAMPLE_PATH := "res://data/projects/sample_30s.json"

var _doc = null


func run(r) -> void:
	_doc = ProjectDoc.new()
	r.check(_doc.load_file(SAMPLE_PATH), "样例项目应能加载: " + str(_doc.parse_error))
	var player = TimelinePlayer.new()
	_test_setup(r, player)
	_test_four_steps(r, player)
	_test_seek_forward(r, player)
	_test_step_to_done(r, player)
	_test_seek_backward(r, player)
	_test_eval_failure(r)
	_test_step_failure_visible(r)


# ---------------------------------------------------------------- setup

func _test_setup(r, player) -> void:
	r.check(player.setup(_doc), "setup 应成功: " + _errors_text(player.errors))
	var duration := _player_duration(player)
	r.check(duration > 29.9 and duration < 30.1, "成片时长应约为 30.0（实际=%s）" % str(duration))
	r.eq(player.sim_event_count(), 8, "sim 事件数应为 8")
	r.eq(player.applied_count(), 0, "初始 applied_count 应为 0")
	r.check(player.has_next(), "初始应还有下一事件")
	var snapshot: Dictionary = player.current_snapshot()
	r.eq(_level_id(snapshot), "level_1", "初始关卡应为 level_1")
	r.eq(_order_state(snapshot, "order_1"), "pending", "order_1 初始状态应为 pending")


# ---------------------------------------------------------------- 前 4 步

func _test_four_steps(r, player) -> void:
	var expected := ["e1", "e2", "e4", "e5"]
	for i in range(expected.size()):
		var result: Dictionary = player.step()
		r.check(bool(result.get("ok", false)), "第 %d 次 step 应成功: %s" % [i + 1, _step_text(result)])
		r.check(not bool(result.get("done", false)), "第 %d 次 step 不应结束" % [i + 1])
		r.eq(_event_id(result.get("event", {})), expected[i], "第 %d 次 step 事件应为 %s" % [i + 1, expected[i]])

	r.eq(player.applied_count(), 4, "4 次 step 后 applied_count 应为 4")
	r.check(is_equal_approx(player.last_applied_time(), 10.0), "last_applied_time 应约为 10.0")
	var snapshot: Dictionary = player.current_snapshot()
	r.eq(_hud_value(snapshot, "coin"), 14, "HUD 金币应为 14")
	r.eq(_hud_value(snapshot, "star"), 1, "HUD 星星应为 1")
	r.eq(_order_state(snapshot, "order_1"), "claimed", "order_1 应为 claimed")


# ---------------------------------------------------------------- 正向 seek

func _test_seek_forward(r, player) -> void:
	player.reset()
	r.eq(player.applied_count(), 0, "reset 后 applied_count 应为 0")

	var seek10: Dictionary = player.seek(10.0)
	r.check(bool(seek10.get("ok", false)), "seek(10.0) 应成功")
	r.eq(int(seek10.get("index", -1)), 4, "seek(10.0) 后 index 应为 4")
	r.check(is_equal_approx(float(seek10.get("last_at", -1.0)), 10.0), "seek(10.0) 返回的 last_at 应约为 10.0")
	r.check(is_equal_approx(player.last_applied_time(), 10.0), "seek(10.0) 后 last_applied_time 应约为 10.0")

	var seek12: Dictionary = player.seek(12.0)
	r.check(bool(seek12.get("ok", false)), "seek(12.0) 应成功")
	r.eq(int(seek12.get("index", -1)), 5, "seek(12.0) 后 index 应为 5")
	r.eq(_level_id(player.current_snapshot()), "level_2", "seek(12.0) 后应进入 level_2")


# ---------------------------------------------------------------- step 到结束

func _test_step_to_done(r, player) -> void:
	var guard := 0
	while player.has_next() and guard < 32:
		var result: Dictionary = player.step()
		r.check(bool(result.get("ok", false)), "继续 step 应成功: " + _step_text(result))
		guard += 1
	r.check(guard < 32, "step 循环不应超时")
	r.check(not player.has_next(), "应用完全部 sim 事件后应没有下一事件")
	r.eq(player.applied_count(), player.sim_event_count(), "applied_count 应等于 sim_event_count")
	var snapshot: Dictionary = player.current_snapshot()
	r.eq(_level_id(snapshot), "level_2", "最终关卡应为 level_2")
	r.check(bool(snapshot.get("level_complete", false)), "最终 level_complete 应为 true")


# ---------------------------------------------------------------- 回退 seek

func _test_seek_backward(r, player) -> void:
	player.reset()
	var forward: Dictionary = player.seek(12.0)
	r.eq(int(forward.get("index", -1)), 5, "回退测试前 seek(12.0) 的 index 应为 5")

	var back: Dictionary = player.seek(3.0)
	r.check(bool(back.get("ok", false)), "seek(3.0) 应成功")
	r.eq(int(back.get("index", -1)), 1, "seek(3.0) 后 index 应为 1")
	r.eq(_level_id(player.current_snapshot()), "level_1", "seek(3.0) 后应回到 level_1")
	r.check(is_equal_approx(player.last_applied_time(), 3.0), "seek(3.0) 后 last_applied_time 应约为 3.0")


# ---------------------------------------------------------------- 求值失败

func _test_eval_failure(r) -> void:
	var data: Dictionary = _doc.data.duplicate(true)
	var timeline_v: Variant = data.get("timeline", [])
	if typeof(timeline_v) != TYPE_ARRAY:
		r.check(false, "样例 data 应含 timeline 数组")
		return
	var timeline: Array = timeline_v
	timeline.append({"id": "w", "channel": "sim", "type": "wait", "at": 1.0, "payload": {}})

	var bad_doc = ProjectDoc.new()
	bad_doc.from_dict(data, "<player-failure-test>")
	var player = TimelinePlayer.new()
	r.check(not player.setup(bad_doc), "含 wait 事件的项目 setup 应失败")
	var errors_v: Variant = player.errors
	r.check(typeof(errors_v) == TYPE_ARRAY and (errors_v as Array).size() > 0, "setup 失败时 errors 应非空")


# ---------------------------------------------------------------- step 失败可见

## 坐标非法但 payload 结构合规的事件能通过校验与 setup；step 应返回真实失败原因，
## 供编辑器展示，而不是只推进不出声。
func _test_step_failure_visible(r) -> void:
	var data: Dictionary = _doc.data.duplicate(true)
	data["timeline"] = [
		{
			"id": "m1",
			"channel": "sim",
			"type": "merge",
			"at": 1.0,
			"payload": {"from": [2, 3], "to": [5, 5]},
		},
	]
	var doc = ProjectDoc.new()
	doc.from_dict(data, "<player-step-failure-test>")
	var player = TimelinePlayer.new()
	r.check(player.setup(doc), "payload 坐标非法不应阻断 setup: " + _errors_text(player.errors))
	r.eq(player.sim_event_count(), 1, "单事件时间轴应有 1 条 sim 事件")
	var result: Dictionary = player.step()
	r.check(not bool(result.get("ok", true)), "失败事件的 step 应返回 ok=false")
	var message := str(result.get("message", ""))
	r.check(not message.is_empty(), "失败事件的 step 应返回非空 message")
	r.eq(message, "实体不同", "失败事件的 step 文案")


# ---------------------------------------------------------------- helpers

func _level_id(snapshot: Dictionary) -> String:
	var level_v: Variant = snapshot.get("level", {})
	if typeof(level_v) == TYPE_DICTIONARY:
		return str((level_v as Dictionary).get("id", ""))
	return ""


func _order_state(snapshot: Dictionary, order_id: String) -> String:
	var orders_v: Variant = snapshot.get("orders", [])
	if typeof(orders_v) != TYPE_ARRAY:
		return ""
	for order_v in orders_v:
		if typeof(order_v) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_v
		if str(order.get("id", "")) == order_id:
			return str(order.get("state", ""))
	return ""


func _hud_value(snapshot: Dictionary, key: String) -> int:
	var hud_v: Variant = snapshot.get("hud", {})
	if typeof(hud_v) != TYPE_DICTIONARY:
		return -1
	return int((hud_v as Dictionary).get(key, -1))


func _event_id(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return str((value as Dictionary).get("id", ""))
	return ""


func _step_text(result: Dictionary) -> String:
	return "ok=%s done=%s event=%s" % [
		str(result.get("ok", false)),
		str(result.get("done", false)),
		_event_id(result.get("event", {})),
	]


func _errors_text(errors) -> String:
	var parts: Array = []
	if typeof(errors) == TYPE_ARRAY:
		for e in errors:
			if typeof(e) == TYPE_DICTIONARY:
				parts.append(str((e as Dictionary).get("message", str(e))))
			else:
				parts.append(str(e))
	else:
		parts.append(str(errors))
	return " | ".join(parts)


## duration 在断言中出现但未在方法清单中单列：兼容方法 / 属性两种暴露方式，
## 最后退路是求值后事件（at_resolved + duration 的最大值）。
func _player_duration(player) -> float:
	if player.has_method("duration"):
		return float(player.call("duration"))
	if _has_property(player, "duration"):
		var value: Variant = player.get("duration")
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return float(value)

	var max_end := -1.0
	if not _has_property(player, "events"):
		return max_end
	var events_v: Variant = player.get("events")
	if typeof(events_v) != TYPE_ARRAY:
		return max_end
	for event_v in events_v:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		var at := 0.0
		var at_v: Variant = event.get("at_resolved", 0.0)
		if typeof(at_v) == TYPE_INT or typeof(at_v) == TYPE_FLOAT:
			at = float(at_v)
		var duration := 0.0
		var duration_v: Variant = event.get("duration")
		if typeof(duration_v) == TYPE_INT or typeof(duration_v) == TYPE_FLOAT:
			duration = float(duration_v)
		max_end = maxf(max_end, at + duration)
	return max_end


func _has_property(obj, prop_name: String) -> bool:
	for prop_v in obj.get_property_list():
		if typeof(prop_v) == TYPE_DICTIONARY and str((prop_v as Dictionary).get("name", "")) == prop_name:
			return true
	return false
