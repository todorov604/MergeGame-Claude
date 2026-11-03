extends RefCounted

## 模拟执行器（M0 第 1 周第 2 步）：
## 事件求值 -> 依序执行 sim 命令 -> 每步记录状态 hash 与结果。
## 不依赖 Node / SceneTree；预览、单步、离线渲染共用同一执行器。

const EventEvaluator := preload("res://core/event_evaluator.gd")
const SimState := preload("res://core/sim/sim_state.gd")
const MergeEngine := preload("res://core/sim/merge_engine.gd")

const CHANNEL_SIM := "sim"

var _merge_engine = MergeEngine.new()


## project_doc 需有 .data:Dictionary。返回：
## {"ok","events","final_hash","snapshot","evaluator_errors"}。
func run(project_doc, seed_in: int) -> Dictionary:
	var data: Dictionary = {}
	if project_doc != null:
		var data_v: Variant = project_doc.data
		if typeof(data_v) == TYPE_DICTIONARY:
			data = data_v

	var evaluator = EventEvaluator.new()
	var timeline_v: Variant = data.get("timeline", [])
	var timeline: Array = []
	if typeof(timeline_v) == TYPE_ARRAY:
		timeline = timeline_v
	if not evaluator.evaluate(timeline):
		return {
			"ok": false,
			"events": [],
			"final_hash": "",
			"snapshot": {},
			"initial_snapshot": {},
			"snapshots": [],
			"evaluator_errors": evaluator.errors,
		}

	var state = SimState.new()
	state.setup(data, seed_in)
	var initial_snapshot: Dictionary = state.snapshot()
	var snapshots: Array = []

	var all_ok := true
	for event_v in evaluator.events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		if _string_or_empty(event.get("channel")) != CHANNEL_SIM:
			continue
		var entry := {
			"id": _string_or_empty(event.get("id")),
			"at": float(event.get("at_resolved", 0.0)),
			"type": _string_or_empty(event.get("type")),
			"ok": false,
			"message": "",
			"state_hash": "",
		}
		var result: Dictionary = _apply(state, event)
		entry["ok"] = bool(result.get("ok", false))
		entry["message"] = _string_or_empty(result.get("message"))
		entry["state_hash"] = state.state_hash()
		state.event_log.append(entry)
		snapshots.append(state.snapshot())
		if not bool(entry["ok"]):
			all_ok = false

	return {
		"ok": all_ok,
		"events": state.event_log,
		"final_hash": state.state_hash(),
		"snapshot": state.snapshot(),
		"initial_snapshot": initial_snapshot,
		"snapshots": snapshots,
		"evaluator_errors": [],
	}


func _apply(state, event: Dictionary) -> Dictionary:
	var event_type := _string_or_empty(event.get("type"))
	var payload: Dictionary = {}
	var payload_v: Variant = event.get("payload", {})
	if typeof(payload_v) == TYPE_DICTIONARY:
		payload = payload_v
	var at := float(event.get("at_resolved", 0.0))

	match event_type:
		"tap":
			return _apply_tap(state, payload, at)
		"merge":
			return _apply_merge(state, payload)
		"drag":
			return _apply_drag(state, payload)
		"deliver":
			return _apply_deliver(state, payload)
		"order_claim":
			return _apply_order_claim(state, payload)
		"energy_tick":
			return _apply_energy_tick(state)
		"level_complete":
			return _apply_level_complete(state)
		"level_next":
			return _apply_level_next(state)
		"board_full":
			return {"ok": true, "message": "棋盘已满提示"}
	return {"ok": false, "message": "未实现的事件类型"}


func _apply_tap(state, payload: Dictionary, at: float) -> Dictionary:
	var target_v: Variant = payload.get("target")
	var slot: Array = []
	if typeof(target_v) == TYPE_DICTIONARY:
		slot = _xy_or_empty((target_v as Dictionary).get("slot"))
	if slot.is_empty():
		return _fail("tap 缺少 target.slot")

	var cell: Dictionary = state.board.get_cell(int(slot[0]), int(slot[1]))
	if cell.is_empty():
		return _fail("目标格没有实体")
	var entity_id := _string_or_empty(cell.get("entity"))
	var entity_def := _entity_def(state.project_data, entity_id)
	if _string_or_empty(entity_def.get("kind")) != "generator":
		return _fail("目标不是生成器")

	var tap_result: Dictionary = state.generators.tap(
		state.project_data, state.board, slot, at, state.rng)
	var message := _string_or_empty(tap_result.get("message"))
	if bool(tap_result.get("board_full", false)):
		message = "棋盘已满"
	return {"ok": bool(tap_result.get("ok", false)), "message": message}


