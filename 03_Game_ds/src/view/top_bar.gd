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
## 钱条 => 贴图 key。_draw() 与 counter_center() 共用这一张表。
const BAR_ART := {"energy": "energy_bar", "coin": "coin_bar", "gem": "gem_bar"}
## 金币图标在 coin_bar.png 里的相对位置：金币圆盘的金色本体 bbox=(3,2)-(72,73)，
## 中心 (37.5,37.5)，除以贴图 255x82。**量自贴图本身**，不是估的。
## 交叉验证：成片 frame 00040.png 顶栏里那枚金币的实测中心 (459.0,56.5)，
## 本比例映射出来的页面坐标 (458.79,54.84)，差 1.7px（贴图带投影）。
const COIN_ICON_RATIO := Vector2(37.5 / 255.0, 37.5 / 82.0)
## 钻石图标在 gem_bar.png 里的相对位置：粉钻本体 bbox=(2,2)-(73,60)，中心 (37.5,31) / 246x67。
const GEM_ICON_RATIO := Vector2(37.5 / 246.0, 31.0 / 67.0)
## 体力条里那道闪电的相对位置：亮黄 bbox=(3,3)-(57,81)，中心 (30,42) / 243x90。
const ENERGY_ICON_RATIO := Vector2(30.0 / 243.0, 42.0 / 90.0)
const ICON_RATIOS := {"coin": COIN_ICON_RATIO, "gem": GEM_ICON_RATIO, "energy": ENERGY_ICON_RATIO}
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


## 等比放进矩形（与 panel 的 draw_ui_fit 同一规则）。**纯几何，不画**。
## 飞行动画的落点要靠它把"贴图里的图标位置"换算到页面坐标，所以它必须能在
## 没有绘制上下文（甚至没有贴图）的时候调用。
func fit_rect_for(key: String, rect: Rect2) -> Rect2:
	var texture := _ui(key)
	if texture == null:
		return Rect2()
	var src := texture.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return Rect2()
	var s: float = minf(rect.size.x / src.x, rect.size.y / src.y)
	var size := src * s
	return Rect2(rect.position + (rect.size - size) * 0.5, size)


## 等比放进矩形并画出来；返回实际画出来的矩形（调用方按它的高度定字号）。
func _draw_fit_rect(key: String, rect: Rect2) -> Rect2:
	var box := fit_rect_for(key, rect)
	if box.size.x <= 0.0:
		return Rect2()
	draw_texture_rect(_ui(key), box, false)
	return box


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


## 飞行动画的落点：某根条里那枚图标的中心（本控件坐标系）。
## **成片与实机都调这一个函数，谁都不许再写死坐标。**
## 2026-11-09 之前成片写死 (473.6,49.6) —— 那是已退役 hud_view 的公式换算出来的，
## 落在数字左边，比图标实际中心偏右 15px、偏上 6px（实机读的也是那个隐藏控件）。
func counter_center(key: String) -> Vector2:
	var rects := bar_rects()
	var ratio: Vector2 = ICON_RATIOS.get(key, Vector2(0.5, 0.5))
	if not rects.has(key):
		return Vector2(BAR_CENTER_X, BAR_CENTER_Y) * scale + position
	var rect: Rect2 = rects[key]
	var box := fit_rect_for(String(BAR_ART.get(key, "")), rect)
	if box.size.x <= 0.0:
		# 无贴图（无资产模式/单测）：coin_bar 的长宽比与它的 bar 矩形完全一致，
		# 所以退回矩形本身算出来的落点和有贴图时相同。
		box = rect
	return (box.position + box.size * ratio) * scale + position


func _draw() -> void:
	if _state.is_empty():
		return
	var rects := bar_rects()
	var art_rects := {}
	for key in BAR_ART.keys():
		var art := _draw_fit_rect(String(BAR_ART[key]), rects[key])
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
	# 2026-11-09：体力数字和金币/钻石一样有"显示值 + 弹跳"（订单奖励飞上来时逐格涨）
	var energy_shown := int(_state.get("energy", 0))
	var energy_pop := 0.0
	if float(_state.get("energy_display", -1.0)) >= 0.0:
		energy_shown = int(round(float(_state.get("energy_display", 0.0))))
		energy_pop = float(_state.get("energy_pop", 0.0))
	if energy_pop > 0.001:
		draw_set_transform(energy_rect.get_center(), 0.0,
				Vector2(1.0 + energy_pop, 1.0 + energy_pop))
		_text(Rect2(-energy_rect.size * 0.5, energy_rect.size), str(energy_shown), digit_px,
				num_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_text(energy_rect, str(energy_shown), digit_px, num_color)
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
		# 2026-11-09：钻石和金币一样有"显示值 + 弹跳"（订单奖励飞上来时逐格涨）。
		# 键名分别 coin_display/pop 与 gem_display/gem_pop，没值就退回快照数字。
		var disp_key := "coin_display" if key == "coin" else "gem_display"
		var pop_key := "pop" if key == "coin" else "gem_pop"
		if float(_state.get(disp_key, -1.0)) >= 0.0:
			shown = int(round(float(_state.get(disp_key, 0.0))))
			pop = float(_state.get(pop_key, 0.0))
		# 2026-11-09 操作者：钻石数字要和闪电/金币**同一个字号**（原来单独缩到 0.56 档，
		# 看着像"宝石条上的小字"）。三根条现在共用 digit_px。
		var px := digit_px
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