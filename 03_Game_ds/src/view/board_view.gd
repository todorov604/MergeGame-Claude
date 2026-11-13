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
## 单独格子.png is a 167x167 rounded tile (border ~6px, corner radius ~28px); 30 keeps
## the drawn radius and border thickness when it is 9-sliced over 983x1263.
const PLATE_CORNER := 30.0
## 单独格子 tile's blue border is 8px thick with a ~16px corner curve; light cells
## must stay inside that band, otherwise the outer row/column paints over the border
## (and past the rounded corner). 16px is the measured inner edge of the border.
const PLATE_PAD := 16.0
const UiFonts := preload("res://src/core/ui_fonts.gd")
const IceCell := preload("res://src/core/ice_cell.gd")
const FlyPath := preload("res://src/core/fly_path.gd")
const Safeboxes := preload("res://src/core/safeboxes.gd")
const Pulse := preload("res://src/core/pulse.gd")

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
## 2026-11-05 棋盘底改版（用户给的电影票效果）：大底用 单独格子.png 九宫格拉伸，
## 亮格用 浅色格.png 隔格铺一层。两者都是 PRODUCTION 资产，主题里给 id 即生效。
const UI_BOARD_PLATE := "board_plate"
const UI_CELL_LIGHT := "cell_light"
const UI_CELL := "cell"
const UI_SELECT := "select"
const UI_FINISH := "finish"
const UI_GENERATOR := "generator"
const UI_STAMINA := "stamina"
const UI_LOCK := "lock"
const UI_WEB := "web"
const UI_BUBBLE := "bubble"
const UI_ICE := "ice"
const UI_SAFE_1X7 := "safe_1x7"
const UI_SAFE_2X2 := "safe_2x2"
const UI_SAFE_2X3 := "safe_2x3"
const UI_SAFE_2X4 := "safe_2x4"
const UI_SAFE_FRAME := "safe_frame"
const UI_SAFE_LOCK := "safe_lock"
const UI_SAFE_UNKNOWN := "safe_unknown"
const SAFE_KEYS := {
	"1x7": UI_SAFE_1X7, "2x2": UI_SAFE_2X2, "2x3": UI_SAFE_2X3, "2x4": UI_SAFE_2X4,
}
const UI_KEYS := [
	UI_BG_BOTTOM, UI_BG_TOP, UI_BOARD_FRAME, UI_BOARD_PLATE, UI_CELL_LIGHT, UI_CELL, UI_SELECT,
	UI_FINISH, UI_GENERATOR, UI_STAMINA, UI_LOCK, UI_WEB, UI_BUBBLE, UI_ICE,
	UI_SAFE_1X7, UI_SAFE_2X2, UI_SAFE_2X3, UI_SAFE_2X4, UI_SAFE_FRAME, UI_SAFE_LOCK, UI_SAFE_UNKNOWN,
]

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
## The white brackets are drawn slightly larger while dragging, so a 1.34x chip still
## sits inside them (the frame, not the cell, is the size reference in hand).
const DRAG_FRAME_GROW := 1.14
const SELECT_LIFT := Vector2(0.0, -5.0)
const SELECT_TOWARD := 7.0
const COLOR_CAPSULE := Color(0.10, 0.15, 0.21, 0.82)
const COLOR_SHADOW := Color(0.04, 0.08, 0.14)

const FONT_TITLE := 40
const FONT_INK := 30
const FONT_CAPS := 22
const FONT_COUNTER := 26

const OBSTACLE_TYPES := ["lock", "web", "bubble", "bag", "ice"]
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
var _entities: Dictionary = {}
var _generators: Dictionary = {}
var level_index: int = 0
var level_id: String = ""
var board_width: int = COLS
var board_height: int = ROWS

var _items: Dictionary = {} # Vector2i -> {kind, entity, level, hue, label, charges}
var _obstacles: Dictionary = {} # Vector2i -> type
var _selected := Vector2i(-1, -1)
var _completed: Dictionary = {} # Vector2i -> true
## Live drag: {"from": Vector2i, "pos": Vector2} while a chip is under the pointer,
## {} otherwise. The chip and its selection frame are painted at `pos` (page space),
## the original cell is skipped, so the piece visibly follows the hand.
var _drag: Dictionary = {}
var _font_display: Font = null
## Level time used by the ice countdown; the screen feeds its own clock, the film
## feeds frame/FPS. Same input -> same label, so preview and film stay identical.
var ice_elapsed: float = 0.0
## 2026-11-11：JSON 指定的"网/冰下面那枚棋子"，键是 "x,y"。
var _trapped: Dictionary = {}
## 2026-11-13（操作者）：锁盒炸开的专属动画时间轴（秒）
const BOX_RISE_END := 0.26    # 先向上抛起 + 颤悠
const BOX_FADE_END := 0.42    # 再落下 + 渐隐
const BOX_WEB_GROW := 0.38    # 网 + 棋子从小放大（含闪光圈）
const BOX_ANIM_END := BOX_FADE_END + BOX_WEB_GROW + 0.15
## 2026-11-10：每格冰剩余秒数由 **sim** 算好推进来（`ice_seconds` 可配成 45 秒）。
var _ice_left: Dictionary = {}
## Spawn flight: {"spawn": sim.last_spawn, "started": level time}. While it runs the
## produced chip is drawn on the arc instead of its slot.
## Spawn flights, one per accepted tap: [{"spawn", "started"}]. Rapid taps each get
## their own arc instead of waiting for the previous chip to land.
var _flys: Array = []
## Safebox layout handed in by the screen (the sim owns the truth).
var safeboxes: Array = []
## Pickup time of the running drag (scale-in) and a one-shot pulse on one cell after a
## merge (0.4 s) or a drop (0.2 s shrink).
var _drag_started: float = 0.0
var _pulse: Dictionary = {}
## When false the drag draws only the white frame; the screen's ghost layer paints the
## chip itself so it can sit above the order cards.
var drag_chip_visible: bool = true
## Obstacles cleared by a merge: [{"cell": Vector2i, "kind": String, "started": float}].
var _unlocks: Array = []
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
	_entities = entities
	_generators = generators

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
## 成片用：把 sim 的棋子布局整体覆盖过来（[[x, y, entity, level], ...]）。
## 实机是自己维护 _items，成片没有输入循环，只能每帧把快照盖过来。
func set_chips(cells: Array) -> void:
	_items.clear()
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
			continue
		var slot := {
			"x": int((raw as Array)[0]),
			"y": int((raw as Array)[1]),
			"entity": String((raw as Array)[2]),
			"level": int((raw as Array)[3]),
		}
		# 2026-11-12：快照第 5/6 位是图标覆盖。成片每帧都用这份覆盖棋盘，
		# 漏了它们 = "实机对、成片全是默认图"（操作者 00109 帧报的就是这个）。
		if (raw as Array).size() > 4 and not String((raw as Array)[4]).is_empty():
			slot["icon"] = String((raw as Array)[4])
		if (raw as Array).size() > 5 and int((raw as Array)[5]) > 0:
			slot["iconLevel"] = int((raw as Array)[5])
		var key := Vector2i(int(slot["x"]), int(slot["y"]))
		if not _in_bounds(key):
			continue
		_items[key] = _make_item(slot, _entities, _generators)
	queue_redraw()


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


