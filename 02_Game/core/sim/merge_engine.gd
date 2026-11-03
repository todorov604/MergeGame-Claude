extends RefCounted

## 合成规则（M0 冻结规格 §1 / §3.4）：同 entity + 同 level -> level+1。
## M0 明确允许不相邻合并，相邻性不在本层检查；board 由调用方传入。

## 从 from 合并到 to；返回 {"ok", "message", "entity", "level"}。
func merge(board, from: Array, to: Array, max_level: int) -> Dictionary:
	var from_xy: Array = _parse_coords(from)
	var to_xy: Array = _parse_coords(to)
	if from_xy.is_empty() or to_xy.is_empty():
		return _failure("坐标非法")
	var from_x := int(from_xy[0])
	var from_y := int(from_xy[1])
	var to_x := int(to_xy[0])
	var to_y := int(to_xy[1])
	if not board.in_bounds(from_x, from_y) or not board.in_bounds(to_x, to_y):
		return _failure("坐标非法")
	if board.has_obstacle(from_x, from_y) or board.has_obstacle(to_x, to_y):
		return _failure("存在障碍，无法合并")

	var from_cell: Dictionary = board.get_cell(from_x, from_y)
	if from_cell.is_empty():
		return _failure("起始格为空")
	var to_cell: Dictionary = board.get_cell(to_x, to_y)
	if to_cell.is_empty():
		return _failure("目标格为空")

	var from_entity: Variant = from_cell.get("entity")
	var to_entity: Variant = to_cell.get("entity")
	if from_entity != to_entity:
		return _failure("实体不同")
	var from_level := int(from_cell.get("level", 0))
	var to_level := int(to_cell.get("level", 0))
	if from_level != to_level:
		return _failure("等级不同")
	if to_level >= max_level:
		return _failure("达到等级上限")

	var entity := String(from_entity)
	var new_level := to_level + 1
	board.remove_cell(from_x, from_y)
	board.set_cell(to_x, to_y, entity, new_level)
	return {
		"ok": true,
		"message": "合成 %s Lv%d" % [entity, new_level],
		"entity": entity,
		"level": new_level,
	}


func _parse_coords(value: Array) -> Array:
	if value.size() != 2:
		return []
	if not _is_int_like(value[0]) or not _is_int_like(value[1]):
		return []
	return [int(value[0]), int(value[1])]


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"entity": "",
		"level": 0,
	}


## Godot JSON 把数字都解析成 float：TYPE_INT，或有限且等于 floor 的 float。
static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var f := float(value)
	return is_finite(f) and f == floor(f)
