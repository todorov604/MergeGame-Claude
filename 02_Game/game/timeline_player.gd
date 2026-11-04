extends RefCounted

## 时间轴播放器（M0 第 1 周第 5 步）：
## 持有 EventEvaluator 的全量排序事件与 SimRunner 的日志/快照，供预览、单步与 seek 共用。
## 只按 sim 事件推进状态；view/audio 事件仅保留在 events 中供 UI 列表展示。
## 全部逻辑确定性，不读墙钟、不做动画回调。

const EventEvaluator := preload("res://core/event_evaluator.gd")
const SimRunner := preload("res://core/sim/sim_runner.gd")
const Validator := preload("res://core/validator.gd")

const CHANNEL_SIM := "sim"

var events: Array = []          # 全部已排序事件（含 view/audio）
var sim_events: Array = []      # channel=="sim" 的事件（保持 events 顺序）
var sim_log: Array = []         # SimRunner 的 events
var snapshots: Array = []       # 每条 sim 事件后的快照
var initial_snapshot: Dictionary = {}
var index := 0                  # 下一个要应用的 sim 事件下标（applied_count == index）
var errors: Array = []
var duration := 0.0


## 读取 project_doc.data.timeline，求值并跑一遍模拟；成功返回 true 且 reset()。
## 求值失败或 sim 事件/日志/快照数量不一致时：errors 记录原因、状态清空、返回 false。
func setup(project_doc) -> bool:
	errors.clear()
	_clear_state()

	if project_doc == null:
		errors.append({"index": -1, "id": "", "message": "project_doc 为空"})
		return false
	var data_v: Variant = project_doc.data
	if typeof(data_v) != TYPE_DICTIONARY:
		errors.append({"index": -1, "id": "", "message": "project_doc.data 不是 Dictionary"})
		return false
	var data: Dictionary = data_v

	# 0) 项目校验：wait/未注册类型等违规事件不得进入预览与单步。
	var validator = Validator.new()
	validator.validate_project(project_doc, null, true)
	if not validator.errors.is_empty():
		errors = validator.errors.duplicate(true)
		_clear_state()
		return false

	# 1) 求值：解析绝对/相对锚点并按 §3.2 排序。
	var timeline: Array = _array_or_empty(data.get("timeline", []))
	var evaluator = EventEvaluator.new()
	if not evaluator.evaluate(timeline):
		errors.append_array(evaluator.errors)
		_clear_state()
		return false

	# 2) 模拟：seed 取 meta.seed 的 int-like 值，否则 0。
	var seed_value := _seed_from(data)
	var runner = SimRunner.new()
	var run_result: Dictionary = runner.run(project_doc, seed_value)

	# 3) 拆出 sim 事件，并对齐日志/快照数量。
	events = evaluator.events
	sim_events = []
	for event_v in events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		if _string_or_empty(event.get("channel")) == CHANNEL_SIM:
			sim_events.append(event)
	sim_log = _array_or_empty(run_result.get("events", []))
	snapshots = _array_or_empty(run_result.get("snapshots", []))
	initial_snapshot = _dict_or_empty(run_result.get("initial_snapshot", {}))
	duration = evaluator.end_time()

	if sim_events.size() != sim_log.size() or sim_events.size() != snapshots.size():
		errors.append({
			"index": -1,
			"id": "",
			"message": "sim 事件数量不一致: sim_events=%d, sim_log=%d, snapshots=%d" % [
				sim_events.size(), sim_log.size(), snapshots.size()],
		})
		_clear_state()
		return false

	reset()
	return true


## 回到时间轴起点（只改 index，不重新模拟）。
func reset() -> void:
	index = 0


func sim_event_count() -> int:
	return sim_events.size()


func applied_count() -> int:
	return index


func has_next() -> bool:
	return index < sim_events.size()


## 下一个待应用的 sim 事件；没有则返回 {}。
func next_event() -> Dictionary:
	if not has_next():
		return {}
	var event_v: Variant = sim_events[index]
	if typeof(event_v) == TYPE_DICTIONARY:
		var event: Dictionary = event_v
		return event
	return {}