## Live drag state from the screen: {"from": Vector2i, "pos": Vector2} while a chip is
## under the pointer, {} to end. View-only — the sim is untouched until release, and
## the board keeps repainting at pointer rate because the screen calls
## queue_redraw() through this method.
func set_drag_state(state: Dictionary) -> void:
	if state.is_empty():
		_drag = {}
	else:
		if _drag.is_empty():
			_drag_started = _clock
		var from := _to_cell(state.get("from", [-1, -1]))
		_drag = {
			"from": from,
			"pos": Vector2(state.get("pos", Vector2.ZERO)),
		}
	queue_redraw()


## Level time for the ice countdown. Repaints only when the whole second changes.
## Start the generator -> slot flight for the chip the sim just produced.
func start_fly(spawn: Dictionary, started_at: float) -> void:
	if spawn.is_empty():
		return
	_flys.append({"spawn": spawn.duplicate(true), "started": started_at})
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if _flys.is_empty() and _unlocks.is_empty():
		set_process(false)
		return
	queue_redraw()
	if _flys.is_empty():
		return
	var alive: Array = []
	for fly in _flys:
		if FlyPath.progress(float(fly.get("started", 0.0)), _clock) < 1.0:
			alive.append(fly)
	_flys = alive
	if _flys.is_empty():
		set_process(false)


## One-shot scale feedback on a cell: kind is "merge" (0.4 s pop) or "settle" (0.2 s
## shrink after a drop).
func pulse(cell: Vector2i, kind: String, started_at: float = -1.0) -> void:
	if cell.x < 0:
		return
	_pulse = {"cell": cell, "kind": kind, "started": _clock if started_at < 0.0 else started_at}
	queue_redraw()


func set_safeboxes(boxes: Array) -> void:
	safeboxes = boxes.duplicate(true)
	queue_redraw()


func set_ice_elapsed(value: float) -> void:
	if is_equal_approx(value, ice_elapsed):
		return
	var was := IceCell.format_clock(int(floor(ice_elapsed)))
	ice_elapsed = maxf(value, 0.0)
	if IceCell.format_clock(int(floor(ice_elapsed))) != was:
		queue_redraw()


func drag_source() -> Vector2i:
	if _drag.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(_drag.get("from", Vector2i(-1, -1)))


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
			if _obstacles.has(cell):
				_draw_obstacle(cell, String(_obstacles[cell]))

	_draw_safeboxes()
	_draw_unlocks()

	# 2026-11-05: a mission-satisfied chip reads as green cell + finish badge.
	# While the chip is being dragged its cell is skipped here — the green must not be
	# left behind as an empty square; it lands on the target cell after the drop, when
	# the snapshot recomputes the completed set.
	for cell in _completed.keys():
		if not _drag.is_empty() and cell == Vector2i(_drag["from"]):
			continue
		# 2026-11-06: the chip is already in the data while its flight is still in the
		# air — hold the green until it lands, otherwise the cell lights up early.
		if _is_fly_target(cell):
			continue
		_rounded(cell_rect(cell.x, cell.y).grow(-float(CELL_GAP)), 18, COLOR_COMPLETE)

	for y in board_height:
		for x in board_width:
			var cell := Vector2i(x, y)
			if _items.has(cell):
				if not _drag.is_empty() and cell == Vector2i(_drag["from"]):
					continue
				if _is_fly_target(cell):
					continue
				# 2026-11-11：**被障碍盖住的格子不画真实棋子** —— 网 / 冰 自己在障碍层
				# 画了"被扣住的那一枚"，再画一遍会盖在网上面（操作者：网要在上面）。
				var kinds_here: Array = _obstacles_for(cell)
				if kinds_here.has("web") or kinds_here.has("ice"):
					continue
				_draw_item_pulsed(cell, _items[cell])

	for cell in _completed.keys():
		if not _drag.is_empty() and cell == Vector2i(_drag["from"]):
			continue
		if _is_fly_target(cell):
			continue
		_draw_complete_mark(cell)

	for fly in _flys:
		_draw_fly(fly)

	if not _drag.is_empty():
		_draw_drag()
	elif _selected.x >= 0:
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


## §20.6 item 4: the 983x1263 board container at (48,466). The 2026-11-05 redesign
## paints 单独格子.png (a 167px rounded tile with the blue border) as the big base via
## a 9-slice, so the corners keep their radius instead of being stretched 6x. Older
## themes without `board_plate` fall back to the full-size frame texture, then to the
## procedural panel.
func _draw_container() -> void:
	var plate := _ui_texture(UI_BOARD_PLATE)
	if plate != null:
		_draw_plate(plate, Rect2(BOARD_ORIGIN, BOARD_SIZE), PLATE_CORNER)
		return
	var texture := _ui_texture(UI_BOARD_FRAME)
	if texture == null:
		texture = _frame_texture
	if texture != null:
		draw_texture_rect(texture, Rect2(BOARD_ORIGIN, BOARD_SIZE), false)
		return
	var panel := Rect2(BOARD_ORIGIN - Vector2(12.0, 12.0), BOARD_SIZE + Vector2(24.0, 24.0))
	_rounded(panel, 26, COLOR_PANEL)
	_rounded_outline(panel, 26, COLOR_PANEL_EDGE, 2)


