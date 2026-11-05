extends Control
## M1 static board view: the 棋盘.psd geometry as a 7x9 grid of 140.428571 x
## 140.333333 px cells inside the 983x1263 container at (48,466), on a 1080x1920
## canvas (§20.5 / §20.6).
##
## Two drawing layers, picked per element at draw time:
##
##   themed    the AssetGuard + ThemeLoader pair attached through set_asset_theme()
##             resolves `bg_bottom`, `bg_top`, `board_frame`, `cell`, `select`,
##             `lock`, `web`, `bubble`, `ice` to real textures, and each chip
##             resolves through chip_texture(entity, level)
##   procedural  every one of those falls back to the code below when the loader is
##             absent, the id does not resolve, or the file is missing, so a
##             relocated copy without the copies renders the same layout with no
##             texture at all
##
## `_draw()` never loads anything: all IO happens in set_asset_theme() or in the
## theme loader.
##
## A PLACEHOLDER branch exists for the board frame, but it is only reachable when
## `allow_placeholders` is true (`--allow-placeholders` on the command line) and it
## still asks the asset guard first.
##
## No global type name here on purpose: several agents work in this project at the
## same time, so this file is preloaded by whoever needs it.

const AssetGuardScript := "res://src/assets/asset_guard.gd"
const MANIFEST_INDEX := "res://data/manifest_index.json"
const SAMPLE_PROJECT := "res://data/sample_project.json"
const FONT_PATH := "res://assets/fonts/font_zh.otf"
const FRAME_ID := "board_frame"

const COLS := 7
const ROWS := 9
## §20.5: the board container `board_frame` is 983x1263 at (48,466), so one cell is
## 983/7 x 1263/9 = 140.428571 x 140.333333. CELL_W / CELL_H carry that exact
## fraction and cell_rect() derives every edge from the container, so the 63 cells
## tile the container with no remainder and cell (6,8) ends exactly at (1031,1729).
##
## CELL stays the plain integer 140 on purpose: movie_scene.gd does
## `float(BoardView.CELL)` and derives its origin, board size and every cell
## position from BOARD_ORIGIN / BOARD_SIZE / CELL, and all cell-index math here is
## integer Vector2i. Keeping CELL an int means the renderer and the view agree on
## the column/row step without either side rounding a fraction, while the view's
## own geometry uses the exact fractional size.
const CELL := 140
const CELL_GAP := 4
const BOARD_ORIGIN := Vector2(48.0, 466.0)
const BOARD_SIZE := Vector2(983.0, 1263.0)
const CELL_W := 983.0 / 7.0
const CELL_H := 1263.0 / 9.0
const PAGE_SIZE := Vector2(1080.0, 1920.0)

## §20.6 item 1: main_bg_01_bottom is 1080x1536 at (0,384) and fills to the bottom,
## main_bg_01_top is 1080x400 and covers the top band.
const BG_BOTTOM_RECT := Rect2(0.0, 384.0, 1080.0, 1536.0)
const BG_TOP_RECT := Rect2(0.0, 0.0, 1080.0, 400.0)

## §20.6 item 6: 182x182 chip art drawn at 132-140 px, bottom-aligned in the cell,
## over a soft shadow. 132 keeps the 4 px cell gap readable at this cell size.
const CHIP_DRAW_SIZE := 132.0
const SHADOW_STEPS := 3

## §20.6 logical slots handed to ThemeLoader.resolve_ui(). The ids stay opaque to
## this file: it only ever asks the loader for a key and draws what comes back.
const UI_BG_BOTTOM := "bg_bottom"
const UI_BG_TOP := "bg_top"
const UI_BOARD_FRAME := "board_frame"
const UI_CELL := "cell"
const UI_SELECT := "select"
const UI_LOCK := "lock"
const UI_WEB := "web"
const UI_BUBBLE := "bubble"
const UI_ICE := "ice"
const UI_KEYS := [
	UI_BG_BOTTOM, UI_BG_TOP, UI_BOARD_FRAME, UI_CELL, UI_SELECT,
	UI_LOCK, UI_WEB, UI_BUBBLE, UI_ICE,
]
const ICE_COUNTDOWN := "19:28"

const COLOR_PAGE := Color("#E6EDF6")
const COLOR_PANEL := Color("#A8BDD5")
const COLOR_PANEL_EDGE := Color("#93AAC6")
const COLOR_CELL := Color("#C9DAEB")
const COLOR_CELL_LIP := Color("#D8E5F2")
const COLOR_SPECIAL := Color("#C0C8D8")
const COLOR_COMPLETE := Color("#8FD46B")
const COLOR_INK := Color("#22303F")
const COLOR_WHITE := Color(1.0, 1.0, 1.0)
const COLOR_HUE_FALLBACK := Color("#94A3B8")
const COLOR_GLOW := Color(0.35, 0.84, 0.42)
## §7 asks for a yellow selection frame; the PSD reference wears white corner
## brackets, so the procedural frame carries both: yellow brackets + yellow glow.
const COLOR_SELECT := Color("#FFC427")
const SELECT_SCALE := 1.08
const SELECT_LIFT := Vector2(0.0, -5.0)
const SELECT_TOWARD := 7.0
const COLOR_CAPSULE := Color(0.10, 0.15, 0.21, 0.82)
const COLOR_SHADOW := Color(0.04, 0.08, 0.14)

