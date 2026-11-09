extends Control
## 2026-11-06：顶栏（等级爪印 + 体力/金币/钻石条 + 商店按钮）的唯一实现。
## 实机与成片都实例化本组件，谁的像素都不再各画一份。
## 数据由宿主每帧 set_state() 推进；几何/字体/颜色都来自实机原来的常量。

const BAR_HEIGHT := 76.0
const BAR_GAP := 30.0
const BAR_ROW_MAX_W := 760.0
const BAR_LEFT_LIMIT := 120.0
const BAR_RIGHT_LIMIT := 926.0
const BAR_ASPECTS := {"energy": 243.0 / 90.0, "coin": 255.0 / 82.0, "gem": 246.0 / 67.0}
const BAR_CENTER_X := 540.0
const BAR_CENTER_Y := 58.0
const LEVEL_BADGE := Rect2(16.0, 16.0, 96.0, 67.2)
const SHOP := Rect2(930.0, 8.0, 142.0, 132.0)

var _loader = null
var _project: Dictionary = {}
var _colors: Dictionary = {}
var _metrics: Dictionary = {}
var _state: Dictionary = {}
var _tex: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1080.0, 150.0)


func set_asset_theme(loader, project: Dictionary) -> void:
	_loader = loader
	if not project.is_empty():
		_project = project
	_tex.clear()
	queue_redraw()


func set_palette(colors: Dictionary) -> void:
	_colors = colors
	queue_redraw()


func set_metrics(values: Dictionary) -> void:
	_metrics = values
	queue_redraw()


## level / energy / coin / gem / clock（mm:ss）/ coin_display / pop（0..1 缩放增量）
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


## 等比放进矩形（与 panel 的 draw_ui_fit 同一规则）。
## 等比放进矩形；返回实际画出来的矩形（调用方按它的高度定字号）。
func _draw_fit_rect(key: String, rect: Rect2) -> Rect2:
	var texture := _ui(key)
	if texture == null:
		return Rect2()
	var src := texture.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return Rect2()
	var scale: float = minf(rect.size.x / src.x, rect.size.y / src.y)
	var size := src * scale
	var at := rect.position + (rect.size - size) * 0.5
	draw_texture_rect(texture, Rect2(at, size), false)
	return Rect2(at, size)


func _draw_fit(key: String, rect: Rect2) -> bool:
	return _draw_fit_rect(key, rect).size.x > 0.0


func _font() -> Font:
	if _metrics.has("_font_display_bold"):
		return _metrics["_font_display_bold"]
	return null


var font_bold: Font = null
var font_fallback: Font = null


## 与实机同一比例：数字高度约为 bar 实际高度的 0.54（74 高 -> 40px）。
func _size_for(rect: Rect2) -> int:
	return int(round(clampf(rect.size.y * 0.54, 26.0, 40.0)))


func _text(r: Rect2, text: String, size_px: int, color: Color) -> void:
	var f: Font = font_bold if font_bold != null else font_fallback
	if f == null:
		return
	var width := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var pos := Vector2(r.position.x + (r.size.x - width) * 0.5,
			r.position.y + r.size.y * 0.5 + float(size_px) * 0.36)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func bar_rects() -> Dictionary:
	var h := BAR_HEIGHT
	var wide: float = h * (float(BAR_ASPECTS["energy"]) + float(BAR_ASPECTS["coin"])
			+ float(BAR_ASPECTS["gem"])) + BAR_GAP * 2.0
	if wide > BAR_ROW_MAX_W:
		h *= BAR_ROW_MAX_W / wide
	var top := BAR_CENTER_Y - h * 0.5
	var coin_w: float = h * float(BAR_ASPECTS["coin"])
	var energy_w: float = h * float(BAR_ASPECTS["energy"])
	var gem_w: float = h * float(BAR_ASPECTS["gem"])
	var coin := Rect2(BAR_CENTER_X - coin_w * 0.5, top, coin_w, h)
	energy_w = minf(energy_w, coin.position.x - BAR_GAP - BAR_LEFT_LIMIT)
	gem_w = minf(gem_w, BAR_RIGHT_LIMIT - coin.end.x - BAR_GAP)
	var energy := Rect2(coin.position.x - BAR_GAP - energy_w, top, energy_w, h)
	var gem := Rect2(coin.end.x + BAR_GAP, top, gem_w, h)
	return {"energy": energy, "coin": coin, "gem": gem}


func _draw() -> void:
	if _state.is_empty():
		return
	var bars := {"energy": "energy_bar", "coin": "coin_bar", "gem": "gem_bar"}
	var rects := bar_rects()
	var art_rects := {}
	for key in bars.keys():
		var art := _draw_fit_rect(String(bars[key]), rects[key])
		if art.size.x <= 0.0:
			draw_rect(rects[key], Color(1, 1, 1, 0.82), true)
			art = rects[key]
		art_rects[key] = art
	var badge_drawn := _draw_fit("level_badge_bg", LEVEL_BADGE)
	badge_drawn = _draw_fit("level_badge", LEVEL_BADGE) or badge_drawn
	if not badge_drawn:
		draw_rect(LEVEL_BADGE, Color("#5B8DEF"), true)
	_text(LEVEL_BADGE.grow(-6.0), str(int(_state.get("level", 1))), 40,
			Color(1, 1, 1, 0.98))
	var num_color := Color("#3B5C8F")
	var energy_rect: Rect2 = rects["energy"]
	var digit_px := _size_for(energy_rect)
	_text(energy_rect, str(int(_state.get("energy", 0))), digit_px, num_color)
	var clock := String(_state.get("clock", ""))
	var clock_rect := Rect2(energy_rect.position.x, energy_rect.position.y - 8.0,
			energy_rect.size.x, 26.0)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		_text(Rect2(clock_rect.position + offset, clock_rect.size), clock, 22,
				Color(0.12, 0.22, 0.40, 0.85))
	_text(clock_rect, clock, 22, Color(1.0, 1.0, 1.0))
	for key in ["coin", "gem"]:
		var rect: Rect2 = rects[key]
		var shown := int(_state.get(key, 0))
		var pop := 1.0
		if key == "coin" and float(_state.get("coin_display", -1.0)) >= 0.0:
			shown = int(round(float(_state.get("coin_display", 0.0))))
			pop = float(_state.get("pop", 0.0))
		# 宝石条盘面比另外两根矮：数字统一缩到 0.62 档（36 -> 22），避免顶到盘面上下边
		var px := digit_px if key == "coin" else maxi(int(round(float(digit_px) * 0.56)), 20)
		if key == "gem":
			rect = Rect2(rect.position + Vector2(rect.size.x * 0.10, 0.0),
					Vector2(rect.size.x * 0.86, rect.size.y))
		if pop > 0.001:
			draw_set_transform(rect.get_center(), 0.0, Vector2(1.0 + pop, 1.0 + pop))
			_text(Rect2(-rect.size * 0.5, rect.size), str(shown), px, num_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_text(rect, str(shown), px, num_color)
	if not _draw_fit("shop", SHOP):
		draw_rect(SHOP, Color("#5B8DEF"), true)