## Stretch one rounded tile over the whole board without stretching its corners:
## 9 source regions, corners drawn 1:1, edges and centre stretched.
func _draw_plate(texture: Texture2D, rect: Rect2, corner: float) -> void:
	var source := texture.get_size()
	var c := minf(corner, minf(source.x, source.y) * 0.5)
	if c <= 0.0:
		draw_texture_rect(texture, rect, false)
		return
	var inner_w := maxf(rect.size.x - c * 2.0, 0.0)
	var inner_h := maxf(rect.size.y - c * 2.0, 0.0)
	var src_inner_w := source.x - c * 2.0
	var src_inner_h := source.y - c * 2.0
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + c
	var y1 := rect.position.y + c
	# corners
	draw_texture_rect_region(texture, Rect2(x0, y0, c, c), Rect2(0, 0, c, c))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, y0, c, c), Rect2(source.x - c, 0, c, c))
	draw_texture_rect_region(texture, Rect2(x0, rect.end.y - c, c, c), Rect2(0, source.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, rect.end.y - c, c, c),
			Rect2(source.x - c, source.y - c, c, c))
	# edges
	draw_texture_rect_region(texture, Rect2(x1, y0, inner_w, c), Rect2(c, 0, src_inner_w, c))
	draw_texture_rect_region(texture, Rect2(x1, rect.end.y - c, inner_w, c),
			Rect2(c, source.y - c, src_inner_w, c))
	draw_texture_rect_region(texture, Rect2(x0, y1, c, inner_h), Rect2(0, c, c, src_inner_h))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, y1, c, inner_h),
			Rect2(source.x - c, c, c, src_inner_h))
	# centre
	draw_texture_rect_region(texture, Rect2(x1, y1, inner_w, inner_h),
			Rect2(c, c, src_inner_w, src_inner_h))


## §20.6 item 5: light cells. With `cell_light` (2026-11-05 redesign) only every other
## cell is painted, so the plate shows through and the board reads as a checkerboard.
## Without it the theme's cell tile is drawn on every cell, exactly as before.
func _draw_cell(x: int, y: int) -> void:
	var r := cell_rect(x, y).grow(-float(CELL_GAP) * 0.5)
	var light := _ui_texture(UI_CELL_LIGHT)
	if light != null:
		if (x + y) % 2 == 0:
			draw_texture_rect(light, _inner_cell_rect(r), false)
		return
	var texture := _ui_texture(UI_CELL)
	if texture != null:
		draw_texture_rect(texture, r, false)
		return
	_rounded(r, 14, COLOR_CELL)
	_rounded(Rect2(r.position + Vector2(3.0, 3.0), Vector2(r.size.x - 6.0, 5.0)), 3, COLOR_CELL_LIP)


func _is_fly_target(cell: Vector2i) -> bool:
	for fly in _flys:
		var to = (fly.get("spawn", {}) as Dictionary).get("to", [])
		if typeof(to) == TYPE_ARRAY and (to as Array).size() >= 2 \
				and Vector2i(int((to as Array)[0]), int((to as Array)[1])) == cell:
			return true
	return false


func _draw_fly(fly: Dictionary) -> void:
	var t := FlyPath.progress(float(fly.get("started", 0.0)), _clock)
	if t >= 1.0:
		return
	var spawn: Dictionary = fly.get("spawn", {})
	var from = spawn.get("from", [])
	var to = spawn.get("to", [])
	if typeof(from) != TYPE_ARRAY or typeof(to) != TYPE_ARRAY:
		return
	var a := Vector2i(int((from as Array)[0]), int((from as Array)[1]))
	var b := Vector2i(int((to as Array)[0]), int((to as Array)[1]))
	var start: Vector2 = cell_rect(a.x, a.y).get_center()
	# 2026-11-06: 面板里的库存从页面坐标起飞（棋盘本地坐标 = 页面 - position）
	var from_page = spawn.get("from_page", null)
	if typeof(from_page) == TYPE_ARRAY and (from_page as Array).size() >= 2:
		start = Vector2(float((from_page as Array)[0]), float((from_page as Array)[1])) - position
	var end: Vector2 = cell_rect(b.x, b.y).get_center()
	var at := FlyPath.point(start, end, t)
	var base := cell_rect(b.x, b.y).grow(-float(CELL_GAP) * 0.5)
	var half := base.size * 0.5
	var item := {"entity": String(spawn.get("entity", "")), "level": int(spawn.get("level", 1))}
	if not String(spawn.get("icon", "")).is_empty():
		item["icon"] = String(spawn.get("icon", ""))
	if int(spawn.get("icon_level", 0)) > 0:
		item["icon_level"] = int(spawn.get("icon_level", 0))
	# 2026-11-10：飞下去的若是生成器，图标要用它自己的（和低级生成器区分开）。
	var eid := String(item["entity"])
	var kind := String(spawn.get("kind", ""))
	if kind.is_empty():
		kind = String(_as_dict(_entities.get(eid, {})).get("kind", "chip"))
	var texture: Texture2D = null
	if kind == "generator":
		# 有图标覆盖就飞那一套棋子的图，和落格后保持一致
		if not String(item.get("icon", "")).is_empty():
			texture = _chip_texture(item)
		if texture == null:
			texture = _generator_texture(eid)
	else:
		texture = _chip_texture(item)
	draw_set_transform(at, 0.0, Vector2.ONE)
	if texture != null:
		_draw_chip_texture(Rect2(-half, base.size), texture)
	else:
		_draw_chip(Rect2(-half, base.size), item)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _inner_cell_rect(r: Rect2) -> Rect2:
	var inner := Rect2(BOARD_ORIGIN + Vector2(PLATE_PAD, PLATE_PAD),
			BOARD_SIZE - Vector2(PLATE_PAD * 2.0, PLATE_PAD * 2.0))
	var left := maxf(r.position.x, inner.position.x)
	var top := maxf(r.position.y, inner.position.y)
	var right := minf(r.end.x, inner.end.x)
	var bottom := minf(r.end.y, inner.end.y)
	return Rect2(left, top, maxf(right - left, 0.0), maxf(bottom - top, 0.0))


