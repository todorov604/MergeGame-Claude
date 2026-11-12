extends Control
## 2026-11-06：底栏（任务背景板 + ⓘ + 标题/副标题 + 分隔线 + Buy/金币按钮 + 返回/背包）。
## 实机与成片实例化同一组件，几何常量取自 FilmLayout（movie_scene 的布局表）。

const FilmLayout := preload("res://src/render/movie_scene.gd")

var _loader = null
var _project: Dictionary = {}
var _state: Dictionary = {}
var _tex: Dictionary = {}
var font_bold: Font = null
var font_regular: Font = null
var font_num: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(1080.0, 1920.0)


func set_asset_theme(loader, project: Dictionary) -> void:
	_loader = loader
	if not project.is_empty():
		_project = project
	_tex.clear()
	queue_redraw()


func set_state(state: Dictionary) -> void:
	_state = state
	if is_inside_tree():
		queue_redraw()


func _ui(key: String) -> Texture2D:
	if _tex.has(key):
		var cached = _tex[key]
		return cached if cached is Texture2D else null
	var texture: Texture2D = null
	if _loader != null and _loader.has_method("texture_for"):
		var id := ""
		if _loader.has_method("resolve_ui"):
			var resolved = _loader.resolve_ui(key, _project)
			if typeof(resolved) == TYPE_DICTIONARY:
				id = String((resolved as Dictionary).get("id", ""))
			else:
				id = String(resolved)
		if not id.is_empty():
			var loaded = _loader.texture_for(id)
			if loaded is Texture2D:
				texture = loaded
	_tex[key] = texture
	return texture


func _draw_fit(key: String, rect: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	var src := texture.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return false
	var scale: float = minf(rect.size.x / src.x, rect.size.y / src.y)
	var size := src * scale
	draw_texture_rect(texture, Rect2(rect.position + (rect.size - size) * 0.5, size), false)
	return true


func _draw_stretch(key: String, rect: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect(texture, rect, false)
	return true


func _draw_tint(key: String, rect: Rect2, tint: Color) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect(texture, rect, false, tint)
	return true


## 九宫格拉伸（bar_board 的 28px 边角）
func _draw_plate(key: String, rect: Rect2, margin: float) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	var src := texture.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return false
	var m: float = minf(margin, minf(src.x, src.y) * 0.5)
	var cols := [0.0, m, src.x - m, src.x]
	var rows := [0.0, m, src.y - m, src.y]
	var dst_x := [rect.position.x, rect.position.x + m, rect.end.x - m, rect.end.x]
	var dst_y := [rect.position.y, rect.position.y + m, rect.end.y - m, rect.end.y]
	for i in 3:
		for j in 3:
			var sw: float = float(cols[i + 1]) - float(cols[i])
			var sh: float = float(rows[j + 1]) - float(rows[j])
			var dw: float = float(dst_x[i + 1]) - float(dst_x[i])
			var dh: float = float(dst_y[j + 1]) - float(dst_y[j])
			if sw <= 0.0 or sh <= 0.0 or dw <= 0.0 or dh <= 0.0:
				continue
			draw_texture_rect_region(texture, Rect2(float(dst_x[i]), float(dst_y[j]), dw, dh),
					Rect2(float(cols[i]), float(rows[j]), sw, sh))
	return true


func _text_left(r: Rect2, text: String, size_px: int, color: Color, font: Font) -> void:
	if font == null:
		return
	var pos := Vector2(r.position.x, r.position.y + r.size.y * 0.5 + float(size_px) * 0.36)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _text_center(r: Rect2, text: String, size_px: int, color: Color, font: Font,
		outline: Color = Color(0, 0, 0, 0)) -> void:
	if font == null:
		return
	if outline.a > 0.0:
		draw_string_outline(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5
				+ float(size_px) * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				size_px, 6, outline)
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5
			+ float(size_px) * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
			size_px, color)


func _draw() -> void:
	var items: Rect2 = FilmLayout.LAYOUT_ITEMS
	if not _draw_plate("bar_board", items, 28.0):
		if not _draw_stretch("items", items):
			draw_rect(items, Color(1, 1, 1, 0.92), true)
	var coin_size := 124.0
	var coin_rect := Rect2(items.position.x + items.size.x - 24.0 - coin_size,
			items.position.y + FilmLayout.BAR_COIN_OFFSET_Y, coin_size, coin_size)
	_draw_fit("reminder", Rect2(items.position + FilmLayout.BAR_ICON_OFFSET,
			FilmLayout.BAR_ICON_SIZE))
	# 2026-11-11：标题也要能被 JSON 的 shop.title 覆盖（金币数量同理，见下面 reward）。
	_text_left(Rect2(items.position + FilmLayout.BAR_TITLE_OFFSET, FilmLayout.BAR_TITLE_SIZE),
			String(_state.get("title", FilmLayout.BAR_TITLE)), 38, Color("#2E4157"), font_bold)
	var line_left: float = items.position.x + FilmLayout.BAR_TITLE_OFFSET.x
	var line_rect := Rect2(line_left, items.position.y + FilmLayout.BAR_LINE_OFFSET_Y,
			maxf(coin_rect.position.x - FilmLayout.BAR_LINE_GAP - line_left, 0.0),
			FilmLayout.BAR_LINE_H)
	if not _draw_tint("line", line_rect, FilmLayout.BAR_LINE_COLOR):
		draw_rect(line_rect, FilmLayout.BAR_LINE_COLOR, true)
	_text_left(Rect2(items.position + FilmLayout.BAR_SUB_OFFSET, FilmLayout.BAR_SUB_SIZE),
			String(_state.get("subtitle", "美宜制作，Made by MeiXuan")), 28,
			Color("#4B6076"), font_regular)
	_draw_fit("coin_reward", coin_rect)
	_text_center(Rect2(coin_rect.position.x, items.position.y + FilmLayout.BAR_BUY_OFFSET_Y,
			coin_rect.size.x, FilmLayout.BAR_BUY_SIZE_Y), FilmLayout.BAR_BUY, 30,
			FilmLayout.BAR_BUY_COLOR, font_num)
	_text_center(Rect2(coin_rect.position.x, coin_rect.position.y + 76.0, coin_rect.size.x, 40.0),
			str(int(_state.get("reward", FilmLayout.BAR_COIN_REWARD))), 36, Color.WHITE,
			font_num, Color("#2F6B1E"))
	if not _draw_fit("exit", FilmLayout.LAYOUT_EXIT):
		draw_rect(FilmLayout.LAYOUT_EXIT.grow(-8.0), Color(1, 1, 1, 0.92), true)
	if not _draw_fit("bag", FilmLayout.LAYOUT_BAG.grow(FilmLayout.BAG_GROW)):
		draw_rect(FilmLayout.LAYOUT_BAG.grow(-6.0), Color(1, 1, 1, 0.92), true)