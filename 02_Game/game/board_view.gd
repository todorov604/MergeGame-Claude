extends Control

## M0 第 1 周第 3 步：静态棋盘 View（7×9 格、chip、选中、完成、障碍）。
## 全部自绘；棋盘框与字体来自 assets.json，并经 AssetLoader 守卫。
## 本周只做静态：不接时间轴播放 / 动画 / 订单 UI。

const AssetLoader := preload("res://game/asset_loader.gd")

const DESIGN_SIZE := Vector2(1080.0, 1920.0)
const BOARD_ORIGIN := Vector2(48.0, 466.0)
const BOARD_SIZE := Vector2(983.0, 1263.0)
const CELL_INSET := 7.0
const CHIP_INSET := 17.0
const SELECT_HEX := "#ffd83d"
const COMPLETE_HEX := "#3ddc6a"

var project_data: Dictionary = {}
var snapshot: Dictionary = {}
var selection: Array = []
var completed: Array = []
var allow_placeholders := true
var loader = null

var _palette: Array[Color] = [
	Color("#ff8a5c"),
	Color("#5cc8ff"),
	Color("#a07cff"),
	Color("#6be585"),
	Color("#ffd83d"),
	Color("#ff6fa5"),
	Color("#4fd1c5"),
	Color("#c0d3e8"),
]
var _font_cache: Font = null


func setup(project_data_arg: Dictionary, snapshot_arg: Dictionary, selection_arg: Array, completed_arg: Array, allow_placeholders_flag = true) -> void:
	project_data = project_data_arg
	snapshot = snapshot_arg
	selection = selection_arg
	completed = completed_arg
	allow_placeholders = bool(allow_placeholders_flag)
	_font_cache = null
	loader = AssetLoader.new()
	loader.setup("res://assets/assets.json", bool(allow_placeholders_flag))
	queue_redraw()


func refresh(snapshot_arg: Dictionary) -> void:
	snapshot = snapshot_arg
	queue_redraw()


func cell_center(x: int, y: int) -> Vector2:
	return _cell_rect(x, y).get_center()


func cell_center_global(x: int, y: int) -> Vector2:
	return global_position + cell_center(x, y)


func slot_count() -> int:
	var dims := _board_dims()
	return dims.x * dims.y


func cell_count() -> int:
	var board := _snapshot_board()
	var cells_v: Variant = board.get("cells", [])
	if typeof(cells_v) != TYPE_ARRAY:
		return 0
	return (cells_v as Array).size()


func obstacle_count() -> int:
	var board := _snapshot_board()
	var obstacles_v: Variant = board.get("obstacles", [])
	if typeof(obstacles_v) != TYPE_ARRAY:
		return 0
	return (obstacles_v as Array).size()


func _draw() -> void:
	_draw_background()
	_draw_board_frame()
	_draw_slots()
	_draw_chips()
	_draw_obstacles()
	_draw_selection()
	_draw_completed()


func _draw_background() -> void:
	var canvas := size
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		canvas = DESIGN_SIZE
	var top := Color("#35455f")
	var bottom := Color("#101a2b")
	var bands := 32
	var band_height := canvas.y / float(bands)
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(0.0, band_height * float(i), canvas.x, band_height + 1.0), top.lerp(bottom, t))
	# 顶部柔光 + 底部暗角，增强竖向渐变感。
	draw_circle(Vector2(canvas.x * 0.5, canvas.y * 0.18), canvas.x * 0.55, Color(0.45, 0.6, 0.85, 0.10))
	draw_rect(Rect2(0.0, canvas.y * 0.82, canvas.x, canvas.y * 0.18), Color(0.02, 0.04, 0.08, 0.35))


func _draw_board_frame() -> void:
	var rect := Rect2(BOARD_ORIGIN, BOARD_SIZE)
	if loader != null:
		var result: Dictionary = loader.load_texture("board_frame")
		if bool(result.get("ok", false)):
			var texture_v: Variant = result.get("texture")
			if texture_v is Texture2D:
				draw_texture_rect(texture_v as Texture2D, rect, false)
				return
	# 守卫失败或无图时自绘圆角蓝框 + 边框。
	draw_style_box(_make_style(Color("#24415f"), 36, Color("#7fb2e5"), 6), rect)


func _draw_slots() -> void:
	var dims := _board_dims()
	for y in range(dims.y):
		for x in range(dims.x):
			var rect := _cell_rect(x, y).grow(-CELL_INSET)
			var fill := Color("#223550") if ((x + y) % 2) == 0 else Color("#2a4160")
			draw_style_box(_make_style(fill, 12, Color("#1a2a40"), 2), rect)