const FONT_TITLE := 40
const FONT_INK := 30
const FONT_CAPS := 22
const FONT_COUNTER := 26

const OBSTACLE_TYPES := ["lock", "web", "bubble", "ice"]
const DEFAULT_SELECTED := [3, 3]
const DEFAULT_COMPLETED := [[1, 4]]

## §7 item 4 "board full prompt": a procedural toast strip, so the prompt needs no
## .tscn edit and no asset. The manifest id ui_board_full_toast stays REFERENCE_ONLY
## and is deliberately never referenced here; the strip is drawn from code like
## every other board element. The rect sits above the §20.5 items bar (193,1731) and
## stays fully inside the 1080x1920 canvas.
const TOAST_SECONDS := 1.5
const TOAST_FADE := 0.25
const TOAST_RECT := Rect2(190.0, 1600.0, 700.0, 84.0)
const COLOR_TOAST := Color(0.10, 0.15, 0.21, 0.86)

var allow_placeholders: bool = false
## The level caption and the kind legend are debug affordances for a standalone
## board: a composed screen (game_screen) owns that space with its own order cards
## and §20.5 items bar, so it can switch them off with one assignment.
var show_debug_labels: bool = true
var project_path: String = ""
var level_index: int = 0
var level_id: String = ""
var board_width: int = COLS
var board_height: int = ROWS

var _items: Dictionary = {} # Vector2i -> {kind, entity, level, hue, label, charges}
var _obstacles: Dictionary = {} # Vector2i -> type
var _selected := Vector2i(-1, -1)
var _completed: Dictionary = {} # Vector2i -> true
var _font: Font = null
var _frame_texture: Texture2D = null
var _box_cache: Dictionary = {}
var _clock: float = 0.0
var _toast_text: String = ""
var _toast_start: float = 0.0
var _toast_seconds: float = TOAST_SECONDS
## The theme pair attached through set_asset_theme() (and its M1 alias
## set_chip_icons()). Null means "no theme attached": every chip keeps its
## procedural drawing and every UI slot resolves to "".
var _asset_loader = null
var _asset_project: Dictionary = {}
## "bg_bottom" -> Texture2D / null. One resolve per key per attach; _draw() runs
## up to 63 cell lookups per frame and must not walk the theme dictionaries there.
var _ui_tex_cache: Dictionary = {}


func _ready() -> void:
	allow_placeholders = OS.get_cmdline_user_args().has("--allow-placeholders")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _load_font()
	if allow_placeholders:
		_frame_texture = _load_placeholder_frame()
	if _items.is_empty():
		build_from_project(SAMPLE_PROJECT, 0)
	queue_redraw()
	print("[view] ready allow_placeholders=%s %s" % [str(allow_placeholders), debug_summary()])


# --------------------------------------------------------------------- public API