func _apply_merge(state, payload: Dictionary) -> Dictionary:
	var from := _xy_or_empty(payload.get("from"))
	var to := _xy_or_empty(payload.get("to"))
	if from.is_empty() or to.is_empty():
		return _fail("merge 缺少 from/to")

	var max_level := 10
	var from_cell: Dictionary = state.board.get_cell(int(from[0]), int(from[1]))
	if not from_cell.is_empty():
		var entity_def := _entity_def(state.project_data, _string_or_empty(from_cell.get("entity")))
		max_level = _int_like_or(entity_def.get("maxLevel"), 10)

	var merge_result: Dictionary = _merge_engine.merge(state.board, from, to, max_level)
	return {
		"ok": bool(merge_result.get("ok", false)),
		"message": _string_or_empty(merge_result.get("message")),
	}


func _apply_drag(state, payload: Dictionary) -> Dictionary:
	var from := _xy_or_empty(payload.get("from"))
	var to := _xy_or_empty(payload.get("to"))
	if from.is_empty() or to.is_empty():
		return _fail("drag 缺少 from/to")

	var from_x := int(from[0])
	var from_y := int(from[1])
	var to_x := int(to[0])
	var to_y := int(to[1])
	var cell: Dictionary = state.board.get_cell(from_x, from_y)
	if cell.is_empty():
		return _fail("来源格没有实体")
	if not state.board.is_empty_slot(to_x, to_y):
		return _fail("目标格不可放置")

	var entity_id := _string_or_empty(cell.get("entity"))
	var level := _int_like_or(cell.get("level"), 1)
	state.board.set_cell(to_x, to_y, entity_id, level)
	state.board.remove_cell(from_x, from_y)
	return {"ok": true, "message": "移动 %s Lv%d" % [entity_id, level]}


func _apply_deliver(state, payload: Dictionary) -> Dictionary:
	var order_id := _string_or_empty(payload.get("order"))
	if order_id.is_empty():
		return _fail("deliver 缺少 order")
	var deliver_result: Dictionary = state.orders.deliver(state.board, order_id)
	return {
		"ok": bool(deliver_result.get("ok", false)),
		"message": _string_or_empty(deliver_result.get("message")),
	}


func _apply_order_claim(state, payload: Dictionary) -> Dictionary:
	var order_id := _string_or_empty(payload.get("order"))
	if order_id.is_empty():
		return _fail("order_claim 缺少 order")
	var claim_result: Dictionary = state.orders.claim(state.board, order_id, state.hud)
	var ok := bool(claim_result.get("ok", false))
	var message := _string_or_empty(claim_result.get("message"))
	if ok and bool(claim_result.get("level_complete", false)):
		state.level_complete = true
		message += "（关卡完成）"
	return {"ok": ok, "message": message}


func _apply_energy_tick(state) -> Dictionary:
	var mode := _string_or_empty(state.hud.get("energyTickMode"))
	var energy := _int_like_or(state.hud.get("energy"), 0)
	if mode == "increment":
		energy += 1
	else:
		energy = maxi(0, energy - 1)
	state.hud["energy"] = energy
	return {"ok": true, "message": "能量 %d" % energy}


func _apply_level_complete(state) -> Dictionary:
	if state.orders.all_claimed():
		state.level_complete = true
		return {"ok": true, "message": "关卡完成确认"}
	return _fail("订单未全部完成")


func _apply_level_next(state) -> Dictionary:
	if not state.level_complete:
		return _fail("关卡未完成")
	if not state.advance_level():
		return _fail("已是最后一关")
	return {"ok": true, "message": "进入关卡 %s" % state.flow.level_id()}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


func _entity_def(project_data: Dictionary, entity_id: String) -> Dictionary:
	if entity_id.is_empty():
		return {}
	var entities_v: Variant = project_data.get("entities", {})
	if typeof(entities_v) != TYPE_DICTIONARY:
		return {}
	var entities: Dictionary = entities_v
	var def_v: Variant = entities.get(entity_id, {})
	if typeof(def_v) == TYPE_DICTIONARY:
		var def: Dictionary = def_v
		return def
	return {}


## [x, y] 且两元素均为 int-like（TYPE_INT，或有限且等于 floor 的 TYPE_FLOAT）才有效；否则返回 []。
static func _xy_or_empty(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var arr: Array = value
	if arr.size() != 2:
		return []
	if not _is_int_like(arr[0]) or not _is_int_like(arr[1]):
		return []
	return [int(arr[0]), int(arr[1])]


static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		return is_finite(f) and f == floor(f)
	return false


static func _int_like_or(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return fallback


static func _string_or_empty(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""
