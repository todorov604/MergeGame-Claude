extends Control

## M0 P0 顶栏 HUD（1080×120）：等级 / 能量（含 mm:ss 倒计时）/ 金币 / 星星 / 宝石 / EXP。
## 数据优先 snapshot["hud"]，缺失字段回退 project_data["hud"]，再缺省 0。
## 星星贴图优先 theme_arg.star_texture()，否则 AssetLoader 的 ui_icon_star（PLACEHOLDER 受 allow 控制），
## 失败时自绘五角星；字体优先 theme_arg.ui_font()，否则 font_zh，最后 ThemeDB.fallback_font。
## 唯一资源入口 AssetLoader，绝不引用 REFERENCE_ONLY；theme_arg 可为 null。

const AssetLoader := preload("res://game/asset_loader.gd")

const BAR_RECT := Rect2(0.0, 0.0, 1080.0, 120.0)
const BAR_BG := Color(0.05, 0.09, 0.16, 0.82)
const BAR_BORDER := Color(0.62, 0.78, 1.0, 0.18)
const TEXT_PRIMARY := Color("#eaf2ff")
const TEXT_MUTED := Color("#9fb4cf")
const GOLD_LIGHT := Color("#ffd76a")
const GOLD_DARK := Color("#b07a18")
const STAR_FILL := Color("#ffe066")
const STAR_OUTLINE := Color("#d9a81f")

var project_data: Dictionary = {}
var snapshot: Dictionary = {}
var theme_doc = null
var loader = null

var _project_hud: Dictionary = {}
var _level := 0
var _energy := 0
var _energy_tick_seconds := 0.0
var _energy_tick_mode := ""
var _coin := 0
var _star := 0
var _gem := 0
var _exp := 0
var _elapsed := 0.0

var _font_cache: Font = null
var _star_texture: Texture2D = null
var _star_checked := false


func setup(project_data_arg: Dictionary, theme_arg = null, allow_placeholders := true) -> void:
	project_data = project_data_arg
	theme_doc = theme_arg
	_font_cache = null
	_star_texture = null
	_star_checked = false
	loader = AssetLoader.new()
	loader.setup("res://assets/assets.json", bool(allow_placeholders))
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_project_hud = {}
	var hud_v: Variant = project_data.get("hud")
	if typeof(hud_v) == TYPE_DICTIONARY:
		_project_hud = hud_v as Dictionary

	_apply_snapshot({}, 0.0)
	queue_redraw()


func refresh(snapshot_arg: Dictionary, elapsed: float = 0.0) -> void:
	snapshot = snapshot_arg
	_apply_snapshot(snapshot, elapsed)
	queue_redraw()


func level_text() -> String:
	return "Lv %d" % _level


func energy_text() -> String:
	return str(_energy)


func timer_text() -> String:
	var tick := _energy_tick_seconds
	if not is_finite(tick) or tick <= 0.0:
		return "00:00"
	var elapsed := _elapsed
	if not is_finite(elapsed) or elapsed < 0.0:
		elapsed = 0.0
	var remaining := clampf(tick - fmod(elapsed, tick), 0.0, tick)
	var total := int(ceil(remaining))
	# 浮点误差可能把整数秒推高 0.000…1；此时按最近整数取整，避免倒计时多跳一秒。
	if absf(remaining - round(remaining)) < 0.0001:
		total = int(round(remaining))
	total = maxi(total, 0)
	var minutes := int(float(total) / 60.0)
	var seconds := total % 60
	return "%02d:%02d" % [minutes, seconds]


func coin_text() -> String:
	return str(_coin)


func star_text() -> String:
	return str(_star)


func gem_text() -> String:
	return str(_gem)


# ---------------------------------------------------------------------------
# 状态解析
# ---------------------------------------------------------------------------