## Parses one level straight out of project.json (the view must not depend on
## src/core). Returns {"ok", "cells", "items", "obstacles", "error"} plus
## "obstacle_types" and "level_id" for tooling.
func build_from_project(path: String, index: int = 0) -> Dictionary:
	_reset_state()
	var out := {
		"ok": false,
		"cells": 0,
		"items": 0,
		"obstacles": 0,
		"error": "",
		"obstacle_types": [],
		"level_id": "",
	}
	if not FileAccess.file_exists(path):
		out["error"] = "project file not found: " + path
		return out

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		out["error"] = "project root is not a JSON object"
		return out
	var project: Dictionary = parsed

	var levels = project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY or (levels as Array).is_empty():
		out["error"] = "project has no levels array"
		return out
	var levels_arr: Array = levels
	if index < 0 or index >= levels_arr.size():
		out["error"] = "level index out of range: %d (levels=%d)" % [index, levels_arr.size()]
		return out
	var level = levels_arr[index]
	if typeof(level) != TYPE_DICTIONARY:
		out["error"] = "level %d is not an object" % index
		return out

	var entities := _as_dict(project.get("entities", {}))
	var generators := _as_dict(project.get("generators", {}))

	project_path = path
	level_index = index
	level_id = String((level as Dictionary).get("id", "level_%d" % (index + 1)))
	out["level_id"] = level_id

	var board := _as_dict((level as Dictionary).get("board", {}))
	board_width = clampi(int(board.get("width", COLS)), 1, COLS)
	board_height = clampi(int(board.get("height", ROWS)), 1, ROWS)

	for raw in _as_array(board.get("slots", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = raw
		var key := Vector2i(int(slot.get("x", -1)), int(slot.get("y", -1)))
		if not _in_bounds(key):
			continue
		_items[key] = _make_item(slot, entities, generators)

	for raw in _as_array((level as Dictionary).get("obstacles", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var ob: Dictionary = raw
		var type := String(ob.get("type", ""))
		if not OBSTACLE_TYPES.has(type):
			continue
		var cell_ref = ob.get("slot", [])
		if typeof(cell_ref) != TYPE_ARRAY or (cell_ref as Array).size() < 2:
			continue
		var key := Vector2i(int((cell_ref as Array)[0]), int((cell_ref as Array)[1]))
		if not _in_bounds(key):
			continue
		_obstacles[key] = type

	out["ok"] = true
	out["cells"] = board_width * board_height
	out["items"] = _items.size()
	out["obstacles"] = _obstacles.size()
	out["obstacle_types"] = obstacle_types()
	_apply_default_demo_state()
	return out


## View state only: {"selected": [x, y], "completed": [[x, y], ...]}.
func apply_state(state: Dictionary) -> void:
	_selected = Vector2i(-1, -1)
	_completed.clear()
	if state.has("selected"):
		var sel := _to_cell(state["selected"])
		if _in_bounds(sel):
			_selected = sel
	var done = state.get("completed", [])
	if typeof(done) == TYPE_ARRAY:
		for raw in done:
			var cell := _to_cell(raw)
			if _in_bounds(cell):
				_completed[cell] = true
	queue_redraw()


func debug_summary() -> String:
	var selected_text := "none"
	if _selected.x >= 0:
		selected_text = "(%d,%d)" % [_selected.x, _selected.y]
	return "board=%dx%d items=%d obstacles=%d selected=%s complete=%d" % [
		board_width, board_height, _items.size(), _obstacles.size(),
		selected_text, _completed.size(),
	]


## §20.5 geometry. Every edge is computed from the container edge, not accumulated
## from CELL_W, so the last cell ends exactly at (1031,1729) and the 63 cells tile
## the 983x1263 container with zero remainder.
func cell_rect(x: int, y: int) -> Rect2:
	var left := BOARD_ORIGIN.x + BOARD_SIZE.x * float(x) / float(COLS)
	var right := BOARD_ORIGIN.x + BOARD_SIZE.x * float(x + 1) / float(COLS)
	var top := BOARD_ORIGIN.y + BOARD_SIZE.y * float(y) / float(ROWS)
	var bottom := BOARD_ORIGIN.y + BOARD_SIZE.y * float(y + 1) / float(ROWS)
	return Rect2(left, top, right - left, bottom - top)


func obstacle_types() -> Array:
	var seen := {}
	for type in _obstacles.values():
		seen[String(type)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func item_count() -> int:
	return _items.size()


func obstacle_count() -> int:
	return _obstacles.size()


## Attaches the theme's asset table: the per-(entity, level) chip icons *and* the
## board container's own UI textures. Passing a loader is what turns the board from
## procedural blobs into real art; without this call the board renders exactly as
## before (the tests rely on both branches).
func set_asset_theme(loader, project: Dictionary) -> void:
	_asset_loader = loader
	_asset_project = project
	_ui_tex_cache.clear()
	queue_redraw()


## M1 entry point, kept for game_screen.gd and shot_board.gd: the chip icons and
## the UI textures live on the same loader, so this is the same attachment.
func set_chip_icons(loader, project: Dictionary) -> void:
	set_asset_theme(loader, project)


## How many items currently resolve to a texture (tests, tools, debug summary).
func chip_icon_count() -> int:
	if _asset_loader == null:
		return 0
	var count := 0
	for item in _items.values():
		if _chip_texture(item) != null:
			count += 1
	return count


## key -> resolved manifest id, only for the slots that resolve. Empty without a
## loader, which is what the relocated-copy test leans on.
func ui_ids() -> Dictionary:
	var out := {}
	for key in UI_KEYS:
		var id := _ui_id(String(key))
		if not id.is_empty():
			out[String(key)] = id
	return out


## One ASCII line naming every UI slot, for the screenshot tool's log.
func ui_summary() -> String:
	var ids := ui_ids()
	if ids.is_empty():
		return ""
	var parts: Array = []
	for key in UI_KEYS:
		parts.append("%s=%s" % [String(key), String(ids.get(String(key), "-"))])
	return " ".join(parts)


# --------------------------------------------------------------------- toast API
##
## The toast lives on the view clock, not on wall time: callers drive it with
## set_clock(), so the same code is deterministic in a screenshot tool and in the
## film. `_draw()` only paints while the prompt is active.

## Records the view clock. The toast window is measured from this value.
func set_clock(t: float) -> void:
	_clock = maxf(0.0, t)
	if not _toast_text.is_empty():
		queue_redraw()


## Shows `text` for `seconds` (from the current clock) and repaints.
func show_toast(text: String, seconds: float = TOAST_SECONDS) -> void:
	_toast_text = text
	_toast_seconds = seconds if seconds > 0.0 else TOAST_SECONDS
	_toast_start = _clock
	queue_redraw()


func toast_text() -> String:
	return _toast_text


func toast_duration() -> float:
	return _toast_seconds


## 1.0 for the body of the window, linear fade over the last TOAST_FADE seconds,
## 0.0 outside [start, start + duration).
func toast_alpha_at(t: float) -> float:
	if _toast_text.is_empty() or _toast_seconds <= 0.0:
		return 0.0
	var age := t - _toast_start
	if age < 0.0 or age >= _toast_seconds:
		return 0.0
	var fade := minf(TOAST_FADE, _toast_seconds)
	if fade <= 0.0:
		return 1.0
	var remaining := _toast_seconds - age
	if remaining >= fade:
		return 1.0
	return clampf(remaining / fade, 0.0, 1.0)


func toast_active_at(t: float) -> bool:
	return toast_alpha_at(t) > 0.0


# ------------------------------------------------------------------------ drawing

## §20.6 paint order: page background -> board container -> cells -> obstacles ->
## items/chips -> selection -> legend/caption -> toast.
func _draw() -> void:
	_draw_background()
	_draw_container()

	for y in board_height:
		for x in board_width:
			_draw_cell(x, y)

	for y in board_height:
		for x in board_width:
			var cell := Vector2i(x, y)
			if _completed.has(cell):
				_rounded(cell_rect(x, y).grow(-float(CELL_GAP)), 18, COLOR_COMPLETE)

	for y in board_height:
		for x in board_width:
			var cell := Vector2i(x, y)
			if _obstacles.has(cell):
				_draw_obstacle(cell, String(_obstacles[cell]))

	for y in board_height:
		for x in board_width:
			var cell := Vector2i(x, y)
			if _items.has(cell):
				_draw_item(cell, _items[cell])

	for cell in _completed.keys():
		_draw_complete_mark(cell)

	if _selected.x >= 0:
		_draw_selected_item()
		_draw_selection(_selected)

	if show_debug_labels:
		_draw_caption()
		_draw_legend()
	_draw_toast()


## §20.6 item 1. The flat page colour stays underneath, so a build without the two
## background textures is byte-identical to the procedural board.
func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, PAGE_SIZE), COLOR_PAGE, true)
	var bottom := _ui_texture(UI_BG_BOTTOM)
	if bottom != null:
		draw_texture_rect(bottom, BG_BOTTOM_RECT, false)
	var top := _ui_texture(UI_BG_TOP)
	if top != null:
		draw_texture_rect(top, BG_TOP_RECT, false)


## §20.6 item 4: the 983x1263 board container at (48,466). Theme texture first, then
## the PLACEHOLDER copy loaded in _ready(), then the procedural panel.
func _draw_container() -> void:
	var texture := _ui_texture(UI_BOARD_FRAME)
	if texture == null:
		texture = _frame_texture
	if texture != null:
		draw_texture_rect(texture, Rect2(BOARD_ORIGIN, BOARD_SIZE), false)
		return
	var panel := Rect2(BOARD_ORIGIN - Vector2(12.0, 12.0), BOARD_SIZE + Vector2(24.0, 24.0))
	_rounded(panel, 26, COLOR_PANEL)
	_rounded_outline(panel, 26, COLOR_PANEL_EDGE, 2)


## §20.6 item 5: the 94x94 checkerboard tile, scaled to the cell minus a small gap.
func _draw_cell(x: int, y: int) -> void:
	var r := cell_rect(x, y).grow(-float(CELL_GAP) * 0.5)
	var texture := _ui_texture(UI_CELL)
	if texture != null:
		draw_texture_rect(texture, r, false)
		return
	_rounded(r, 14, COLOR_CELL)
	_rounded(Rect2(r.position + Vector2(3.0, 3.0), Vector2(r.size.x - 6.0, 5.0)), 3, COLOR_CELL_LIP)


func _draw_item(key: Vector2i, item: Dictionary) -> void:
	_draw_item_rect(cell_rect(key.x, key.y).grow(-float(CELL_GAP) * 0.5), item)


func _draw_item_rect(r: Rect2, item: Dictionary) -> void:
	match String(item.get("kind", "chip")):
		"generator":
			_draw_generator(r, item)
		"special":
			_draw_special(r, item)
		_:
			_draw_chip(r, item)


func _draw_chip(r: Rect2, item: Dictionary) -> void:
	var texture := _chip_texture(item)
	if texture != null:
		_draw_chip_texture(r, texture)
		_draw_level_capsule(r, int(item.get("level", 1)))
		return
	var hue: Color = item.get("hue", COLOR_HUE_FALLBACK)
	_rounded(r, 18, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 34.0)), 12,
			Color(1.0, 1.0, 1.0, 0.18))
	var label := String(item.get("label", "?"))
	_text_shadow_center(_shift(r, Vector2(0.0, -6.0)), label, FONT_TITLE, COLOR_WHITE)
	_draw_level_capsule(r, int(item.get("level", 1)))


## §20.6 item 6: the 182x182 source art is drawn at CHIP_DRAW_SIZE (132 px, inside
## the 132-140 band), centred horizontally and standing on the bottom edge of the
## cell, over a deterministic soft shadow. No Tween and no wall clock: the same
## call paints the same pixels in a screenshot and in the film.
func _draw_chip_texture(r: Rect2, texture: Texture2D) -> void:
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale := minf(CHIP_DRAW_SIZE, minf(r.size.x, r.size.y)) / maxf(source.x, source.y)
	var drawn := source * scale
	var pos := Vector2(r.position.x + (r.size.x - drawn.x) * 0.5, r.end.y - drawn.y)
	_draw_soft_shadow(Rect2(pos, drawn))
	draw_texture_rect(texture, Rect2(pos, drawn), false)


## A stack of translucent flattened ellipses: a soft floor shadow without a shader,
## a blur pass or any randomness. Kept tight (a little wider than the art and only
## under its bottom third) so it reads as contact shadow, not as a grey box.
func _draw_soft_shadow(rect: Rect2) -> void:
	var centre := Vector2(rect.get_center().x, rect.end.y - rect.size.y * 0.10)
	for i in SHADOW_STEPS:
		var spread := 1.0 - float(i) * 0.26
		var alpha := 0.07 - float(i) * 0.017
		_ellipse(centre, Vector2(rect.size.x * 0.40 * spread, rect.size.y * 0.12 * spread),
				Color(COLOR_SHADOW.r, COLOR_SHADOW.g, COLOR_SHADOW.b, alpha))


func _ellipse(centre: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 28
	for i in steps:
		var a := TAU * float(i) / float(steps)
		points.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)


## The loader owns the disk read and the per-"entity@level" cache; the view only
## maps one item onto that lookup. Null keeps the procedural chip.
func _chip_texture(item: Dictionary) -> Texture2D:
	if _asset_loader == null or not _asset_loader.has_method("chip_texture"):
		return null
	var entity_id := String(item.get("entity", ""))
	if entity_id.is_empty():
		return null
	var texture = _asset_loader.chip_texture(entity_id, int(item.get("level", 1)),
			_asset_project)
	return texture if texture is Texture2D else null


## One UI slot, resolved through the theme loader and cached for this attachment.
func _ui_texture(key: String) -> Texture2D:
	if _ui_tex_cache.has(key):
		var cached = _ui_tex_cache[key]
		return cached if cached is Texture2D else null
	var texture: Texture2D = null
	var id := _ui_id(key)
	if not id.is_empty() and _asset_loader.has_method("texture_for"):
		var loaded = _asset_loader.texture_for(id)
		if loaded is Texture2D:
			texture = loaded
	_ui_tex_cache[key] = texture
	return texture


## theme > project > default, exactly like the chip lookup: "" means "draw it".
func _ui_id(key: String) -> String:
	if _asset_loader == null or not _asset_loader.has_method("resolve_ui"):
		return ""
	var resolved = _asset_loader.resolve_ui(key, _asset_project)
	if typeof(resolved) == TYPE_DICTIONARY:
		return String((resolved as Dictionary).get("id", ""))
	return ""


## Fits `texture` inside `r` with its aspect kept and returns false when there is
## nothing to draw, so the caller can fall back to the procedural art.
func _draw_ui_art(key: String, r: Rect2) -> bool:
	var texture := _ui_texture(key)
	if texture == null:
		return false
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return false
	var scale := minf(r.size.x / source.x, r.size.y / source.y)
	var drawn := source * scale
	draw_texture_rect(texture, Rect2(r.position + (r.size - drawn) * 0.5, drawn), false)
	return true


func _draw_generator(r: Rect2, item: Dictionary) -> void:
	var hue: Color = item.get("hue", COLOR_HUE_FALLBACK)
	_rounded(r, 10, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 30.0)), 8,
			Color(1.0, 1.0, 1.0, 0.16))
	var c := r.get_center() + Vector2(0.0, -12.0)
	var bolt := PackedVector2Array([
		c + Vector2(-11.0, -30.0), c + Vector2(16.0, -30.0), c + Vector2(3.0, -4.0),
		c + Vector2(16.0, -4.0), c + Vector2(-6.0, 34.0), c + Vector2(1.0, 3.0),
		c + Vector2(-16.0, 3.0),
	])
	draw_colored_polygon(bolt, Color(1.0, 0.94, 0.55, 0.95))
	draw_polyline(_closed(bolt), Color(1.0, 0.86, 0.28, 0.9), 2.0, true)
	_text_bottom_right(r, "x%d" % int(item.get("charges", 0)), FONT_COUNTER, COLOR_WHITE, 12.0)


