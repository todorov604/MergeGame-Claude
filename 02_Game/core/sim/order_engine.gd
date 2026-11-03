extends RefCounted

## 订单引擎（M0 冻结规格 §2 / §3.4）：订单副本、交付检查、领取消耗与 HUD 奖励。
## 不依赖 Node / SceneTree；board 由参数传入，只使用约定的棋盘 API。
## 订单状态机：pending（初始）-> ready（deliver 成功）-> claimed（claim 成功）。

const STATE_PENDING := "pending"
const STATE_READY := "ready"
const STATE_CLAIMED := "claimed"

var orders: Array = []       # 当前关卡订单副本，每项 {"id","character","mission","star","coin","state"}
var by_id: Dictionary = {}   # id -> 订单 Dictionary（与 orders 中同一对象）


## 用关卡数据重建订单副本：深拷贝 level["orders"]，每项加 state="pending"。
## 非法条目（非 Dictionary 或缺 id）跳过。
func setup(level: Dictionary) -> void:
	orders.clear()
	by_id.clear()
	var source_v: Variant = level.get("orders")
	if typeof(source_v) != TYPE_ARRAY:
		return
	var source: Array = source_v
	for order_v in source:
		if typeof(order_v) != TYPE_DICTIONARY:
			continue
		var order_id_v: Variant = (order_v as Dictionary).get("id")
		if typeof(order_id_v) != TYPE_STRING or String(order_id_v).is_empty():
			continue
		var order: Dictionary = (order_v as Dictionary).duplicate(true)
		order["state"] = STATE_PENDING
		orders.append(order)
		by_id[String(order_id_v)] = order


func get_order(order_id: String) -> Dictionary:
	var order_v: Variant = by_id.get(order_id)
	if typeof(order_v) == TYPE_DICTIONARY:
		var order: Dictionary = order_v
		return order
	return {}


func state_of(order_id: String) -> String:
	var order := get_order(order_id)
	if order.is_empty():
		return ""
	var state_v: Variant = order.get("state")
	if typeof(state_v) == TYPE_STRING:
		return String(state_v)
	return ""


func all_claimed() -> bool:
	if orders.is_empty():
		return false
	for order_v in orders:
		var order: Dictionary = order_v
		if _string_or_empty(order.get("state")) != STATE_CLAIMED:
			return false
	return true


## 交付检查：棋盘上必须同时存在 mission 全部物品（按 entity+level 计数，multiset）。
## 成功仅把状态置为 ready，不消耗物品；实际消耗在 claim。
func deliver(board, order_id: String) -> Dictionary:
	var order := get_order(order_id)
	if order.is_empty():
		return {"ok": false, "message": "订单不存在"}
	if state_of(order_id) != STATE_PENDING:
		return {"ok": false, "message": "订单状态不允许交付"}
	var available := _board_item_counts(board)
	for item_v in _mission_items(order):
		var item: Dictionary = item_v
		var key := _item_key(String(item["entity"]), int(item["level"]))
		var count := int(available.get(key, 0))
		if count <= 0:
			return {"ok": false, "message": "订单物品不在棋盘"}
		available[key] = count - 1
	order["state"] = STATE_READY
	return {"ok": true, "message": "订单可交付"}


## 领取订单：按 mission 顺序在棋盘上逐件消耗（行优先：y 外层、x 内层）。
## 先找齐全部格子再统一删除；任一缺失则返回失败且不改任何状态。
func claim(board, order_id: String, hud: Dictionary) -> Dictionary:
	var order := get_order(order_id)
	if order.is_empty():
		return _failure("订单不存在")
	if state_of(order_id) != STATE_READY:
		return _failure("订单未就绪")

	var positions: Array = []
	var used: Dictionary = {}
	for item_v in _mission_items(order):
		var item: Dictionary = item_v
		var pos := _find_first_cell(board, String(item["entity"]), int(item["level"]), used)
		if pos.is_empty():
			return _failure("订单物品不在棋盘")
		positions.append(pos)
		used[_pos_key(int(pos[0]), int(pos[1]))] = true

	for pos_v in positions:
		var pos: Array = pos_v
		board.remove_cell(int(pos[0]), int(pos[1]))

	var coin := _as_int(order.get("coin"), 0)
	var star := _as_int(order.get("star"), 0)
	hud["coin"] = _as_int(hud.get("coin"), 0) + coin
	hud["star"] = _as_int(hud.get("star"), 0) + star
	order["state"] = STATE_CLAIMED

	return {
		"ok": true,
		"message": "订单完成 +%d金币 +%d星" % [coin, star],
		"level_complete": all_claimed(),
		"star": star,
		"coin": coin,
	}