## Item draw with the running merge/settle pulse, if this is the pulsing cell.
## A neighbour obstacle just broke: draw it growing and fading, then drop it.
func unlock(cell: Vector2i, kind: String, started_at: float = -1.0, became: String = "") -> void:
	if cell.x < 0 or kind == "safe":
		return
	# 2026-11-10：蓝盒子被砸开时闪的图标应该是**它变成的东西**（网 / 冰），
	# 不是问号袋子 —— 未知 kind 落到 UI_SAFE_UNKNOWN 会闪一下 "?"（操作者报过）。
	var shown := kind
	if kind == "box":
		shown = became if not became.is_empty() else "web"
	_unlocks.append({"cell": cell, "kind": kind, "shown": shown,
			"started": _clock if started_at < 0.0 else started_at})
	set_process(true)
	queue_redraw()


## 锁盒动画当前处在哪个阶段：rise / fall / grow / ""（不在动画里）。
func unlock_phase(cell: Vector2i) -> String:
	for row in _unlocks:
		if String((row as Dictionary).get("kind", "")) != "box":
			continue
		if Vector2i((row as Dictionary).get("cell", Vector2i(-1, -1))) != cell:
			continue
		var a := _clock - float((row as Dictionary).get("started", 0.0))
		if a < 0.0 or a >= BOX_ANIM_END:
			return ""
		if a < BOX_RISE_END:
			return "rise"
		if a < BOX_FADE_END:
			return "fall"
		return "grow"
	return ""


## 正在播放的解锁动画行（测试用；只读副本）。
func unlock_rows() -> Array:
	return _unlocks.duplicate(true)


func _ease_out_back(p: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var q := p - 1.0
	return 1.0 + c3 * q * q * q + c1 * q * q


## 锁盒：向上抛起 + Q 弹颤悠（挤压/拉伸），再落下渐隐。
func _draw_box_rise(base: Rect2, a: float) -> void:
	var tex := _ui_texture(UI_LOCK)
	if tex == null:
		return
	var t_rise := clampf(a / BOX_RISE_END, 0.0, 1.0)
	var offset := 0.0
	var squash := 1.0
	var alpha := 1.0
	var wobble := 0.0
	if a < BOX_RISE_END:
		offset = -36.0 * sin(t_rise * PI * 0.5)
		# 2026-11-13（操作者）：再快一点、少颤几次 —— 频率更高、衰减更快（damp²）
		var damp := (1.0 - t_rise) * (1.0 - t_rise)
		squash = 1.0 + 0.24 * sin(a * 70.0) * damp
		wobble = 0.08 * sin(a * 62.0) * damp
	elif a < BOX_FADE_END:
		var p := clampf((a - BOX_RISE_END) / (BOX_FADE_END - BOX_RISE_END), 0.0, 1.0)
		offset = -36.0 + 42.0 * p
		# 边落边淡：从这一段的 35% 就开始透明，肉眼能看清"消失"
		alpha = clampf(1.0 - (p - 0.35) / 0.65, 0.0, 1.0)
		squash = 1.0 + 0.14 * (1.0 - p) * sin(a * 40.0)
		wobble = 0.06 * (1.0 - p) * sin(a * 40.0)
	var centre := base.get_center() + Vector2(0.0, offset)
	draw_set_transform(centre, wobble, Vector2(1.0 / maxf(squash, 0.2), maxf(squash, 0.2)))
	draw_texture_rect(tex, Rect2(-base.size * 0.5, base.size), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一圈闪光：8 个四角星从内向外扩散并淡出。
func _draw_sparkle_ring(centre: Vector2, radius: float, alpha: float) -> void:
	if alpha <= 0.01:
		return
	for i in 8:
		var ang := TAU * float(i) / 8.0 + radius * 0.01
		var pos := centre + Vector2(cos(ang), sin(ang)) * radius
		var size := 6.0 + 7.0 * alpha
		var col := Color(1.0, 0.97, 0.70, minf(1.0, alpha * 1.35))
		draw_set_transform(pos, ang, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, -size), Vector2(size * 0.28, 0), Vector2(0, size), Vector2(-size * 0.28, 0),
		]), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 网 + 棋子在锁盒消失后从小放大，同时一圈闪光。