func _draw_special(r: Rect2, item: Dictionary) -> void:
	_rounded(r, 14, COLOR_SPECIAL)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 30.0)), 10,
			Color(1.0, 1.0, 1.0, 0.22))
	_text_center(_shift(r, Vector2(0.0, -8.0)), String(item.get("label", "?")), FONT_INK, COLOR_INK)
	_draw_level_capsule(r, int(item.get("level", 1)))


func _draw_level_capsule(r: Rect2, level: int) -> void:
	if _font == null:
		return
	var text := "Lv.%d" % level
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CAPS).x + 16.0
	var cap := Rect2(r.position + Vector2(8.0, r.size.y - 36.0), Vector2(w, 28.0))
	_rounded(cap, 14, COLOR_CAPSULE)
	_text_center(cap, text, FONT_CAPS, COLOR_WHITE)


## Obstacle semantics are unchanged (one type per cell, same four types); only the
## art source changes: themed texture when it resolves, procedural art otherwise.
## The ice cell always carries the 19:28 countdown, texture or not.
func _draw_obstacle(key: Vector2i, type: String) -> void:
	var r := cell_rect(key.x, key.y).grow(-float(CELL_GAP) * 0.5)
	match type:
		"lock":
			if not _draw_ui_art(UI_LOCK, r):
				_draw_lock(r)
		"web":
			if not _draw_ui_art(UI_WEB, r):
				_draw_web(r.get_center())
		"bubble":
			if not _draw_ui_art(UI_BUBBLE, r):
				_draw_bubble(r.get_center())
		"ice":
			if _draw_ui_art(UI_ICE, r):
				_text_bottom_center(r, ICE_COUNTDOWN, FONT_COUNTER, Color(1.0, 1.0, 1.0, 0.96), 10.0)
			else:
				_draw_ice(r)
		_:
			_rounded(r, 14, Color(0.0, 0.0, 0.0, 0.25))