## 下一个 sim 事件的绝对时间；没有则 -1.0。
func next_event_time() -> float:
	if not has_next():
		return -1.0
	return _event_at(sim_events[index])


## events（全部事件，含 view/audio）中第 i 条的绝对时间；越界返回 -1.0。
func event_time(i: int) -> float:
	if i < 0 or i >= events.size():
		return -1.0
	return _event_at(events[i])


## 最后一条已应用的 sim 事件时间；尚未应用任何事件时返回 -1.0。
func last_applied_time() -> float:
	if index <= 0:
		return -1.0
	var i := index - 1
	if i >= sim_events.size():
		return -1.0
	return _event_at(sim_events[i])


## 当前状态快照：index==0 为初始快照，否则为最后一条已应用事件的快照。
func current_snapshot() -> Dictionary:
	if index <= 0:
		return initial_snapshot
	var i := index - 1
	if i >= snapshots.size():
		return initial_snapshot
	var snapshot_v: Variant = snapshots[i]
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		var snapshot: Dictionary = snapshot_v
		return snapshot
	return initial_snapshot


## 应用下一条 sim 事件（直接推进到预计算快照）。
## ok/message 取该事件在 SimRunner 日志中的真实结果：失败事件同样推进到预计算快照，
## 由调用方（编辑器）负责显示失败原因。
func step() -> Dictionary:
	if not has_next():
		return {
			"ok": false,
			"done": true,
			"event": {},
			"snapshot": current_snapshot(),
			"index": index,
		}
	var applied_index := index
	var event := next_event()
	var snapshot := _snapshot_at(index)
	var next_index := index + 1
	index = next_index
	var ok := false
	var message := ""
	if applied_index >= 0 and applied_index < sim_log.size():
		var log_v: Variant = sim_log[applied_index]
		if typeof(log_v) == TYPE_DICTIONARY:
			var log_entry: Dictionary = log_v
			ok = bool(log_entry.get("ok", false))
			message = _string_or_empty(log_entry.get("message"))
	return {
		"ok": ok,
		"done": false,
		"event": event,
		"snapshot": snapshot,
		"index": next_index,
		"message": message,
	}


## 跳到 time：必要时先回到起点，然后连续应用 at <= time 的 sim 事件（不逐步回调）。
func seek(time: float) -> Dictionary:
	if time < last_applied_time() or (index == 0 and time < 0.0):
		reset()
	while has_next() and next_event_time() <= time:
		index += 1
	return {
		"ok": true,
		"index": index,
		"snapshot": current_snapshot(),
		"last_at": last_applied_time(),
	}


# ---------------------------------------------------------------------------
# 内部辅助
# ---------------------------------------------------------------------------

func _clear_state() -> void:
	events = []
	sim_events = []
	sim_log = []
	snapshots = []
	initial_snapshot = {}
	index = 0
	duration = 0.0


func _snapshot_at(i: int) -> Dictionary:
	if i < 0 or i >= snapshots.size():
		return {}
	var snapshot_v: Variant = snapshots[i]
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		var snapshot: Dictionary = snapshot_v
		return snapshot
	return {}


static func _event_at(event_v: Variant) -> float:
	if typeof(event_v) != TYPE_DICTIONARY:
		return 0.0
	var event: Dictionary = event_v
	var at_v: Variant = event.get("at_resolved", 0.0)
	if typeof(at_v) == TYPE_INT or typeof(at_v) == TYPE_FLOAT:
		return float(at_v)
	return 0.0


## meta.seed 为 int-like（整数或整值 float）才采用，否则 0。
static func _seed_from(data: Dictionary) -> int:
	var meta_v: Variant = data.get("meta", {})
	if typeof(meta_v) != TYPE_DICTIONARY:
		return 0
	var meta: Dictionary = meta_v
	var seed_v: Variant = meta.get("seed")
	if typeof(seed_v) == TYPE_INT:
		return int(seed_v)
	if typeof(seed_v) == TYPE_FLOAT:
		var f := float(seed_v)
		if is_finite(f) and f == floor(f):
			return int(f)
	return 0


static func _string_or_empty(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""


static func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _dict_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
