extends RefCounted
## Multi-cell "safebox" layout for the bottom of the board.
##
## Four art sizes exist (1x7 / 2x2 / 2x3 / 2x4). The layout is a pure function of
## (board size, seed, level index) so the live board and the film place the boxes on
## the same cells, and the sim can block exactly those cells.
##
##  * 1x7  : pinned to the last row (the wide locker row)
##  * 2x4 + 2x3 : the two rows right above it, order shuffled
##  * 2x2  : two rows above that, random column
##
## Each box also carries its two labels: the lightning charge (<= 30) and the
## level badge (10..20), both drawn with the project display font.

const Rng := preload("res://src/core/rng.gd")

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


## `sizes` is the level's declaration (e.g. ["1x7","2x4","2x3","2x2"]); an empty list
## means the level has no safeboxes at all, so every other fixture stays unchanged.
static func layout(width: int, height: int, seed_value: int, level_index: int, sizes: Array,
		avoid: Array = []) -> Array:
	var out: Array = []
	if width <= 0 or height <= 0 or sizes.is_empty():
		return out
	var rng = Rng.make(seed_value + 9173, 7 + level_index)

	# 2026-11-09: 宽的 1x7 柜子可以要**多个**（操作者：多加几个 7*1 那样的盒子）。
	# 从最后一行往上叠，一行一个；行数不够就停止。原来只认一个，多写的会被静默丢掉。
	var wide: Vector2i = BOX_SPECS[SIZE_1X7]
	var wide_count := 0
	for size in sizes:
		if String(size) == SIZE_1X7:
			wide_count += 1
	for i in wide_count:
		var row := height - wide.y - i
		if row < 0:
			break
		out.append(_box(SIZE_1X7, 0, row, mini(wide.x, width), wide.y, rng))

	# Two-row boxes pack left to right, one shuffled order, overflowing upwards.
	var tall: Array = []
	for size in sizes:
		if size != SIZE_1X7 and BOX_SPECS.has(size):
			tall.append(String(size))
	# deterministic shuffle (Fisher-Yates on the layout RNG)
	for i in range(tall.size() - 1, 0, -1):
		var j: int = rng.next_int(i + 1)
		var tmp = tall[i]
		tall[i] = tall[j]
		tall[j] = tmp

	# Cells already holding level items must stay playable, so a box slides right (or
	# up a band) until it no longer covers one of them.
	var blocked := {}
	for cell in avoid:
		if typeof(cell) == TYPE_VECTOR2I:
			blocked[cell] = true
		elif typeof(cell) == TYPE_ARRAY and (cell as Array).size() >= 2:
			blocked[Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))] = true

	# Without the wide locker the two-row boxes anchor to the very bottom row instead
	# of leaving an empty row underneath them.
	var cursor_x := 0
	var band_y := height - (2 + wide_count)
	# Keep every box inside the bottom four rows: a box that cannot fit there is
	# dropped instead of floating in the middle of the board.
	var band_floor := maxi(height - 5 - wide_count, 0)
	for size in tall:
		var spec: Vector2i = BOX_SPECS[size]
		if spec.y > height:
			continue
		var placed := false
		while band_y >= band_floor:
			if cursor_x + spec.x > width:
				cursor_x = 0
				band_y -= spec.y
				continue
			if _overlaps(cursor_x, band_y, spec.x, spec.y, blocked):
				cursor_x += 1
				continue
			out.append(_box(String(size), cursor_x, band_y, spec.x, spec.y, rng))
			cursor_x += spec.x
			placed = true
			break
		if not placed:
			break
	return out


static func _overlaps(x: int, y: int, w: int, h: int, blocked: Dictionary) -> bool:
	for dy in h:
		for dx in w:
			if blocked.has(Vector2i(x + dx, y + dy)):
				return true
	return false


static func _box(size: String, x: int, y: int, w: int, h: int, rng) -> Dictionary:
	return {
		"size": size,
		"x": x,
		"y": y,
		"w": w,
		"h": h,
		"charges": 1 + rng.next_int(30),
		"level": 10 + rng.next_int(11),
	}


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
