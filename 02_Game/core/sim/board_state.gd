extends RefCounted

## 棋盘状态（M0 冻结规格 §2 数据模型 v2）：网格、实体格与障碍物。
## 纯数据层，不依赖 Node / SceneTree；遍历顺序一律显式（行优先 y -> x）。

const OBSTACLE_TYPES := ["lock", "web", "bubble", "ice"]

var width := 0
var height := 0
var cells: Dictionary = {}      # "x,y" -> {"entity": String, "level": int}
var obstacles: Dictionary = {}  # "x,y" -> String（lock/web/bubble/ice）


func setup(w: int, h: int) -> void:
	width = w
	height = h
	cells.clear()
	obstacles.clear()


## 从关卡数据装载棋盘；坐标或字段非法的条目跳过，不崩溃。
func load_from_level(level: Dictionary) -> void:
	setup(0, 0)
	var board_v: Variant = level.get("board")
	if typeof(board_v) == TYPE_DICTIONARY:
		var board: Dictionary = board_v
		setup(_dimension(board.get("width")), _dimension(board.get("height")))
		_load_slots(board.get("slots"))
	_load_obstacles(level.get("obstacles"))


## 载入后把等级夹到 [1, min(hard_cap, 实体 maxLevel)]；M0 等级上限 10。
func clamp_levels(entities: Dictionary, hard_cap: int) -> void:
	for cell_key in cells.keys():
		var cell: Dictionary = cells[cell_key]
		var entity_id := ""
		var entity_v: Variant = cell.get("entity")
		if typeof(entity_v) == TYPE_STRING:
			entity_id = String(entity_v)
		var max_level := hard_cap
		var def_v: Variant = entities.get(entity_id, {})
		if typeof(def_v) == TYPE_DICTIONARY:
			var def: Dictionary = def_v
			var max_level_v: Variant = def.get("maxLevel")
			if _is_int_like(max_level_v) and int(max_level_v) > 0:
				max_level = mini(hard_cap, int(max_level_v))
		cell["level"] = clampi(int(cell.get("level", 1)), 1, max_level)


func key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func has_obstacle(x: int, y: int) -> bool:
	return obstacles.has(key(x, y))


func obstacle_type(x: int, y: int) -> String:
	var type_v: Variant = obstacles.get(key(x, y), "")
	if typeof(type_v) == TYPE_STRING:
		return String(type_v)
	return ""


func has_cell(x: int, y: int) -> bool:
	return cells.has(key(x, y))


func get_cell(x: int, y: int) -> Dictionary:
	var cell: Dictionary = cells.get(key(x, y), {})
	return cell


func set_cell(x: int, y: int, entity: String, level: int) -> void:
	cells[key(x, y)] = {"entity": entity, "level": level}


func remove_cell(x: int, y: int) -> void:
	cells.erase(key(x, y))


func is_empty_slot(x: int, y: int) -> bool:
	return in_bounds(x, y) and not has_obstacle(x, y) and not has_cell(x, y)


## 行优先扫描：for y in 0..height-1，for x in 0..width-1；无空位返回 []。
func first_empty_slot() -> Array:
	for y in range(height):
		for x in range(width):
			if is_empty_slot(x, y):
				return [x, y]
	return []


func count_cells() -> int:
	return cells.size()


## 确定性快照（供状态 hash）：cells / obstacles 都按 y 再 x 升序。
func snapshot() -> Dictionary:
	var cell_list: Array = []
	for cell_key in cells.keys():
		var cell_xy: Array = _split_key(String(cell_key))
		if cell_xy.is_empty():
			continue
		var cell: Dictionary = cells[cell_key]
		cell_list.append({
			"x": int(cell_xy[0]),
			"y": int(cell_xy[1]),
			"entity": String(cell.get("entity", "")),
			"level": int(cell.get("level", 0)),
		})
	cell_list.sort_custom(_compare_xy)

	var obstacle_list: Array = []
	for obstacle_key in obstacles.keys():
		var obstacle_xy: Array = _split_key(String(obstacle_key))
		if obstacle_xy.is_empty():
			continue
		obstacle_list.append({
			"x": int(obstacle_xy[0]),
			"y": int(obstacle_xy[1]),
			"type": String(obstacles[obstacle_key]),
		})
	obstacle_list.sort_custom(_compare_xy)

	return {
		"width": width,
		"height": height,
		"cells": cell_list,
		"obstacles": obstacle_list,
	}


func _load_slots(slots_v: Variant) -> void:
	if typeof(slots_v) != TYPE_ARRAY:
		return
	var slots: Array = slots_v
	for i in range(slots.size()):
		var slot_v: Variant = slots[i]
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_v
		var x_v: Variant = slot.get("x")
		var y_v: Variant = slot.get("y")
		if not _is_int_like(x_v) or not _is_int_like(y_v):
			continue
		var x := int(x_v)
		var y := int(y_v)
		if not in_bounds(x, y):
			continue
		var entity_v: Variant = slot.get("entity")
		if typeof(entity_v) != TYPE_STRING or String(entity_v).is_empty():
			continue
		var level_v: Variant = slot.get("level")
		if not _is_int_like(level_v) or int(level_v) < 1:
			continue
		set_cell(x, y, String(entity_v), int(level_v))


func _load_obstacles(obstacles_v: Variant) -> void:
	if typeof(obstacles_v) != TYPE_ARRAY:
		return
	var obstacle_list: Array = obstacles_v
	for i in range(obstacle_list.size()):
		var obstacle_v: Variant = obstacle_list[i]
		if typeof(obstacle_v) != TYPE_DICTIONARY:
			continue
		var obstacle: Dictionary = obstacle_v
		var slot_v: Variant = obstacle.get("slot")
		if typeof(slot_v) != TYPE_ARRAY:
			continue
		var coords: Array = slot_v
		if coords.size() != 2:
			continue
		if not _is_int_like(coords[0]) or not _is_int_like(coords[1]):
			continue
		var x := int(coords[0])
		var y := int(coords[1])
		if not in_bounds(x, y):
			continue
		var type_v: Variant = obstacle.get("type")
		if typeof(type_v) != TYPE_STRING:
			continue
		var type_text := String(type_v)
		if not (type_text in OBSTACLE_TYPES):
			continue
		obstacles[key(x, y)] = type_text


func _compare_xy(a: Dictionary, b: Dictionary) -> bool:
	if int(a["y"]) != int(b["y"]):
		return int(a["y"]) < int(b["y"])
	return int(a["x"]) < int(b["x"])


static func _split_key(text: String) -> Array:
	var parts := text.split(",")
	if parts.size() != 2:
		return []
	var x_text := parts[0].strip_edges()
	var y_text := parts[1].strip_edges()
	if not x_text.is_valid_int() or not y_text.is_valid_int():
		return []
	return [x_text.to_int(), y_text.to_int()]


static func _dimension(value: Variant) -> int:
	if not _is_int_like(value):
		return 0
	var size := int(value)
	if size < 0:
		return 0
	return size


## Godot JSON 把数字都解析成 float：TYPE_INT，或有限且等于 floor 的 float。
static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var f := float(value)
	return is_finite(f) and f == floor(f)
