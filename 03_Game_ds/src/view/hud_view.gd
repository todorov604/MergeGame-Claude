extends Control
## Top HUD (M0 step 4): level badge, energy + plus, coin, star, gem, exp bar.
##
## Everything is drawn procedurally; the only file it touches is the PRODUCTION
## font. No manifest icon id is used, so the strictest asset mode still renders.
##
## The eight HUD fields are explicit data from project.hud — nothing is derived
## from meta.duration or from the timeline:
##   level / energy / energyTickSeconds / energyTickMode / coin / star / gem / exp

const FONT_PATH := "res://assets/fonts/font_zh.otf"
const FIELDS := [
	"level", "energy", "energyTickSeconds", "energyTickMode", "coin", "star", "gem", "exp",
]
const DEFAULTS := {
	"level": 1,
	"energy": 0,
	"energyTickSeconds": 120,
	"energyTickMode": "decrement",
	"coin": 0,
	"star": 0,
	"gem": 0,
	"exp": 0,
}
const WIDTH := 1080.0
const HEIGHT := 185.0

var values: Dictionary = {}
var palette: Dictionary = {}
var _font: Font = null
var _boxes: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(WIDTH, HEIGHT)
	_font = _load_font()
	if values.is_empty():
		build_from_hud(DEFAULTS)
	queue_redraw()


# ------------------------------------------------------------------- public API

## Returns the resolved eight fields (a copy), so callers and tests never alias
## the view's own dictionary.
func build_from_hud(hud_in: Dictionary) -> Dictionary:
	values = DEFAULTS.duplicate(true)
	if typeof(hud_in) == TYPE_DICTIONARY:
		for key in FIELDS:
			if hud_in.has(key):
				values[key] = hud_in[key]
	values["level"] = int(values.get("level", 1))
	values["energy"] = int(values.get("energy", 0))
	values["coin"] = int(values.get("coin", 0))
	values["star"] = int(values.get("star", 0))
	values["gem"] = int(values.get("gem", 0))
	values["exp"] = int(values.get("exp", 0))
	values["energyTickSeconds"] = int(values.get("energyTickSeconds", 120))
	values["energyTickMode"] = String(values.get("energyTickMode", "decrement"))
	if is_inside_tree():
		queue_redraw()
	return values.duplicate(true)


func get_value(key: String):
	return values.get(key, null)


func set_palette(colors: Dictionary) -> void:
	if typeof(colors) == TYPE_DICTIONARY and not colors.is_empty():
		palette = colors
		if is_inside_tree():
			queue_redraw()


## Where a flying coin / star / gem should land, in this control's local space.
func counter_center(key: String) -> Vector2:
	var pill := _pill_rect(key)
	var icon := Vector2(pill.position.x + 40.0, pill.get_center().y)
	match key:
		"level":
			return Vector2(pill.position.x + 34.0, pill.get_center().y)
		"energy":
			return icon
		"exp":
			return Vector2(pill.position.x + 34.0, pill.get_center().y)
	return icon


func debug_summary() -> String:
	return "hud level=%d energy=%d tick=%ds/%s coin=%d star=%d gem=%d exp=%d" % [
		int(values.get("level", 0)),
		int(values.get("energy", 0)),
		int(values.get("energyTickSeconds", 0)),
		String(values.get("energyTickMode", "?")),
		int(values.get("coin", 0)),
		int(values.get("star", 0)),
		int(values.get("gem", 0)),
		int(values.get("exp", 0)),
	]


# ---------------------------------------------------------------------- layout

func _pill_rect(key: String) -> Rect2:
	match key:
		"level":
			return Rect2(20.0, 20.0, 120.0, 84.0)
		"energy":
			return Rect2(150.0, 20.0, 390.0, 84.0)
		"coin":
			return Rect2(552.0, 20.0, 240.0, 84.0)
		"gem":
			return Rect2(804.0, 20.0, 252.0, 84.0)
		"star":
			return Rect2(150.0, 114.0, 200.0, 58.0)
		"exp":
			return Rect2(362.0, 114.0, 694.0, 58.0)
	return Rect2(0.0, 0.0, 10.0, 10.0)


# --------------------------------------------------------------------- drawing

