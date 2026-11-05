extends Control
## Presentation layer (M0 step 4). Consumes the SAME resolved event stream as the
## sim through GameScreen, and never touches sim state: `play_event` only records
## a motion, `set_clock` only advances presentation time.
##
## Handled events: deliver, order_claim, star_fly, coin_popup, character_leave,
## character_next, levelup, transition. Everything else returns false and is left
## to the caller.
##
## It also draws the theme backdrop (board tint, board frame, bottom band), which
## is what makes a theme swap visible without editing any view code.

const FONT_PATH := "res://assets/fonts/font_zh.otf"
const HANDLED := [
	"deliver", "order_claim", "star_fly", "coin_popup",
	"character_leave", "character_next", "levelup", "transition",
]
const PAGE := Vector2(1080.0, 1920.0)

var palette: Dictionary = {}
var metrics: Dictionary = {}
var anchors: Dictionary = {}
var info: Dictionary = {}
var motions: Array = []
var counts: Dictionary = {}
var clock: float = 0.0

var _font: Font = null
var _boxes: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = PAGE
	_font = _load_font()
	queue_redraw()


# ------------------------------------------------------------------- public API

func set_palette(colors: Dictionary) -> void:
	if typeof(colors) == TYPE_DICTIONARY and not colors.is_empty():
		palette = colors
		if is_inside_tree():
			queue_redraw()


func set_metrics(values: Dictionary) -> void:
	if typeof(values) == TYPE_DICTIONARY:
		metrics = values


## Anchor table keyed by "cell:x,y", "order:<id>", "card:<id>", "hud:coin"...
## All values are page coordinates.
func set_anchors(table: Dictionary) -> void:
	if typeof(table) == TYPE_DICTIONARY:
		anchors = table


## Backdrop data: {board: Rect2, level: int, level_id: String, title: String}.
func set_backdrop(data: Dictionary) -> void:
	if typeof(data) == TYPE_DICTIONARY:
		info = data
		if is_inside_tree():
			queue_redraw()


func set_clock(t: float) -> void:
	var before := clock
	clock = t
	if not motions.is_empty():
		var alive: Array = []
		for m in motions:
			if clock <= float(m.get("start", 0.0)) + float(m.get("dur", 0.0)) + 0.05:
				alive.append(m)
		motions = alive
	if is_inside_tree() and not is_equal_approx(before, clock):
		queue_redraw()


## Returns true when the event type is presentation-owned. Payload is optional:
## a missing order id or slot falls back to the backdrop anchors.
func play_event(ev: Dictionary) -> bool:
	if typeof(ev) != TYPE_DICTIONARY:
		return false
	var type := String(ev.get("type", ""))
	if not HANDLED.has(type):
		return false
	counts[type] = int(counts.get(type, 0)) + 1

	var at := float(ev.get("at", clock))
	var dur := float(ev.get("duration", 0.0))
	var payload := _dict(ev.get("payload", {}))
	var order_id := String(payload.get("order", ""))
	if order_id.is_empty():
		order_id = String(info.get("order", ""))
	var order_at := _order_anchor(order_id)
	var hue: Color = _c("accent", Color("#5B8DEF"))
	if payload.has("hue"):
		hue = Color.from_string(String(payload.get("hue", "")), hue)

	match type:
		"deliver":
			motions.append({
				"kind": "item",
				"start": at,
				"dur": dur if dur > 0.0 else 0.55,
				"from": _cell_anchor(payload.get("from", null)),
				"to": order_at,
				"text": "",
				"hue": hue,
			})
		"order_claim":
			motions.append({
				"kind": "item",
				"start": at,
				"dur": dur if dur > 0.0 else 0.60,
				"from": _card_anchor(order_id),
				"to": order_at,
				"text": "",
				"hue": hue,
			})
			motions.append({"kind": "flash", "start": at, "dur": 0.7, "at": order_at})
		"star_fly":
			motions.append({
				"kind": "stars",
				"start": at,
				"dur": dur if dur > 0.0 else 0.8,
				"from": order_at,
				"to": _hud_anchor("star"),
				"n": maxi(1, int(payload.get("count", 1))),
			})
		"coin_popup":
			var amount := int(payload.get("amount", 1))
			motions.append({
				"kind": "coins",
				"start": at,
				"dur": dur if dur > 0.0 else 0.9,
				"from": order_at,
				"to": _hud_anchor("coin"),
				"text": "+%d" % amount,
			})
		"character_leave":
			motions.append({"kind": "fade", "start": at, "dur": dur if dur > 0.0 else 0.6,
					"at": order_at})
		"character_next":
			motions.append({"kind": "ring", "start": at, "dur": dur if dur > 0.0 else 0.6,
					"at": order_at})
		"levelup":
			motions.append({
				"kind": "banner",
				"start": at,
				"dur": dur if dur > 0.0 else 1.4,
				"level": int(payload.get("level", int(info.get("level", 1)))),
			})
		"transition":
			motions.append({"kind": "veil", "start": at, "dur": dur if dur > 0.0 else 0.6})

	if is_inside_tree():
		queue_redraw()
	return true


