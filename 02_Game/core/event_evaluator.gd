extends RefCounted

## 事件求值器（M0 冻结规格 §3）：解析绝对/相对锚点，按确定性规则排序。
## 不依赖 Node / SceneTree；预览、单步、离线渲染共用同一求值器。

const CHANNEL_SIM := "sim"
const CHANNEL_VIEW := "view"
const CHANNEL_AUDIO := "audio"
const CHANNEL_PRIORITY := {"sim": 0, "view": 1, "audio": 2}
const SIM_TYPES := ["tap", "drag", "merge", "deliver", "order_claim", "board_full", "energy_tick", "level_complete", "level_next"]
const VIEW_TYPES := ["camera", "text", "highlight", "select", "hint", "star_fly", "coin_popup", "character_leave", "character_next", "levelup", "cta", "transition"]
const AUDIO_TYPES := []

var errors: Array = []
var events: Array = []


## 解析锚点并排序；返回是否无错误（errors 为空）。
func evaluate(timeline: Array) -> bool:
	errors.clear()
	events.clear()

	# 1) 基础检查 + 建立 id -> index 表（重复 id 报错，锚点解析用第一个）。
	var id_to_index: Dictionary = {}
	for i in range(timeline.size()):
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			errors.append({"index": i, "id": "", "message": "事件必须是对象"})
			continue
		var entry_id: Variant = (entry_v as Dictionary).get("id")
		if typeof(entry_id) == TYPE_STRING and not String(entry_id).is_empty():
			if id_to_index.has(entry_id):
				errors.append({"index": i, "id": String(entry_id), "message": "事件 ID 重复: %s" % entry_id})
			else:
				id_to_index[entry_id] = i

	# 2) 递归解析 at（memo + visiting 循环检测）；失败的事件不进入 events。
	var memo: Dictionary = {}
	var visiting: Dictionary = {}
	for i in range(timeline.size()):
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var resolved: Dictionary = _resolve_index(i, timeline, id_to_index, memo, visiting)
		if bool(resolved["ok"]):
			var copy: Dictionary = (entry_v as Dictionary).duplicate(true)
			copy["at_resolved"] = float(resolved["value"])
			events.append(copy)
		else:
			errors.append({
				"index": i,
				"id": String(resolved["id"]),
				"message": String(resolved["message"]),
			})

	# 3) 确定性排序（M0 §3.2）：at -> channel 优先级 -> track -> order -> id。
	events.sort_custom(_compare_events)
	return errors.is_empty()


## 成片时长：events 中最大的 at_resolved + duration（duration 非数字按 0）。
func end_time() -> float:
	if events.is_empty():
		return 0.0
	var result: float = -INF
	for event_v in events:
		var event: Dictionary = event_v
		var at_resolved := 0.0
		var at_v: Variant = event.get("at_resolved", 0.0)
		if typeof(at_v) == TYPE_INT or typeof(at_v) == TYPE_FLOAT:
			at_resolved = float(at_v)
		var duration := 0.0
		var duration_v: Variant = event.get("duration")
		if typeof(duration_v) == TYPE_INT or typeof(duration_v) == TYPE_FLOAT:
			duration = float(duration_v)
		result = maxf(result, at_resolved + duration)
	return result


## 未知 channel 记 99（排在最后）。
static func channel_priority(ch: String) -> int:
	if CHANNEL_PRIORITY.has(ch):
		return int(CHANNEL_PRIORITY[ch])
	return 99


func _resolve_index(index: int, timeline: Array, id_to_index: Dictionary, memo: Dictionary, visiting: Dictionary) -> Dictionary:
	if memo.has(index):
		return memo[index]
	var entry_v: Variant = timeline[index]
	var entry_id := ""
	if typeof(entry_v) == TYPE_DICTIONARY:
		var raw_id: Variant = (entry_v as Dictionary).get("id")
		if typeof(raw_id) == TYPE_STRING:
			entry_id = String(raw_id)
	visiting[index] = true
	var result := {"ok": false, "value": 0.0, "id": entry_id, "message": "缺少合法 at"}
	if typeof(entry_v) == TYPE_DICTIONARY:
		var at_v: Variant = (entry_v as Dictionary).get("at")
		if typeof(at_v) == TYPE_INT or typeof(at_v) == TYPE_FLOAT:
			result = {"ok": true, "value": float(at_v), "id": entry_id, "message": ""}
		elif typeof(at_v) == TYPE_DICTIONARY:
			var anchor: Dictionary = at_v
			var after_v: Variant = anchor.get("after")
			if typeof(after_v) != TYPE_STRING or String(after_v).is_empty():
				result["message"] = "缺少合法 at"
			elif not id_to_index.has(after_v):
				result["message"] = "锚点不存在: %s" % after_v
			else:
				var offset := 0.0
				var offset_ok := true
				if anchor.has("offset"):
					var offset_v: Variant = anchor["offset"]
					if typeof(offset_v) == TYPE_INT or typeof(offset_v) == TYPE_FLOAT:
						offset = float(offset_v)
					else:
						offset_ok = false
				if not offset_ok:
					result["message"] = "缺少合法 at"
				else:
					var target_index: int = id_to_index[after_v]
					if visiting.has(target_index):
						var cycle_id := entry_id
						if cycle_id.is_empty():
							cycle_id = String(after_v)
						result["message"] = "锚点循环: %s" % cycle_id
					else:
						var sub: Dictionary = _resolve_index(target_index, timeline, id_to_index, memo, visiting)
						if bool(sub["ok"]):
							result = {
								"ok": true,
								"value": float(sub["value"]) + offset,
								"id": entry_id,
								"message": "",
							}
						else:
							result["message"] = String(sub["message"])
	visiting.erase(index)
	memo[index] = result
	return result


func _compare_events(a: Dictionary, b: Dictionary) -> bool:
	var at_a := float(a.get("at_resolved", 0.0))
	var at_b := float(b.get("at_resolved", 0.0))
	if at_a != at_b:
		return at_a < at_b
	var priority_a := channel_priority(_string_or_empty(a.get("channel")))
	var priority_b := channel_priority(_string_or_empty(b.get("channel")))
	if priority_a != priority_b:
		return priority_a < priority_b
	var track_a := _int_like_or(a.get("track"), 0)
	var track_b := _int_like_or(b.get("track"), 0)
	if track_a != track_b:
		return track_a < track_b
	var order_a := _int_like_or(a.get("order"), 0)
	var order_b := _int_like_or(b.get("order"), 0)
	if order_a != order_b:
		return order_a < order_b
	return _string_or_empty(a.get("id")) < _string_or_empty(b.get("id"))


static func _string_or_empty(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return String(v)
	return ""


static func _int_like_or(v: Variant, fallback: int) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_finite(f) and f == floor(f):
			return int(f)
	return fallback