func _draw_lock(r: Rect2) -> void:
	_rounded(r, 14, Color(0.05, 0.09, 0.15, 0.55))
	var c := r.get_center()
	var metal := Color(0.91, 0.94, 0.97)
	draw_arc(c + Vector2(0.0, -6.0), 17.0, PI, TAU, 28, metal, 7.0, true)
	_rounded(Rect2(c + Vector2(-26.0, -4.0), Vector2(52.0, 40.0)), 7, metal)
	var hole := Color(0.16, 0.22, 0.30)
	draw_circle(c + Vector2(0.0, 10.0), 5.5, hole, true, -1.0, true)
	draw_rect(Rect2(c + Vector2(-2.5, 10.0), Vector2(5.0, 12.0)), hole, true)


func _draw_web(c: Vector2) -> void:
	var white := Color(1.0, 1.0, 1.0, 0.70)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * 8.0, c + dir * 62.0, white, 3.0, true)
	for ring in [22.0, 40.0, 58.0]:
		var pts := PackedVector2Array()
		for i in 9:
			var a0 := TAU * float(i) / 8.0
			pts.append(c + Vector2(cos(a0), sin(a0)) * float(ring))
			if i < 8:
				var am := a0 + TAU / 16.0
				pts.append(c + Vector2(cos(am), sin(am)) * float(ring) * 0.86)
		draw_polyline(pts, white, 2.5, true)