func active_count() -> int:
	return motions.size()


func debug_summary() -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s:%d" % [String(key), int(counts[key])])
	return "fly handled=%d active=%d clock=%.2f [%s]" % [
		int(counts.size()), motions.size(), clock, " ".join(parts),
	]


# --------------------------------------------------------------------- anchors

func _cell_anchor(raw) -> Vector2:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		var key := "cell:%d,%d" % [int((raw as Array)[0]), int((raw as Array)[1])]
		var found = anchors.get(key, null)
		if found is Vector2:
			return found
	var board = info.get("board", null)
	if board is Rect2:
		return (board as Rect2).get_center()
	return PAGE * 0.5


func _order_anchor(order_id: String) -> Vector2:
	var found = anchors.get("order:" + order_id, null)
	if found is Vector2:
		return found
	var fallback = anchors.get("order:default", null)
	if fallback is Vector2:
		return fallback
	return Vector2(540.0, 300.0)


func _card_anchor(order_id: String) -> Vector2:
	var found = anchors.get("card:" + order_id, null)
	if found is Vector2:
		return found
	return _order_anchor(order_id)


func _hud_anchor(key: String) -> Vector2:
	var found = anchors.get("hud:" + key, null)
	if found is Vector2:
		return found
	match key:
		"coin":
			return Vector2(592.0, 62.0)
		"star":
			return Vector2(184.0, 143.0)
		"gem":
			return Vector2(844.0, 62.0)
	return Vector2(540.0, 62.0)


# --------------------------------------------------------------------- drawing

func _draw() -> void:
	_draw_backdrop()
	for motion in motions:
		# A motion past its duration must never be painted, even if the clock stopped
		# (frozen preview): otherwise a finished delivery stays glued to the card as a
		# floating hue square.
		var dur := float(motion.get("dur", 0.0))
		if dur > 0.0 and clock > float(motion.get("start", 0.0)) + dur:
			continue
		_draw_motion(motion)


func _draw_backdrop() -> void:
	if info.is_empty():
		return
	var board = info.get("board", null)
	var tint_alpha := float(metrics.get("tint_alpha", 0.0))
	if board is Rect2 and tint_alpha > 0.0:
		var tint: Color = _c("board_tint", Color.WHITE)
		draw_rect(board as Rect2, Color(tint.r, tint.g, tint.b, tint_alpha), true)
	if board is Rect2:
		var radius := int(round(float(metrics.get("board_radius", 28.0))))
		var edge: Color = _c("panel_edge", Color("#93AAC6"))
		_rounded_outline((board as Rect2).grow(10.0), radius, edge, 4)

	var band_h := float(metrics.get("band_height", 208.0))
	if band_h <= 0.0:
		return
	var band := Rect2(0.0, PAGE.y - band_h, PAGE.x, band_h)
	var band_color: Color = _c("band", Color("#A8BDD5"))
	draw_rect(band, band_color, true)
	draw_rect(Rect2(band.position, Vector2(band.size.x, 3.0)),
			band_color.lightened(0.25), true)
	var ink: Color = _c("ink", Color("#22303F"))
	_text(Vector2(40.0, band.position.y + 62.0),
			"LEVEL %d" % int(info.get("level", 1)), 44, Color.WHITE)
	_text(Vector2(40.0, band.position.y + 100.0), String(info.get("level_id", "")), 24,
			Color(1.0, 1.0, 1.0, 0.78))
	var hint := String(info.get("title", ""))
	if not hint.is_empty():
		_text_right(Vector2(PAGE.x - 40.0, band.position.y + 62.0), hint, 24, ink)
	_text_right(Vector2(PAGE.x - 40.0, band.position.y + 100.0), "M0 / 30s TEMPLATE", 20,
			Color(1.0, 1.0, 1.0, 0.70))