func _draw_box_grow(base: Rect2, cell: Vector2i, a: float) -> void:
	var p := clampf((a - BOX_FADE_END) / BOX_WEB_GROW, 0.0, 1.0)
	var s_scale: float = lerpf(0.15, 1.0, _ease_out_back(p))
	var alpha := clampf(p * 4.0, 0.0, 1.0)
	var centre := base.get_center()
	draw_set_transform(centre, 0.0, Vector2(s_scale, s_scale))
	var local := Rect2(-base.size * 0.5, base.size)
	var chip := _trapped_chip_for(cell)
	if not chip.is_empty():
		var chip_tex := _chip_texture(chip)
		if chip_tex != null:
			draw_texture_rect(chip_tex, local, false, Color(1, 1, 1, alpha))
	var web_tex := _ui_texture(UI_WEB)
	if web_tex != null:
		draw_texture_rect(web_tex, local, false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sparkle_t := clampf(p, 0.0, 1.0)
	_draw_sparkle_ring(centre, lerpf(base.size.x * 0.18, base.size.x * 0.72, sparkle_t),
			pow(1.0 - sparkle_t, 1.2))


## 这一格正在播锁盒动画 → 正常图层先别画（否则会提前露出网和棋子）。
func _box_anim_active(cell: Vector2i) -> bool:
	return unlock_phase(cell) != ""


func _draw_unlocks() -> void:
	var alive: Array = []
	for row in _unlocks:
		var started := float((row as Dictionary).get("started", 0.0))
		var is_box := String((row as Dictionary).get("kind", "")) == "box"
		var dur := 0.45 if bool((row as Dictionary).get("melt", false)) else 0.35
		var elapsed := _clock - started
		var t := elapsed / dur
		if is_box:
			if elapsed >= BOX_ANIM_END:
				continue
			alive.append(row)
			var bcell: Vector2i = (row as Dictionary).get("cell", Vector2i(-1, -1))
			var brect := cell_rect(bcell.x, bcell.y).grow(-float(CELL_GAP) * 0.5)
			if elapsed < BOX_FADE_END:
				_draw_box_rise(brect, elapsed)
			else:
				_draw_box_grow(brect, bcell, elapsed)
			continue
		if t >= 1.0:
			continue
		alive.append(row)
		var cell: Vector2i = (row as Dictionary).get("cell", Vector2i(-1, -1))
		var kind := String((row as Dictionary).get("kind", ""))
		var base := cell_rect(cell.x, cell.y).grow(-float(CELL_GAP) * 0.5)
		var melt := bool((row as Dictionary).get("melt", false))
		# 2026-11-10：冰是"时间到 → 自己化掉"，效果做成**扩大消失**
		# （1.0 → 1.9 倍，同时淡到 0），比爆炸解锁的 1.6 倍更明显。
		var scale: float = 1.0 + (1.9 - 1.0) * t if melt else 1.0 + 0.6 * t
		var alpha: float = clampf(1.0 - t, 0.0, 1.0)
		var shown := String((row as Dictionary).get("shown", kind))
		var tex: Texture2D = null
		match shown:
			"lock": tex = _ui_texture(UI_LOCK)
			"web": tex = _ui_texture(UI_WEB)
			"ice": tex = _ui_texture(UI_ICE)
			"bag", "bubble": tex = _ui_texture(UI_SAFE_UNKNOWN)
			_: tex = null
		draw_set_transform(base.get_center(), 0.0, Vector2(scale, scale))
		var local := Rect2(-base.size * 0.5, base.size)
		if tex != null:
			draw_texture_rect(tex, local, false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_unlocks = alive
	if _unlocks.is_empty():
		set_process(_flys.size() > 0)


func _draw_item_pulsed(key: Vector2i, item: Dictionary) -> void:
	if _pulse.is_empty() or Vector2i(_pulse.get("cell", Vector2i(-1, -1))) != key:
		_draw_item(key, item)
		return
	var kind := String(_pulse.get("kind", ""))
	var started := float(_pulse.get("started", 0.0))
	if _clock - started >= Pulse.duration_of(kind):
		_pulse = {}
		_draw_item(key, item)
		return
	var scale := Pulse.scale_at(kind, started, _clock)
	var centre := cell_rect(key.x, key.y).get_center()
	draw_set_transform(centre, 0.0, Vector2(scale, scale))
	_draw_item_at_origin(key, item)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_item_at_origin(key: Vector2i, item: Dictionary) -> void:
	var cell := cell_rect(key.x, key.y)
	_draw_item_rect(Rect2(Vector2(-cell.size.x * 0.5, -cell.size.y * 0.5), cell.size), item)


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
		return
	var hue: Color = item.get("hue", COLOR_HUE_FALLBACK)
	_rounded(r, 18, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 34.0)), 12,
			Color(1.0, 1.0, 1.0, 0.18))
	var label := String(item.get("label", "?"))
	_text_shadow_center(_shift(r, Vector2(0.0, -6.0)), label, FONT_TITLE, COLOR_WHITE)


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
## Public accessor so other layers (the order claim flight) can draw the same art.
func chip_texture(entity_id: String, level: int) -> Texture2D:
	return _chip_texture({"entity": entity_id, "level": level})


## 2026-11-10：这一格的贴图 —— 生成器用生成器图，棋子用棋子图。
## 成片拖拽 ghost 以前只认 chip，拖生成器时查不到贴图 → 没有 ghost（操作者报"直接就移过去了"）。
func item_texture(kind: String, entity_id: String, level: int, icon: String = "",
		icon_level: int = 0) -> Texture2D:
	var chip := chip_texture(icon if not icon.is_empty() else entity_id,
			icon_level if (not icon.is_empty() and icon_level > 0) else level)
	if chip != null:
		return chip
	# 生成器（名字不一定在 generators 表里）兜底用生成器图，别让 ghost 直接消失
	return _ui_texture(UI_GENERATOR)


## 这一格是不是生成器（成片判断要不要补体力角标）。
func is_generator_entity(entity_id: String) -> bool:
	var meta: Dictionary = _as_dict(_generators.get(entity_id, {}))
	return not meta.is_empty()


func _chip_texture(item: Dictionary) -> Texture2D:
	if _asset_loader == null or not _asset_loader.has_method("chip_texture"):
		return null
	# 图标覆盖优先：JSON 的 slot.icon（编辑器里「图标」选的那一套系列）
	var override := String(item.get("icon", ""))
	var entity_id := override if not override.is_empty() else String(item.get("entity", ""))
	if entity_id.is_empty():
		return null
	var lv := int(item.get("level", 1))
	if not override.is_empty() and int(item.get("icon_level", 0)) > 0:
		lv = int(item.get("icon_level", 0))
	var texture = _asset_loader.chip_texture(entity_id, lv, _asset_project)
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