func _draw_bubble(c: Vector2) -> void:
	draw_circle(c, 56.0, Color(0.72, 0.86, 1.0, 0.32), true, -1.0, true)
	draw_circle(c, 56.0, Color(1.0, 1.0, 1.0, 0.85), false, 6.0, true)
	draw_circle(c + Vector2(-21.0, -21.0), 13.0, Color(1.0, 1.0, 1.0, 0.75), true, -1.0, true)
	draw_circle(c + Vector2(-6.0, -31.0), 6.0, Color(1.0, 1.0, 1.0, 0.60), true, -1.0, true)


func _draw_ice(r: Rect2) -> void:
	var inner := r.grow(-4.0)
	_rounded(inner, 14, Color(1.0, 1.0, 1.0, 0.35))
	_rounded_outline(inner, 14, Color(1.0, 1.0, 1.0, 0.80), 3)
	var c := inner.get_center()
	draw_line(c + Vector2(-34.0, -40.0), c + Vector2(-6.0, -6.0), Color(1.0, 1.0, 1.0, 0.55), 3.0, true)
	draw_line(c + Vector2(6.0, 6.0), c + Vector2(34.0, 40.0), Color(1.0, 1.0, 1.0, 0.55), 3.0, true)
	draw_line(c + Vector2(28.0, -38.0), c + Vector2(10.0, -12.0), Color(1.0, 1.0, 1.0, 0.35), 2.0, true)
	_text_bottom_center(inner, ICE_COUNTDOWN, FONT_COUNTER, Color(1.0, 1.0, 1.0, 0.96), 10.0)


func _draw_complete_mark(key: Vector2i) -> void:
	var c := cell_rect(key.x, key.y).get_center()
	var badge := c + Vector2(36.0, 34.0)
	draw_circle(badge, 22.0, Color(0.25, 0.55, 0.20, 0.96), true, -1.0, true)
	draw_circle(badge, 22.0, Color(1.0, 1.0, 1.0, 0.55), false, 2.0, true)
	var check := PackedVector2Array([
		badge + Vector2(-11.0, 1.0), badge + Vector2(-3.0, 9.0), badge + Vector2(11.0, -9.0),
	])
	draw_polyline(check, Color(1.0, 1.0, 1.0, 1.0), 6.0, true)


## §7: "选中提示：黄框 + 停留放大/靠近".
## The selected chip is redrawn lifted toward the board centre and scaled up 8%,
## then framed: the themed `select` frame sits centred on the cell (§20.6 item 7),
## and the procedural fallback keeps the yellow glow + corner brackets.
func _selection_offset(key: Vector2i) -> Vector2:
	var centre := cell_rect(key.x, key.y).get_center()
	var board_centre := BOARD_ORIGIN + BOARD_SIZE * 0.5
	var toward := Vector2.ZERO
	if not centre.is_equal_approx(board_centre):
		toward = (board_centre - centre).normalized() * SELECT_TOWARD
	return toward + SELECT_LIFT