func _draw_chips() -> void:
	var board := _snapshot_board()
	var cells_v: Variant = board.get("cells", [])
	if typeof(cells_v) != TYPE_ARRAY:
		return
	var cells: Array = cells_v
	var dims := _board_dims()
	var font := _ui_font()
	for cell_v in cells:
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v
		var x := _int_field(cell, "x")
		var y := _int_field(cell, "y")
		if x < 0 or y < 0 or x >= dims.x or y >= dims.y:
			continue
		var entity := _string_field(cell, "entity")
		if entity.is_empty():
			continue
		_draw_chip(x, y, entity, _int_field(cell, "level"), font)


func _draw_chip(x: int, y: int, entity: String, level: int, font: Font) -> void:
	var chip_rect := _cell_rect(x, y).grow(-CHIP_INSET)
	var fill := _entity_color(entity)
	var border := fill.lightened(clampf(0.22 + 0.06 * float(maxi(level, 0)), 0.22, 0.9))
	draw_style_box(_make_style(fill, 20, border, 4), chip_rect)

	var center := chip_rect.get_center()
	_draw_text_centered(font, "Lv%d" % level, Vector2(center.x, center.y - chip_rect.size.y * 0.16), 24, Color(1.0, 1.0, 1.0, 0.95))
	_draw_text_centered(font, entity.substr(0, 8), Vector2(center.x, center.y + chip_rect.size.y * 0.16), 20, Color(1.0, 1.0, 1.0, 0.8))


func _draw_obstacles() -> void:
	var board := _snapshot_board()
	var obstacles_v: Variant = board.get("obstacles", [])
	if typeof(obstacles_v) != TYPE_ARRAY:
		return
	var dims := _board_dims()
	var obstacles: Array = obstacles_v
	for obstacle_v in obstacles:
		if typeof(obstacle_v) != TYPE_DICTIONARY:
			continue
		var obstacle: Dictionary = obstacle_v
		var x := _int_field(obstacle, "x")
		var y := _int_field(obstacle, "y")
		if not _in_bounds(Vector2i(x, y), dims):
			continue
		match _string_field(obstacle, "type"):
			"lock":
				_draw_lock(x, y)
			"web":
				_draw_web(x, y)
			"bubble":
				_draw_bubble(x, y)


func _draw_lock(x: int, y: int) -> void:
	var rect := _cell_rect(x, y).grow(-CELL_INSET)
	draw_style_box(_make_style(Color(0.42, 0.45, 0.5, 0.88), 16, Color(0.27, 0.29, 0.33, 0.9), 3), rect)
	var center := rect.get_center()
	var dark := Color("#20242c")
	draw_arc(center + Vector2(0.0, -6.0), 20.0, PI, TAU, 28, dark, 9.0, true)
	draw_rect(Rect2(center + Vector2(-30.0, -8.0), Vector2(60.0, 46.0)), dark, true)
	draw_circle(center + Vector2(0.0, 8.0), 6.0, Color(0.75, 0.78, 0.82, 0.9))


func _draw_web(x: int, y: int) -> void:
	var rect := _cell_rect(x, y).grow(-CELL_INSET - 4.0)
	var line_color := Color(0.88, 0.9, 0.96, 0.72)
	var line_width := 3.0
	var top_left := rect.position
	var top_right := rect.position + Vector2(rect.size.x, 0.0)
	var bottom_right := rect.position + rect.size
	var bottom_left := rect.position + Vector2(0.0, rect.size.y)
	draw_line(top_left.lerp(bottom_right, 0.16), bottom_right.lerp(top_left, 0.16), line_color, line_width, true)
	draw_line(top_right.lerp(bottom_left, 0.16), bottom_left.lerp(top_right, 0.16), line_color, line_width, true)
	var center := rect.get_center()
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.position.x + rect.size.x, center.y), line_color, line_width * 0.8, true)
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.position.y + rect.size.y), line_color, line_width * 0.8, true)
	draw_arc(center, minf(rect.size.x, rect.size.y) * 0.22, 0.0, TAU, 24, line_color, line_width * 0.8, true)


func _draw_bubble(x: int, y: int) -> void:
	var rect := _cell_rect(x, y).grow(-CELL_INSET)
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.42
	draw_circle(center, radius, Color(0.7, 0.88, 1.0, 0.10))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.7, 0.88, 1.0, 0.8), 7.0, true)
	draw_arc(center, radius * 0.72, PI * 1.12, PI * 1.62, 20, Color(1.0, 1.0, 1.0, 0.55), 5.0, true)
	draw_circle(center + Vector2(-radius * 0.42, -radius * 0.46), radius * 0.12, Color(1.0, 1.0, 1.0, 0.85))


func _draw_selection() -> void:
	var dims := _board_dims()
	for item_v in selection:
		var xy := _parse_xy(item_v)
		if not _in_bounds(xy, dims):
			continue
		var rect := _cell_rect(xy.x, xy.y).grow(-3.0)
		var style := _make_style(Color(0.0, 0.0, 0.0, 0.0), 16, Color(SELECT_HEX), 6)
		style.draw_center = false
		draw_style_box(style, rect)