func _draw_motion(m: Dictionary) -> void:
	var start := float(m.get("start", 0.0))
	var dur := maxf(0.001, float(m.get("dur", 0.5)))
	var p := clampf((clock - start) / dur, 0.0, 1.0)
	var ease := p * p * (3.0 - 2.0 * p)
	match String(m.get("kind", "")):
		"item":
			_draw_item(m, p, ease)
		"stars":
			_draw_stars(m, p)
		"coins":
			_draw_coins(m, p, ease)
		"flash":
			_draw_flash(m, p)
		"fade":
			_draw_fade(m, p)
		"ring":
			_draw_ring(m, p)
		"banner":
			_draw_banner(m, p, ease)
		"veil":
			_draw_veil(m, p)


func _draw_item(m: Dictionary, p: float, ease: float) -> void:
	var from: Vector2 = m.get("from", Vector2.ZERO)
	var to: Vector2 = m.get("to", Vector2.ZERO)
	var ctrl := (from + to) * 0.5 + Vector2(0.0, -180.0)
	var pos := _bezier(from, ctrl, to, ease)
	var side := lerpf(66.0, 40.0, ease)
	var alpha := 1.0 - pow(p, 3.0)
	var accent: Color = m.get("hue", _c("accent", Color("#5B8DEF")))
	var box := Rect2(pos - Vector2(side * 0.5, side * 0.5), Vector2(side, side))
	_rounded(box, 16, Color(accent.r, accent.g, accent.b, alpha))
	_rounded_outline(box, 16, Color(1.0, 1.0, 1.0, alpha * 0.8), 2)


func _draw_stars(m: Dictionary, p: float) -> void:
	var from: Vector2 = m.get("from", Vector2.ZERO)
	var to: Vector2 = m.get("to", Vector2.ZERO)
	var n := int(m.get("n", 1))
	for i in n:
		var local := clampf(p - float(i) * 0.12, 0.0, 1.0)
		if local <= 0.0:
			continue
		var ease := local * local * (3.0 - 2.0 * local)
		var ctrl := (from + to) * 0.5 + Vector2(0.0, -140.0 - 30.0 * float(i))
		var pos := _bezier(from, ctrl, to, ease)
		var alpha := 1.0 - pow(local, 4.0)
		_star(pos, lerpf(20.0, 11.0, ease), Color(1.0, 0.95, 0.55, alpha))


func _draw_coins(m: Dictionary, p: float, ease: float) -> void:
	var from: Vector2 = m.get("from", Vector2.ZERO)
	var to: Vector2 = m.get("to", Vector2.ZERO)
	var ctrl := (from + to) * 0.5 + Vector2(0.0, -120.0)
	var pos := _bezier(from, ctrl, to, ease)
	var alpha := minf(1.0, p * 3.0) * (1.0 - pow(p, 4.0))
	if alpha <= 0.0:
		return
	var gold: Color = _c("coin", Color("#F6C445"))
	draw_circle(pos, lerpf(24.0, 14.0, ease), Color(gold.r, gold.g, gold.b, alpha),
			true, -1.0, true)
	draw_circle(pos, lerpf(24.0, 14.0, ease), Color(1.0, 1.0, 1.0, alpha * 0.6), false, 2.0,
			true)
	var text := String(m.get("text", ""))
	if not text.is_empty():
		_text(pos + Vector2(-18.0, -26.0 - 24.0 * ease), text, 30,
				Color(gold.darkened(0.15).r, gold.darkened(0.15).g, gold.darkened(0.15).b,
						alpha))


func _draw_flash(m: Dictionary, p: float) -> void:
	var at: Vector2 = m.get("at", Vector2.ZERO)
	var done: Color = _c("done", Color("#8FD46B"))
	draw_circle(at, lerpf(40.0, 84.0, p), Color(done.r, done.g, done.b, 0.45 * (1.0 - p)),
			true, -1.0, true)