## 2026-11-05: the generator is the project's own icon (猫形置物架) with the small
## 体力 lightning in its bottom-left corner. The x<charges> badge is hidden for now.
## 生成器贴图：实体可以在 `visual.icon` 里指定自己的贴图 id（高级生成器用），
## 没写的退回主题里的通用生成器图。飞行中的生成器也走这一份（操作者要求飞行图标一致）。
func _generator_texture(entity_id: String) -> Texture2D:
	if not entity_id.is_empty():
		var ent: Dictionary = _as_dict(_entities.get(entity_id, {}))
		var icon_id := String(_as_dict(ent.get("visual", {})).get("icon", ""))
		if not icon_id.is_empty() and _asset_loader != null 				and _asset_loader.has_method("texture_for"):
			var tex = _asset_loader.texture_for(icon_id)
			if tex is Texture2D:
				return tex
	return _ui_texture(UI_GENERATOR)


func _draw_generator(r: Rect2, item: Dictionary) -> void:
	# 2026-11-12：编辑器给生成器选了「图标」时，画那一套棋子的图，而不是通用生成器图。
	var icon: Texture2D = null
	if not String(item.get("icon", "")).is_empty():
		icon = _chip_texture(item)
	if icon == null:
		icon = _generator_texture(String(item.get("entity", "")))
	if icon != null:
		_draw_chip_texture(r, icon)
		_draw_stamina_badge(r)
		return
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
	_draw_stamina_badge(r)


## Small 体力 lightning pinned to the cell's bottom-left corner (39x53 source).
func _draw_stamina_badge(r: Rect2) -> void:
	var stamina := _ui_texture(UI_STAMINA)
	if stamina == null:
		return
	var source := stamina.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var size := Vector2(26.0, 26.0 * source.y / source.x)
	# 2026-11-05: position against the rect that was handed in, not the board-clamped
	# cell — the drag draws with a transform around the pointer, and the board clamp
	# used to park the badge on a fixed cell (the "drifting lightning").
	var inner := r.grow(-2.0)
	draw_texture_rect(stamina, Rect2(inner.end.x - size.x, inner.end.y - size.y, size.x, size.y), false)


func _draw_special(r: Rect2, item: Dictionary) -> void:
	_rounded(r, 14, COLOR_SPECIAL)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 30.0)), 10,
			Color(1.0, 1.0, 1.0, 0.22))
	_text_center(_shift(r, Vector2(0.0, -8.0)), String(item.get("label", "?")), FONT_INK, COLOR_INK)


## Obstacle semantics are unchanged (one type per cell, same four types); only the
## art source changes: themed texture when it resolves, procedural art otherwise.
## An ice cell freezes a deterministic chip and labels its level (project font).
## 用 sim 快照覆盖障碍表：`[[x, y, [kinds...]], ...]`。
## 解锁、蓝盒子变成网/冰这类**运行时变化**必须每帧同步，否则画面上还是旧的（甚至空白）。
func set_obstacles(rows: Array) -> void:
	var next := {}
	for raw in rows:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
			continue
		var pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
		if not _in_bounds(pos):
			continue
		var kinds: Array = (raw as Array)[2]
		if kinds.is_empty():
			continue
		next[pos] = String(kinds[0])
	if next.size() == _obstacles.size():
		var same := true
		for k in next.keys():
			if String(_obstacles.get(k, "")) != String(next[k]):
				same = false
				break
		if same:
			return
	_obstacles = next
	queue_redraw()


## 某格身上的障碍种类（数组）。
func _obstacles_for(cell: Vector2i) -> Array:
	if not _obstacles.has(cell):
		return []
	var raw = _obstacles[cell]
	if typeof(raw) == TYPE_ARRAY:
		return raw
	return [String(raw)]


func _draw_obstacle(key: Vector2i, type: String) -> void:
	var r := cell_rect(key.x, key.y).grow(-float(CELL_GAP) * 0.5)
	match type:
		"safe":
			return  # one multi-cell group, drawn by _draw_safeboxes()
		"lock":
			if _box_anim_active(key):
				return
			if not _draw_ui_art(UI_LOCK, r):
				_draw_lock(r)
		"web":
			if _box_anim_active(key):
				return
			# 2026-11-05: same treatment as ice — a deterministic chip sits under the
			# web so the cell is never empty behind the lines.
			var webbed := _trapped_chip_for(key)
			if not webbed.is_empty():
				var web_tex := _chip_texture(webbed)
				if web_tex != null:
					_draw_chip_texture(r, web_tex)
				else:
					_draw_chip(r, webbed)
			if not _draw_ui_art(UI_WEB, r):
				_draw_web(r.get_center())
		"bubble":
			if not _draw_ui_art(UI_BUBBLE, r):
				_draw_bubble(r.get_center())
		"bag":
			if not _draw_ui_art(UI_SAFE_UNKNOWN, r):
				_draw_bubble(r.get_center())
		"ice":
			# 2026-11-05: a deterministic chip is frozen under the ice and the timer
			# placeholder is replaced by a real label (project display font).
			var frozen := _trapped_chip_for(key)
			if not frozen.is_empty():
				var texture := _chip_texture(frozen)
				if texture != null:
					_draw_chip_texture(r, texture)
				else:
					_draw_chip(r, frozen)
			if not _draw_ui_art(UI_ICE, r):
				_draw_ice(r)
			_draw_ice_label(key, r, frozen)
		_:
			_rounded(r, 14, Color(0.0, 0.0, 0.0, 0.25))


## 键既接受 Vector2i（sim.trapped_chips 原样传进来）也接受 "x,y" 字符串
## （成片读的是 snapshot 里的字符串键）—— 两边都归一成字符串，否则查不到就退回默认棋子。
func set_trapped_chips(rows: Dictionary) -> void:
	var next := {}
	for raw_key in rows.keys():
		var key := ""
		if typeof(raw_key) == TYPE_VECTOR2I:
			key = "%d,%d" % [raw_key.x, raw_key.y]
		elif typeof(raw_key) == TYPE_STRING:
			key = String(raw_key)
		else:
			continue
		var raw = rows[raw_key]
		if typeof(raw) == TYPE_DICTIONARY:
			next[key] = raw
	if next == _trapped:
		return
	_trapped = next
	queue_redraw()


