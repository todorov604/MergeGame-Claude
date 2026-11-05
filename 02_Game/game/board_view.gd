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
const HINT_CHIP_SCALE := 1.08
const HINT_CHIP_OFFSET := 6.0
const SELECT_HEX := "#ffd83d"
const COMPLETE_HEX := "#3ddc6a"
## 棋盘.psd §20.5 布局数值。
const BG_BOTTOM_RECT := Rect2(0.0, 384.0, 1080.0, 1536.0)
const BG_TOP_RECT := Rect2(0.0, 0.0, 1080.0, 400.0)
const ITEMS_RECT := Rect2(193.0, 1731.0, 693.0, 183.0)
const EXIT_RECT := Rect2(20.0, 1734.0, 164.0, 174.0)
const CABINET_RECT := Rect2(938.0, 1739.0, 109.0, 147.0)
const CHIP_ICON_MAX := 140.0

var project_data: Dictionary = {}
var snapshot: Dictionary = {}
var selection: Array = []
var completed: Array = []
var _hint_slots: Array = []
var allow_placeholders := true
var loader = null
var theme_doc = null

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
var _texture_cache: Dictionary = {}
var _shadow_style: StyleBoxFlat = null


func setup(project_data_arg: Dictionary, snapshot_arg: Dictionary, selection_arg: Array, completed_arg: Array, allow_placeholders_flag = true, theme_arg = null) -> void:
	project_data = project_data_arg
	snapshot = snapshot_arg
	selection = selection_arg
	completed = completed_arg
	allow_placeholders = bool(allow_placeholders_flag)
	theme_doc = theme_arg
	_font_cache = null
	_texture_cache = {}
	_shadow_style = null
	_hint_slots = []
	loader = AssetLoader.new()
	loader.setup("res://assets/assets.json", bool(allow_placeholders_flag))
	queue_redraw()


func refresh(snapshot_arg: Dictionary) -> void:
	snapshot = snapshot_arg
	queue_redraw()


func set_selection(selection_arg: Array) -> void:
	selection = selection_arg
	queue_redraw()


func set_completed(completed_arg: Array) -> void:
	completed = completed_arg
	queue_redraw()


## 提示槽位：[[x, y], ...]。只影响 chip 绘制（放大 + 向首个提示槽靠近），不影响命中。
func set_hint_slots(slots: Array) -> void:
	_hint_slots = []
	for slot_v in slots:
		var xy := _parse_xy(slot_v)
		if xy.x < 0 or xy.y < 0:
			continue
		_hint_slots.append([xy.x, xy.y])
	queue_redraw()


func clear_hint() -> void:
	_hint_slots = []
	queue_redraw()


func hint_active() -> bool:
	return not _hint_slots.is_empty()


func hint_slot_count() -> int:
	return _hint_slots.size()


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
	_draw_chrome()
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
	var bg_bottom := _texture_or_null("board_bg")
	var bg_top := _texture_or_null("local_bg_top")
	if bg_bottom != null or bg_top != null:
		draw_rect(Rect2(Vector2.ZERO, canvas), Color("#101a2b"))
		if bg_bottom != null:
			draw_texture_rect(bg_bottom, BG_BOTTOM_RECT, false)
		if bg_top != null:
			draw_texture_rect(bg_top, BG_TOP_RECT, false)
		_draw_theme_tint(canvas)
		return

	var top := Color("#35455f")
	var bottom := Color("#101a2b")
	if theme_doc != null:
		var theme_top_v: Variant = theme_doc.background_top
		var theme_bottom_v: Variant = theme_doc.background_bottom
		if typeof(theme_top_v) == TYPE_COLOR:
			top = theme_top_v
		if typeof(theme_bottom_v) == TYPE_COLOR:
			bottom = theme_bottom_v
	var bands := 32
	var band_height := canvas.y / float(bands)
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(0.0, band_height * float(i), canvas.x, band_height + 1.0), top.lerp(bottom, t))
	# 顶部柔光 + 底部暗角，增强竖向渐变感。
	draw_circle(Vector2(canvas.x * 0.5, canvas.y * 0.18), canvas.x * 0.55, Color(0.45, 0.6, 0.85, 0.10))
	draw_rect(Rect2(0.0, canvas.y * 0.82, canvas.x, canvas.y * 0.18), Color(0.02, 0.04, 0.08, 0.35))