## character_leave: the portrait dissolves into the page colour and a closing ring
## marks the slot it left. Drawn in the page colour on purpose, so it reads as a
## soft wipe instead of a shadow.
func _draw_fade(m: Dictionary, p: float) -> void:
	var at: Vector2 = m.get("at", Vector2.ZERO)
	var page: Color = _c("page", Color("#E6EDF6"))
	var radius := lerpf(26.0, 104.0, p)
	draw_circle(at, radius, Color(page.r, page.g, page.b, 0.72 * (1.0 - p)), true, -1.0, true)
	draw_arc(at, lerpf(96.0, 34.0, p), 0.0, TAU, 40,
			Color(1.0, 1.0, 1.0, 0.55 * (1.0 - p)), 4.0, true)


func _draw_ring(m: Dictionary, p: float) -> void:
	var at: Vector2 = m.get("at", Vector2.ZERO)
	var accent: Color = _c("accent", Color("#5B8DEF"))
	draw_arc(at, lerpf(36.0, 92.0, p), 0.0, TAU, 40,
			Color(accent.r, accent.g, accent.b, 0.75 * (1.0 - p)), 6.0, true)


func _draw_banner(m: Dictionary, p: float, ease: float) -> void:
	var fade_in := clampf(p / 0.18, 0.0, 1.0)
	var fade_out := clampf((1.0 - p) / 0.22, 0.0, 1.0)
	var alpha := minf(fade_in, fade_out)
	if alpha <= 0.0:
		return
	var center := Vector2(PAGE.x * 0.5, 760.0)
	var rect := Rect2(center - Vector2(420.0, 110.0), Vector2(840.0, 220.0))
	var banner: Color = _c("banner", Color.WHITE)
	_rounded(rect.grow(8.0), 40, Color(0.08, 0.12, 0.18, alpha * 0.16))
	_rounded(rect, 34, Color(banner.r, banner.g, banner.b, alpha))
	_rounded_outline(rect, 34, Color(1.0, 1.0, 1.0, alpha * 0.95), 4)
	var ink: Color = _c("ink", Color("#22303F"))
	var accent: Color = _c("accent", Color("#5B8DEF"))
	_text_center(Rect2(rect.position, Vector2(rect.size.x, 108.0)),
			"LEVEL %d" % int(m.get("level", 1)), 70, Color(ink.r, ink.g, ink.b, alpha))
	_text_center(Rect2(rect.position + Vector2(0.0, 118.0), Vector2(rect.size.x, 70.0)),
			"LEVEL CLEAR", 32, Color(accent.r, accent.g, accent.b, alpha))
	for i in 16:
		var angle := TAU * float(i) / 16.0 + ease * 1.4
		var dot := center + Vector2(cos(angle) * 486.0, sin(angle) * 152.0 + 10.0 * float(i % 3))
		var hue := Color.from_hsv(fmod(float(i) / 16.0 + 0.10, 1.0), 0.55, 0.98)
		draw_circle(dot, 7.0, Color(hue.r, hue.g, hue.b, alpha * 0.9), true, -1.0, true)


func _draw_veil(m: Dictionary, p: float) -> void:
	var page: Color = _c("page", Color("#E6EDF6"))
	var alpha := sin(PI * p) * 0.88
	draw_rect(Rect2(Vector2.ZERO, PAGE), Color(page.r, page.g, page.b, alpha), true)


# ---------------------------------------------------------------- primitives

func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var inv := 1.0 - t
	return a * (inv * inv) + b * (2.0 * inv * t) + c * (t * t)


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


func _star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var radius := r if i % 2 == 0 else r * 0.45
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(pts, color)


func _text(pos: Vector2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _text_right(right_pos: Vector2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	_text(Vector2(right_pos.x - measured.x, right_pos.y), text, size_px, color)


func _text_center(rect: Rect2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var ascent := _font.get_ascent(size_px)
	var descent := _font.get_descent(size_px)
	_text(Vector2(
		rect.position.x + (rect.size.x - measured.x) * 0.5,
		rect.position.y + (rect.size.y - (ascent + descent)) * 0.5 + ascent
	), text, size_px, color)


func _dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _load_font() -> Font:
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.size() > 0:
		var file := FontFile.new()
		file.data = bytes
		if file.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > 0.0:
			return file
	return ThemeDB.fallback_font