func _trapped_chip_for(cell: Vector2i) -> Dictionary:
	var key := "%d,%d" % [cell.x, cell.y]
	if _trapped.has(key):
		var raw = _trapped[key]
		if typeof(raw) == TYPE_DICTIONARY:
			return raw
	return IceCell.chip(_asset_project, cell)


func set_ice_remaining_map(rows: Dictionary) -> void:
	if rows == _ice_left:
		return
	_ice_left = rows.duplicate()
	# 2026-11-10：倒计时每秒都在变，必须自己触发重绘 —— 以前只有点击/事件才会重画，
	# 操作者看到的是"不点鼠标就不刷新"。
	queue_redraw()


## 冰到点自己化掉：播一次"扩大消失"（实机与成片同一套绘制）。
func melt(cell: Vector2i, kind: String, started_at: float = -1.0) -> void:
	if cell.x < 0:
		return
	_unlocks.append({"cell": cell, "kind": kind, "shown": kind, "melt": true,
			"started": _clock if started_at < 0.0 else started_at})
	set_process(true)
	queue_redraw()


func _draw_ice_label(key: Vector2i, r: Rect2, frozen: Dictionary) -> void:
	if frozen.is_empty():
		return
	if _font_display == null:
		_font_display = UiFonts.load_font(UiFonts.DISPLAY_BOLD)
	if _font_display == null:
		return
	var font := _font_display
	var left := -1
	if _ice_left.has(key):
		left = int(_ice_left[key])
	if left < 0:
		var start := IceCell.start_seconds(key)
		left = clampi(start - int(floor(maxf(ice_elapsed, 0.0))), 0, IceCell.MAX_SECONDS)
	var text := IceCell.format_clock(left)
	var size := 26
	var baseline := Vector2(r.position.x, r.end.y - 8.0)
	var width := r.size.x
	# dark outline first, then white
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER, width, size,
				Color(0.12, 0.20, 0.30, 0.85))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(1, 1, 1, 1))


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



## Multi-cell safeboxes: one art per box, then bubble + lightning/charges + Lv frame +
## lock on top. Geometry and labels come from the sim's layout, so the film and the
## live board agree without any extra state.
func _draw_safeboxes() -> void:
	for raw in safeboxes:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var box: Dictionary = raw
		var x0 := int(box.get("x", 0))
		var y0 := int(box.get("y", 0))
		var w := int(box.get("w", 1))
		var h := int(box.get("h", 1))
		if w <= 0 or h <= 0:
			continue
		var rect := cell_rect(x0, y0).merge(cell_rect(x0 + w - 1, y0 + h - 1))
		var art := _ui_texture(SAFE_KEYS.get(String(box.get("size", "")), ""))
		if art != null:
			draw_texture_rect(art, rect, false)
		_draw_safe_overlay(rect, box)


func _draw_safe_overlay(rect: Rect2, box: Dictionary) -> void:
	var tpl: Dictionary = Safeboxes.TEMPLATE
	var centre := rect.get_center()
	var bubble := _ui_texture(UI_BUBBLE)
	if bubble != null:
		var bs: float = tpl["bubble"]
		draw_texture_rect(bubble, Rect2(centre + Vector2(0.0, float(tpl["bubble_offset_y"]))
				- Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false)
	var bolt := _ui_texture(UI_STAMINA)
	if bolt != null:
		var bsize: Vector2 = tpl["bolt"]
		draw_texture_rect(bolt, Rect2(centre + Vector2(0.0, float(tpl["bolt_offset_y"]))
				- bsize * 0.5, bsize), false)
	_draw_safe_label(Rect2(rect.position.x, centre.y + float(tpl["x_offset_y"]) - 20.0,
			rect.size.x, 40.0), "x%d" % int(box.get("charges", 0)), int(tpl["x_size"]), Color(1, 1, 1, 1))
	var frame := _ui_texture(UI_SAFE_FRAME)
	var fsize: Vector2 = tpl["frame"]
	var frame_rect := Rect2(centre + Vector2(0.0, float(tpl["frame_offset_y"])) - fsize * 0.5, fsize)
	if frame != null:
		var src := frame.get_size()
		_draw_nine(frame, frame_rect, minf(14.0, minf(src.x, src.y) * 0.34))
	_draw_safe_label_left(frame_rect.grow(-float(tpl["lv_pad_x"])),
			"Lv.%d" % int(box.get("level", 10)), int(tpl["lv_size"]), Color("#33475B"))
	var lock := _ui_texture(UI_SAFE_LOCK)
	if lock != null:
		var lsize: Vector2 = tpl["lock"]
		draw_texture_rect(lock, Rect2(Vector2(frame_rect.end.x - lsize.x * 0.32,
				frame_rect.get_center().y - lsize.y * 0.5), lsize), false)


## 9-slice draw: corners stay 1:1, edges/centre stretch, so a rounded plate keeps its
## radius at any size.
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


## Centered label with a dark outline, drawn with the project display font.
func _draw_safe_label(r: Rect2, text: String, size: int, color: Color) -> void:
	if _font_display == null:
		_font_display = UiFonts.load_font(UiFonts.DISPLAY_BOLD)
	var font := _font_display if _font_display != null else _font
	if font == null:
		return
	var baseline := Vector2(r.position.x, r.get_center().y + float(size) * 0.36)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size,
				Color(0.16, 0.25, 0.36, 0.85))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, color)


## Left-aligned label with the same dark outline.
func _draw_safe_label_left(r: Rect2, text: String, size: int, color: Color) -> void:
	if _font_display == null:
		_font_display = UiFonts.load_font(UiFonts.DISPLAY_BOLD)
	var font := _font_display if _font_display != null else _font
	if font == null:
		return
	var baseline := Vector2(r.position.x, r.get_center().y + float(size) * 0.36)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(0.16, 0.25, 0.36, 0.85))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_complete_mark(key: Vector2i) -> void:
	_draw_complete_mark_at(cell_rect(key.x, key.y).get_center(), 1.0)


