extends RefCounted
## Multi-cell "safebox" — pure decoration, placed by JSON coordinates.
##
## 2026-11-12（操作者改口径）：柜子不再由算法排布，改成关卡 JSON 里逐个数：
##
##   "safes": [
##     { "size": "2x4", "slot": [1, 6], "charges": 10, "level": 22 },
##     { "size": "1x7", "slot": [0, 8] }
##   ]
##
## `slot` 是**左上角锚点**；`size` 决定占位（1x7=7x1、2x2=2x2、2x3=3x2、2x4=4x2）。
## `charges`（画成 xN）默认 10，`level`（画成 Lv.N）默认 22。
##
## 旧的字符串写法 `["2x4","2x3"]`（只写尺寸、位置靠算法）**已废弃**：
## `validate_entries()` 会把它报成 SAFE_LEGACY_STRING。
##
## 规则上柜子只是"占格阻挡"：棋子不能落进去，爆炸不会破坏它，没有倒计时也没有解锁。

const SIZE_1X7 := "1x7"
const SIZE_2X2 := "2x2"
const SIZE_2X3 := "2x3"
const SIZE_2X4 := "2x4"

## One fixed overlay template for every safebox: identical sizes and offsets, only the
## two numbers change. All values are design pixels, centred on the box.
const TEMPLATE := {
	"bubble": 96.0,
	"bubble_offset_y": -8.0,
	"bolt": Vector2(42.0, 57.0),
	"bolt_offset_y": -26.0,
	"x_size": 30,
	"x_offset_y": 0.0,
	"frame": Vector2(84.0, 30.0),
	"frame_offset_y": 44.0,
	"lv_size": 20,
	"lv_pad_x": 10.0,
	"lock": Vector2(34.0, 40.0),
}

const BOX_SPECS := {
	"1x7": Vector2i(7, 1),
	"2x2": Vector2i(2, 2),
	"2x3": Vector2i(3, 2),
	"2x4": Vector2i(4, 2),
}


## 每个柜子的默认数值（JSON 不写时使用）
const DEFAULT_CHARGES := 10
const DEFAULT_LEVEL := 22


## 一个 size 在棋盘上占几格宽 / 几格高。
static func span_of(size: String) -> Vector2i:
	return BOX_SPECS.get(size, Vector2i.ZERO)


## 柜子覆盖的所有格子（左上角锚点 + 宽高）。
static func cells_of(size: String, x: int, y: int) -> Array:
	var spec := span_of(size)
	var out: Array = []
	for dy in spec.y:
		for dx in spec.x:
			out.append(Vector2i(x + dx, y + dy))
	return out