func _draw_selected_item() -> void:
	if not _items.has(_selected):
		return
	var cell := cell_rect(_selected.x, _selected.y)
	var base := cell.grow(-float(CELL_GAP) * 0.5)
	var half := base.size * 0.5
	var origin := cell.get_center() + _selection_offset(_selected)
	# A themed chip is transparent art: the lift shadow would read as a grey box
	# around the icon, so it stays on the procedural chip only.
	if _chip_texture(_items[_selected]) == null:
		draw_set_transform(origin + Vector2(0.0, 12.0), 0.0, Vector2(SELECT_SCALE, SELECT_SCALE))
		_rounded(Rect2(-half, base.size), 20, Color(0.05, 0.09, 0.14, 0.18))
	draw_set_transform(origin, 0.0, Vector2(SELECT_SCALE, SELECT_SCALE))
	_draw_item_rect(Rect2(-half, base.size), _items[_selected])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_selection(key: Vector2i) -> void:
	var cell := cell_rect(key.x, key.y)
	var texture := _ui_texture(UI_SELECT)
	if texture != null:
		# §20.6 item 7: the frame covers the whole cell, centred on it. The chip
		# above still carries the lift/scale; the frame itself does not travel.
		var frame_size := texture.get_size()
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			draw_texture_rect(texture, Rect2(cell.get_center() - frame_size * 0.5, frame_size), false)
			return

	var tile := cell.grow(-float(CELL_GAP) * 0.5)
	var offset := _selection_offset(key)
	var r := Rect2(tile.position + offset, tile.size)
	_rounded_outline(r.grow(9.0), 22, Color(COLOR_SELECT.r, COLOR_SELECT.g, COLOR_SELECT.b, 0.26), 10)
	_rounded_outline(r.grow(3.0), 19, Color(COLOR_SELECT.r, COLOR_SELECT.g, COLOR_SELECT.b, 0.85), 5)

	var arm := 26.0
	var width := 6.0
	var ink := Color(COLOR_SELECT.r, COLOR_SELECT.g, COLOR_SELECT.b, 1.0)
	var left := r.position.x
	var top := r.position.y
	var right := r.position.x + r.size.x
	var bottom := r.position.y + r.size.y
	var corners := [
		PackedVector2Array([Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top)]),
		PackedVector2Array([Vector2(right - arm, top), Vector2(right, top), Vector2(right, top + arm)]),
		PackedVector2Array([Vector2(left, bottom - arm), Vector2(left, bottom), Vector2(left + arm, bottom)]),
		PackedVector2Array([Vector2(right - arm, bottom), Vector2(right, bottom), Vector2(right, bottom - arm)]),
	]
	for corner in corners:
		draw_polyline(corner, ink, width, true)


## The level line sits in the free strip above the board container (466 - 46).
func _draw_caption() -> void:
	if _font == null:
		return
	var text := "LEVEL %d / %s" % [level_index + 1, level_id]
	var pos := Vector2(BOARD_ORIGIN.x, BOARD_ORIGIN.y - 46.0)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.30, 0.40, 0.52, 0.85))