## 贴图背景上叠一层很淡的主题色，保证换主题成片仍不同，又不盖住 PSD 画面。
func _draw_theme_tint(canvas: Vector2) -> void:
	if theme_doc == null:
		return
	var top_v: Variant = theme_doc.background_top
	var bottom_v: Variant = theme_doc.background_bottom
	if typeof(top_v) != TYPE_COLOR or typeof(bottom_v) != TYPE_COLOR:
		return
	var top: Color = top_v
	var bottom: Color = bottom_v
	var bands := 16
	var band_height := canvas.y / float(bands)
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var color := top.lerp(bottom, t)
		color.a = 0.05 + 0.03 * t
		draw_rect(Rect2(0.0, band_height * float(i), canvas.x, band_height + 1.0), color)


## 底部信息条 / 左下退出 / 右下背包（棋盘.psd §20.5）。
func _draw_chrome() -> void:
	var items := _texture_or_null("local_items_bar")
	if items != null:
		draw_texture_rect(items, ITEMS_RECT, false)
	var exit_icon := _texture_or_null("local_icon_exit")
	if exit_icon != null:
		draw_texture_rect(exit_icon, EXIT_RECT, false)
	var cabinet := _texture_or_null("ui_button_secondary")
	if cabinet != null:
		draw_texture_rect(cabinet, CABINET_RECT, false)


func _draw_board_frame() -> void:
	var rect := Rect2(BOARD_ORIGIN, BOARD_SIZE)
	if theme_doc != null:
		var theme_texture_v: Variant = theme_doc.board_frame_texture()
		if theme_texture_v is Texture2D:
			draw_texture_rect(theme_texture_v as Texture2D, rect, false)
			return
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
	var slot_texture := _texture_or_null("slot_empty")
	for y in range(dims.y):
		for x in range(dims.x):
			var rect := _cell_rect(x, y).grow(-CELL_INSET)
			if slot_texture != null:
				draw_texture_rect(slot_texture, rect, false)
				continue
			var fill := Color("#c7dcef") if ((x + y) % 2) == 0 else Color("#cfe3f4")
			draw_style_box(_make_style(fill, 18, Color("#7fb2e5"), 5), rect)


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
	var chip_rect := _chip_draw_rect(x, y)
	var icon := chip_icon_texture(entity, level)
	if icon != null:
		_draw_chip_icon(icon, _icon_draw_rect(x, y))
		return
	var fill := _entity_color(entity)
	var border := fill.lightened(clampf(0.22 + 0.06 * float(maxi(level, 0)), 0.22, 0.9))
	draw_style_box(_make_style(fill, 20, border, 4), chip_rect)

	var center := chip_rect.get_center()
	_draw_text_centered(font, "Lv%d" % level, Vector2(center.x, center.y - chip_rect.size.y * 0.16), 24, Color(1.0, 1.0, 1.0, 0.95))
	_draw_text_centered(font, entity.substr(0, 8), Vector2(center.x, center.y + chip_rect.size.y * 0.16), 20, Color(1.0, 1.0, 1.0, 0.8))


## chip 图标纹理（主题优先）；未配置/加载失败返回 null，绘制回退为自绘 chip。
func chip_icon_texture(entity: String, level: int) -> Texture2D:
	if theme_doc == null or not theme_doc.has_method("chip_texture"):
		return null
	var texture_v: Variant = theme_doc.chip_texture(entity, level)
	if texture_v is Texture2D:
		return texture_v
	return null


