extends RefCounted

## 生成器规则（M0 冻结规格 §2）：点击产出、次数/冷却、稀有直出订单物品、棋盘满。
## 与 board 的交互只通过 BoardState 的公开 API；随机数只使用调用方传入的 rng。

var config: Dictionary = {}   # project.generators
var states: Dictionary = {}   # entity_id -> {"charges": int, "next_time": float}


func setup(generators_config: Dictionary) -> void:
	config = generators_config
	states.clear()


## 换关时调用；下次 tap 时按 config 懒初始化。
func reset() -> void:
	states = {}


## 点击生成器。返回 {"ok", "message", "board_full", "entity", "level", "direct_order"}。
func tap(project_data: Dictionary, board, slot: Array, at_time: float, rng) -> Dictionary:
	# 1) 坐标
	var coords: Array = _parse_coords(slot)
	if coords.is_empty():
		return _failure("坐标非法")
	var x := int(coords[0])
	var y := int(coords[1])
	if not board.in_bounds(x, y):
		return _failure("坐标非法")

	# 2) 目标格必须有 cell
	var cell: Dictionary = board.get_cell(x, y)
	if cell.is_empty():
		return _failure("目标格没有生成器")

	# 3) 实体必须声明为 generator，且 config 里存在对应行为
	var entity_id := ""
	var entity_v: Variant = cell.get("entity")
	if typeof(entity_v) == TYPE_STRING:
		entity_id = String(entity_v)
	if entity_id.is_empty() or not _is_generator(project_data, entity_id):
		return _failure("目标不是生成器")
	var generator_v: Variant = config.get(entity_id)
	if typeof(generator_v) != TYPE_DICTIONARY:
		return _failure("目标不是生成器")
	var generator: Dictionary = generator_v

	# 4) 状态懒初始化
	if not states.has(entity_id):
		states[entity_id] = {
			"charges": _int_or_zero(generator.get("charges")),
			"next_time": 0.0,
		}
	var state: Dictionary = states[entity_id]

	# 5) 冷却
	var next_time := _float_or_zero(state.get("next_time"))
	if at_time < next_time:
		return _failure("冷却中")

	# 6) 次数
	var charges := int(state.get("charges", 0))
	if charges <= 0:
		return _failure("次数用尽")

	# 7) 棋盘已满：不扣次数、不更新时间
	var empty: Array = board.first_empty_slot()
	if empty.is_empty():
		return _failure("棋盘已满", true)

	# 8) 权重表：先 outputs（按数组顺序），再 rareOutputs
	var table: Array = []
	var total := _collect_entries(table, generator.get("outputs"), false)
	total += _collect_entries(table, generator.get("rareOutputs"), true)
	if total <= 0.0:
		return _failure("产出表为空")

	# 9) 顺序累加选中，写入第一个空位
	var roll: float = float(rng.randf()) * total
	var chosen: Dictionary = table[table.size() - 1]
	var accumulated := 0.0
	for entry_v in table:
		var entry: Dictionary = entry_v
		accumulated += float(entry["weight"])
		if roll < accumulated:
			chosen = entry
			break

	var entity := String(chosen["entity"])
	var level := int(chosen["level"])
	var direct_order := bool(chosen["direct_order"])
	board.set_cell(int(empty[0]), int(empty[1]), entity, level)
	state["charges"] = charges - 1
	state["next_time"] = at_time + _float_or_zero(generator.get("cooldown"))
	return {
		"ok": true,
		"message": "产出 %s Lv%d" % [entity, level],
		"board_full": false,
		"entity": entity,
		"level": level,
		"direct_order": direct_order,
	}


## outputs 与 rareOutputs 共用：weight 必须是 >0 的数字；返回加入的总权重。
func _collect_entries(target: Array, items_v: Variant, is_rare: bool) -> float:
	var added := 0.0
	if typeof(items_v) != TYPE_ARRAY:
		return added
	var items: Array = items_v
	for item_v in items:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var entity_v: Variant = item.get("entity")
		if typeof(entity_v) != TYPE_STRING or String(entity_v).is_empty():
			continue
		var weight_v: Variant = item.get("weight")
		if typeof(weight_v) != TYPE_INT and typeof(weight_v) != TYPE_FLOAT:
			continue
		var weight := float(weight_v)
		if not (weight > 0.0):
			continue
		var level := 1
		var level_v: Variant = item.get("level")
		if _is_int_like(level_v):
			level = int(level_v)
		var direct_order := false
		if is_rare:
			var direct_v: Variant = item.get("directOrder")
			if typeof(direct_v) == TYPE_BOOL:
				direct_order = bool(direct_v)
		target.append({
			"entity": String(entity_v),
			"level": level,
			"direct_order": direct_order,
			"weight": weight,
		})
		added += weight
	return added


func _is_generator(project_data: Dictionary, entity_id: String) -> bool:
	var entities_v: Variant = project_data.get("entities")
	if typeof(entities_v) != TYPE_DICTIONARY:
		return false
	var entities: Dictionary = entities_v
	var entity_v: Variant = entities.get(entity_id)
	if typeof(entity_v) != TYPE_DICTIONARY:
		return false
	var entity: Dictionary = entity_v
	var kind_v: Variant = entity.get("kind")
	return typeof(kind_v) == TYPE_STRING and String(kind_v) == "generator"


func _parse_coords(value: Array) -> Array:
	if value.size() != 2:
		return []
	if not _is_int_like(value[0]) or not _is_int_like(value[1]):
		return []
	return [int(value[0]), int(value[1])]


func _failure(message: String, board_full: bool = false) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"board_full": board_full,
		"entity": "",
		"level": 0,
		"direct_order": false,
	}


static func _int_or_zero(value: Variant) -> int:
	if _is_int_like(value):
		return int(value)
	return 0


static func _float_or_zero(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return 0.0


## Godot JSON 把数字都解析成 float：TYPE_INT，或有限且等于 floor 的 float。
static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var f := float(value)
	return is_finite(f) and f == floor(f)