## Debug affordance for a standalone board: the kind legend stays below the
## container, where a composed screen (game_screen draws its own items bar and
## footer band on top) can cover it — the top band belongs to the order cards.
func _draw_legend() -> void:
	if _font == null:
		return
	var y := BOARD_ORIGIN.y + BOARD_SIZE.y + 48.0
	var x := BOARD_ORIGIN.x
	var entries := [
		["chip", "CHIP"], ["generator", "GENERATOR"], ["special", "SPECIAL"],
		["lock", "LOCK"], ["web", "WEB"], ["bubble", "BUBBLE"], ["ice", "ICE"],
	]
	for entry in entries:
		var label := String(entry[1])
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var swatch := Rect2(Vector2(x, y - 11.0), Vector2(20.0, 14.0))
		_rounded(swatch, 5, _legend_color(String(entry[0])))
		draw_string(_font, Vector2(x + 26.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(0.32, 0.41, 0.51, 0.9))
		x += 26.0 + w + 18.0


## §7 item 4: half-transparent rounded strip + centred text, painted only while the
## prompt is alive. Nothing is drawn after the window closes, so a still frame
## without a prompt stays byte-identical to the pre-toast board.
func _draw_toast() -> void:
	if not toast_active_at(_clock):
		return
	var alpha := toast_alpha_at(_clock)
	var bar := TOAST_RECT
	_rounded(bar, 24, Color(COLOR_TOAST.r, COLOR_TOAST.g, COLOR_TOAST.b, COLOR_TOAST.a * alpha))
	_rounded_outline(bar, 24, Color(1.0, 1.0, 1.0, 0.55 * alpha), 2)
	_text_center(bar, _toast_text, FONT_INK, Color(1.0, 1.0, 1.0, alpha))


func _legend_color(kind: String) -> Color:
	match kind:
		"generator":
			return Color("#5B8DEF")
		"special":
			return COLOR_SPECIAL
		"lock":
			return Color(0.16, 0.22, 0.30)
		"web":
			return Color(0.65, 0.72, 0.80)
		"bubble":
			return Color(0.72, 0.86, 1.0)
		"ice":
			return Color(0.93, 0.97, 1.0)
		_:
			return Color("#F2A65A")


# ------------------------------------------------------------------ draw primitives

func _rounded(rect: Rect2, radius: int, color: Color) -> void:
	var box := _style_box(radius, false)
	box.bg_color = color
	box.border_color = Color(0.0, 0.0, 0.0, 0.0)
	box.set_border_width_all(0)
	draw_style_box(box, rect)


func _rounded_outline(rect: Rect2, radius: int, color: Color, width: int) -> void:
	var box := _style_box(radius, true)
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.border_color = color
	box.set_border_width_all(width)
	draw_style_box(box, rect)


func _style_box(radius: int, outline: bool) -> StyleBoxFlat:
	var key := "%s:%d" % ["o" if outline else "f", radius]
	var box: StyleBoxFlat = _box_cache.get(key)
	if box == null:
		box = StyleBoxFlat.new()
		box.set_corner_radius_all(radius)
		box.anti_aliasing = true
		_box_cache[key] = box
	return box


func _text_center(rect: Rect2, text: String, size: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var ascent := _font.get_ascent(size)
	var descent := _font.get_descent(size)
	var pos := Vector2(
		rect.position.x + (rect.size.x - measured.x) * 0.5,
		rect.position.y + (rect.size.y - (ascent + descent)) * 0.5 + ascent
	)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_shadow_center(rect: Rect2, text: String, size: int, color: Color) -> void:
	_text_center(_shift(rect, Vector2(1.5, 2.5)), text, size, Color(0.0, 0.0, 0.0, 0.22))
	_text_center(rect, text, size, color)


func _text_bottom_right(rect: Rect2, text: String, size: int, color: Color, pad: float) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(
		rect.position.x + rect.size.x - pad - measured.x,
		rect.position.y + rect.size.y - pad - _font.get_descent(size)
	)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_bottom_center(rect: Rect2, text: String, size: int, color: Color, pad: float) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(
		rect.position.x + (rect.size.x - measured.x) * 0.5,
		rect.position.y + rect.size.y - pad - _font.get_descent(size)
	)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _shift(rect: Rect2, offset: Vector2) -> Rect2:
	return Rect2(rect.position + offset, rect.size)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out


# ------------------------------------------------------------------------- helpers

func _reset_state() -> void:
	_items.clear()
	_obstacles.clear()
	_completed.clear()
	_selected = Vector2i(-1, -1)


func _apply_default_demo_state() -> void:
	apply_state({"selected": DEFAULT_SELECTED, "completed": DEFAULT_COMPLETED})


func _make_item(slot: Dictionary, entities: Dictionary, generators: Dictionary) -> Dictionary:
	var entity := String(slot.get("entity", ""))
	var definition := _as_dict(entities.get(entity, {}))
	var visual := _as_dict(definition.get("visual", {}))
	var kind := String(definition.get("kind", "chip"))
	var hue := Color.from_string(String(visual.get("hue", "")), COLOR_HUE_FALLBACK)
	var label := String(visual.get("label", entity.left(3)))
	if label.is_empty():
		label = "?"
	var charges := 0
	var behavior := _as_dict(generators.get(entity, {}))
	if not behavior.is_empty():
		charges = int(behavior.get("charges", 0))
	return {
		"kind": kind,
		"entity": entity,
		"level": int(slot.get("level", 1)),
		"hue": hue,
		"label": label,
		"charges": charges,
	}


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < board_width and cell.y < board_height


func _to_cell(raw) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Vector2:
		return Vector2i(int((raw as Vector2).x), int((raw as Vector2).y))
	if typeof(raw) == TYPE_ARRAY:
		var arr: Array = raw
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i(-1, -1)


func _as_dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _load_font() -> Font:
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.size() > 0:
		var file := FontFile.new()
		file.data = bytes
		if file.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CAPS).x > 0.0:
			return file
	push_warning("[view] font fallback to engine default")
	return ThemeDB.fallback_font


## PLACEHOLDER branch: reachable only with --allow-placeholders, and it asks the
## asset guard before touching the file. Loads bytes directly so a relocated copy
## without an import cache still works. Never called from _draw().
func _load_placeholder_frame() -> Texture2D:
	var guard_script = load(AssetGuardScript)
	if guard_script == null:
		return null
	var guard = guard_script.new()
	if not guard.load_from(MANIFEST_INDEX, true):
		return null
	if not String(guard.check_ref(FRAME_ID)).is_empty():
		push_warning("[view] placeholder blocked by guard: " + FRAME_ID)
		return null
	var path := String(guard.local_path(FRAME_ID))
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	print("[view] placeholder in use: %s (usage=PLACEHOLDER, allowed by flag)" % FRAME_ID)
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------ live board
##
## Additive entry point for the game screen: builds the same view from an
## in-memory level dictionary, so the board can be re-rendered from the sim's
## live snapshot after every sim event. build_from_project above keeps its exact
## previous behaviour (file IO + demo selection); this path never applies demo
## state, because the caller feeds select/completed explicitly.

func build_from_level_data(level_data: Dictionary, entities: Dictionary,
		generators: Dictionary) -> Dictionary:
	_reset_state()
	var out := {
		"ok": false,
		"cells": 0,
		"items": 0,
		"obstacles": 0,
		"error": "",
		"obstacle_types": [],
		"level_id": "",
	}
	if typeof(level_data) != TYPE_DICTIONARY or (level_data as Dictionary).is_empty():
		out["error"] = "level data is empty"
		return out
	var level: Dictionary = level_data
	level_id = String(level.get("id", ""))
	out["level_id"] = level_id

	var board := _as_dict(level.get("board", {}))
	board_width = clampi(int(board.get("width", COLS)), 1, COLS)
	board_height = clampi(int(board.get("height", ROWS)), 1, ROWS)

	for raw in _as_array(board.get("slots", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = raw
		var key := Vector2i(int(slot.get("x", -1)), int(slot.get("y", -1)))
		if not _in_bounds(key):
			continue
		_items[key] = _make_item(slot, entities, generators)

	for raw in _as_array(level.get("obstacles", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var ob: Dictionary = raw
		var type := String(ob.get("type", ""))
		if not OBSTACLE_TYPES.has(type):
			continue
		var cell_ref = ob.get("slot", [])
		if typeof(cell_ref) != TYPE_ARRAY or (cell_ref as Array).size() < 2:
			continue
		var key := Vector2i(int((cell_ref as Array)[0]), int((cell_ref as Array)[1]))
		if not _in_bounds(key):
			continue
		_obstacles[key] = type

	out["ok"] = true
	out["cells"] = board_width * board_height
	out["items"] = _items.size()
	out["obstacles"] = _obstacles.size()
	out["obstacle_types"] = obstacle_types()
	return out