## fit=scale：182→约 140，保持宽高比、格内底边对齐，并加轻微阴影。
## 不在最后二次钳到 140：base 矩形本身约 140，hint 时 1.08 放大应生效。
func _draw_chip_icon(icon: Texture2D, draw_rect: Rect2) -> void:
	var source_size := icon.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var scale := minf(draw_rect.size.x / source_size.x, draw_rect.size.y / source_size.y)
	var draw_size := source_size * scale
	var icon_rect := Rect2(
		Vector2(draw_rect.get_center().x - draw_size.x * 0.5, draw_rect.end.y - draw_size.y - 2.0),
		draw_size
	)
	var shadow_rect := Rect2(
		Vector2(icon_rect.position.x + draw_size.x * 0.18, icon_rect.end.y - 10.0),
		Vector2(draw_size.x * 0.64, 12.0)
	)
	if _shadow_style == null:
		_shadow_style = _make_style(Color(0.0, 0.0, 0.0, 0.16), 6, Color(0.0, 0.0, 0.0, 0.0), 0)
	draw_style_box(_shadow_style, shadow_rect)
	draw_texture_rect(icon, icon_rect, false)


## chip 的实际绘制矩形：普通格子返回原矩形；提示格围绕格心放大并向首个提示槽偏移。
## 只用于绘制，cell_rect / 命中检测保持不变。
func _chip_draw_rect(x: int, y: int) -> Rect2:
	return _hint_rect(x, y, _cell_rect(x, y).grow(-CHIP_INSET))


## chip 图标的绘制矩形：贴齐格子（底边对齐），提示时同样放大/偏移。
func _icon_draw_rect(x: int, y: int) -> Rect2:
	return _hint_rect(x, y, _cell_rect(x, y))


func _hint_rect(x: int, y: int, base: Rect2) -> Rect2:
	if not hint_active() or not _hint_has_slot(x, y):
		return base
	var cell_center := _cell_rect(x, y).get_center()
	var center := cell_center
	var dims := _board_dims()
	var first := _parse_xy(_hint_slots[0])
	if _in_bounds(first, dims):
		var direction := _cell_rect(first.x, first.y).get_center() - cell_center
		if direction.length_squared() > 0.0001:
			center += direction.normalized() * HINT_CHIP_OFFSET
	var scaled_size := base.size * HINT_CHIP_SCALE
	return Rect2(center - scaled_size * 0.5, scaled_size)


func _hint_has_slot(x: int, y: int) -> bool:
	for slot_v in _hint_slots:
		var xy := _parse_xy(slot_v)
		if xy.x == x and xy.y == y:
			return true
	return false


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
				var lock_texture := _texture_or_null("obstacle_lock")
				if lock_texture != null:
					draw_texture_rect(lock_texture, _cell_rect(x, y), false)
				else:
					_draw_lock(x, y)
			"web":
				var web_texture := _texture_or_null("obstacle_web")
				if web_texture != null:
					draw_texture_rect(web_texture, _cell_rect(x, y), false)
				else:
					_draw_web(x, y)
			"bubble":
				var bubble_texture := _texture_or_null("obstacle_bubble")
				if bubble_texture != null:
					draw_texture_rect(bubble_texture, _cell_rect(x, y), false)
				else:
					_draw_bubble(x, y)
			"ice":
				var ice_texture := _texture_or_null("obstacle_ice")
				if ice_texture != null:
					draw_texture_rect(ice_texture, _cell_rect(x, y), false)
				else:
					_draw_ice(x, y)


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