func _draw_completed() -> void:
	var dims := _board_dims()
	for item_v in completed:
		var xy := _parse_xy(item_v)
		if not _in_bounds(xy, dims):
			continue
		var rect := _cell_rect(xy.x, xy.y).grow(-CELL_INSET)
		var center := rect.position + Vector2(rect.size.x * 0.82, rect.size.y * 0.18)
		var radius := minf(rect.size.x, rect.size.y) * 0.16
		draw_circle(center, radius, Color(COMPLETE_HEX))
		draw_arc(center, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.9), 2.0, true)
		var check_scale := radius * 0.55
		var check_color := Color.WHITE
		draw_line(center + Vector2(-0.75 * check_scale, 0.0), center + Vector2(-0.1 * check_scale, 0.55 * check_scale), check_color, 4.0, true)
		draw_line(center + Vector2(-0.1 * check_scale, 0.55 * check_scale), center + Vector2(0.8 * check_scale, -0.5 * check_scale), check_color, 4.0, true)


func _board_dims() -> Vector2i:
	var board := _snapshot_board()
	var w := _int_field(board, "width")
	var h := _int_field(board, "height")
	if w <= 0 or h <= 0:
		var level := _current_level_dict()
		var level_board: Dictionary = {}
		var board_v: Variant = level.get("board")
		if typeof(board_v) == TYPE_DICTIONARY:
			level_board = board_v as Dictionary
		w = _int_field(level_board, "width")
		h = _int_field(level_board, "height")
	if w <= 0 or h <= 0:
		return Vector2i(0, 0)
	return Vector2i(w, h)


func _snapshot_board() -> Dictionary:
	var board_v: Variant = snapshot.get("board")
	if typeof(board_v) == TYPE_DICTIONARY:
		return board_v as Dictionary
	return {}


func _current_level_dict() -> Dictionary:
	var levels_v: Variant = project_data.get("levels")
	if typeof(levels_v) != TYPE_ARRAY:
		return {}
	var levels: Array = levels_v
	if levels.is_empty():
		return {}
	var index := 0
	var level_snap_v: Variant = snapshot.get("level")
	if typeof(level_snap_v) == TYPE_DICTIONARY:
		index = _int_field(level_snap_v as Dictionary, "index")
	index = clampi(index, 0, levels.size() - 1)
	var level_v: Variant = levels[index]
	if typeof(level_v) == TYPE_DICTIONARY:
		return level_v as Dictionary
	return {}


func _cell_rect(x: int, y: int) -> Rect2:
	var dims := _board_dims()
	var cell_size := Vector2(BOARD_SIZE.x / float(dims.x), BOARD_SIZE.y / float(dims.y))
	return Rect2(BOARD_ORIGIN + Vector2(float(x) * cell_size.x, float(y) * cell_size.y), cell_size)


func _entity_color(entity: String) -> Color:
	# djb2 稳定哈希：同一 entity 跨运行得到同一颜色。
	var hash_value := 5381
	for i in range(entity.length()):
		hash_value = (hash_value * 33 + entity.unicode_at(i)) % 2147483647
	return _palette[hash_value % _palette.size()]


func _ui_font() -> Font:
	if _font_cache != null:
		return _font_cache
	if loader != null:
		var en: Dictionary = loader.load_font("font_en")
		var en_font: Variant = en.get("font")
		if bool(en.get("ok", false)) and en_font is Font:
			_font_cache = en_font
		else:
			var zh: Dictionary = loader.load_font("font_zh")
			var zh_font: Variant = zh.get("font")
			if bool(zh.get("ok", false)) and zh_font is Font:
				_font_cache = zh_font
	if _font_cache == null:
		_font_cache = ThemeDB.fallback_font
	return _font_cache


func _make_style(fill: Color, corner: int, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(corner)
	style.set_border_width_all(border_width)
	style.border_color = border
	return style


func _draw_text_centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2(center.x - text_size.x * 0.5, baseline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _in_bounds(xy: Vector2i, dims: Vector2i) -> bool:
	return xy.x >= 0 and xy.y >= 0 and xy.x < dims.x and xy.y < dims.y


func _parse_xy(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(_to_int(arr[0]), _to_int(arr[1]))
	elif typeof(value) == TYPE_VECTOR2I:
		var v2i: Vector2i = value
		return v2i
	elif typeof(value) == TYPE_VECTOR2:
		var v2: Vector2 = value
		return Vector2i(int(v2.x), int(v2.y))
	return Vector2i(-1, -1)


static func _int_field(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return 0


static func _string_field(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key, "")
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""


static func _to_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		return int(value)
	return -1