## Mission-satisfied badge: the project's own `main_icon_finish.png` (ui_icon_finish)
## when the theme resolves it, otherwise the old procedural circle + check.
func _draw_complete_mark_at(centre: Vector2, scale: float) -> void:
	var texture := _ui_texture(UI_FINISH)
	if texture != null:
		var source := texture.get_size()
		if source.x > 0.0 and source.y > 0.0:
			var size := source * scale
			var badge := centre + Vector2(36.0, 34.0) * scale
			draw_texture_rect(texture, Rect2(badge - size * 0.5, size), false)
			return
	var badge := centre + Vector2(36.0, 34.0) * scale
	var radius := 22.0 * scale
	draw_circle(badge, radius, Color(0.25, 0.55, 0.20, 0.96), true, -1.0, true)
	draw_circle(badge, radius, Color(1.0, 1.0, 1.0, 0.55), false, 2.0, true)
	var check := PackedVector2Array([
		badge + Vector2(-11.0, 1.0) * scale, badge + Vector2(-3.0, 9.0) * scale,
		badge + Vector2(11.0, -9.0) * scale,
	])
	draw_polyline(check, Color(1.0, 1.0, 1.0, 1.0), 6.0 * scale, true)


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
	_draw_selection_at(cell_rect(key.x, key.y).get_center(), _selection_offset(key))


## White corner frame centred on `center` (page space). Drag passes the pointer
## position, so the same frame travels with the chip; the slot uses the cell centre.
func _draw_selection_at(center: Vector2, offset: Vector2, frame_scale: float = 1.0) -> void:
	var texture := _ui_texture(UI_SELECT)
	if texture != null:
		# §20.6 item 7: the frame covers the whole cell, centred on it. The chip
		# above still carries the lift/scale; the frame itself does not travel.
		var frame_size := texture.get_size() * frame_scale
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			draw_texture_rect(texture, Rect2(center + offset - frame_size * 0.5, frame_size), false)
			return

	var tile_size := Vector2(CELL_W, CELL_H) - Vector2(CELL_GAP, CELL_GAP)
	var r := Rect2(center + offset - tile_size * 0.5, tile_size)
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


## Chip currently under the pointer: scaled like a selected chip, framed by the same
## white brackets. The source cell is skipped in the item pass (see _draw).
## The white selection frame's texture, so the screen's ghost layer can draw it above
## the order cards.
func drag_frame_texture() -> Texture2D:
	var texture := _ui_texture(UI_SELECT)
	if texture == null:
		texture = _ui_texture("select")
	return texture


## Current drag pulse scale, so an external ghost layer can match the board.
func drag_scale_now() -> float:
	return Pulse.drag_scale(_drag_started, _clock)


## 拖拽棋子的矩形（页面坐标）。上层 ghost / 成片叠加层用它画棋子和白角框，
## 保证和棋盘自己的绘制**逐像素同一份几何**（§8 不许有第二份）。
func drag_chip_rect() -> Rect2:
	if _drag.is_empty():
		return Rect2()
	var from := Vector2i(_drag.get("from", Vector2i(-1, -1)))
	# 拖拽时源格可能已经从 _items 里摘掉（成片就这么做，避免和上层叠成两枚），
	# 所以这里**不能**用 _items.has(from) 当判据，只看 _drag 有没有合法坐标。
	if from.x < 0 or from.y < 0:
		return Rect2()
	var cell := cell_rect(from.x, from.y)
	var base := cell.grow(-float(CELL_GAP) * 0.5)
	var s := Pulse.drag_scale(_drag_started, _clock)
	var pos: Vector2 = _drag.get("pos", Vector2.ZERO)
	return Rect2(pos - base.size * s * 0.5, base.size * s)


func _draw_drag() -> void:
	var from := Vector2i(_drag.get("from", Vector2i(-1, -1)))
	if not _items.has(from):
		return
	var pos: Vector2 = _drag.get("pos", Vector2.ZERO)
	var cell := cell_rect(from.x, from.y)
	var base := cell.grow(-float(CELL_GAP) * 0.5)
	var half := base.size * 0.5
	var drag_scale := Pulse.drag_scale(_drag_started, _clock)
	if drag_chip_visible:
		draw_set_transform(pos, 0.0, Vector2(drag_scale, drag_scale))
		_draw_item_rect(Rect2(-half, base.size), _items[from])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _completed.has(from):
		_draw_complete_mark_at(pos, drag_scale)
	if drag_chip_visible:
		# 2026-11-10：生成器和棋子用**同一个**白框比例 —— 上一版给生成器单独放大到 1.62，
		# 实机里框比棋盘格还大（操作者截图报"游戏里白框太大"）。成片那边是 1.05 的矩形比例，
		# 看着正常，实机就按棋子这套走。
		_draw_selection_at(pos, Vector2.ZERO, DRAG_FRAME_GROW)
	# 2026-11-05: the stamina badge is the top-most layer of a dragged generator, so it
	# is painted after the white frame instead of underneath it.
	if drag_chip_visible and String((_items[from] as Dictionary).get("kind", "chip")) == "generator":
		draw_set_transform(pos, 0.0, Vector2(drag_scale, drag_scale))
		_draw_stamina_badge(Rect2(-half, base.size))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	var item := {
		"kind": kind,
		"entity": entity,
		"level": int(slot.get("level", 1)),
		"hue": hue,
		"label": label,
		"charges": charges,
	}
	# 2026-11-12：图标覆盖要跟着 item 走（棋盘格与飞行都用 _chip_texture(item)）。
	# 漏掉这两个字段 = "编辑器里换了图，落格后又变回原样"。
	if not String(slot.get("icon", "")).is_empty():
		item["icon"] = String(slot.get("icon", ""))
	if int(slot.get("iconLevel", 0)) > 0:
		item["icon_level"] = int(slot.get("iconLevel", 0))
	return item


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


## 测试用：视图里这一格显示的剩余秒数（-1 = 没数据）。
func ice_remaining_for(cell: Vector2i) -> int:
	return int(_ice_left.get(cell, -1))