func _draw_ice(x: int, y: int) -> void:
	# 半透明冰蓝圆角覆盖 + 白色裂纹：与锁（灰）、蛛网（放射线）、泡泡（圆形）区分。
	var rect := _cell_rect(x, y).grow(-CELL_INSET)
	draw_style_box(_make_style(Color(0.55, 0.84, 1.0, 0.42), 16, Color(0.82, 0.95, 1.0, 0.9), 3), rect)
	var line_color := Color(1.0, 1.0, 1.0, 0.85)
	var crack_start := rect.position + rect.size * Vector2(0.2, 0.14)
	var crack_end := rect.position + rect.size * Vector2(0.76, 0.74)
	draw_line(crack_start, crack_end, line_color, 3.0, true)
	var branch_a := crack_start.lerp(crack_end, 0.45)
	draw_line(branch_a, branch_a + rect.size * Vector2(0.14, 0.26), line_color, 2.2, true)
	var branch_b := crack_start.lerp(crack_end, 0.72)
	draw_line(branch_b, branch_b + rect.size * Vector2(-0.18, 0.2), line_color, 2.2, true)
	draw_line(crack_start, crack_start + rect.size * Vector2(0.22, -0.06), line_color, 2.0, true)


func _draw_selection() -> void:
	var dims := _board_dims()
	var select_texture := _texture_or_null("ui_select_frame")
	for item_v in selection:
		var xy := _parse_xy(item_v)
		if not _in_bounds(xy, dims):
			continue
		var rect := _cell_rect(xy.x, xy.y)
		if select_texture != null:
			draw_texture_rect(select_texture, rect.grow(2.0), false)
			continue
		var style := _make_style(Color(0.0, 0.0, 0.0, 0.0), 16, Color(SELECT_HEX), 6)
		style.draw_center = false
		draw_style_box(style, rect.grow(-3.0))


func _draw_completed() -> void:
	var dims := _board_dims()
	var finish_texture := _texture_or_null("local_icon_finish")
	for item_v in completed:
		var xy := _parse_xy(item_v)
		if not _in_bounds(xy, dims):
			continue
		var rect := _cell_rect(xy.x, xy.y).grow(-CELL_INSET)
		var center := rect.position + Vector2(rect.size.x * 0.82, rect.size.y * 0.18)
		if finish_texture != null:
			var finish_size := 52.0
			draw_texture_rect(
				finish_texture,
				Rect2(center - Vector2(finish_size * 0.5, finish_size * 0.5), Vector2(finish_size, finish_size)),
				false
			)
			continue
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


func _active_palette() -> Array:
	if theme_doc != null:
		var palette_v: Variant = theme_doc.palette
		if typeof(palette_v) == TYPE_ARRAY and not (palette_v as Array).is_empty():
			return palette_v as Array
	return _palette


func _entity_color(entity: String) -> Color:
	var palette := _active_palette()
	# djb2 稳定哈希：同一 entity 跨运行得到同一颜色。
	var hash_value := 5381
	for i in range(entity.length()):
		hash_value = (hash_value * 33 + entity.unicode_at(i)) % 2147483647
	return palette[hash_value % palette.size()]


func _ui_font() -> Font:
	if _font_cache != null:
		return _font_cache
	if theme_doc != null:
		var theme_font_v: Variant = theme_doc.ui_font()
		if theme_font_v is Font:
			_font_cache = theme_font_v
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


## 按资源 ID 取纹理并缓存（每帧逐格调用不会重复解码）。
## 大面积背景在运行时降采样一半再放大绘制：保持 §20.5 的布局尺寸，
## 但降低逐帧 PNG 编码耗时，保证 30s 出片 ≤5 分钟。
func _texture_or_null(resource_id: String) -> Texture2D:
	if _texture_cache.has(resource_id):
		return _texture_cache[resource_id] as Texture2D
	var texture: Texture2D = null
	if loader != null:
		var result: Dictionary = loader.load_texture(resource_id)
		var texture_v: Variant = result.get("texture")
		if bool(result.get("ok", false)) and texture_v is Texture2D:
			texture = texture_v
	if texture != null and (resource_id == "board_bg" or resource_id == "local_bg_top"):
		var image := texture.get_image()
		if image != null and not image.is_empty():
			image = image.duplicate()
			image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2), Image.INTERPOLATE_BILINEAR)
			texture = ImageTexture.create_from_image(image)
	_texture_cache[resource_id] = texture
	return texture


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
