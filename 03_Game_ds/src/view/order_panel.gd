extends Control
## Order cards + character portraits (M0 step 4), 1-2 cards per level.
##
## Card anatomy, all procedural:
##   portrait  round badge in the character hue + first letter of the display name
##   mission   one small chip per required item (entity + level) with a have/need
##             counter, turning green when the requirement is met
##   reward    coin and star amount
##   done      green capsule (#8FD46B) with a white check, covering the body
##
## The panel never reads the sim directly: GameScreen feeds it level data and
## then the live order rows, so the same widget works for a static screenshot.

const FONT_PATH := "res://assets/fonts/font_zh.otf"
const COLOR_DONE := Color("#8FD46B")
const UiFonts := preload("res://src/core/ui_fonts.gd")
const WIDTH := 1080.0
const HEIGHT := 250.0
const MAX_CARDS := 2
const MARGIN := 18.0
const MAX_CARD_W := 286.0

var cards: Array = []
var palette: Dictionary = {}
var metrics: Dictionary = {}

var _project: Dictionary = {}
var _rects: Dictionary = {}
var _font: Font = null
var _boxes: Dictionary = {}
var _level_id: String = ""
var _layout_size := Vector2(-1.0, -1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(WIDTH, HEIGHT)
	_font = _load_font()
	queue_redraw()


# ------------------------------------------------------------------- public API

## Entities/characters give the hue and display name; without it the panel still
## works from ids alone (useful in headless tests).
## Asset access for the card plate + mission icons (same loader the board uses).
var _loader = null
var _font_bold: Font = null
## Per-card anchors from the screen: [{"center": float, "bottom": float, "width": float}]
## in panel-local coordinates, so a card sits centred under its character and shares
## that character's drawn width.
var _anchors: Array = []


func set_asset_theme(loader, project: Dictionary) -> void:
	_loader = loader
	if not project.is_empty():
		_project = project
	queue_redraw()


func _ui_texture(key: String) -> Texture2D:
	if _loader == null or not _loader.has_method("texture_for"):
		return null
	var id := ""
	if _loader.has_method("resolve_ui"):
		var resolved = _loader.resolve_ui(key, _project)
		if typeof(resolved) == TYPE_DICTIONARY:
			id = String((resolved as Dictionary).get("id", ""))
		else:
			id = String(resolved)
	if id.is_empty():
		return null
	var loaded = _loader.texture_for(id)
	return loaded if loaded is Texture2D else null


func _chip_texture(entity_id: String, level: int) -> Texture2D:
	if _loader == null or not _loader.has_method("chip_texture"):
		return null
	var loaded = _loader.chip_texture(entity_id, level, _project)
	return loaded if loaded is Texture2D else null


## 9-slice draw: corners stay 1:1 so the plate keeps its rounded radius.
func _draw_nine(texture: Texture2D, r: Rect2, corner: float) -> void:
	var src := texture.get_size()
	var c := minf(corner, minf(src.x, src.y) * 0.5)
	if c <= 0.0:
		draw_texture_rect(texture, r, false)
		return
	var inner_w := maxf(r.size.x - c * 2.0, 0.0)
	var inner_h := maxf(r.size.y - c * 2.0, 0.0)
	var sw := src.x - c * 2.0
	var sh := src.y - c * 2.0
	draw_texture_rect_region(texture, Rect2(r.position.x, r.position.y, c, c), Rect2(0, 0, c, c))
	draw_texture_rect_region(texture, Rect2(r.end.x - c, r.position.y, c, c), Rect2(src.x - c, 0, c, c))
	draw_texture_rect_region(texture, Rect2(r.position.x, r.end.y - c, c, c), Rect2(0, src.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(r.end.x - c, r.end.y - c, c, c), Rect2(src.x - c, src.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(r.position.x + c, r.position.y, inner_w, c), Rect2(c, 0, sw, c))
	draw_texture_rect_region(texture, Rect2(r.position.x + c, r.end.y - c, inner_w, c), Rect2(c, src.y - c, sw, c))
	draw_texture_rect_region(texture, Rect2(r.position.x, r.position.y + c, c, inner_h), Rect2(0, c, c, sh))
	draw_texture_rect_region(texture, Rect2(r.end.x - c, r.position.y + c, c, inner_h), Rect2(src.x - c, c, c, sh))
	draw_texture_rect_region(texture, Rect2(r.position.x + c, r.position.y + c, inner_w, inner_h),
			Rect2(c, c, sw, sh))


func set_card_anchors(rows: Array) -> void:
	_anchors = rows.duplicate(true)
	_layout()
	queue_redraw()


func set_project(project: Dictionary) -> void:
	_project = project if typeof(project) == TYPE_DICTIONARY else {}
	if not cards.is_empty():
		queue_redraw()


func build_from_level(level: Dictionary) -> Dictionary:
	cards = []
	_rects = {}
	_level_id = ""
	if typeof(level) != TYPE_DICTIONARY:
		return {"ok": false, "cards": 0, "missions": 0, "level_id": ""}
	_level_id = String(level.get("id", ""))
	var orders = level.get("orders", [])
	var missions := 0
	if typeof(orders) == TYPE_ARRAY:
		for raw in (orders as Array):
			if typeof(raw) != TYPE_DICTIONARY or cards.size() >= MAX_CARDS:
				continue
			var card := _make_card(raw)
			missions += (card["mission"] as Array).size()
			cards.append(card)
	_layout()
	if is_inside_tree():
		queue_redraw()
	return {"ok": true, "cards": cards.size(), "missions": missions, "level_id": _level_id}


## Live progress from a sim snapshot: [{id, mission:[[entity, level, have],...],
## star, coin, done}]. Unknown fields are ignored, so a partial row is safe.
func sync_orders(rows: Array) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var card := _card(String(row.get("id", "")))
		if card.is_empty():
			continue
		card["done"] = bool(row.get("done", false))
		var mission_rows = row.get("mission", [])
		var items: Array = card["mission"]
		var done := bool(card["done"])
		for i in range(items.size()):
			# A claimed order reads as satisfied even though the sim zeroes `have`
			# on claim; that is a display derivation, the sim data stays untouched.
			if done:
				items[i]["have"] = int(items[i]["need"])
				continue
			if typeof(mission_rows) != TYPE_ARRAY or i >= (mission_rows as Array).size():
				continue
			var m = (mission_rows as Array)[i]
			if typeof(m) == TYPE_ARRAY and (m as Array).size() >= 3:
				items[i]["have"] = int((m as Array)[2])
	if is_inside_tree():
		queue_redraw()


func set_order_done(order_id: String, done: bool) -> bool:
	var card := _card(order_id)
	if card.is_empty():
		return false
	card["done"] = done
	if is_inside_tree():
		queue_redraw()
	return true


func set_mission_have(order_id: String, index: int, have: int) -> bool:
	var card := _card(order_id)
	if card.is_empty():
		return false
	var items: Array = card["mission"]
	if index < 0 or index >= items.size():
		return false
	items[index]["have"] = have
	if is_inside_tree():
		queue_redraw()
	return true


func card_rect(order_id: String) -> Rect2:
	if _rects.is_empty():
		_layout()
	var r = _rects.get(order_id, null)
	if r is Rect2:
		return r
	return Rect2()


## Character portrait centre in this control's local space: the landing point of
## a delivered item, and the anchor for star/coin flights.
func portrait_center(order_id: String) -> Vector2:
	var r := card_rect(order_id)
	if r.size.x <= 0.0:
		return Vector2(size.x * 0.5, size.y * 0.5)
	return Vector2(r.position.x + 62.0, r.position.y + 66.0)


func mission_chip_center(order_id: String, index: int) -> Vector2:
	var r := card_rect(order_id)
	if r.size.x <= 0.0:
		return Vector2(size.x * 0.5, size.y * 0.5)
	return Vector2(r.position.x + 120.0 + 100.0 * float(index) + 31.0, r.position.y + 123.0)


func set_palette(colors: Dictionary) -> void:
	if typeof(colors) == TYPE_DICTIONARY and not colors.is_empty():
		palette = colors
		if is_inside_tree():
			queue_redraw()


func set_metrics(values: Dictionary) -> void:
	if typeof(values) == TYPE_DICTIONARY:
		metrics = values
		if is_inside_tree():
			queue_redraw()


func debug_summary() -> String:
	var done := 0
	var missions := 0
	var parts: Array = []
	for card in cards:
		if bool(card.get("done", false)):
			done += 1
		var items: Array = card.get("mission", [])
		missions += items.size()
		var tokens: Array = []
		for item in items:
			tokens.append("%s@%d %d/%d" % [String(item.get("entity", "")),
					int(item.get("level", 0)), int(item.get("have", 0)), int(item.get("need", 1))])
		parts.append("%s:%s:%s done=%d" % [String(card.get("id", "")),
				String(card.get("character", "")), " ".join(tokens),
				1 if bool(card.get("done", false)) else 0])
	var tail := ""
	if not parts.is_empty():
		tail = " " + " | ".join(parts)
	return "cards=%d done=%d missions=%d%s" % [cards.size(), done, missions, tail]


# ---------------------------------------------------------------------- layout

func _layout() -> void:
	_rects = {}
	_layout_size = Vector2(size.x, size.y)
	var total_w := size.x if size.x > 0.0 else WIDTH
	var total_h := size.y if size.y > 0.0 else HEIGHT
	var n := cards.size()
	if n == 0:
		return
	var gap := float(metrics.get("card_gap", 14.0))
	var card_w := minf((total_w - MARGIN * 2.0 - gap * float(n - 1)) / float(n), MAX_CARD_W)
	var row_w := card_w * float(n) + gap * float(n - 1)
	var start_x := (total_w - row_w) * 0.5
	# 2026-11-05: compact card — content only (mission + rewards), centred in the band.
	var card_h := minf(total_h - 8.0, 140.0)
	var start_y := maxf((total_h - card_h) * 0.5, 4.0)
	for i in n:
		var rect := Rect2(start_x + float(i) * (card_w + gap), start_y, card_w, card_h)
		if _anchors.size() == n:
			# WYSIWYG anchor: the card is as wide as its character and bottom-aligned.
			var a: Dictionary = _anchors[i]
			var w := maxf(float(a.get("width", card_w)), 200.0)
			var bottom := float(a.get("bottom", start_y + card_h))
			var cx := float(a.get("center", rect.get_center().x))
			rect = Rect2(cx - w * 0.5, bottom - card_h, w, card_h)
		_rects[String(cards[i]["id"])] = rect


# --------------------------------------------------------------------- drawing

func _draw() -> void:
	if _rects.size() != cards.size() or _layout_size != Vector2(size.x, size.y):
		_layout()
	# Opaque page strip: the panel sits on top of the board's own caption row, and
	# the sim owns the playfield below it, so the panel paints its own background.
	draw_rect(Rect2(Vector2.ZERO, Vector2(maxf(size.x, WIDTH), maxf(size.y, HEIGHT))),
			_c("page", Color("#E6EDF6")), true)
	for card in cards:
		_draw_card(card, card_rect(String(card.get("id", ""))))


func _draw_card(card: Dictionary, r: Rect2) -> void:
	if r.size.x <= 0.0:
		return
	var radius := int(round(float(metrics.get("card_radius", 22.0))))
	var card_bg: Color = _c("card", Color.WHITE)
	var card_edge: Color = _c("card_edge", Color("#BACCE0"))
	var ink: Color = _c("ink", Color("#22303F"))
	var dim: Color = _c("ink_dim", Color("#5C6B7D"))

	# 2026-11-05: the card plate is 任务背景板 (九宫格) instead of the flat white box.
	var plate := _ui_texture("bar_board")
	if plate != null:
		_draw_nine(plate, r, 26.0)
	else:
		_rounded(r, radius, card_bg)
		_rounded_outline(r, radius, card_edge, 2)

	# 2026-11-05: the avatar circle, the display name and the character id are gone —
	# the card is just the mission slot plus the reward column.
	var items: Array = card.get("mission", [])
	var chip_size := 125.0
	var gap := 14.0
	var row := chip_size * float(items.size()) + gap * float(maxi(items.size() - 1, 0))
	var chip_x := (r.size.x - row) * 0.5
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var chip := Rect2(r.position + Vector2(chip_x + (chip_size + gap) * float(i),
				(r.size.y - chip_size) * 0.5), Vector2(chip_size, chip_size))
		var hue: Color = item.get("hue", Color("#94A3B8"))
		var ready := int(item.get("have", 0)) >= int(item.get("need", 1))
		# 2026-11-05: the mission slot shows the real chip icon when the loader can
		# resolve it; the procedural tile stays as the no-asset fallback.
		var icon := _chip_texture(String(item.get("entity", "")), int(item.get("level", 1)))
		if icon != null:
			draw_texture_rect(icon, chip.grow(6.0), false)
		else:
			_rounded(chip, 14, hue if ready else hue.lerp(Color(1.0, 1.0, 1.0), 0.28))
			_rounded_outline(chip, 14, hue.darkened(0.22), 2)
			_text_center(chip, String(item.get("label", "?")), 24, Color.WHITE)


	_draw_reward_row(r, int(card.get("coin", 0)), 0.0)
	if int(card.get("star", 0)) > 0:
		_draw_star_row(r, int(card.get("star", 0)))

	if bool(card.get("done", false)):
		# 2026-11-05: no green rim, no small check — one confirm badge centred on the card.
		var confirm := _ui_texture("confirm")
		var size := Vector2(126.0, 74.0)
		var at := Rect2(r.get_center() - size * 0.5, size)
		if confirm != null:
			draw_texture_rect(confirm, at, false)
		else:
			_rounded(at, 20, _c("done", COLOR_DONE))


## Coin reward above the card: task_reward icon + "+N", right-aligned with the card.
func _draw_reward_row(r: Rect2, amount: int, dy: float) -> void:
	var icon := _ui_texture("task_reward")
	var icon_size := Vector2(132.0, 49.0)
	var text_size := 34
	var label := "+%d" % amount
	var base_y := r.position.y - 54.0 + dy
	if icon != null:
		var icon_rect := Rect2(Vector2(r.end.x - icon_size.x, base_y), icon_size)
		draw_texture_rect(icon, icon_rect, false)
		var font := _font_display()
		if font != null:
			# 2026-11-05: the number is right-aligned inside the reward pill, so its right
			# edge lines up with the card's right edge.
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			var at := Vector2(icon_rect.end.x - 14.0 - width,
					icon_rect.get_center().y + float(text_size) * 0.36)
			draw_string(font, at + Vector2(1.5, 1.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
					text_size, Color(0.24, 0.14, 0.02, 0.55))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size,
					Color(1.0, 0.97, 0.86))
	else:
		_coin(Vector2(r.end.x - 30.0, base_y + 24.0))
		_text_right(Vector2(r.end.x - 54.0, base_y + 6.0), label, 28, _c("ink", Color("#22303F")))


## Star reward sits under the coin row, same right edge.
func _draw_star_row(r: Rect2, amount: int) -> void:
	_star(Vector2(r.end.x - 18.0, r.position.y - 106.0), 15.0)
	var label := "+%d" % amount
	var corner := Vector2(r.end.x - 40.0, r.position.y - 122.0)
	_text_right(corner + Vector2(1.5, 1.5), label, 26, Color(0.22, 0.14, 0.02, 0.6))
	_text_right(corner, label, 26, Color(1.0, 0.97, 0.86))


func _font_display() -> Font:
	if _font_bold == null:
		_font_bold = UiFonts.load_font(UiFonts.DISPLAY_BOLD)
	return _font_bold


func _text_right(top_right: Vector2, text: String, size_px: int, color: Color) -> void:
	var font := _font_display()
	if font == null:
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(top_right.x - width, top_right.y + float(size_px)),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _pill(r: Rect2) -> void:
	var pill_rect := Rect2(r.position + Vector2(14.0, r.size.y - 56.0),
			Vector2(r.size.x - 28.0, 44.0))
	var done_color: Color = _c("done", COLOR_DONE)
	_rounded(pill_rect, 23, done_color)
	_rounded_outline(pill_rect, 23, done_color.darkened(0.18), 2)
	_check(Vector2(pill_rect.position.x + 34.0, pill_rect.get_center().y), 16.0)
	_text_center(Rect2(pill_rect.position + Vector2(56.0, 0.0),
			Vector2(pill_rect.size.x - 70.0, pill_rect.size.y)), "DONE", 26, Color.WHITE)


func _portrait(c: Vector2, radius: float, card: Dictionary) -> void:
	var hue: Color = card.get("hue", Color("#94A3B8"))
	draw_circle(c, radius + 3.0, hue.darkened(0.28), true, -1.0, true)
	draw_circle(c, radius, hue, true, -1.0, true)
	# 2026-11-05: the little arc highlight ("小花") is gone; the portrait is a clean disc.
	var initial := String(card.get("initial", "?"))
	_text_center(Rect2(c - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
			initial, 40, Color.WHITE)


func _check(c: Vector2, radius: float) -> void:
	draw_circle(c, radius, Color(0.20, 0.50, 0.16, 0.96), true, -1.0, true)
	var pts := PackedVector2Array([
		c + Vector2(-radius * 0.48, 0.0), c + Vector2(-radius * 0.10, radius * 0.40),
		c + Vector2(radius * 0.50, -radius * 0.42),
	])
	draw_polyline(pts, Color.WHITE, maxf(3.0, radius * 0.30), true)


func _coin(c: Vector2) -> void:
	var gold: Color = _c("coin", Color("#F6C445"))
	draw_circle(c, 15.0, gold.darkened(0.20), true, -1.0, true)
	draw_circle(c, 12.0, gold, true, -1.0, true)


func _star(c: Vector2, r: float) -> void:
	var hue: Color = _c("star", Color("#F2B233"))
	var pts := PackedVector2Array()
	for i in 10:
		var radius := r if i % 2 == 0 else r * 0.45
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(pts, hue)


# ---------------------------------------------------------------- primitives

func _make_card(raw: Dictionary) -> Dictionary:
	var cid := String(raw.get("character", ""))
	var ent := _dict(_dict(_project.get("entities", {})).get(cid, {}))
	var vis := _dict(ent.get("visual", {}))
	var ch := _dict(_dict(_project.get("characters", {})).get(cid, {}))
	var display := String(ch.get("display", ""))
	if display.is_empty():
		display = cid
	var items: Array = []
	var raw_mission = raw.get("mission", [])
	if typeof(raw_mission) == TYPE_ARRAY:
		for m in (raw_mission as Array):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var entity_id := String((m as Dictionary).get("entity", ""))
			var ent2 := _dict(_dict(_project.get("entities", {})).get(entity_id, {}))
			var vis2 := _dict(ent2.get("visual", {}))
			items.append({
				"entity": entity_id,
				"level": int((m as Dictionary).get("level", 1)),
				"have": 0,
				"need": 1,
				"hue": Color.from_string(String(vis2.get("hue", "")), Color("#94A3B8")),
				"label": String(vis2.get("label", entity_id.left(3))),
			})
	return {
		"id": String(raw.get("id", "")),
		"character": cid,
		"display": display,
		"initial": display.substr(0, 1) if not display.is_empty() else "?",
		"hue": Color.from_string(String(vis.get("hue", "")), Color("#94A3B8")),
		"mission": items,
		"star": int(raw.get("star", 0)),
		"coin": int(raw.get("coin", 0)),
		"done": bool(raw.get("done", false)),
	}


func _card(order_id: String) -> Dictionary:
	for card in cards:
		if String(card.get("id", "")) == order_id:
			return card
	return {}


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


func _text_at(pos: Vector2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	draw_string(_font, pos + Vector2(0.0, float(size_px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			size_px, color)


func _text_center(rect: Rect2, text: String, size_px: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var ascent := _font.get_ascent(size_px)
	var descent := _font.get_descent(size_px)
	var pos := Vector2(
		rect.position.x + (rect.size.x - measured.x) * 0.5,
		rect.position.y + (rect.size.y - (ascent + descent)) * 0.5 + ascent
	)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


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