## 供 hash 使用的稳定快照：按 id 升序，只含 id 与 state。
func snapshot() -> Array:
	var result: Array = []
	for order_v in orders:
		var order: Dictionary = order_v
		result.append({
			"id": _string_or_empty(order.get("id")),
			"state": _string_or_empty(order.get("state")),
		})
	result.sort_custom(_compare_snapshot_entries)
	return result


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "level_complete": false, "star": 0, "coin": 0}


## mission -> [{"entity": String, "level": int}]；非法条目跳过（依赖 validator 先拦截）。
func _mission_items(order: Dictionary) -> Array:
	var items: Array = []
	var mission_v: Variant = order.get("mission")
	if typeof(mission_v) != TYPE_ARRAY:
		return items
	var mission: Array = mission_v
	for item_v in mission:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var entity_v: Variant = item.get("entity")
		if typeof(entity_v) != TYPE_STRING or String(entity_v).is_empty():
			continue
		var level_v: Variant = item.get("level")
		if typeof(level_v) != TYPE_INT and typeof(level_v) != TYPE_FLOAT:
			continue
		items.append({"entity": String(entity_v), "level": _as_int(level_v, 0)})
	return items


## 扫描棋盘全格，按 (entity, level) 计数。
func _board_item_counts(board) -> Dictionary:
	var counts: Dictionary = {}
	for y in range(int(board.height)):
		for x in range(int(board.width)):
			if not board.has_cell(x, y):
				continue
			var cell_v: Variant = board.get_cell(x, y)
			if typeof(cell_v) != TYPE_DICTIONARY:
				continue
			var cell: Dictionary = cell_v
			var entity_v: Variant = cell.get("entity")
			if typeof(entity_v) != TYPE_STRING:
				continue
			var key := _item_key(String(entity_v), _as_int(cell.get("level"), 0))
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


## 行优先（y 外层、x 内层）找第一个匹配 (entity, level) 且未被本次领取占用的格子。
func _find_first_cell(board, entity: String, item_level: int, used: Dictionary) -> Array:
	for y in range(int(board.height)):
		for x in range(int(board.width)):
			if used.has(_pos_key(x, y)):
				continue
			if not board.has_cell(x, y):
				continue
			var cell_v: Variant = board.get_cell(x, y)
			if typeof(cell_v) != TYPE_DICTIONARY:
				continue
			var cell: Dictionary = cell_v
			var entity_v: Variant = cell.get("entity")
			if typeof(entity_v) != TYPE_STRING or String(entity_v) != entity:
				continue
			if _as_int(cell.get("level"), 0) != item_level:
				continue
			return [x, y]
	return []


static func _item_key(entity: String, item_level: int) -> String:
	return "%s|%d" % [entity, item_level]


static func _pos_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _compare_snapshot_entries(a: Dictionary, b: Dictionary) -> bool:
	var id_a := _string_or_empty(a.get("id"))
	var id_b := _string_or_empty(b.get("id"))
	if id_a != id_b:
		return id_a < id_b
	return _string_or_empty(a.get("state")) < _string_or_empty(b.get("state"))


static func _string_or_empty(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""


## JSON 数字一律为 float：int-like 转换，非数字回退 fallback。
static func _as_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f):
			return int(f)
	return fallback