func _draw() -> void:
	var panel: Color = _c("panel", Color("#A8BDD5"))
	var edge: Color = _c("panel_edge", Color("#93AAC6"))
	var ink: Color = _c("ink", Color("#22303F"))
	var radius := 26

	_pill(_pill_rect("level"), radius, panel, edge)
	var level_rect := _pill_rect("level")
	_text_right(level_rect.grow(-10.0), str(int(values.get("level", 0))), 46, Color.WHITE)
	_text_left(level_rect.position + Vector2(16.0, 30.0), "LV", 18,
			Color(1.0, 1.0, 1.0, 0.75))

	_pill(_pill_rect("energy"), radius, panel, edge)
	var energy_rect := _pill_rect("energy")
	_bolt(Vector2(energy_rect.position.x + 40.0, energy_rect.get_center().y),
			Color("#F5E05A"))
	_text_right(Rect2(energy_rect.position + Vector2(66, 8), Vector2(energy_rect.size.x - 126, 44)),
			str(int(values.get("energy", 0))), 40, Color.WHITE)
	_text_left(energy_rect.position + Vector2(70.0, 48.0),
			"%ds %s" % [int(values.get("energyTickSeconds", 0)),
					String(values.get("energyTickMode", ""))], 17,
			Color(1.0, 1.0, 1.0, 0.72))
	_plus(Vector2(energy_rect.position.x + energy_rect.size.x - 30.0, energy_rect.get_center().y))

	_pill(_pill_rect("coin"), radius, panel, edge)
	_coin(Vector2(_pill_rect("coin").position.x + 40.0, _pill_rect("coin").get_center().y))
	_text_right(_pill_rect("coin").grow(-10.0), str(int(values.get("coin", 0))), 36, Color.WHITE,
			52.0)

	_pill(_pill_rect("gem"), radius, panel, edge)
	_gem(Vector2(_pill_rect("gem").position.x + 40.0, _pill_rect("gem").get_center().y))
	_text_right(_pill_rect("gem").grow(-10.0), str(int(values.get("gem", 0))), 36, Color.WHITE,
			52.0)

	_pill(_pill_rect("star"), radius, panel, edge)
	_star(Vector2(_pill_rect("star").position.x + 34.0, _pill_rect("star").get_center().y), 18.0)
	_text_right(_pill_rect("star").grow(-10.0), str(int(values.get("star", 0))), 32, Color.WHITE,
			46.0)

	var exp_rect := _pill_rect("exp")
	_pill(exp_rect, radius, panel, edge)
	_text_left(exp_rect.position + Vector2(16.0, 34.0), "EXP", 20,
			Color(1.0, 1.0, 1.0, 0.85))
	var exp := int(values.get("exp", 0))
	var bar := Rect2(exp_rect.position + Vector2(76, 18), Vector2(exp_rect.size.x - 96, 22))
	_rounded(bar, 11, Color(0.0, 0.0, 0.0, 0.18))
	var ratio := clampf(float(exp) / 10.0, 0.0, 1.0)
	if ratio > 0.0:
		_rounded(Rect2(bar.position, Vector2(maxf(bar.size.x * ratio, 22.0), bar.size.y)), 11,
				_c("accent", Color("#5B8DEF")))
	_text_right(Rect2(exp_rect.position, Vector2(exp_rect.size.x - 16.0, exp_rect.size.y)),
			str(exp), 22, ink)


# ---------------------------------------------------------------- primitives

func _c(key: String, fallback: Color) -> Color:
	var value = palette.get(key, null)
	if value is Color:
		return value
	return fallback


func _rounded(rect: Rect2, radius: int, color: Color) -> void:
	var box := _box(radius, false)
	box.bg_color = color
	box.border_color = Color(0.0, 0.0, 0.0, 0.0)
	box.set_border_width_all(0)
	draw_style_box(box, rect)


func _rounded_outline(rect: Rect2, radius: int, color: Color, width: int) -> void:
	var box := _box(radius, true)
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.border_color = color
	box.set_border_width_all(width)
	draw_style_box(box, rect)


func _box(radius: int, outline: bool) -> StyleBoxFlat:
	var key := "%d:%s" % [radius, str(outline)]
	var box: StyleBoxFlat = _boxes.get(key)
	if box == null:
		box = StyleBoxFlat.new()
		box.set_corner_radius_all(radius)
		box.anti_aliasing = true
		_boxes[key] = box
	return box


func _pill(rect: Rect2, radius: int, fill: Color, edge: Color) -> void:
	_rounded(rect, radius, fill)
	_rounded_outline(rect, radius, edge, 2)


func _bolt(c: Vector2, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-9.0, -26.0), c + Vector2(14.0, -26.0), c + Vector2(2.0, -3.0),
		c + Vector2(14.0, -3.0), c + Vector2(-6.0, 30.0), c + Vector2(0.0, 2.0),
		c + Vector2(-14.0, 2.0),
	])
	draw_colored_polygon(pts, color)


func _plus(c: Vector2) -> void:
	draw_circle(c, 18.0, Color(0.32, 0.72, 0.40, 0.95), true, -1.0, true)
	draw_circle(c, 18.0, Color(1.0, 1.0, 1.0, 0.55), false, 2.0, true)
	draw_line(c + Vector2(-8.0, 0.0), c + Vector2(8.0, 0.0), Color.WHITE, 4.0, true)
	draw_line(c + Vector2(0.0, -8.0), c + Vector2(0.0, 8.0), Color.WHITE, 4.0, true)


func _coin(c: Vector2) -> void:
	var gold: Color = _c("coin", Color("#F6C445"))
	draw_circle(c, 20.0, gold.darkened(0.18), true, -1.0, true)
	draw_circle(c, 17.0, gold, true, -1.0, true)
	draw_circle(c, 11.0, gold.lightened(0.22), true, -1.0, true)


func _gem(c: Vector2) -> void:
	var hue: Color = _c("gem", Color("#B27BEA"))
	var pts := PackedVector2Array([
		c + Vector2(0.0, -22.0), c + Vector2(19.0, -4.0), c + Vector2(0.0, 22.0),
		c + Vector2(-19.0, -4.0),
	])
	draw_colored_polygon(pts, hue)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			hue.lightened(0.25), 2.0, true)


func _star(c: Vector2, r: float) -> void:
	var hue: Color = _c("star", Color("#F2B233"))
	var pts := PackedVector2Array()
	for i in 10:
		var radius := r if i % 2 == 0 else r * 0.45
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(pts, hue)


func _text_left(pos: Vector2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	draw_string(_font, pos + Vector2(0.0, float(size_px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			size_px, color)


func _text_right(rect: Rect2, text: String, size_px: int, color: Color, pad: float = 12.0) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var ascent := _font.get_ascent(size_px)
	var pos := Vector2(
		rect.position.x + rect.size.x - pad - measured.x,
		rect.position.y + (rect.size.y - (ascent + _font.get_descent(size_px))) * 0.5 + ascent
	)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _load_font() -> Font:
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.size() > 0:
		var file := FontFile.new()
		file.data = bytes
		if file.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > 0.0:
			return file
	return ThemeDB.fallback_font