func _apply_snapshot(snapshot_arg: Dictionary, elapsed: float) -> void:
	var hud: Dictionary = {}
	var hud_v: Variant = snapshot_arg.get("hud")
	if typeof(hud_v) == TYPE_DICTIONARY:
		hud = hud_v as Dictionary

	_level = _resolve_int(hud, "level")
	_energy = _resolve_int(hud, "energy")
	_energy_tick_seconds = _resolve_number(hud, "energyTickSeconds")
	_energy_tick_mode = _resolve_string(hud, "energyTickMode")
	_coin = _resolve_int(hud, "coin")
	_star = _resolve_int(hud, "star")
	_gem = _resolve_int(hud, "gem")
	_exp = _resolve_int(hud, "exp")
	_elapsed = elapsed if is_finite(elapsed) else 0.0


## snapshot 字段优先，其次 project_data.hud，最后 0；非法类型视同缺失。
func _resolve_number(hud: Dictionary, key: String) -> float:
	var value := _number_of(hud[key]) if hud.has(key) else NAN
	if not is_nan(value):
		return value
	value = _number_of(_project_hud[key]) if _project_hud.has(key) else NAN
	if not is_nan(value):
		return value
	return 0.0


func _resolve_int(hud: Dictionary, key: String) -> int:
	return int(_resolve_number(hud, key))


func _resolve_string(hud: Dictionary, key: String) -> String:
	if hud.has(key) and typeof(hud[key]) == TYPE_STRING:
		return String(hud[key])
	if _project_hud.has(key) and typeof(_project_hud[key]) == TYPE_STRING:
		return String(_project_hud[key])
	return ""


## JSON 数字统一是 float；int-like 的 float 转为数值，NaN/INF/非数字返回 NAN。
func _number_of(value: Variant) -> float:
	if typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_finite(number):
			return number
	return NAN


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	_draw_panel()
	var font := _ui_font()
	_draw_level_badge(font)
	_draw_separator(158.0)
	_draw_energy(font)
	_draw_separator(438.0)
	_draw_coin(font)
	_draw_star(font)
	_draw_gem(font)
	_draw_exp(font)


func _draw_panel() -> void:
	draw_style_box(_make_style(BAR_BG, 22, BAR_BORDER, 3), BAR_RECT)


func _draw_separator(x: float) -> void:
	draw_line(Vector2(x, 24.0), Vector2(x, 96.0), Color(0.62, 0.78, 1.0, 0.12), 2.0, true)


func _draw_level_badge(font: Font) -> void:
	var center := Vector2(78.0, 60.0)
	var radius := 46.0
	var points := PackedVector2Array()
	for i in range(6):
		var angle := -PI * 0.5 + PI / 3.0 * float(i)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color("#1e3a5f"))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color("#6fa8e8"), 3.0, true)
	if font != null:
		_draw_text_centered(font, level_text(), center, 27, TEXT_PRIMARY)


func _draw_energy(font: Font) -> void:
	var bolt_center := Vector2(206.0, 46.0)
	var bolt := PackedVector2Array([
		bolt_center + Vector2(7.0, -22.0),
		bolt_center + Vector2(-12.0, 5.0),
		bolt_center + Vector2(-2.0, 5.0),
		bolt_center + Vector2(-6.0, 22.0),
		bolt_center + Vector2(13.0, -5.0),
		bolt_center + Vector2(2.0, -5.0),
	])
	draw_colored_polygon(bolt, Color("#ffd83d"))
	var bolt_outline := bolt.duplicate()
	bolt_outline.append(bolt[0])
	draw_polyline(bolt_outline, GOLD_DARK, 2.0, true)

	if font == null:
		return
	draw_string(font, Vector2(236.0, 66.0), energy_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, TEXT_PRIMARY)
	var timer := timer_text()
	draw_string(font, Vector2(236.0, 106.0), timer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, TEXT_MUTED)
	var timer_width := font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
	_draw_tick_mode_arrow(Vector2(236.0 + timer_width + 15.0, 99.0))