## 校验一关的 `safes` 声明。返回 `[{index, code, msg, cells}]`，空数组 = 全部合法。
## `occupied` 是"已经被占用的格子 -> 原因"（棋子 / 障碍），用于报"压住东西"。
static func validate_entries(entries, width: int, height: int, occupied: Dictionary = {}) -> Array:
	var errs: Array = []
	if entries == null:
		return errs
	if typeof(entries) != TYPE_ARRAY:
		errs.append({"index": -1, "code": "SAFE_TYPE", "msg": "safes must be an array", "cells": []})
		return errs
	var taken := {}
	for i in (entries as Array).size():
		var raw = entries[i]
		var tag := "safes[%d]" % i
		if typeof(raw) == TYPE_STRING:
			errs.append({"index": i, "code": "SAFE_LEGACY_STRING",
				"msg": "%s uses the removed string form \"%s\"; write {\"size\": \"%s\", \"slot\": [x, y]} instead" % [tag, String(raw), String(raw)],
				"cells": []})
			continue
		if typeof(raw) != TYPE_DICTIONARY:
			errs.append({"index": i, "code": "SAFE_TYPE", "msg": tag + " must be an object", "cells": []})
			continue
		var box: Dictionary = raw
		var size := String(box.get("size", ""))
		if not BOX_SPECS.has(size):
			errs.append({"index": i, "code": "SAFE_SIZE", "msg": tag + ".size must be one of " + str(BOX_SPECS.keys()), "cells": []})
			continue
		var slot = box.get("slot", null)
		if typeof(slot) != TYPE_ARRAY or (slot as Array).size() != 2:
			errs.append({"index": i, "code": "SAFE_SLOT", "msg": tag + ".slot must be [x, y]", "cells": []})
			continue
		var x := int((slot as Array)[0])
		var y := int((slot as Array)[1])
		var spec := span_of(size)
		if x < 0 or y < 0:
			errs.append({"index": i, "code": "SAFE_OOB", "msg": "%s (%s @ (%d,%d)) has a negative anchor" % [tag, size, x, y], "cells": []})
			continue
		if x + spec.x > width or y + spec.y > height:
			errs.append({"index": i, "code": "SAFE_OOB",
				"msg": "%s (%s @ (%d,%d)) is outside %dx%d: needs %dx%d" % [tag, size, x, y, width, height, spec.x, spec.y],
				"cells": []})
			continue
		for key in ["charges", "level"]:
			if box.has(key) and int(box.get(key, 0)) < 1:
				errs.append({"index": i, "code": "SAFE_NUMBER",
					"msg": "%s.%s must be an integer >= 1" % [tag, key], "cells": []})
		var cells := cells_of(size, x, y)
		var clash := ""
		for cell in cells:
			if taken.has(cell):
				clash = "overlaps %s at (%d,%d)" % [String(taken[cell]), cell.x, cell.y]
				break
			if occupied.has(cell):
				clash = "covers %s at (%d,%d)" % [String(occupied[cell]), cell.x, cell.y]
				break
		if not clash.is_empty():
			errs.append({"index": i, "code": "SAFE_OVERLAP", "msg": "%s (%s @ (%d,%d)) %s" % [tag, size, x, y, clash], "cells": cells})
			continue
		for cell in cells:
			taken[cell] = "safes[%d]" % i
	return errs


## sim / 成片用：只取合法的柜子，产出
## `{size, x, y, w, h, charges, level, cells}`（字段与 board_view.set_safeboxes 一致）。
static func parse(entries, width: int, height: int, occupied: Dictionary = {}) -> Array:
	var out: Array = []
	if entries == null or typeof(entries) != TYPE_ARRAY:
		return out
	for raw in (entries as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var box: Dictionary = raw
		var size := String(box.get("size", ""))
		if not BOX_SPECS.has(size):
			continue
		var slot = box.get("slot", null)
		if typeof(slot) != TYPE_ARRAY or (slot as Array).size() != 2:
			continue
		var x := int((slot as Array)[0])
		var y := int((slot as Array)[1])
		var spec := span_of(size)
		if x < 0 or y < 0 or x + spec.x > width or y + spec.y > height:
			continue
		var cells := cells_of(size, x, y)
		var blocked := false
		for cell in cells:
			if occupied.has(cell):
				blocked = true
				break
		if blocked:
			continue
		out.append({
			"size": size, "x": x, "y": y, "w": spec.x, "h": spec.y,
			"charges": maxi(int(box.get("charges", DEFAULT_CHARGES)), 1),
			"level": maxi(int(box.get("level", DEFAULT_LEVEL)), 1),
			"cells": cells,
		})
		for cell in cells:
			occupied[cell] = "safebox"
	return out


## Cells covered by the layout, so the sim can mark them blocked.
static func cells(boxes: Array) -> Array:
	var out: Array = []
	for box in boxes:
		if typeof(box) != TYPE_DICTIONARY:
			continue
		for dy in int((box as Dictionary).get("h", 0)):
			for dx in int((box as Dictionary).get("w", 0)):
				out.append(Vector2i(int(box["x"]) + dx, int(box["y"]) + dy))
	return out
