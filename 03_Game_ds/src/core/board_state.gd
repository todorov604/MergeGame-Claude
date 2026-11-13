extends RefCounted
## Board grid for one level: occupied cells plus obstacles.
##
## Cells are keyed by Vector2i (x, y) and hold {"entity": String, "level": int}.
## Obstacles are keyed by the same Vector2i and hold an Array of type strings.
## Row-major order (y first, then x) is the only iteration order exposed by
## first_free_cell / sorted_cells, so scans stay deterministic.

var width: int = 7
var height: int = 9
var cells: Dictionary = {}
var obstacles: Dictionary = {}


func load_level(level_data: Dictionary) -> void:
	width = 7
	height = 9
	cells = {}
	obstacles = {}

	var b = level_data.get("board", null)
	if typeof(b) == TYPE_DICTIONARY:
		var board_data: Dictionary = b
		var w = board_data.get("width", 7)
		var h = board_data.get("height", 9)
		if typeof(w) == TYPE_INT or typeof(w) == TYPE_FLOAT:
			width = int(w)
		if typeof(h) == TYPE_INT or typeof(h) == TYPE_FLOAT:
			height = int(h)
		if width <= 0:
			width = 7
		if height <= 0:
			height = 9
		for s in board_data.get("slots", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var pos := _pos_from(s)
			if pos.x < 0 or not in_bounds(pos):
				continue
			var extra := {}
			if (s as Dictionary).has("mode"):
				extra["mode"] = String(s.get("mode", ""))
			if (s as Dictionary).has("sequence"):
				extra["sequence"] = s.get("sequence", [])
			put(pos, String(s.get("entity", "")), int(s.get("level", 1)),
					String(s.get("icon", "")), int(s.get("iconLevel", 0)), extra)

	var obs = level_data.get("obstacles", null)
	if typeof(obs) == TYPE_ARRAY:
		for o in obs:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var pos := _pos_or_neg(o.get("slot", null))
			if pos.x < 0 or not in_bounds(pos):
				continue
			var kind := String(o.get("type", ""))
			if kind.is_empty():
				continue
			add_obstacle(pos, kind)


func _pos_from(src) -> Vector2i:
	if typeof(src) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var d: Dictionary = src
	if d.has("x") and d.has("y"):
		return _vec(d["x"], d["y"])
	if d.has("slot"):
		return _pos_or_neg(d["slot"])
	return Vector2i(-1, -1)


func _vec(x, y) -> Vector2i:
	if not (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT):
		return Vector2i(-1, -1)
	if not (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT):
		return Vector2i(-1, -1)
	return Vector2i(int(x), int(y))


func _pos_or_neg(v) -> Vector2i:
	if typeof(v) != TYPE_ARRAY:
		return Vector2i(-1, -1)
	var arr: Array = v
	if arr.size() < 2:
		return Vector2i(-1, -1)
	return _vec(arr[0], arr[1])


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


func has_item(pos: Vector2i) -> bool:
	return cells.has(pos)


func item(pos: Vector2i) -> Dictionary:
	var v = cells.get(pos, {})
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v


## 2026-11-12：`icon` 是编辑器的图标覆盖（JSON 的 slot.icon），空 = 跟 entity。
## `extra` 带上这一格的生成器产出配置（mode / sequence），移动时要原样带走。
func put(pos: Vector2i, entity: String, level: int, icon: String = "", icon_level: int = 0,
		extra: Dictionary = {}) -> void:
	var item := {"entity": entity, "level": level}
	if not icon.is_empty():
		item["icon"] = icon
		# icon_level 只对"图标覆盖"有意义：空/0 = 用这一格自己的 level
		if icon_level > 0:
			item["icon_level"] = icon_level
	if extra.has("mode"):
		item["mode"] = String(extra.get("mode", ""))
	if extra.has("sequence"):
		item["sequence"] = (extra.get("sequence", []) as Array).duplicate(true)
	cells[pos] = item


func take(pos: Vector2i) -> Dictionary:
	if not cells.has(pos):
		return {}
	var v: Dictionary = cells[pos]
	cells.erase(pos)
	return v


func add_obstacle(pos: Vector2i, kind: String) -> void:
	if not obstacles.has(pos):
		obstacles[pos] = []
	var arr: Array = obstacles[pos]
	if not arr.has(kind):
		arr.append(kind)


func remove_obstacle(pos: Vector2i, kind: String) -> bool:
	if not obstacles.has(pos):
		return false
	var arr: Array = obstacles[pos]
	if not arr.has(kind):
		return false
	arr.erase(kind)
	if arr.is_empty():
		obstacles.erase(pos)
	return true


func is_blocked(pos: Vector2i) -> bool:
	if not obstacles.has(pos):
		return false
	var arr = obstacles[pos]
	return typeof(arr) == TYPE_ARRAY and not (arr as Array).is_empty()


func obstacle_types(pos: Vector2i) -> Array:
	var arr = obstacles.get(pos, [])
	if typeof(arr) != TYPE_ARRAY:
		return []
	return (arr as Array).duplicate()


## Row-major scan: y outer, x inner. Blocked cells are not free (a generator must
## never drop an item under a web / bubble / lock). Full -> Vector2i(-1, -1).
func first_free_cell() -> Vector2i:
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if cells.has(pos):
				continue
			if is_blocked(pos):
				continue
			return pos
	return Vector2i(-1, -1)


func item_count() -> int:
	return cells.size()


func sorted_cells() -> Array:
	var keys: Array = cells.keys()
	keys.sort_custom(func(a, b):
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return keys


func snapshot() -> Dictionary:
	var cell_rows: Array = []
	for pos in sorted_cells():
		var it: Dictionary = cells[pos]
		# 第 5 位是图标覆盖（没有就是空串），旧读者只用前 4 位，兼容
		cell_rows.append([pos.x, pos.y, String(it["entity"]), int(it["level"]),
				String(it.get("icon", "")), int(it.get("icon_level", 0))])

	var obs_rows: Array = []
	var okeys: Array = obstacles.keys()
	okeys.sort_custom(func(a, b):
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for pos in okeys:
		var types: Array = (obstacles[pos] as Array).duplicate()
		types.sort()
		obs_rows.append([pos.x, pos.y, types])

	return {
		"width": width,
		"height": height,
		"cells": cell_rows,
		"obstacles": obs_rows,
	}