func _draw_tick_mode_arrow(center: Vector2) -> void:
	if _energy_tick_mode != "decrement" and _energy_tick_mode != "increment":
		return
	var direction := 1.0 if _energy_tick_mode == "decrement" else -1.0
	var points := PackedVector2Array([
		center + Vector2(-7.0, -5.0 * direction),
		center + Vector2(7.0, -5.0 * direction),
		center + Vector2(0.0, 6.0 * direction),
	])
	draw_colored_polygon(points, Color(0.9, 0.75, 0.35, 0.9))


func _draw_coin(font: Font) -> void:
	var center := Vector2(500.0, 54.0)
	draw_circle(center, 23.0, Color("#f5b83d"))
	draw_circle(center, 18.0, GOLD_LIGHT)
	draw_arc(center, 23.0, 0.0, TAU, 32, GOLD_DARK, 3.0, true)
	if font != null:
		draw_string(font, Vector2(534.0, 66.0), coin_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, Color("#ffe9a8"))


func _draw_star(font: Font) -> void:
	var center := Vector2(700.0, 54.0)
	var texture := _star_texture_or_null()
	if texture != null:
		draw_texture_rect(texture, Rect2(center - Vector2(23.0, 23.0), Vector2(46.0, 46.0)), false)
	else:
		_draw_star_polygon(center, 23.0)
	if font != null:
		draw_string(font, Vector2(734.0, 66.0), star_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, Color("#fff2a8"))


func _draw_star_polygon(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var point_radius := radius if (i % 2) == 0 else radius * 0.45
		var angle := -PI * 0.5 + PI / 5.0 * float(i)
		points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)
	draw_colored_polygon(points, STAR_FILL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, STAR_OUTLINE, 2.0, true)


func _draw_gem(font: Font) -> void:
	var center := Vector2(900.0, 54.0)
	var outer := PackedVector2Array([
		center + Vector2(0.0, -24.0),
		center + Vector2(19.0, 0.0),
		center + Vector2(0.0, 24.0),
		center + Vector2(-19.0, 0.0),
	])
	draw_colored_polygon(outer, Color("#3fb7e8"))
	var inner := PackedVector2Array([
		center + Vector2(0.0, -15.0),
		center + Vector2(11.0, 0.0),
		center + Vector2(0.0, 15.0),
		center + Vector2(-11.0, 0.0),
	])
	draw_colored_polygon(inner, Color("#9fe8ff"))
	var outline := outer.duplicate()
	outline.append(outer[0])
	draw_polyline(outline, Color("#1f6e93"), 2.0, true)
	if font != null:
		draw_string(font, Vector2(934.0, 66.0), gem_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, Color("#bff0ff"))


func _draw_exp(font: Font) -> void:
	if font == null:
		return
	var text := "EXP %d" % _exp
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18)
	draw_string(font, Vector2(1056.0 - text_size.x, 106.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.72, 0.82, 0.92, 0.75))


# ---------------------------------------------------------------------------
# 资源辅助
# ---------------------------------------------------------------------------

func _star_texture_or_null() -> Texture2D:
	if typeof(theme_doc) == TYPE_OBJECT and theme_doc.has_method("star_texture"):
		var theme_texture_v: Variant = theme_doc.star_texture()
		if theme_texture_v is Texture2D:
			return theme_texture_v
	if _star_checked:
		return _star_texture
	_star_checked = true
	if loader != null:
		var result: Dictionary = loader.load_texture("ui_icon_star")
		var texture_v: Variant = result.get("texture")
		if bool(result.get("ok", false)) and texture_v is Texture2D:
			_star_texture = texture_v
	return _star_texture


func _ui_font() -> Font:
	if _font_cache != null:
		return _font_cache
	if typeof(theme_doc) == TYPE_OBJECT and theme_doc.has_method("ui_font"):
		var theme_font_v: Variant = theme_doc.ui_font()
		if theme_font_v is Font:
			_font_cache = theme_font_v
			return _font_cache
	if loader != null:
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
