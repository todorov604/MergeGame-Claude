extends Control
## M0 offline render scene: 1080x1920, fixed 60 fps, frame-count driven.
##
##   godot --path . --resolution 1080x1920 --write-movie output/render.avi \
##         --fixed-fps 60 --quit-after 1800 res://src/render/movie_scene.tscn \
##         -- --frames=1800
##
## Why a frame counter and not `delta`: Movie Maker renders as fast as the GPU
## allows, so wall-clock accumulation would make take A and take B drift apart and
## the two framemd5 digests would never match. `t = (frame - 1) / 60` is the only
## clock in this file; the event evaluator is advanced to `t` once per frame, so
## the film is a pure function of (project, seed, frame index).
##
## Nothing here reads Time.get_ticks_*(), and no animation is Tween-based: every
## moving element is positioned from the frame index or from an event timestamp.
##
## Visual language (cell size, board origin, palette, chip capsule) is taken from
## src/view/board_view.gd at runtime, so the film and the static board view cannot
## drift apart. board_view itself only knows how to draw a *static* snapshot, which
## is why this scene replays the shared evaluator into its own draw pass instead of
## instancing board_view.tscn.

const BoardView = preload("res://src/view/board_view.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const EventEvaluator = preload("res://src/core/event_evaluator.gd")
const AssetGuard = preload("res://src/assets/asset_guard.gd")
const RenderPlan = preload("res://src/render/render_plan.gd")
const RenderManifest = preload("res://src/render/render_manifest.gd")
const ThemeLoader = preload("res://src/theme/theme_loader.gd")
const TakeIo = preload("res://src/core/take_io.gd")
const CompletedCells = preload("res://src/core/completed_cells.gd")
const IceCell = preload("res://src/core/ice_cell.gd")
const FlyPath = preload("res://src/core/fly_path.gd")
const Safeboxes = preload("res://src/core/safeboxes.gd")
const Pulse = preload("res://src/core/pulse.gd")

const FPS := 60
const MANIFEST_INDEX := "res://data/manifest_index.json"
const DEFAULT_PROJECT := "res://data/sample_project.json"
const OUT_DIR := "res://output"
const OUT_MANIFEST := "res://output/render_manifest.json"
const FONT_ZH := "res://assets/fonts/font_zh.otf"
const FONT_EN := "res://assets/fonts/font_en.ttf"
const FRAME_ID := "board_frame"
const FRAME_TEXTURE := "res://assets/ui/board_frame.png"
## Free-mode cursor overlay: the same white 3D glove the live window draws
## (ui_cursor_hand, 256x256 source). The hotspot is a ratio of the square texture, so
## the hand's fingertip lands exactly on the recorded click point.
const CURSOR_ID := "ui_cursor_hand"
const CURSOR_TEXTURE := "res://assets/ui/cursor_hand.png"
## 按下时手整体下沉多少像素（看得见的"点下去"）。
const CURSOR_PRESS_DIP := 7.0
const CURSOR_HOTSPOT_RATIO := Vector2(0.135, 0.004)
const CURSOR_SIZE := 96.0

## Bottom bar (2026-11-05): three layered assets + two text labels, all data so the
## bar is real UI instead of a flattened PSD slice.
const BAR_TITLE := "壳木壳木，CamelCamel"
const BAR_SUBTITLE := "美宣制作，Made by MeiXuan"
const UiFonts = preload("res://src/core/ui_fonts.gd")
const FONT_DISPLAY_BOLD := UiFonts.DISPLAY_BOLD
const FONT_DISPLAY_REGULAR := UiFonts.DISPLAY_REGULAR
## Third label of the bottom bar (2026-11-05): the reward count on the green
## coin_reward button. Digits use the source Montserrat Black, not the CJK round
## font, because 江城圆体 renders numerals narrow and the reward number must stay
## legible at 34 px against the button's green.
const BAR_COIN_REWARD := 88
const FONT_DISPLAY_NUM := "res://font/源字体/英文/Montserrat-Black.ttf"
## 2026-11-05 版式（对齐参考截图）：ⓘ 上移与标题同高、两段 label 之间加 common_line
## 分隔线、第二段 label 左移到 ⓘ 下方左缘。几何量放常量里，实时画面
## （game_screen.gd 的 Chrome）读同一份，预览与成片才不会各画一套。
const BAR_ICON_OFFSET := Vector2(34.0, 36.0)
const BAR_ICON_SIZE := Vector2(56.0, 56.0)
const BAR_TITLE_OFFSET := Vector2(100.0, 30.0)
const BAR_TITLE_SIZE := Vector2(430.0, 48.0)
const BAR_SUB_OFFSET := Vector2(44.0, 100.0)
const BAR_SUB_SIZE := Vector2(440.0, 44.0)
## 分隔线：common_line.png 是 10×4 纯白，绘制时调制到参考图取样色 #C4D7E2。
const BAR_LINE_OFFSET_Y := 88.0
const BAR_LINE_H := 4.0
const BAR_LINE_GAP := 20.0
const BAR_LINE_COLOR := Color("#C4D7E2")
## 金币按钮：整块下移，把 "Buy" 标题让到按钮上方的空白处。
const BAR_COIN_OFFSET_Y := 46.0
const BAR_BUY := "Buy"
## 2026-11-05: the bottom-right fridge/bag art reads a size small, so it is drawn a
## ring larger than its layout rect (the rect itself stays put).
const BAG_GROW := 10.0
const BAR_BUY_OFFSET_Y := 12.0
const BAR_BUY_SIZE_Y := 30.0
const BAR_BUY_COLOR := Color("#93A9BE")

## §20.5 棋盘.psd structure (1080x1920 canvas). Every number below is the PSD's own
## geometry, not a tuned guess: the two background layers, the 983x1263 board
## container (drawn by the board code, never covered here), the order characters,
## the top money bar, the bottom items bar and the three buttons. The film and the
## live screen (game_screen.gd) read this same table, so a preview screenshot and a
## delivered frame cannot disagree about where a panel lives.
##
## Layout invariants (checked by output/v2_layout_check.gd):
##   * the topband / order cards / bottom bar never intersect the board container
##   * the order cards sit below the money bar (y>=120) and above the board (y<=466)
##   * part2's 524 px art is top-anchored at -58 so its bottom edge is exactly the
##     board top (466) instead of painting over the board
const LAYOUT_BG_BOTTOM := Rect2(0.0, 384.0, 1080.0, 1536.0)
const LAYOUT_BG_TOP := Rect2(0.0, 0.0, 1080.0, 400.0)
const LAYOUT_LEVEL_BADGE_BG := Rect2(8.0, 0.0, 118.0, 104.0)
const LAYOUT_LEVEL_BADGE := Rect2(18.0, 8.0, 98.0, 84.0)
const LAYOUT_ENERGY := Rect2(136.0, 16.0, 300.0, 88.0)
const LAYOUT_COIN := Rect2(444.0, 16.0, 240.0, 88.0)
const LAYOUT_GEM := Rect2(690.0, 16.0, 228.0, 88.0)
const LAYOUT_STAR := Rect2(18.0, 96.0, 98.0, 32.0)
const LAYOUT_SHOP := Rect2(930.0, 8.0, 142.0, 132.0)
## part1/part2 are the PSD slices at their own sizes; only the character part is
## drawn (the slices also bake in an order card + counters, which would double the
## real cards). The character region is scaled to fill down to the card band, so the
## body ends exactly where the §20.5 order cards start.
const LAYOUT_PART1 := Rect2(213.5, 15.0, 373.0, 370.0)
const LAYOUT_PART2 := Rect2(613.5, -58.0, 373.0, 524.0)
const PART1_CHAR_SRC := Rect2(0.0, 0.0, 373.0, 188.0)
const PART2_CHAR_SRC := Rect2(0.0, 0.0, 373.0, 232.0)
const PART1_CHAR_RECT := Rect2(213.5, 15.0, 373.0, 237.0)
const PART2_CHAR_RECT := Rect2(613.5, -58.0, 373.0, 310.0)
const LAYOUT_CARD1 := Rect2(232.0, 252.0, 372.0, 190.0)
const LAYOUT_CARD2 := Rect2(628.0, 252.0, 372.0, 190.0)
const LAYOUT_ITEMS := Rect2(193.0, 1731.0, 693.0, 183.0)
const LAYOUT_EXIT := Rect2(16.0, 1738.0, 164.0, 174.0)
const LAYOUT_BAG := Rect2(940.0, 1755.0, 109.0, 147.0)
## Floating prompts stay out of the board rect: the toast + level-up flash live in
## the strip between the money bar and the order cards, the text/hint banners sit on
## the card band, and the CTA takes over the bottom items bar. (A toast at y=1600,
## where board_view.gd puts its own strip, would land on the 466..1729 board
## container, which the §20.5 film layout forbids.)
const LAYOUT_TOAST := Rect2(190.0, 124.0, 700.0, 84.0)
const LAYOUT_LEVELUP := Rect2(240.0, 160.0, 600.0, 96.0)
const LAYOUT_TEXT := Rect2(100.0, 258.0, 880.0, 84.0)
const LAYOUT_HINT := Rect2(190.0, 350.0, 700.0, 84.0)
const LAYOUT_CTA := Rect2(193.0, 1745.0, 693.0, 150.0)

## §20.5/§20.6 logical ui slots. The loader resolves key -> manifest id and loads a
## guard-checked texture; the ids the film actually drew are recorded in the render
## manifest, so the layout art is named in output/*.manifest.json.
const UI_KEYS := [
	"bg_bottom", "bg_top", "board_frame", "board_plate", "cell_light", "cell", "select",
	"bar_board", "reminder", "coin_reward", "line",
	"generator", "stamina",
	"level_badge", "level_badge_bg", "energy_timer", "money_bg", "finish", "ice", "bubble",
	"lock", "web", "exit", "bag", "items", "part1", "part2", "plus", "shop",
	"char_waitress", "char_technician", "char_customer", "char_police", "char_blonde", "char_racer", "char_manager", "char_glasses", "char_worker",
	"task_reward", "safe_unknown", "confirm", "energy_bar", "coin_bar", "gem_bar",
	"gem", "energy",
]
## Same 9-slice corner as board_view.PLATE_CORNER: the board base is one 167px rounded
## tile stretched over 983x1263, and its corners must not scale with the board.
const PLATE_CORNER := 30.0
## Same 16px inner edge as board_view.PLATE_PAD: light cells are clamped to the plate's
## fill area so the outer ring cannot paint over the border or past the rounded corner.
const PLATE_PAD := 16.0

## §7 item 4 prompt in the film: same geometry and fade curve as board_view, so a
## preview screenshot and the delivered frame cannot disagree about the prompt.
const TOAST_SECONDS := 1.5
const TOAST_FADE := 0.25
const TOAST_RECT := LAYOUT_TOAST
const TOAST_COLOR := Color(0.10, 0.15, 0.21, 0.86)

const COLOR_INK := Color("#22303F")
const COLOR_WHITE := Color(1.0, 1.0, 1.0)
const COLOR_PILL := Color("#E8F0FA")
const COLOR_PILL_EDGE := Color("#B9CCE2")
const COLOR_ACCENT := Color("#3E6FD6")
const COLOR_ENERGY := Color("#F6B93B")
const COLOR_COIN := Color("#E9B44C")
const COLOR_STAR := Color("#F5C542")
const COLOR_GEM := Color("#C86BFF")
const COLOR_CTA := Color("#3FBF6A")
const COLOR_DONE := Color("#8FD46B")
const COLOR_CAPSULE := Color(0.10, 0.15, 0.21, 0.82)
const COLOR_BAND := Color("#A8BDD5")
const COLOR_INK_DIM := Color(0.30, 0.40, 0.52, 0.9)

const CHIP_FONT := 40
const CAPS_FONT := 22
const INK_FONT := 28
const SMALL_FONT := 20
const HUD_FONT := 34

var project_path := DEFAULT_PROJECT
var frame_cap := 0
var allow_placeholders := false
var seed_value := 7391
var out_manifest := OUT_MANIFEST
## `--theme=<name>` re-skins the film from data only; empty means project.theme.
var theme_name := ""
## Diagnostic hook: extra manifest ids to push through the guard before the first
## frame. `--probe-ref=audio_bgm` must abort the render (usage TODO), which is how the
## governance red line gets an end-to-end check instead of only a unit test. Any id the
## guard refuses works here; the v7 snapshot has zero REFERENCE_ONLY records.
var probe_refs: Array = []
## `--take=<file>`: replay a free-mode recording (cursor path + click log + the sim
## events the player produced). Empty means a timeline film, exactly as before.
var take_path := ""
## `--no-cursor`: render a clean take (no hand overlay) from the same recording.
var no_cursor := false
var _take: Dictionary = {}
var _cursor_tex: Texture2D = null

var _model = null
var _evaluator = null
var _guard = null
var _theme_loader = null
## 2026-11-06：成片的订单带直接托管实机组件（卡片/库存），几何与行为不再另写一份。
var _live_band = null
var _live_top = null
var _live_bottom = null
var _overlay = null
var _live_board = null
var _live_fly = null
## 金币数字分批上涨（与实机同规则）：tick 队列 + 当前显示值 + 弹跳时刻。
var _coin_ticks: Array = []
var _coin_display: float = -1.0
var _coin_pop_at: float = -1000.0
## 2026-11-09：钻石数字与金币同一套（订单卡蓝条的钻石奖励飞上顶栏后分批涨 + 弹跳）。
var _gem_ticks: Array = []
var _gem_display: float = -1.0
var _gem_pop_at: float = -1000.0
## 体力数字（2026-11-09）：和金币/钻石同一套 tick + lerp + 弹跳。
var _energy_ticks: Array = []
var _energy_display: float = -1.0
var _energy_pop_at: float = -1000.0
var _board_level := -1
var _band_level := -1
var _guard_blocked: Array = []
var _rejected: Array = []
var _colors: Dictionary = {}
var _metrics: Dictionary = {}
var _toast_text := ""
var _toast_at := -1.0e9
var _frame := 0

## Generator -> slot flights, one per replayed tap: [{"spawn", "started"}]. Several can
## be in the air at once, exactly like the live board.
var _flys: Array = []
## Merge pop on the result cell: {"cell", "started"}.
var _pulse: Dictionary = {}
## Order-claim flights: [{"from": Vector2, "to": Vector2, "texture", "started"}].
var _claim_flys: Array = []
var _t := 0.0
var _total_frames := 0
var _end_time := 0.0
var _finished := false

var _page := Vector2(1080.0, 1920.0)
## Board geometry is never hardcoded here: the defaults are BoardView's own
## constants and _ready() re-reads them, so a board-layout change in board_view.gd
## moves the film with it.
var _origin := BoardView.BOARD_ORIGIN
var _board_size := BoardView.BOARD_SIZE
var _cols := int(BoardView.COLS)
var _rows := int(BoardView.ROWS)
var _cell_gap := int(BoardView.CELL_GAP)
var _font_zh: Font = null
var _font_en: Font = null
var _font_display_bold: Font = null
var _font_display_regular: Font = null
var _font_display_num: Font = null
var _frame_tex: Texture2D = null
var _sb_cache: Dictionary = {}
var _hue_cache: Dictionary = {}
var _snap: Dictionary = {}
## "bg_bottom" -> Texture2D or null, resolved once in _ready() before the first
## frame. _draw() never touches the theme dictionaries or the disk: a 1800-frame
## take is a pure function of the frame index plus these cached textures.
var _ui_tex: Dictionary = {}
## Manifest ids of the ui slots that really produced a texture (i.e. the layout art
## this take actually drew). Fed into the render manifest.
var _ui_ids: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = _page
	_parse_args()
	_page = BoardView.PAGE_SIZE
	_origin = BoardView.BOARD_ORIGIN
	_board_size = BoardView.BOARD_SIZE
	_cols = int(BoardView.COLS)
	_rows = int(BoardView.ROWS)
	_cell_gap = int(BoardView.CELL_GAP)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_font_zh = _load_font(FONT_ZH)
	_font_en = _load_font(FONT_EN)
	_font_display_bold = _load_font(FONT_DISPLAY_BOLD)
	_font_display_regular = _load_font(FONT_DISPLAY_REGULAR)
	_font_display_num = _load_font(FONT_DISPLAY_NUM)

	var model = ProjectModel.new()
	if not model.load_file(project_path):
		_fail("project load failed: " + String(model.load_error))
		return
	_model = model
	if not take_path.is_empty() and not _load_take():
		return

	_evaluator = EventEvaluator.new()
	_evaluator.setup(_model, seed_value, self)
	var timeline: Array = _model.project.get("timeline", [])
	if not _take.is_empty():
		timeline = _take.get("timeline", [])
	var loaded: Dictionary = _evaluator.load_timeline(timeline)
	if not bool(loaded.get("ok", false)):
		_fail("timeline resolve failed: " + str(loaded.get("errors", [])))
		return
	_end_time = float(loaded.get("end_time", 0.0))
	if not _take.is_empty():
		# The recording may run past the last click (the hand keeps moving, or the
		# player pauses before pressing R again): the film covers the whole take.
		_end_time = maxf(_end_time, float(_take.get("duration", 0.0)))

	var planned := RenderPlan.frame_count(_end_time, FPS)
	if frame_cap > 0:
		_total_frames = mini(frame_cap, planned) if planned > 0 else frame_cap
	else:
		_total_frames = planned
	if _total_frames <= 0:
		_fail("frame plan is empty (end_time=%.3f)" % _end_time)
		return

	_guard = AssetGuard.new()
	if not _guard.load_from(MANIFEST_INDEX, allow_placeholders):
		_fail("asset guard load failed: " + String(_guard.load_error))
		return
	# §7 item 7: the film must follow the theme. Palette + metrics come from the
	# same ThemeLoader the live screen uses, so a theme change reaches the film
	# without touching this file.
	_theme_loader = ThemeLoader.new()
	_theme_loader.setup(_guard, allow_placeholders)
	var resolved_theme := theme_name
	if resolved_theme.is_empty():
		resolved_theme = String(_model.project.get("theme", "themes/default"))
	var theme_result: Dictionary = _theme_loader.load_theme(resolved_theme, _model.project)
	if not bool(theme_result.get("ok", false)):
		_fail("theme load failed: " + str(theme_result.get("errors", [])))
		return
	theme_name = resolved_theme
	_colors = _theme_loader.colors()
	_metrics = _theme_loader.metrics
	if allow_placeholders:
		var code := String(_guard.check_ref(FRAME_ID))
		if code.is_empty():
			_frame_tex = _load_font_texture(FRAME_TEXTURE)
	# §20.5: every layout texture is resolved here, once, before the first frame.
	# _draw() only reads the cache, so no frame ever touches the filesystem.
	_resolve_ui_art()
	_setup_live_board()
	_setup_live_band()
	_setup_live_top()
	_setup_live_bottom()
	# 交付飞行必须在订单带之后建（Godot 后添加的子节点画在上面），
	# 否则芯片会被卡片盖住 —— 这正是"一个在上面、一个在下面"的那半。
	_setup_live_fly()
	_setup_overlay()
	if not _take.is_empty() and not no_cursor:
		_cursor_tex = _load_cursor()

	var refs: Array = ["font_en", "font_zh"]
	# §M1: the manifest must name the icon set the film drew with, so a theme swap
	# is visible in output/render_manifest.json and a REFERENCE_ONLY chip aborts the
	# render instead of silently falling back to procedural art.
	for chip_id in _theme_loader.chip_refs():
		refs.append(String(chip_id))
	# §20.5 layout art: only slots whose texture really loaded, so the manifest names
	# the panels the frame actually painted (a blocked/absent id stays out of the
	# block list and the film falls back to the procedural panel instead).
	for ui_id in _ui_ids:
		refs.append(String(ui_id))
	if _cursor_tex != null:
		refs.append(CURSOR_ID)
	if allow_placeholders:
		refs.append(FRAME_ID)
	for extra in probe_refs:
		refs.append(String(extra))
	var manifest: Dictionary = RenderManifest.build({
		"project": project_path,
		"project_title": String(_model.project.get("meta", {}).get("title", "")),
		"fps": FPS,
		"frames": _total_frames,
		"end_time": _end_time,
		"allow_placeholders": allow_placeholders,
		"refs": refs,
	}, _guard)
	RenderManifest.write_file(out_manifest, manifest)
	if not bool(manifest.get("ok", false)):
		for b in manifest.get("blocked", []):
			print("[movie] BLOCKED " + String(b.get("id", "")) + " " + String(b.get("code", "")))
		print("[movie] FAIL asset guard rejected this render")
		_finished = true
		get_tree().quit(3)
		return

	print("[movie] project=%s frames=%d fps=%d end=%.3f seed=%d allow_placeholders=%s" % [
		project_path, _total_frames, FPS, _end_time, seed_value,
		"true" if allow_placeholders else "false",
	])
	print("[movie] theme=%s ok=true" % theme_name)
	print("[movie] ui " + _ui_line())
	print("[movie] layout " + _layout_line())
	print("[movie] manifest " + RenderManifest.summary(manifest) + " [" + RenderManifest.detail(manifest) + "]")
	print("[movie] window=%dx%d viewport=%dx%d" % [
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		int(_page.x), int(_page.y),
	])


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--frames="):
			frame_cap = int(arg.substr(9))
		elif arg.begins_with("--project="):
			project_path = arg.substr(10)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--out-manifest="):
			out_manifest = arg.substr(15)
		elif arg.begins_with("--theme="):
			theme_name = arg.substr(8)
		elif arg == "--allow-placeholders":
			allow_placeholders = true
		elif arg == "--no-cursor":
			no_cursor = true
		elif arg.begins_with("--take="):
			take_path = arg.substr(7)
		elif arg.begins_with("--probe-ref="):
			probe_refs.append(arg.substr(12))


## `--take=<file>`: the recording is the film's script (timeline + cursor path).
## Validated before a single frame, so a broken take fails loudly instead of
## rendering a film with a frozen or jumping hand.
func _load_take() -> bool:
	var take: Dictionary = TakeIo.load_file(take_path)
	if take.is_empty():
		_fail("take not readable: " + take_path)
		return false
	var check: Dictionary = TakeIo.validate(take)
	if not bool(check.get("ok", false)):
		_fail("take invalid: " + str(check.get("errors", [])))
		return false
	_take = take
	# Recorded events are sim events; older takes may carry no `channel` at all.
	# Normalising here keeps those takes renderable instead of silently refusing
	# every event (see TakeIo.normalize_timeline).
	_take["timeline"] = TakeIo.normalize_timeline(take.get("timeline", []))
	seed_value = int(take.get("seed", seed_value))
	print("[movie] take " + take_path + " " + TakeIo.summary(take))
	return true


## The film's hand is the same registered asset the window uses (ui_cursor_hand,
## CC0). ThemeLoader goes through AssetGuard, so a missing registration blocks the
## render instead of drawing an invisible cursor.
func _load_cursor() -> Texture2D:
	if _theme_loader != null:
		var loaded = _theme_loader.texture_for(CURSOR_ID)
		if loaded is Texture2D:
			return loaded
	return _load_font_texture(CURSOR_TEXTURE)


func _draw_cursor() -> void:
	_paint_cursor(self)


## 光标画到指定 CanvasItem（成片里必须画在最上层 overlay，否则被托管组件盖住）。
## 拖拽中的棋子：画在**最上层**（订单带之上），几何与实机 DragGhost 一致 —— 起点格
## 那枚棋子跟着指针走，源格只留白角框（由棋盘画）。数据来自 take 的 drag 采样。
func _paint_drag(target: CanvasItem) -> void:
	if _live_board == null or _take.is_empty() or target == null:
		return
	var drag: Dictionary = TakeIo.drag_at(_take, _t)
	if drag.is_empty():
		return
	var raw = drag.get("from", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
		return
	var from := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	var it := _item_at_cell(from)
	if it.is_empty():
		return
	var entity_id := String(it.get("entity", ""))
	var kind := "generator" if _live_board.is_generator_entity(entity_id) else "chip"
	var tex: Texture2D = _live_board.item_texture(kind, entity_id, int(it.get("level", 1)))
	if tex == null:
		return
	# 几何只有一份：直接问棋盘要"拖拽棋子的矩形"，别在这里再算一遍
	var rect: Rect2 = _live_board.drag_chip_rect()
	if rect.size.x <= 0.0:
		return
	target.draw_texture_rect(tex, rect, false)
	# 白角框：和棋子同一个矩形四角外扩一点（实机 DragGhost 也画这个框）
	var frame: Texture2D = _live_board.drag_frame_texture()
	if frame != null:
		# 白角框画在棋子**可见本体**外面一圈：棋子贴图自带留白，所以框比矩形小
		# （0.72 是量着实机拖拽框与棋子的比例定的，和游戏一致）。
		# 2026-11-10：生成器贴图留白少，框按 0.72 会显得太小（操作者："白框加大一点儿"）。
		var frame_ratio := 1.05 if kind == "generator" else 0.72
		var fr := Rect2(rect.get_center() - rect.size * frame_ratio * 0.5,
				rect.size * frame_ratio)
		target.draw_texture_rect(frame, fr, false)


func _paint_cursor(target: CanvasItem) -> void:
	if no_cursor or _take.is_empty() or _cursor_tex == null or target == null:
		return
	var pos: Dictionary = TakeIo.cursor_at(_take, _t)
	if not bool(pos.get("visible", false)):
		return
	# 2026-11-10：手"按下去"要有看得见的幅度 ——
	# 拖拽期间一直保持按下，松手才回弹；点击（含右键）后 0.22s 内也是按下。
	var pressed: bool = not TakeIo.drag_at(_take, _t).is_empty() 			or not TakeIo.click_at(_take, _t).is_empty()
	var press: float = TakeIo.PRESS_SCALE if pressed else 1.0
	var dip: float = CURSOR_PRESS_DIP if pressed else 0.0
	var size := Vector2(CURSOR_SIZE, CURSOR_SIZE) * press
	var origin := Vector2(float(pos["x"]), float(pos["y"])) 			- CURSOR_HOTSPOT_RATIO * size + Vector2(0.0, dip)
	target.draw_texture_rect(_cursor_tex, Rect2(origin, size), false)
	# 涟漪画在手之上：右键交付时指针压在卡片上，画在下面会被盖住
	_paint_press_ring(target)


## 按下反馈：以点击点为中心扩散的白环（0.25s），与实机同一套参数。
func _paint_press_ring(target: CanvasItem) -> void:
	var click: Dictionary = TakeIo.click_at(_take, _t)
	if click.is_empty():
		return
	var age := _t - float(click.get("t", -99.0))
	if age < 0.0 or age > TakeIo.RING_SECONDS:
		return
	var p := age / TakeIo.RING_SECONDS
	var centre := Vector2(float(click.get("x", 0.0)), float(click.get("y", 0.0)))
	var radius := lerpf(18.0, TakeIo.RING_RADIUS, p)
	var alpha := 0.75 * (1.0 - p)
	target.draw_arc(centre, radius, 0.0, TAU, 48, Color(1, 1, 1, alpha), 8.0, true)
	target.draw_arc(centre, radius * 0.62, 0.0, TAU, 48, Color(1, 1, 1, alpha * 0.5), 4.0, true)


func _load_font(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return null
	# load_dynamic_font() reads the .otf/.ttf straight off disk: no import cache
	# (.godot/) and no sidecar .import files are needed, so a freshly copied or
	# relocated project renders text on the very first run.
	var ff := FontFile.new()
	if ff.load_dynamic_font(path) != OK:
		return null
	return ff


func _load_font_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ ui layout art

## Resolves every §20.5 slot through the theme loader exactly once. `has_method`
## guards keep the film renderable against an older loader (the layout then draws
## its procedural fallbacks instead of erroring out), and a null texture is a valid
## outcome: it means "no art for this slot, draw the plain panel".
func _resolve_ui_art() -> void:
	_ui_tex = {}
	_ui_ids = []
	for raw_key in UI_KEYS:
		var key := String(raw_key)
		var id := ""
		if _theme_loader != null and _theme_loader.has_method("resolve_ui"):
			var resolved = _theme_loader.resolve_ui(key, _model.project)
			if typeof(resolved) == TYPE_DICTIONARY:
				id = String((resolved as Dictionary).get("id", ""))
		var texture: Texture2D = null
		if not id.is_empty() and _theme_loader != null and _theme_loader.has_method("texture_for"):
			var loaded = _theme_loader.texture_for(id)
			if loaded is Texture2D:
				texture = loaded
		_ui_tex[key] = texture
		if texture != null:
			_ui_ids.append(id)


func _ui(key: String) -> Texture2D:
	var value = _ui_tex.get(key, null)
	return value if value is Texture2D else null


## "key=id ..." for the render log: names the layout art this take resolved.
func _ui_line() -> String:
	var parts: Array = []
	for raw_key in UI_KEYS:
		var key := String(raw_key)
		var texture := _ui(key)
		parts.append("%s=%s" % [key, "yes" if texture != null else "-"])
	return "resolved=%d of %d %s" % [_ui_ids.size(), UI_KEYS.size(), " ".join(parts)]


## One ASCII line with the landed §20.5 rects (the board is read from BoardView).
func _layout_line() -> String:
	return "board=(%.0f,%.0f,%.0f,%.0f) bg=(%.0f,%.0f)+(%.0f,%.0f) items=(%.0f,%.0f,%.0f,%.0f) exit=(%.0f,%.0f,%.0f,%.0f) bag=(%.0f,%.0f,%.0f,%.0f) shop=(%.0f,%.0f,%.0f,%.0f)" % [
		_origin.x, _origin.y, _board_size.x, _board_size.y,
		LAYOUT_BG_BOTTOM.position.x, LAYOUT_BG_BOTTOM.position.y,
		LAYOUT_BG_BOTTOM.size.x, LAYOUT_BG_BOTTOM.size.y,
		LAYOUT_ITEMS.position.x, LAYOUT_ITEMS.position.y, LAYOUT_ITEMS.size.x, LAYOUT_ITEMS.size.y,
		LAYOUT_EXIT.position.x, LAYOUT_EXIT.position.y, LAYOUT_EXIT.size.x, LAYOUT_EXIT.size.y,
		LAYOUT_BAG.position.x, LAYOUT_BAG.position.y, LAYOUT_BAG.size.x, LAYOUT_BAG.size.y,
		LAYOUT_SHOP.position.x, LAYOUT_SHOP.position.y, LAYOUT_SHOP.size.x, LAYOUT_SHOP.size.y,
	]


## Stretches a slot texture onto exactly `r` (backgrounds / strips / the PSD-sliced
## characters are authored at the target size). False when the slot has no art.
func _draw_ui_stretch(key: String, r: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect(texture, r, false)
	return true


## Draws one source region of a slot texture into `r`, which is how the two order
## characters avoid their baked-in order cards.
## 9-slice draw for the board base: corners 1:1, edges/centre stretched, so the
## 167px tile's radius and border thickness survive being stretched to 983x1263.
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
	var x1 := x0 + c
	var y1 := y0 + c
	draw_texture_rect_region(texture, Rect2(x0, y0, c, c), Rect2(0, 0, c, c))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, y0, c, c), Rect2(source.x - c, 0, c, c))
	draw_texture_rect_region(texture, Rect2(x0, rect.end.y - c, c, c), Rect2(0, source.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, rect.end.y - c, c, c),
			Rect2(source.x - c, source.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(x1, y0, inner_w, c), Rect2(c, 0, src_inner_w, c))
	draw_texture_rect_region(texture, Rect2(x1, rect.end.y - c, inner_w, c),
			Rect2(c, source.y - c, src_inner_w, c))
	draw_texture_rect_region(texture, Rect2(x0, y1, c, inner_h), Rect2(0, c, c, src_inner_h))
	draw_texture_rect_region(texture, Rect2(rect.end.x - c, y1, c, inner_h),
			Rect2(source.x - c, c, c, src_inner_h))
	draw_texture_rect_region(texture, Rect2(x1, y1, inner_w, inner_h),
			Rect2(c, c, src_inner_w, src_inner_h))


## Multi-cell safeboxes, same layout function as the live board.
func _draw_safeboxes(level_index: int) -> void:
	var sizes: Array = []
	if _model != null:
		sizes = _model.level(level_index).get("safes", [])
	var boxes: Array = Safeboxes.layout(_cols, _rows, seed_value, level_index, sizes)
	for raw in boxes:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var box: Dictionary = raw
		var x0 := int(box.get("x", 0))
		var y0 := int(box.get("y", 0))
		var w := int(box.get("w", 1))
		var h := int(box.get("h", 1))
		if w <= 0 or h <= 0:
			continue
		var rect: Rect2 = _slot_rect(x0, y0).merge(_slot_rect(x0 + w - 1, y0 + h - 1))
		var art := _ui("safe_" + String(box.get("size", "")))
		if art != null:
			draw_texture_rect(art, rect, false)
		_draw_safe_overlay(rect, box)


func _draw_safe_overlay(rect: Rect2, box: Dictionary) -> void:
	var tpl: Dictionary = Safeboxes.TEMPLATE
	var centre := rect.get_center()

	var bubble := _ui("bubble")
	if bubble != null:
		var bs: float = tpl["bubble"]
		draw_texture_rect(bubble, Rect2(centre + Vector2(0.0, float(tpl["bubble_offset_y"]))
				- Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false)

	var bolt := _ui("stamina")
	if bolt != null:
		var bsize: Vector2 = tpl["bolt"]
		draw_texture_rect(bolt, Rect2(centre + Vector2(0.0, float(tpl["bolt_offset_y"]))
				- bsize * 0.5, bsize), false)

	_draw_safe_label(Rect2(rect.position.x, centre.y + float(tpl["x_offset_y"]) - 20.0,
			rect.size.x, 40.0), "x%d" % int(box.get("charges", 0)), int(tpl["x_size"]), Color(1, 1, 1, 1))

	var frame := _ui("safe_frame")
	var fsize: Vector2 = tpl["frame"]
	var frame_rect := Rect2(centre + Vector2(0.0, float(tpl["frame_offset_y"])) - fsize * 0.5, fsize)
	if frame != null:
		var src := frame.get_size()
		_draw_plate(frame, frame_rect, minf(14.0, minf(src.x, src.y) * 0.34))
	_draw_safe_label_left(frame_rect.grow(-float(tpl["lv_pad_x"])),
			"Lv.%d" % int(box.get("level", 10)), int(tpl["lv_size"]), Color("#33475B"))

	var lock := _ui("safe_lock")
	if lock != null:
		var lsize: Vector2 = tpl["lock"]
		draw_texture_rect(lock, Rect2(Vector2(frame_rect.end.x - lsize.x * 0.32,
				frame_rect.get_center().y - lsize.y * 0.5), lsize), false)


func _draw_safe_label_left(r: Rect2, text: String, size: int, color: Color) -> void:
	var font := _font_display_bold if _font_display_bold != null else _font_zh
	if font == null:
		return
	var baseline := Vector2(r.position.x, r.get_center().y + float(size) * 0.36)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(0.16, 0.25, 0.36, 0.85))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_safe_label(r: Rect2, text: String, size: int, color: Color) -> void:
	var font := _font_display_bold if _font_display_bold != null else _font_zh
	if font == null:
		return
	var baseline := Vector2(r.position.x, r.get_center().y + float(size) * 0.36)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size,
				Color(0.16, 0.25, 0.36, 0.85))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, color)


## Finish badge exactly like board_view: the ui_icon_finish texture, centred at
## cell centre + (36,34), at the texture's own size.
func _draw_finish_badge(cell: Vector2i) -> void:
	var texture := _ui("finish")
	if texture == null:
		return
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var centre: Vector2 = _slot_rect(cell.x, cell.y).get_center() + Vector2(36.0, 34.0)
	draw_texture_rect(texture, Rect2(centre - size * 0.5, size), false)


func _draw_ui_region(key: String, src: Rect2, r: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect_region(texture, r, src)
	return true


## Keeps the source aspect, fits inside `r`, centres it: the §20.5 boxes for the
## exit/bag/shop buttons are not the assets' own sizes (156x174 -> 164x174,
## 144x180 -> 109x147), so scaling by box would squash the art.
func _draw_ui_fit(key: String, r: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return false
	var used := minf(r.size.x / source.x, r.size.y / source.y)
	var drawn := source * used
	draw_texture_rect(texture, Rect2(r.position + (r.size - drawn) * 0.5, drawn), false)
	return true


## Stretch a ui slot to the exact rect with a tint. The bottom-bar rule uses this:
## common_line.png ships as a 10x4 pure-white sliver, so a modulate pass is what
## turns it into the #C4D7E2 separator the reference capture shows.
func _draw_ui_tint(key: String, r: Rect2, tint: Color) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect(texture, r, false, tint)
	return true


## §20.5 cell geometry read off BoardView: 983/7 x 1263/9, so the 63 cells tile the
## container with no remainder. The film never hardcodes 140 / 980 / 1260.
func _slot_rect(x: int, y: int) -> Rect2:
	var left := _origin.x + _board_size.x * float(x) / float(_cols)
	var right := _origin.x + _board_size.x * float(x + 1) / float(_cols)
	var top := _origin.y + _board_size.y * float(y) / float(_rows)
	var bottom := _origin.y + _board_size.y * float(y + 1) / float(_rows)
	return Rect2(left, top, right - left, bottom - top)


## Energy countdown in the PSD's `mm:ss` shape, from the sim HUD's tick seconds.
func _mmss(seconds: int) -> String:
	var total := maxi(0, seconds)
	return "%02d:%02d" % [total / 60, total % 60]


# --------------------------------------------------------------- frame driving

func _process(_delta: float) -> void:
	if _finished:
		return
	_frame += 1
	_t = float(_frame - 1) / float(FPS)
	_advance_to(_t)
	if _frame >= _total_frames:
		# the last frame is at (frames-1)/fps, i.e. one frame short of end_time;
		# without this drain a zero-duration event exactly at the end would be lost
		_advance_to(_end_time)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()
	if _frame >= _total_frames:
		_finish()


## Feeds every event whose resolved time is <= t. The evaluator does the ordering
## and the sim mutation; this scene only reads the resulting snapshot.
## True when the take's click log records a refused click at this timestamp.
func _failed_live_at(at: float) -> bool:
	if at < 0.0:
		return false
	for raw in (_take.get("clicks", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if bool((raw as Dictionary).get("ok", true)):
			continue
		if absf(float((raw as Dictionary).get("t", -99.0)) - at) <= 0.004:
			return true
	return false


func _advance_to(t: float) -> void:
	if _evaluator == null:
		return
	var evs: Array = _evaluator.events
	while _evaluator.cursor < evs.size():
		var ev: Dictionary = evs[_evaluator.cursor]
		if float(ev.get("at", 0.0)) > t + 1e-6:
			break
		var r: Dictionary = _evaluator.step()
		var channel := String(r.get("channel", ""))
		# Any refused event is a broken take, not just a refused sim one: a timeline
		# whose `channel` is missing used to fail EV_CHANNEL here while the film kept
		# rendering the cursor over a frozen board (the "merge did nothing" dud).
		if not bool(r.get("ok", false)):
			# A command the player already got refused in free mode (the click log has
			# ok=false at that instant) is not a broken take: older recorders wrote
			# every attempt, and failing the whole film over it left only the .avi.
			if channel == "sim" and _failed_live_at(float(r.get("at", -1.0))):
				pass
			else:
				_rejected.append({
					"id": String(r.get("id", "")),
					"channel": channel,
					"code": String(r.get("code", "")),
				})
		if channel == "sim" and bool(r.get("ok", false)) \
				and (String(r.get("type", "")) == "merge" or String(r.get("type", "")) == "drag"):
			var payload = (ev.get("payload", {}) as Dictionary)
			var to_raw = payload.get("to", [])
			if typeof(to_raw) == TYPE_ARRAY and (to_raw as Array).size() >= 2:
				_pulse = {"cell": Vector2i(int((to_raw as Array)[0]), int((to_raw as Array)[1])),
						"started": float(r.get("at", t))}
		# 2026-11-10：一枚一枚交（右键棋子 / 拖到卡上 / 右键卡上任务格子）在 take 里是
		# `deliver` 事件。成片按同一条数据播：只飞一枚，落点是**那一行的底板中心**；
		# sim 回 settled=true 时才走整单结算的表现（和点卡结算同一套）。
		if channel == "sim" and bool(r.get("ok", false)) 				and String(r.get("type", "")) == "deliver":
			var d_payload = (ev.get("payload", {}) as Dictionary)
			var d_from = d_payload.get("from", [])
			var d_order := String(d_payload.get("order", ""))
			var d_sim = (r.get("sim", {}) as Dictionary)
			var d_row := int(d_sim.get("row", d_payload.get("row", 0)))
			var at_now := float(r.get("at", t))
			if typeof(d_from) == TYPE_ARRAY and (d_from as Array).size() >= 2:
				# 2026-11-10：拖拽交付时棋子跟着手走，成片用**当时的光标位置**当起点，
				# 时长 0.16s；右键交付（光标不在订单带上）仍从棋子那一格飞 0.55s。
				# 2026-11-10：**只有拖拽**（via=drag）才从光标位置起飞；
				# 右键棋子 / 右键卡上任务格时指针就在订单带上，若也用光标位置，
				# 起点≈终点，看起来就是"棋子直接消失没有飞行"。
				var d_cell := Vector2i(int((d_from as Array)[0]), int((d_from as Array)[1]))
				# 2026-11-10：拖拽交付**不飞棋子**（棋子本来就在手上），只做落袋反馈；
				# 右键棋子 / 右键任务格才从棋盘飞过来。
				var d_delay := 0.0
				if _live_band != null:
					d_delay = _live_band.reveal_card(d_order, 0.26)
				if not _deliver_is_drag(d_payload, at_now, d_cell):
					_play_deliver_flight(d_order, d_row, d_cell, at_now + d_delay,
							_deliver_origin(d_payload, at_now, d_cell), 0.0)
				if _live_band != null:
					_live_band.punch_row(d_order, d_row, d_delay)
					_live_band.hold_sort(d_order, d_delay + 0.75)
			if bool(d_sim.get("settled", false)):
				_play_settle_effects(d_order, float(r.get("at", t)))
		if channel == "sim" and bool(r.get("ok", false)) \
				and String(r.get("type", "")) == "order_claim":
			var claim_payload = (ev.get("payload", {}) as Dictionary)
			var src_raw = claim_payload.get("src", [])
			var ord := String(claim_payload.get("order", ""))
			if typeof(src_raw) == TYPE_ARRAY and (src_raw as Array).size() >= 2:
				var src_cell := Vector2i(int((src_raw as Array)[0]), int((src_raw as Array)[1]))
				var ord_rect := _claim_card_rect(ord)
				_play_claim_effects(ord, src_cell, float(r.get("at", t)), claim_taken(r))
				# 交付后金库立刻 +N（sim 是瞬时的）；这笔 N 从关卡订单数据取，不依赖显示值。
				var coin_after := int(_evaluator.sim.hud.get("coin", 0))
				var gained := _order_coin_from_model(ord, int(_evaluator.sim.level_index))
				if gained <= 0:
					gained = maxi(coin_after - int(round(_coin_display)), 0)
				_coin_display = minf(_coin_display, float(coin_after - gained))
				_queue_coin_ticks(gained, float(r.get("at", t)))
				var gem_gain := _order_gem(ord)
				if gem_gain > 0:
					_queue_gem_ticks(gem_gain, float(r.get("at", t)))
				var stamina_gain := _order_energy(ord)
				if stamina_gain > 0:
					_queue_energy_ticks(stamina_gain, float(r.get("at", t)))
				if _live_band != null:
					# 与实机同一时序：芯片 0.55s + 金币起飞后 1s，卡片才缩。
					_live_band.hold_done(ord, 1.55)
		if channel == "sim" and bool(r.get("ok", false)) \
				and String(r.get("type", "")) in ["tap", "stockpile_tap"] and _live_board != null:
			var spawn_now: Dictionary = _evaluator.sim.last_spawn
			if not spawn_now.is_empty():
				if String(r.get("type", "")) == "stockpile_tap":
					var sp: Dictionary = spawn_now.duplicate(true)
					var sp_rect: Rect2 = Layout.STOCKPILE_RECT
					sp["from_page"] = [sp_rect.get_center().x, sp_rect.get_center().y]
					_live_board.start_fly(sp, float(r.get("at", t)))
				else:
					_live_board.start_fly(spawn_now, float(r.get("at", t)))
		if channel == "sim" and bool(r.get("ok", false)) \
				and String(r.get("type", "")) in ["merge", "drag"] and _live_board != null:
			var pl = (ev.get("payload", {}) as Dictionary)
			var to_r = pl.get("to", [])
			if typeof(to_r) == TYPE_ARRAY and (to_r as Array).size() >= 2:
				_live_board.pulse(Vector2i(int((to_r as Array)[0]), int((to_r as Array)[1])),
						"merge" if String(r.get("type", "")) == "merge" else "settle",
						float(r.get("at", t)))
		if channel == "sim" and bool(r.get("ok", false)) \
				and String(r.get("type", "")) == "merge" and _live_board != null:
			for row in _evaluator.sim.last_unlocks:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var cr = (row as Dictionary).get("cell", [])
				if typeof(cr) != TYPE_ARRAY or (cr as Array).size() < 2:
					continue
				_live_board.unlock(Vector2i(int((cr as Array)[0]), int((cr as Array)[1])),
						String((row as Dictionary).get("kind", "")), float(r.get("at", t)),
						String((row as Dictionary).get("became", "")))
		if channel == "sim" and bool(r.get("ok", false)) and String(r.get("type", "")) == "tap":
			var spawn: Dictionary = _evaluator.sim.last_spawn
			if not spawn.is_empty():
				_flys.append({"spawn": spawn.duplicate(true), "started": float(r.get("at", t))})
		if channel == "sim":
			# §7 item 4: the film shows the same prompt the live screen shows, either
			# as an explicit board_full marker or as the sim's verdict on some event.
			if String(r.get("code", "")) == "SIM_BOARD_FULL" \
					or String(r.get("type", "")) == "board_full":
				_prompt_board_full(float(r.get("at", t)))
	_snap = _evaluator.sim.snapshot()
	if not _snap.has("hud"):
		_snap = _evaluator.sim.snapshot()


func _finish() -> void:
	_finished = true
	var cells := 0
	var obs := 0
	if _snap.has("board"):
		var b: Dictionary = _snap["board"]
		cells = (b.get("cells", []) as Array).size()
		obs = (b.get("obstacles", []) as Array).size()
	var level_id := "?"
	if _snap.has("level_id"):
		level_id = String(_snap["level_id"])
	print("[movie] done frames=%d t=%.3f level=%s cells=%d obstacles=%d rejected=%d" % [
		_frame, _t, level_id, cells, obs, _rejected.size(),
	])
	if not _take.is_empty():
		print("[movie] take " + TakeIo.summary(_take) + " cursor="
				+ ("off" if no_cursor else "on"))
	# A take the sim refused is not a film. Before this gate the log could say
	# "rejected=8" and render.sh still reported ok=1, so a timeline that only
	# looked valid shipped as a silently incomplete video.
	if not _rejected.is_empty():
		print("[movie] FAIL rejected=%d" % _rejected.size())
		for r in _rejected:
			print("[movie] rejected " + String(r.get("id", "")) + " " + String(r.get("code", "")))
		print("[movie] exit=3")
		get_tree().quit(3)
		return
	print("[movie] exit=0")
	get_tree().quit(0)


func _fail(message: String) -> void:
	_finished = true
	print("[movie] FAIL " + message)
	print("[movie] exit=1")
	get_tree().quit(1)


# ------------------------------------------------------------------- view sink

## Called by the shared evaluator for every event on every channel. Only view
## events change what the camera shows; sim events are already reflected in the
## snapshot. Nothing is stored per frame beyond the snapshot, so a redraw is
## reproducible from (frame index) alone.
func on_event(_ev: Dictionary) -> void:
	pass


# ----------------------------------------------------------------------- draw

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _page), _palette("page", BoardView.COLOR_PAGE), true)
	# Paint order is the PSD's own stacking: band + two background layers, then the
	# two order characters, then the money bar (its pills sit on top of the
	# characters' hair, exactly like the preview), the order cards over the
	# characters' bodies, the board container, and finally the bottom items bar.
	_draw_band()
	_draw_background()
	if _snap.is_empty():
		return
	_sync_live_band()


	_draw_view_layer()


## Bottom band: metrics.band_height is the one theme knob with no other consumer, so
## the band is what makes a "thicker band" a visible property of the film. It is
## clamped to start at the board's bottom edge, so the band never paints on the
## §20.5 board container; with the two background textures present it sits
## underneath them and is only visible in the no-asset fallback.
## 建面板：与实机同一位置/尺寸/主题，唯一差异是立绘交给成片自己画（层级）。
## 棋盘也托管实机组件（board_view）：进关建一次，之后每帧只推状态与时钟。
## 交付时：芯片飞向卡片（0.55s），然后金币螺旋飞到顶栏（与实机同一套 FlyAnim 事件）。
## 与实机同规则：tick 起点 = 芯片落地(0.55s)，0.85s 内均匀发完。
func _queue_coin_ticks(amount: int, at: float) -> void:
	if amount <= 0:
		return
	var n: int = clampi(amount / 5, 3, 8)
	var start := at + 0.55
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		_coin_ticks.append({"at": start + gap * float(i),
				"amount": base + (1 if i < rest else 0)})


## 2026-11-09：体力数字 tick —— 30~100 的量级，每 ~10 一跳（3~10 跳），与金币同规则。
func _queue_energy_ticks(amount: int, at: float) -> void:
	if amount <= 0:
		return
	var n: int = clampi(int(round(float(amount) / 10.0)), 3, 10)
	var start := at + 0.61
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		_energy_ticks.append({"at": start + gap * float(i),
				"amount": base + (1 if i < rest else 0)})


## 2026-11-09：钻石数字 tick —— 与金币同规则（0.85s 内发完，每颗一跳）。
## 数量小（1-5），所以 n = 数量本身，一跳一颗。
func _queue_gem_ticks(amount: int, at: float) -> void:
	if amount <= 0:
		return
	var n: int = clampi(amount, 1, 5)
	var start := at + 0.67
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		_gem_ticks.append({"at": start + gap * float(i),
				"amount": base + (1 if i < rest else 0)})


## 单枚交付的飞行：起点 = 事件里的格子，落点 = 那一行的底板中心。
func _play_deliver_flight(order_id: String, row: int, cell: Vector2i, at: float,
		from_point: Vector2 = Vector2(-1, -1), dur: float = 0.0) -> void:
	if _live_fly == null or _live_band == null:
		return
	var it := _item_at_cell(cell)
	var tex: Texture2D = null
	if not it.is_empty():
		tex = _chip_texture(String(it.get("entity", "")), int(it.get("level", 1)))
	if tex == null:
		tex = _claim_texture(order_id)
	if tex == null:
		return
	var target: Vector2 = _live_band.position + _live_band.mission_row_center(order_id, row)
	var payload := {"from": [cell.x, cell.y], "order": order_id,
			"to_point": [target.x, target.y], "texture": tex}
	if from_point.x >= 0.0:
		payload["from_point"] = [from_point.x, from_point.y]
		payload["dur"] = dur if dur > 0.0 else FlyAnimScene.deliver_duration(from_point, target)
	else:
		var cell_centre: Vector2 = _live_board.cell_rect(cell.x, cell.y).get_center() 				+ _live_board.position
		payload["from_point"] = [cell_centre.x, cell_centre.y]
		payload["dur"] = dur if dur > 0.0 else FlyAnimScene.deliver_duration(cell_centre, target)
	_live_fly.play_event({"type": "deliver_chip", "at": at, "payload": payload})


## 这一枚该从哪儿起飞。
## 1) 事件带 `via`（新 take）：只有 `drag` 用光标位置；
## 2) 老 take 没有 `via`：看**录制里的拖拽采样** —— 交付前 1.2s 内有过一次从同一格开始的
##    拖拽，就说明这一枚是"拖过去的"，从**松手时的光标位置**飞；否则从棋子那一格飞。
## 不这么判的话，拖拽交付会从**已经被拖空的那一格**凭空冒出一枚飞过去。
func _deliver_is_drag(payload: Dictionary, at: float, cell: Vector2i) -> bool:
	var via := String(payload.get("via", ""))
	if not via.is_empty():
		return via == "drag"
	return _dragged_from(cell, at)


func _deliver_origin(payload: Dictionary, at: float, cell: Vector2i) -> Vector2:
	var cursor_pos: Dictionary = TakeIo.cursor_at(_take, at)
	var cp := Vector2(-1.0, -1.0)
	if not cursor_pos.is_empty():
		cp = Vector2(float(cursor_pos.get("x", -1.0)), float(cursor_pos.get("y", -1.0)))
	var via := String(payload.get("via", ""))
	var dragged := via == "drag"
	if via.is_empty():
		dragged = _dragged_from(cell, at)
	if dragged and cp.x >= 0.0:
		return cp
	return Vector2(-1, -1)


## 交付前 1.2s 内，有没有一次从 `cell` 起手的拖拽（老 take 的兜底判据）。
func _dragged_from(cell: Vector2i, at: float) -> bool:
	var rows = _take.get("drag", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		return false
	var best_t := -99999.0
	var best_from := Vector2i(-1, -1)
	for row in rows:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 5:
			continue
		var t := float((row as Array)[0])
		if t <= at + 0.05 and t > best_t:
			best_t = t
			best_from = Vector2i(int((row as Array)[1]), int((row as Array)[2]))
	if best_from != cell:
		return false
	return at - best_t <= 1.2


## 页面坐标点是否落在订单带上（用来判断这次交付是不是"拖到卡上"）。
func _band_contains(point: Vector2) -> bool:
	if _live_band == null:
		return false
	return Rect2(_live_band.position, _live_band.size).has_point(point)


## 整单收满后的结算表现：奖励飞顶栏 + 数字 tick + 卡片 hold 后缩掉。
func _play_settle_effects(order_id: String, at: float) -> void:
	var coin_after := int(_evaluator.sim.hud.get("coin", 0))
	var gained := _order_coin_from_model(order_id, int(_evaluator.sim.level_index))
	if gained <= 0:
		gained = maxi(coin_after - int(round(_coin_display)), 0)
	_coin_display = minf(_coin_display, float(coin_after - gained))
	_queue_coin_ticks(gained, at)
	var gem_gain := _order_gem(order_id)
	if gem_gain > 0:
		_queue_gem_ticks(gem_gain, at)
	var stamina_gain := _order_energy(order_id)
	if stamina_gain > 0:
		_queue_energy_ticks(stamina_gain, at)
	# 起点 = 这一张卡的金币图标（不是卡片中心）
	var centre: Vector2 = _live_band.position + _live_band.reward_origin(order_id, "coin") 			if _live_band != null else orders_anchor(order_id)
	if gained > 0:
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.55, "payload": {
			"from_point": [centre.x, centre.y], "amount": gained,
			"count": clampi(gained / 5, 3, 8), "texture": _ui("coin_big")}})
	# 2026-11-10：逐枚交付的结算也要播钻石 / 体力螺旋（原来只播金币，
	# 交付改成一枚一枚之后这条路不再经过 _play_claim_effects，两个奖励就丢了）。
	var gem_from: Vector2 = _live_band.position + _live_band.reward_origin(order_id, "gem") 			if _live_band != null else orders_anchor(order_id)
	var energy_from: Vector2 = _live_band.position + _live_band.reward_origin(order_id, "energy") 			if _live_band != null else orders_anchor(order_id)
	if gem_gain > 0:
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.67, "payload": {
			"from_point": [gem_from.x, gem_from.y], "amount": gem_gain,
			"count": clampi(gem_gain, 1, 5), "texture": _ui("gem"), "spin": -1.0}})
	if stamina_gain > 0:
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.61, "payload": {
			"from_point": [energy_from.x, energy_from.y], "amount": stamina_gain,
			"count": 3, "texture": _ui("energy"), "spin": 1.0}})
	if _live_band != null:
		_live_band.hold_done(order_id, 1.55)


func _play_claim_effects(order_id: String, cell: Vector2i, at: float, taken: Array = []) -> void:
	if _live_fly == null:
		return
	# 与实机一致：sim 消耗了几枚就飞几枚（2 行任务的订单会飞两枚），
	# 起点 = 每枚被消耗的格子，落点 = 订单卡中心。数据来自 sim 的 `taken`。
	var target := orders_anchor(order_id)
	var flown := 0
	if typeof(taken) == TYPE_ARRAY:
		for i in (taken as Array).size():
			var raw = (taken as Array)[i]
			if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
				continue
			var pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
			var it := _item_at_cell(pos)
			var tex: Texture2D = null
			if not it.is_empty():
				tex = _chip_texture(String(it.get("entity", "")), int(it.get("level", 1)))
			if tex == null:
				tex = _claim_texture(order_id)
			if tex == null:
				continue
			_live_fly.play_event({"type": "deliver_chip", "at": at + 0.08 * float(i), "payload": {
				"from": [pos.x, pos.y], "order": order_id,
				"to_point": [target.x, target.y], "texture": tex}})
			flown += 1
	if flown == 0:
		var src_item := _item_at_cell(cell)
		var texture: Texture2D = null
		if not src_item.is_empty():
			texture = _chip_texture(String(src_item.get("entity", "")), int(src_item.get("level", 1)))
		if texture == null:
			texture = _claim_texture(order_id)
		if texture != null:
			_live_fly.play_event({"type": "deliver_chip", "at": at, "payload": {
				"from": [cell.x, cell.y], "order": order_id,
				"to_point": [target.x, target.y], "texture": texture}})
	var amount := _order_coin(order_id)
	if amount > 0:
		var centre := orders_anchor(order_id)
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.55, "payload": {
			"from_point": [centre.x, centre.y], "amount": amount,
			"count": clampi(amount / 5, 3, 8), "texture": _ui("coin_big")}})
	# 2026-11-09：体力奖励 —— 和金币同一个方向（正螺旋），落点是顶栏体力条。
	var stamina := _order_energy(order_id)
	if stamina > 0:
		var s_card := _claim_card_rect(order_id)
		var s_from := Vector2(s_card.get_center().x - s_card.size.x * 0.18,
		
				s_card.position.y + s_card.size.y * (1.0 - Layout.GEM_STRIP_RATIO * 0.5))
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.61, "payload": {
			"from_point": [s_from.x, s_from.y], "amount": stamina,
			"count": clampi(int(round(float(stamina) / 10.0)), 3, 10),
			"texture": _ui("energy"), "anchor": "energy", "spin": 1.0}})

	# 2026-11-09：钻石奖励 —— 起点是卡片底部蓝条中心，落点是顶栏钻石条（fly_anim 的 gem 锚点）。
	var gems := _order_gem(order_id)
	if gems > 0:
		var strip := orders_anchor(order_id)
		var card_rect := _claim_card_rect(order_id)
		strip = Vector2(strip.x, card_rect.position.y
				+ card_rect.size.y * (1.0 - Layout.GEM_STRIP_RATIO * 0.5))
		_live_fly.play_event({"type": "coin_spiral", "at": at + 0.67, "payload": {
			"from_point": [strip.x, strip.y], "amount": gems,
			"count": clampi(gems, 1, 5), "texture": _ui("gem"),
			"anchor": "gem", "spin": -1.0}})



## 交付前快照里某个格子的棋子（entity/level）；空格返回 {}。
func _item_at_cell(cell: Vector2i) -> Dictionary:
	var cells = (_snap.get("board", {}) as Dictionary).get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		return {}
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
			continue
		if int((raw as Array)[0]) == cell.x and int((raw as Array)[1]) == cell.y:
			return {"entity": String((raw as Array)[2]), "level": int((raw as Array)[3])}
	return {}


func orders_anchor(order_id: String) -> Vector2:
	if _live_band == null:
		return Vector2(540.0, 320.0)
	var r: Rect2 = _live_band.card_rect(order_id)
	return r.get_center() + _live_band.position


## 订单奖励金币：直接查关卡数据，和 sim 的瞬时到账解耦。
func _order_coin_from_model(order_id: String, level_index: int = -1) -> int:
	if _model == null:
		return 0
	var idx := level_index
	if idx < 0:
		idx = int(_snap.get("level_index", 0))
	var level: Dictionary = _model.level(idx)
	for raw in level.get("orders", []):
		if typeof(raw) == TYPE_DICTIONARY and String((raw as Dictionary).get("id", "")) == order_id:
			return int((raw as Dictionary).get("coin", 0))
	return 0


func _order_coin(order_id: String) -> int:
	for raw in _snap.get("orders", []):
		if typeof(raw) == TYPE_DICTIONARY and String((raw as Dictionary).get("id", "")) == order_id:
			return int((raw as Dictionary).get("coin", 0))
	return 0


## 2026-11-09：订单卡的体力（闪电）奖励数。
func _order_energy(order_id: String) -> int:
	for raw in _snap.get("orders", []):
		if typeof(raw) == TYPE_DICTIONARY and String((raw as Dictionary).get("id", "")) == order_id:
			return int((raw as Dictionary).get("energy", 0))
	return 0


## 2026-11-09：订单卡的钻石奖励数（快照里的 orders[].gem）。
func _order_gem(order_id: String) -> int:
	for raw in _snap.get("orders", []):
		if typeof(raw) == TYPE_DICTIONARY and String((raw as Dictionary).get("id", "")) == order_id:
			return int((raw as Dictionary).get("gem", 0))
	return 0


func _setup_live_fly() -> void:
	_live_fly = FlyAnimScene.new()
	_live_fly.name = "LiveFly"
	add_child(_live_fly)
	_live_fly.set_palette(_colors)
	_live_fly.set_metrics(_metrics)
	_refresh_flight_anchors()


func _setup_live_board() -> void:
	if not is_instance_valid(_model):
		return
	_live_board = BoardScene.instantiate()
	_live_board.name = "LiveBoard"
	_live_board.position = Vector2.ZERO
	add_child(_live_board)
	_live_board.set_chip_icons(_theme_loader, _model.project)
	# 2026-11-09：棋盘也要拿到主题资源，否则拖动白角框（ui_select_frame）取不到贴图。
	_live_board.set_asset_theme(_theme_loader, _model.project)
	_live_board.show_debug_labels = false


func _sync_live_board() -> void:
	if _live_board == null or _snap.is_empty():
		return
	var idx := int(_snap.get("level_index", 0))
	if idx != _board_level:
		_board_level = idx
		var level: Dictionary = _model.level(idx)
		if not level.is_empty():
			_live_board.build_from_level_data(level, _model.project.get("entities", {}), {})
	_live_board.set_clock(_t)
	# 2026-11-10：障碍逐帧同步（解锁 / 盒子换型要立刻显示，否则画面上是空白格）
	var bsnap: Dictionary = (_snap.get("board", {}) as Dictionary)
	_live_board.set_obstacles(bsnap.get("obstacles", []))
	# FlyAnim 的起点/落点全部来自实机几何：每帧刷新，芯片才会从"被点的那个格子"起飞。
	_refresh_flight_anchors()
	# 拖动回放：手拖着棋子走，起点格保留四边选中框（与实机同一套绘制）
	var drag_now: Dictionary = TakeIo.drag_at(_take, _t)
	if drag_now.is_empty():
		_live_board.set_drag_state({})
		_live_board.drag_chip_visible = false
	else:
		# 2026-11-10：拖拽中的棋子**不能**由棋盘画 —— 棋盘在订单带下面，
		# 拖到任务栏上时棋子会被卡片盖住。改成由最上层的 FilmOverlay 画
		# （和实机的 DragGhost 层同一层级语义），棋盘只保留源格的白角框。
		_live_board.drag_chip_visible = false
		_live_board.set_drag_state(drag_now)
	var cells_now = (_snap.get("board", {}) as Dictionary).get("cells", [])
	# 2026-11-10：拖拽中，源格的棋子已经被"拿在手上"，棋盘不该再画它
	# （否则会和上层那枚叠成两枚）。实机同样在拖拽时把源格留空。
	if typeof(cells_now) == TYPE_ARRAY and not drag_now.is_empty():
		var keep: Array = []
		var dfrom = drag_now.get("from", [])
		for row in cells_now:
			if typeof(row) == TYPE_ARRAY and (row as Array).size() >= 2 					and typeof(dfrom) == TYPE_ARRAY and (dfrom as Array).size() >= 2 					and int((row as Array)[0]) == int((dfrom as Array)[0]) 					and int((row as Array)[1]) == int((dfrom as Array)[1]):
				continue
			keep.append(row)
		cells_now = keep
	if typeof(cells_now) == TYPE_ARRAY:
		_live_board.set_chips(cells_now)

	_live_board.apply_state({"selected": [-1, -1],
			"completed": CompletedCells.from_snapshot(_snap)})
	if _live_board.has_method("set_safeboxes") and _evaluator != null and _evaluator.sim != null:
		_live_board.set_safeboxes(_evaluator.sim.safeboxes)
	# 2026-11-10：必须放在**所有** board 状态写入之后 —— set_chips / apply_state 都会把
	# drag_chip_visible 复位成 true，棋盘就会再画一枚拖拽棋子（上层那枚 + 这枚 = 两枚）。
	_live_board.drag_chip_visible = false


func _setup_live_band() -> void:
	_live_band = OrderPanel.new()
	_live_band.name = "LiveOrderBand"
	_live_band.position = Vector2(0.0, 210.0)
	_live_band.size = Vector2(1080.0, 250.0)
	_live_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_band.draw_portraits = true
	_live_band.draw_page_strip = false
	add_child(_live_band)
	_live_band.set_palette(_colors)
	_live_band.set_metrics(_metrics)
	_live_band.set_asset_theme(_theme_loader, _model.project)


## 顶栏也用实机组件，位置/尺寸/字体与实机一致。
func _setup_live_top() -> void:
	_live_top = TopBarScene.new()
	_live_top.name = "LiveTopBar"
	_live_top.position = Vector2.ZERO
	_live_top.size = Vector2(1080.0, 150.0)
	_live_top.font_bold = _font_display_bold
	_live_top.font_fallback = _font_zh
	add_child(_live_top)
	# 2026-11-09：立绘由订单带画，得盖在顶栏药丸**上面**（原来带子在顶栏下面，
	# 放大后的头顶会被金币/钻石药丸吃掉）。带子和顶栏在画面上不重叠，调顺序没有副作用。
	move_child(_live_band, _live_top.get_index() + 1)
	_live_top.set_palette(_colors)
	_live_top.set_metrics(_metrics)
	_live_top.set_asset_theme(_theme_loader, _model.project)


## 交付消耗了哪几格 —— 飞行动画的数量**只认这一份数据**（AGENTS §6.8/§6.9）。
## evaluator.step() 的报告把 sim 的返回字典嵌在 "sim" 键下，顶层只有 ok/code/id/type/
## channel/at；`r.get("taken")` 永远是空数组，于是成片每次都走兜底、只飞一枚，
## 2 行任务的订单也飞不出第二枚（和 §6.7 的 payload 是同一个坑）。
static func claim_taken(report: Dictionary) -> Array:
	var sim_res = report.get("sim", {})
	if typeof(sim_res) != TYPE_DICTIONARY:
		return []
	var taken = (sim_res as Dictionary).get("taken", [])
	if typeof(taken) != TYPE_ARRAY:
		return []
	return taken


## 与实机同一算式：1800 - (秒数 % 1800)。
func _energy_countdown() -> int:
	var elapsed := int(floor(_t)) % 1800
	return 1800 - elapsed


func _push_live_top() -> void:
	if _live_top == null or _snap.is_empty():
		return
	var hud: Dictionary = _snap.get("hud", {})
	var coin_now := int(hud.get("coin", 0))
	if _coin_display < 0.0:
		_coin_display = float(coin_now)
	if not _coin_ticks.is_empty():
		var keep: Array = []
		for row in _coin_ticks:
			if _t >= float((row as Dictionary).get("at", 0.0)):
				_coin_display = minf(_coin_display + float((row as Dictionary).get("amount", 0)),
						float(coin_now))
				_coin_pop_at = _t
			else:
				keep.append(row)
		_coin_ticks = keep
	elif absf(_coin_display - float(coin_now)) > 0.01:
		_coin_display = lerpf(_coin_display, float(coin_now), 0.25)
		if absf(_coin_display - float(coin_now)) < 1.0:
			_coin_display = float(coin_now)
	var pop := 0.0
	var since := _t - _coin_pop_at
	if since >= 0.0 and since < 0.35:
		pop = 0.38 * sin(PI * since / 0.35)
	# 2026-11-09：钻石数字同一套 tick + lerp + 弹跳
	var gem_now := int(hud.get("gem", 0))
	if _gem_display < 0.0:
		_gem_display = float(gem_now)
	if not _gem_ticks.is_empty():
		var gem_keep: Array = []
		for row in _gem_ticks:
			if _t >= float((row as Dictionary).get("at", 0.0)):
				_gem_display = minf(_gem_display + float((row as Dictionary).get("amount", 0)),
						float(gem_now))
				_gem_pop_at = _t
			else:
				gem_keep.append(row)
		_gem_ticks = gem_keep
	elif absf(_gem_display - float(gem_now)) > 0.01:
		_gem_display = lerpf(_gem_display, float(gem_now), 0.25)
		if absf(_gem_display - float(gem_now)) < 0.5:
			_gem_display = float(gem_now)
	var gem_pop := 0.0
	var gem_since := _t - _gem_pop_at
	if gem_since >= 0.0 and gem_since < 0.35:
		gem_pop = 0.38 * sin(PI * gem_since / 0.35)
	# 2026-11-09：体力数字同一套 tick + lerp + 弹跳
	var energy_now := int(hud.get("energy", 0))
	if _energy_display < 0.0:
		_energy_display = float(energy_now)
	if not _energy_ticks.is_empty():
		var energy_keep: Array = []
		for row in _energy_ticks:
			if _t >= float((row as Dictionary).get("at", 0.0)):
				_energy_display = minf(_energy_display + float((row as Dictionary).get("amount", 0)),
						float(energy_now))
				_energy_pop_at = _t
			else:
				energy_keep.append(row)
		_energy_ticks = energy_keep
	elif absf(_energy_display - float(energy_now)) > 0.01:
		_energy_display = lerpf(_energy_display, float(energy_now), 0.25)
		if absf(_energy_display - float(energy_now)) < 0.5:
			_energy_display = float(energy_now)
	var energy_pop := 0.0
	var energy_since := _t - _energy_pop_at
	if energy_since >= 0.0 and energy_since < 0.35:
		energy_pop = 0.38 * sin(PI * energy_since / 0.35)
	_live_top.set_state({
		"level": int(hud.get("level", 1)),
		"energy": int(hud.get("energy", 0)),
		"coin": int(hud.get("coin", 0)),
		"gem": int(hud.get("gem", 0)),
		"clock": _mmss(_energy_countdown()),
		"coin_display": _coin_display,
		"pop": pop,
		"gem_display": _gem_display,
		"gem_pop": gem_pop,
		"energy_display": _energy_display,
		"energy_pop": energy_pop,
	})


## 底栏同样托管实机组件。
## 把实机棋盘的每格中心 + 订单卡中心喂给 FlyAnim（否则它只会退回棋盘中心）。
func _refresh_flight_anchors() -> void:
	if _live_fly == null or _live_board == null or _live_top == null:
		return
	var table := {}
	for y in 9:
		for x in 7:
			table["cell:%d,%d" % [x, y]] = _live_board.cell_rect(x, y).get_center()
	table["hud:coin"] = _hud_coin_anchor()
	table["hud:gem"] = _hud_gem_anchor()
	table["hud:energy"] = _hud_energy_anchor()
	table["order:default"] = Vector2(540.0, 320.0)
	if _live_band != null:
		for card in _live_band.cards:
			if typeof(card) != TYPE_DICTIONARY:
				continue
			var cid := String((card as Dictionary).get("id", ""))
			if cid.is_empty():
				continue
			table["order:" + cid] = _live_band.card_rect(cid).get_center() + _live_band.position
	_live_fly.set_anchors(table)


## 金币螺旋的落点：顶栏组件里那枚金币图标的中心。
## 与实机调**同一个函数**（top_bar.counter_center），成片不许自己猜坐标。
## 2026-11-09 之前这里是写死的 (473.6,49.6)，来自已退役 hud_view 的公式。
## 体力落点同理：问顶栏组件要（与实机同一个函数）。
func _hud_energy_anchor() -> Vector2:
	if _live_top == null:
		return Vector2.ZERO
	return _live_top.counter_center("energy")


## 钻石落点同理：问顶栏组件要（与实机同一个函数）。
func _hud_gem_anchor() -> Vector2:
	if _live_top == null:
		return Vector2.ZERO
	return _live_top.counter_center("gem")


func _hud_coin_anchor() -> Vector2:
	if _live_top == null:
		# 走不到：_refresh_flight_anchors() 已经把 _live_top 判空了。
		return Vector2.ZERO
	return _live_top.counter_center("coin")


## 最上层：手型光标 + toast，必须画在托管进来的实机组件之上。
func _setup_overlay() -> void:
	_overlay = FilmOverlay.new()
	_overlay.name = "FilmOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.position = Vector2.ZERO
	_overlay.size = _page
	_overlay.host = self
	add_child(_overlay)


func _setup_live_bottom() -> void:
	_live_bottom = BottomBarScene.new()
	_live_bottom.name = "LiveBottomBar"
	add_child(_live_bottom)
	_live_bottom.font_bold = _font_display_bold
	_live_bottom.font_regular = _font_display_regular
	_live_bottom.font_num = _font_display_num
	_live_bottom.set_asset_theme(_theme_loader, _model.project)


func _sync_live_band() -> void:
	if _live_band == null or _snap.is_empty():
		return
	var idx := int(_snap.get("level_index", 0))
	if idx != _band_level:
		_band_level = idx
		var level: Dictionary = _model.level(idx)
		if not level.is_empty():
			_live_band.build_from_level(level)
	_sync_live_board()
	if _live_fly != null:
		_live_fly.set_clock(_t)
	_push_live_top()
	_live_band.set_clock(_t)
	_live_band.sync_orders(OrderRows.build(_snap, _model))
	# 2026-11-09：库存状态读快照（take 里的 stockpile_tap 已回放进 sim）。
	var stock = _snap.get("stockpile", {})
	if typeof(stock) == TYPE_DICTIONARY and bool((stock as Dictionary).get("enabled", false)):
		_live_band.set_stockpile(int((stock as Dictionary).get("count", 0)),
				String((stock as Dictionary).get("entity", "")),
				int((stock as Dictionary).get("level", 1)))
	else:
		_live_band.clear_stockpile()


## 成片没有点击回放时，库存展示按第一张未完成订单的低一级（与实机进关规则一致）。
func _stockpile_preview_from_snap() -> Dictionary:
	var orders: Array = _snap.get("orders", [])
	for raw in orders:
		if typeof(raw) != TYPE_DICTIONARY or bool((raw as Dictionary).get("done", false)):
			continue
		var mission = (raw as Dictionary).get("mission", [])
		if typeof(mission) != TYPE_ARRAY:
			continue
		for m in mission:
			if typeof(m) == TYPE_ARRAY and (m as Array).size() >= 2:
				return {"entity": String((m as Array)[0]),
						"level": maxi(int((m as Array)[1]) - 1, 1)}
	return {}


func _draw_band() -> void:
	var height := _metric("band_height", 0.0)
	if height <= 0.0:
		return
	var top := _origin.y + _board_size.y
	var used := minf(height, maxf(0.0, _page.y - top))
	if used <= 0.0:
		return
	draw_rect(Rect2(0.0, _page.y - used, _page.x, used), _palette("band", COLOR_BAND), true)


## §20.6 item 1: main_bg_01_bottom 1080x1536 at (0,384) under main_bg_01_top
## 1080x400 at (0,0). A missing texture keeps the flat page colour + band, which is
## the relocated-copy fallback.
func _draw_background() -> void:
	_draw_ui_stretch("bg_bottom", LAYOUT_BG_BOTTOM)
	_draw_ui_stretch("bg_top", LAYOUT_BG_TOP)


## §20.5 order characters part1 373x370 / part2 373x524. Only the character region of
## each slice is painted (the slices bake in their own order card + counters), scaled
## to end exactly where the order cards start, and painted behind those cards.
func _draw_characters() -> void:
	# 2026-11-06: 每张卡上方各画自己的立绘，几何与实机 OrderPanel 一致，
	# 队列里没有未完成的订单就不画人（part1/part2 兜底彻底下线）。
	var cards := _order_cards(_snap)
	var orders: Array = _snap.get("orders", [])
	var i := 0
	for raw in orders:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if bool((raw as Dictionary).get("done", false)):
			continue
		if i >= cards.size():
			break
		var who := String((raw as Dictionary).get("character", ""))
		var card: Rect2 = cards[i]
		var w := _portrait_width(who)
		# 2026-11-09：与实机同一套 —— 头顶落在卡片上沿往上 PORTRAIT_TOP_ABOVE_CARD
		var rect := Rect2(card.get_center().x - w * 0.5,
				card.position.y - Layout.PORTRAIT_TOP_ABOVE_CARD, w, PORTRAIT_HEIGHT)
		_draw_ui_fit(_portrait_key(who), rect)
		i += 1


func _draw_topbar(snap: Dictionary) -> void:
	var hud: Dictionary = snap.get("hud", {})

	var badge_drawn := _draw_ui_stretch("level_badge_bg", LAYOUT_LEVEL_BADGE_BG)
	badge_drawn = _draw_ui_stretch("level_badge", LAYOUT_LEVEL_BADGE) or badge_drawn
	if not badge_drawn:
		_hud_pill(LAYOUT_LEVEL_BADGE_BG.grow(-6.0), _palette("accent", COLOR_ACCENT),
				Color(0, 0, 0, 0), _hud_radius())
	_text_in(LAYOUT_LEVEL_BADGE, str(int(hud.get("level", 1))), 44, COLOR_WHITE)

	# Energy: countdown icon + mm:ss + bolt + count, one pill (§20.6 item 2).
	var er := LAYOUT_ENERGY
	_hud_pill(er, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	var timer := _ui("energy_timer")
	if timer != null:
		draw_texture_rect(timer, Rect2(er.position + Vector2(10.0, 18.0), Vector2(52.0, 52.0)), false)
	_text_left(Rect2(er.position.x + 70.0, er.position.y + 2.0, 120.0, 34.0),
			_mmss(int(hud.get("energyTickSeconds", 0))), 22, _palette("ink_dim", COLOR_INK_DIM))
	_bolt(Vector2(er.position.x + 76.0, er.position.y + 60.0), 13.0, COLOR_ENERGY)
	_text_left(Rect2(er.position.x + 94.0, er.position.y + 34.0, 110.0, 46.0),
			str(int(hud.get("energy", 0))), HUD_FONT, _palette("ink", COLOR_INK))
	_plus_slot(Rect2(er.position.x + er.size.x - 54.0, er.position.y + 22.0, 44.0, 44.0))

	# Coin / star / gem: a money base plate behind the icon, then the counter.
	_money_pill(LAYOUT_COIN, "coin", int(hud.get("coin", 0)))
	_money_pill(LAYOUT_GEM, "gem", int(hud.get("gem", 0)))
	# The star counter rides under the level badge (the PSD top bar has no fifth
	# pill, but the sim's star value still has to be on screen).
	_hud_pill(LAYOUT_STAR, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), 16)
	_star(Vector2(LAYOUT_STAR.position.x + 22.0, LAYOUT_STAR.get_center().y), 11.0)
	_text_left(Rect2(LAYOUT_STAR.position.x + 40.0, LAYOUT_STAR.position.y, 52.0, LAYOUT_STAR.size.y),
			str(int(hud.get("star", 0))), 20, _palette("ink", COLOR_INK))

	if not _draw_ui_fit("shop", LAYOUT_SHOP):
		_hud_pill(LAYOUT_SHOP, _palette("accent", COLOR_ACCENT), Color(1, 1, 1, 0.55), 30)
		draw_rect(Rect2(LAYOUT_SHOP.position + Vector2(26.0, 34.0),
				Vector2(LAYOUT_SHOP.size.x - 52.0, 46.0)), Color(1, 1, 1, 0.85), true)
		draw_colored_polygon(PackedVector2Array([
			LAYOUT_SHOP.position + Vector2(16.0, 34.0),
			LAYOUT_SHOP.position + Vector2(LAYOUT_SHOP.size.x * 0.5, 12.0),
			LAYOUT_SHOP.position + Vector2(LAYOUT_SHOP.size.x - 16.0, 34.0),
		]), Color(1, 1, 1, 0.85))


## One currency pill: money_bg art behind the icon, the procedural coin/star/gem,
## the counter, and the `plus` art (or a procedural + button).
func _money_pill(r: Rect2, kind: String, value: int) -> void:
	_hud_pill(r, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	var c := Vector2(r.position.x + 44.0, r.get_center().y)
	var base := _ui("money_bg")
	if base != null:
		draw_texture_rect(base, Rect2(r.position + Vector2(8.0, (r.size.y - 66.0) * 0.5),
				Vector2(68.0, 66.0)), false)
	match kind:
		"coin":
			_coin(c, 20.0)
		"star":
			_star(c, 20.0)
		_:
			_gem(c, 18.0)
	_text_left(Rect2(r.position.x + 76.0, r.position.y, maxf(40.0, r.size.x - 146.0), r.size.y),
			str(value), HUD_FONT, _palette("ink", COLOR_INK))
	_plus_slot(Rect2(r.position.x + r.size.x - 50.0, r.position.y + 22.0, 44.0, 44.0))


## §20.6: the plus affordance next to every counter. The PSD's own
## common_main_btn_plussign art when the theme resolves it, a green + disc otherwise.
func _plus_slot(r: Rect2) -> void:
	if _draw_ui_fit("plus", r):
		return
	var c := r.get_center()
	draw_circle(c, r.size.x * 0.42, Color(0.32, 0.72, 0.40, 0.95), true, -1.0, true)
	draw_circle(c, r.size.x * 0.42, Color(1, 1, 1, 0.55), false, 2.0, true)
	draw_line(c + Vector2(-r.size.x * 0.18, 0.0), c + Vector2(r.size.x * 0.18, 0.0),
			COLOR_WHITE, 4.0, true)
	draw_line(c + Vector2(0.0, -r.size.x * 0.18), c + Vector2(0.0, r.size.x * 0.18),
			COLOR_WHITE, 4.0, true)


## §20.5 order cards: the existing card drawing (title, mission rows, check dots,
## character badge) moved onto the 372x190 rects, plus the PSD's `finish` check on
## the done state and a mission pill behind each requirement.
## WYSIWYG order cards: identical geometry to OrderPanel — 286 wide, 124 tall,
## centred in the band, mission icons 96px in the middle, reward pill above the card
## right-aligned with a "+N" label. The film must show exactly what the live screen shows.
const Layout := preload("res://src/view/layout_shared.gd")
const OrderPanel := preload("res://src/view/order_panel.gd")
const OrderRows := preload("res://src/view/order_rows.gd")
const TopBarScene := preload("res://src/view/top_bar.gd")
const BottomBarScene := preload("res://src/view/bottom_bar.gd")
const BoardScene := preload("res://src/view/board_view.tscn")
const FlyAnimScene := preload("res://src/view/fly_anim.gd")
const CARD_H := Layout.CARD_H
const CARD_GAP := Layout.CARD_GAP_X
## 2026-11-06: 队列几何与实机 OrderPanel 对齐（左起点 250 / 卡宽 250 / 间距 18）。
const QUEUE_ORIGIN_X := Layout.QUEUE_ORIGIN_X
const QUEUE_CARD_W := Layout.QUEUE_CARD_W
const PORTRAIT_TOP := 18.0
const PORTRAIT_HEIGHT := Layout.PORTRAIT_H
## 立绘底边压卡片上沿的距离（实机 ORDER_PANEL 的 26px）。
const PORTRAIT_SINK := Layout.PORTRAIT_SINK
const PORTRAIT_CENTER_LEFT := 393.0
const PORTRAIT_CENTER_RIGHT := 800.0
## 2026-11-09: MISSION_ICON / REWARD_ICON 随 _draw_orders 一起删了 —— 成片不再自己画卡片，
## 任务图标与奖励行都由托管的 order_panel 画（AGENTS §8 双画面同步）。


func _portrait_key(character: String) -> String:
	if character == "char_01":
		return "char_blonde"
	if character == "char_02":
		return "char_glasses"
	return "char_" + character.replace("char_", "")


func _portrait_width(character: String) -> float:
	var texture := _ui(_portrait_key(character))
	if texture == null:
		return QUEUE_CARD_W
	return PORTRAIT_HEIGHT * (texture.get_width() / maxf(texture.get_height(), 1.0))


func _portrait_center(character: String) -> float:
	return PORTRAIT_CENTER_LEFT


## Card = as wide as its character, centred under it, bottom-aligned with the portrait.
func _order_cards(snap: Dictionary) -> Array:
	# 2026-11-06：几何只认 layout_shared（页面坐标），成片不再自己算一遍。
	var orders: Array = snap.get("orders", [])
	var out: Array = []
	var index := 0
	for raw in orders:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if bool((raw as Dictionary).get("done", false)):
			continue
		out.append(Layout.card_rect(index))
		index += 1
	return out


## Card rect for one order (fallback: the anchor point as a zero rect).
func _claim_card_rect(order_id: String) -> Rect2:
	var cards := _order_cards(_snap)
	var orders: Array = _snap.get("orders", [])
	for i in range(mini(cards.size(), orders.size())):
		if typeof(orders[i]) == TYPE_DICTIONARY \
				and String((orders[i] as Dictionary).get("id", "")) == order_id:
			return cards[i]
	return Rect2(Vector2(540.0, 300.0), Vector2.ZERO)


## The order's first mission chip art, used by the claim flight.
func _claim_texture(order_id: String) -> Texture2D:
	for raw in _snap.get("orders", []) if _snap is Dictionary else []:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var o: Dictionary = raw
		if String(o.get("id", "")) != order_id:
			continue
		var mission: Array = o.get("mission", [])
		if mission.is_empty() or typeof(mission[0]) != TYPE_ARRAY:
			return null
		var row: Array = mission[0]
		return _chip_texture(String(row[0]), int(row[1]))
	return null


func _draw_claim_flys() -> void:
	_paint_claim_flys(self)


## 交付飞行的芯片要压在订单卡/顶栏之上（实机是最上层），所以由 FilmOverlay 调它。
func _paint_claim_flys(target: CanvasItem) -> void:
	if target == null:
		return
	var now := float(_frame) / float(FPS)
	var alive: Array = []
	for fly in _claim_flys:
		var started := float(fly.get("started", 0.0))
		var dur := 0.55
		var t := (now - started) / dur
		if t >= 1.0:
			continue
		alive.append(fly)
		if t < 0.0:
			continue
		var ease := t * t * (3.0 - 2.0 * t)
		var from: Vector2 = fly.get("from", Vector2.ZERO)
		var to: Vector2 = fly.get("to", Vector2.ZERO)
		var ctrl := (from + to) * 0.5 + Vector2(0.0, -150.0)
		var pos := from.lerp(ctrl, ease).lerp(ctrl.lerp(to, ease), ease)
		var texture = fly.get("texture", null)
		if not (texture is Texture2D):
			continue
		var size: Vector2 = texture.get_size()
		var side: float = lerpf(120.0, 2.5 * 132.0, ease)
		var alpha := 1.0 if t < 0.78 else clampf((1.0 - t) / 0.22, 0.0, 1.0)
		var scale := side / maxf(size.x, 1.0)
		target.draw_set_transform(pos, 0.0, Vector2(scale, scale))
		target.draw_texture_rect(texture, Rect2(-size * 0.5, size), false, Color(1, 1, 1, alpha))
		target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_claim_flys = alive


func _star_icon(c: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * rr)
	draw_colored_polygon(pts, _palette("star", Color("#F2B233")))


func _draw_board(snap: Dictionary) -> void:
	# 2026-11-05 redesign: 单独格子.png as the big base (9-sliced), then 浅色格.png on
	# every other cell. Themes/older takes without those ids keep the M1 frame + full
	# slot_empty grid, so nothing that shipped before changes appearance.
	var plate := _ui("board_plate")
	if plate != null:
		_draw_plate(plate, Rect2(_origin, _board_size), PLATE_CORNER)
	else:
		var frame := _ui("board_frame")
		if frame != null:
			draw_texture_rect(frame, Rect2(_origin, _board_size), false)
		else:
			var panel := Rect2(_origin - Vector2(12.0, 12.0), _board_size + Vector2(24.0, 24.0))
			_hud_pill(panel, _palette("panel", BoardView.COLOR_PANEL),
					_palette("panel_edge", BoardView.COLOR_PANEL_EDGE), _board_radius())
			if _frame_tex != null:
				draw_texture_rect(_frame_tex, Rect2(_origin, _board_size), false)

	var board: Dictionary = snap.get("board", {})
	var width := int(board.get("width", _cols))
	var height := int(board.get("height", _rows))
	var light := _ui("cell_light")
	var cell_tex := _ui("cell")
	for y in range(mini(height, _rows)):
		for x in range(mini(width, _cols)):
			if light != null:
				if (x + y) % 2 == 0:
					draw_texture_rect(light, _inner_cell_rect(_slot_rect(x, y).grow(-float(_cell_gap) * 0.5)), false)
			else:
				_cell_rect(x, y, cell_tex)

	# 所见即所得: the same order-mission rule the live board uses paints the green
	# cell here. Derived from the snapshot only, so the frame stays deterministic.
	var completed: Array = CompletedCells.from_snapshot(snap)
	for cell in completed:
		if typeof(cell) != TYPE_ARRAY or (cell as Array).size() < 2:
			continue
		var pos := Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))
		_rounded(_slot_rect(pos.x, pos.y).grow(-float(_cell_gap)), 18, BoardView.COLOR_COMPLETE)

	# metrics.tint_alpha washes the board base in palette.board_tint; at the default
	# 0.0 nothing is painted, so the default film keeps its flat board.
	var tint := _metric("tint_alpha", 0.0)
	if tint > 0.0:
		var tint_color: Color = _palette("board_tint", COLOR_WHITE)
		draw_rect(Rect2(_origin, _board_size), Color(tint_color.r, tint_color.g, tint_color.b, tint), true)

	var cells: Array = board.get("cells", [])
	var flying_to: Array = []
	for fly in _flys:
		var to_raw = (fly.get("spawn", {}) as Dictionary).get("to", [])
		if typeof(to_raw) == TYPE_ARRAY and (to_raw as Array).size() >= 2:
			flying_to.append(Vector2i(int((to_raw as Array)[0]), int((to_raw as Array)[1])))
	var now := float(_frame) / float(FPS)
	var alive: Array = []
	for fly in _flys:
		if FlyPath.progress(float(fly.get("started", 0.0)), now) < 1.0:
			alive.append(fly)
	_flys = alive
	for raw in cells:
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 4:
			var item_pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
			if flying_to.has(item_pos):
				continue
			_draw_item_pulsed(item_pos, String((raw as Array)[2]), int((raw as Array)[3]))

	var obstacles: Array = board.get("obstacles", [])
	for raw in obstacles:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
			continue
		var pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
		for kind in (raw as Array)[2]:
			_draw_obstacle(pos, String(kind))

	_draw_safeboxes(int(snap.get("level_index", 0)))

	for fly in _flys:
		_draw_fly(fly)

	for cell in completed:
		if typeof(cell) != TYPE_ARRAY or (cell as Array).size() < 2:
			continue
		_draw_finish_badge(Vector2i(int((cell as Array)[0]), int((cell as Array)[1])))


## §20.5 bottom band: the items bar texture at (193,1731) 693x183, the exit button
## bottom-left, the bag bottom-right. 2026-11-05: the white "LEVEL n / level_id"
## plate was removed by request; the band is the texture alone until a text-free
## items.png exists.
func _draw_bottom_bar(snap: Dictionary) -> void:
	# Layer 1: 任务背景板 9-sliced to the whole bar; Layer 2: 提醒 icon; Layer 3: the
	# 奖励金币 button. Labels are drawn on top with the project display fonts.
	var bar := _ui("bar_board")
	if bar != null:
		_draw_plate(bar, LAYOUT_ITEMS, 28.0)
	elif not _draw_ui_stretch("items", LAYOUT_ITEMS):
		_hud_pill(LAYOUT_ITEMS, _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), _card_radius())

	# coin first: the rule below stops BAR_LINE_GAP short of it.
	var coin_size := 124.0
	var coin_rect := Rect2(
			LAYOUT_ITEMS.position.x + LAYOUT_ITEMS.size.x - 24.0 - coin_size,
			LAYOUT_ITEMS.position.y + BAR_COIN_OFFSET_Y,
			coin_size, coin_size)
	# ① ⓘ 上移：顶部与标题同高（原 y+62 偏下）。
	_draw_ui_fit("reminder", Rect2(LAYOUT_ITEMS.position + BAR_ICON_OFFSET, BAR_ICON_SIZE))
	# ② label1（标题）。
	_text_left_font(_font_display_bold,
			Rect2(LAYOUT_ITEMS.position + BAR_TITLE_OFFSET, BAR_TITLE_SIZE),
			BAR_TITLE, 38, Color("#2E4157"))
	# ③ 两段之间的分隔线：common_line（10×4 纯白）横向拉伸并调制到参考图取样色
	# #C4D7E2；主题没给线时退回同色实心矩形，任何主题都有分隔。
	var line_left: float = LAYOUT_ITEMS.position.x + BAR_TITLE_OFFSET.x
	var line_rect := Rect2(line_left, LAYOUT_ITEMS.position.y + BAR_LINE_OFFSET_Y,
			maxf(coin_rect.position.x - BAR_LINE_GAP - line_left, 0.0), BAR_LINE_H)
	if not _draw_ui_tint("line", line_rect, BAR_LINE_COLOR):
		draw_rect(line_rect, BAR_LINE_COLOR, true)
	# ④ label2 左移：退到 ⓘ 下方左缘（参考图里副标题比标题更靠左）。
	_text_left_font(_font_display_regular,
			Rect2(LAYOUT_ITEMS.position + BAR_SUB_OFFSET, BAR_SUB_SIZE),
			BAR_SUBTITLE, 28, Color("#4B6076"))
	# ⑤ 金币按钮整体下移，上方腾出 "Buy" 标题位。
	_draw_ui_fit("coin_reward", coin_rect)
	_text_center_font(_font_display_num,
			Rect2(coin_rect.position.x, LAYOUT_ITEMS.position.y + BAR_BUY_OFFSET_Y,
					coin_rect.size.x, BAR_BUY_SIZE_Y),
			BAR_BUY, 30, BAR_BUY_COLOR)
	# Third label: the reward count sits in the plain green strip under the paw
	# coin (the coin art itself ends around y+78 of the 124 px button), so it never
	# paints over the icon. White with a dark-green outline reads on the button's
	# light green and survives a re-skin that recolours the plate.
	_text_center_font(_font_display_num,
			Rect2(coin_rect.position.x, coin_rect.position.y + 76.0,
					coin_rect.size.x, 40.0),
			str(BAR_COIN_REWARD), 36, Color(1.0, 1.0, 1.0, 1.0), Color("#2F6B1E"))
	if not _draw_ui_fit("exit", LAYOUT_EXIT):
		_hud_pill(LAYOUT_EXIT.grow(-8.0), _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), _card_radius())
		var c := LAYOUT_EXIT.get_center()
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-26.0, 0.0), c + Vector2(2.0, -28.0), c + Vector2(2.0, -12.0),
			c + Vector2(28.0, -12.0), c + Vector2(28.0, 12.0), c + Vector2(2.0, 12.0),
			c + Vector2(2.0, 28.0),
		]), _palette("ink", COLOR_INK))
	if not _draw_ui_fit("bag", LAYOUT_BAG.grow(BAG_GROW)):
		_hud_pill(LAYOUT_BAG.grow(-6.0), _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), 18)
		draw_rect(Rect2(LAYOUT_BAG.position + Vector2(22.0, 24.0),
				Vector2(LAYOUT_BAG.size.x - 44.0, LAYOUT_BAG.size.y - 48.0)),
				_palette("ink_dim", COLOR_INK_DIM), false, 4.0)


## Clamp a light-cell rect to the plate's inner area (border 8px + corner curve).
## Interior cells are untouched; only the outer ring shrinks, so the checkerboard
## never paints over the border.
func _inner_cell_rect(r: Rect2) -> Rect2:
	var inner := Rect2(_origin + Vector2(PLATE_PAD, PLATE_PAD),
			_board_size - Vector2(PLATE_PAD * 2.0, PLATE_PAD * 2.0))
	var left := maxf(r.position.x, inner.position.x)
	var top := maxf(r.position.y, inner.position.y)
	var right := minf(r.end.x, inner.end.x)
	var bottom := minf(r.end.y, inner.end.y)
	return Rect2(left, top, maxf(right - left, 0.0), maxf(bottom - top, 0.0))


func _cell_rect(x: int, y: int, cell_tex: Texture2D = null) -> void:
	var r: Rect2 = _slot_rect(x, y).grow(-float(_cell_gap) * 0.5)
	if cell_tex != null:
		draw_texture_rect(cell_tex, r, false)
		return
	var cell: Color = _palette("cell", BoardView.COLOR_CELL)
	_rounded(r, 14, cell)
	# cell_lip is not a palette key of its own: derive it from the theme cell so a
	# re-skin moves the lip with the tile instead of leaving a stale blue line.
	var lip: Color = _palette("cell_lip", cell.lightened(0.12))
	_rounded(Rect2(r.position + Vector2(3.0, 3.0), Vector2(r.size.x - 6.0, 5.0)), 3, lip)


## Merge pop: the result chip is drawn scaled around its cell centre for 0.4 s.
func _draw_item_pulsed(pos: Vector2i, entity_id: String, level: int) -> void:
	if _pulse.is_empty() or Vector2i(_pulse.get("cell", Vector2i(-1, -1))) != pos:
		_draw_item(pos, entity_id, level)
		return
	var started := float(_pulse.get("started", 0.0))
	var now := float(_frame) / float(FPS)
	if now - started >= Pulse.MERGE_DURATION:
		_pulse = {}
		_draw_item(pos, entity_id, level)
		return
	var scale := Pulse.merge_scale(started, now)
	var rect: Rect2 = _slot_rect(pos.x, pos.y)
	var local: Rect2 = Rect2(-rect.size * 0.5, rect.size).grow(-6.0)
	draw_set_transform(rect.get_center(), 0.0, Vector2(scale, scale))
	var ent: Dictionary = _model.entity(entity_id)
	if String(ent.get("kind", "chip")) == "chip":
		_draw_chip(local, entity_id, level)
	else:
		_draw_item(pos, entity_id, level)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_item(pos: Vector2i, entity_id: String, level: int) -> void:
	var r: Rect2 = _slot_rect(pos.x, pos.y).grow(-6.0)
	var ent: Dictionary = _model.entity(entity_id)
	var kind := String(ent.get("kind", "chip"))
	match kind:
		"generator":
			_draw_generator(r, entity_id, level)
		"special":
			_rounded(r, 14, BoardView.COLOR_SPECIAL)
			_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 30.0)), 10, Color(1, 1, 1, 0.22))
			_text_in(r, _short_label(entity_id), INK_FONT, _palette("ink", COLOR_INK))
		_:
			_draw_chip(r, entity_id, level)


func _draw_chip(r: Rect2, entity_id: String, level: int) -> void:
	var texture := _chip_texture(entity_id, level)
	if texture != null:
		_draw_chip_texture(r, texture)
		return
	var hue := _hue(entity_id)
	_rounded(r, 18, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 34.0)), 12, Color(1, 1, 1, 0.18))
	_text_in(Rect2(r.position, Vector2(r.size.x, r.size.y - 18.0)), _short_label(entity_id), CHIP_FONT, COLOR_WHITE)


## Same fit=scale placement as the live board, so a frame of the film and a board
## screenshot of the same chip are pixel-comparable: keep the source aspect, scale
## to fit the chip rect, centre it.
func _draw_chip_texture(r: Rect2, texture: Texture2D) -> void:
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale := minf(r.size.x / source.x, r.size.y / source.y)
	var drawn := source * scale
	draw_texture_rect(texture, Rect2(r.position + (r.size - drawn) * 0.5, drawn), false)


## The loader resolves theme > project > default and caches per "entity@level",
## so a 1800-frame take reads each PNG once. Null keeps the procedural chip.
func _chip_texture(entity_id: String, level: int) -> Texture2D:
	if _theme_loader == null or _model == null:
		return null
	var texture = _theme_loader.chip_texture(entity_id, level, _model.project)
	return texture if texture is Texture2D else null


func _draw_generator(r: Rect2, entity_id: String, level: int) -> void:
	var icon := _ui("generator")
	if icon != null:
		_draw_chip_texture(r, icon)
		_draw_stamina_badge(r)
		return
	var hue := _hue(entity_id)
	_rounded(r, 10, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 30.0)), 8, Color(1, 1, 1, 0.16))
	var c := r.get_center() + Vector2(0.0, -14.0)
	var bolt := PackedVector2Array([
		c + Vector2(-11.0, -32.0), c + Vector2(16.0, -32.0), c + Vector2(3.0, -4.0),
		c + Vector2(16.0, -4.0), c + Vector2(-6.0, 34.0), c + Vector2(1.0, 3.0),
		c + Vector2(-16.0, 3.0),
	])
	draw_colored_polygon(bolt, Color(1.0, 0.94, 0.55, 0.95))
	draw_polyline(_closed(bolt), Color(1.0, 0.86, 0.28, 0.9), 2.0, true)
	_draw_stamina_badge(r)


## Same bottom-left 体力 badge as the live board.
func _draw_stamina_badge(r: Rect2) -> void:
	var stamina := _ui("stamina")
	if stamina == null:
		return
	var source := stamina.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var size := Vector2(26.0, 26.0 * source.y / source.x)
	var inner := _inner_cell_rect(r)
	draw_texture_rect(stamina, Rect2(inner.end.x - size.x - 2.0, inner.end.y - size.y - 2.0, size.x, size.y), false)


## Generator -> slot flight, one draw per active spawn.
func _draw_fly(fly: Dictionary) -> void:
	var t := FlyPath.progress(float(fly.get("started", 0.0)), float(_frame) / float(FPS))
	if t >= 1.0:
		return
	var spawn: Dictionary = fly.get("spawn", {})
	var from = spawn.get("from", [])
	var to = spawn.get("to", [])
	if typeof(from) != TYPE_ARRAY or typeof(to) != TYPE_ARRAY:
		return
	var a := Vector2i(int((from as Array)[0]), int((from as Array)[1]))
	var b := Vector2i(int((to as Array)[0]), int((to as Array)[1]))
	var at := FlyPath.point(_slot_rect(a.x, a.y).get_center(), _slot_rect(b.x, b.y).get_center(), t)
	var base: Rect2 = _slot_rect(b.x, b.y).grow(-float(_cell_gap) * 0.5)
	var half := base.size * 0.5
	var texture := _chip_texture(String(spawn.get("entity", "")), int(spawn.get("level", 1)))
	if texture == null:
		return
	draw_set_transform(at, 0.0, Vector2.ONE)
	_draw_chip_texture(Rect2(-half, base.size), texture)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_obstacle(pos: Vector2i, kind: String) -> void:
	var r: Rect2 = _slot_rect(pos.x, pos.y).grow(-float(_cell_gap) * 0.5)
	# §20.6 item 9: the PSD obstacle art when the theme resolves it, the procedural
	# art otherwise. An ice cell freezes a deterministic chip and shows its level
	# through the project display font (the old hard-coded timer is gone).
	match kind:
		"safe":
			return  # one multi-cell group is drawn by _draw_safeboxes()
		"bag":
			# 2026-11-05: the little "?" bag obstacle, same art as the live board.
			if _draw_ui_fit("safe_unknown", r):
				return
			if _draw_ui_fit("bubble", r):
				return
		"lock":
			if _draw_ui_fit("lock", r):
				return
			_rounded(r, 14, Color(0.05, 0.09, 0.15, 0.55))
			var c := r.get_center()
			var metal := Color(0.91, 0.94, 0.97)
			draw_arc(c + Vector2(0.0, -6.0), 17.0, PI, TAU, 28, metal, 7.0, true)
			_rounded(Rect2(c + Vector2(-26.0, -4.0), Vector2(52.0, 40.0)), 7, metal)
			draw_circle(c + Vector2(0.0, 10.0), 5.5, Color(0.16, 0.22, 0.30), true, -1.0, true)
		"web":
			var webbed: Dictionary = IceCell.chip(_model.project if _model != null else {}, pos)
			if not webbed.is_empty():
				var web_tex := _chip_texture(String(webbed["entity"]), int(webbed["level"]))
				if web_tex != null:
					_draw_chip_texture(r, web_tex)
			if _draw_ui_fit("web", r):
				return
			var c := r.get_center()
			var white := Color(1.0, 1.0, 1.0, 0.70)
			for i in range(8):
				var a := TAU * float(i) / 8.0
				var dir := Vector2(cos(a), sin(a))
				draw_line(c + dir * 8.0, c + dir * 62.0, white, 3.0, true)
			for ring in [22.0, 40.0, 58.0]:
				var pts := PackedVector2Array()
				for i in range(9):
					var a0 := TAU * float(i) / 8.0
					pts.append(c + Vector2(cos(a0), sin(a0)) * float(ring))
					if i < 8:
						var am := a0 + TAU / 16.0
						pts.append(c + Vector2(cos(am), sin(am)) * float(ring) * 0.86)
				draw_polyline(pts, white, 2.5, true)
		"bag":
			if _draw_ui_fit("safe_unknown", r):
				return
			if _draw_ui_fit("bubble", r):
				return
		"bubble":
			if _draw_ui_fit("bubble", r):
				return
			var c2 := r.get_center()
			draw_circle(c2, 56.0, Color(0.72, 0.86, 1.0, 0.32), true, -1.0, true)
			draw_circle(c2, 56.0, Color(1.0, 1.0, 1.0, 0.85), false, 6.0, true)
			draw_circle(c2 + Vector2(-21.0, -21.0), 13.0, Color(1.0, 1.0, 1.0, 0.75), true, -1.0, true)
		"ice":
			var inner := r.grow(-4.0)
			var frozen: Dictionary = IceCell.chip(_model.project if _model != null else {}, pos)
			if not frozen.is_empty():
				var chip_tex := _chip_texture(String(frozen["entity"]), int(frozen["level"]))
				if chip_tex != null:
					_draw_chip_texture(r, chip_tex)
			if not _draw_ui_fit("ice", r):
				_rounded(inner, 14, Color(1.0, 1.0, 1.0, 0.35))
				_rounded_outline(inner, 14, Color(1.0, 1.0, 1.0, 0.80), 3)
			_draw_ice_label(pos, inner, frozen)
		_:
			_rounded(r, 14, Color(0.0, 0.0, 0.0, 0.25))


## Same label as the live board: frozen chip level in 江城圆体 700W with a dark edge.
func _draw_ice_label(cell: Vector2i, r: Rect2, frozen: Dictionary) -> void:
	if frozen.is_empty():
		return
	if _font_display_bold == null:
		return
	var left := IceCell.remaining_seconds(cell, float(_frame) / float(FPS))
	var text := IceCell.format_clock(left)
	var baseline := Vector2(r.position.x, r.end.y - 8.0)
	for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
		draw_string(_font_display_bold, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER,
				r.size.x, 26, Color(0.12, 0.20, 0.30, 0.85))
	draw_string(_font_display_bold, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26,
			Color(1, 1, 1, 1))


# --------------------------------------------------------------- view events

func _draw_view_layer() -> void:
	if _evaluator == null:
		return
	var sel := Vector2i(-1, -1)
	var hl := Vector2i(-1, -1)
	for ev in _evaluator.events:
		var at := float(ev.get("at", 0.0))
		if at > _t + 1e-6:
			continue
		var dur := float(ev.get("duration", 0.0))
		var active := dur > 0.0 and _t <= at + dur + 1e-6
		var type := String(ev.get("type", ""))
		var payload: Dictionary = ev.get("payload", {}) if typeof(ev.get("payload", {})) == TYPE_DICTIONARY else {}
		var p := 0.0
		if dur > 0.0:
			p = clampf((_t - at) / dur, 0.0, 1.0)
		match type:
			"select":
				sel = _payload_slot(payload)
			"highlight":
				if active:
					hl = _payload_slot(payload)
			"text":
				if active:
					_banner(_locale(String(payload.get("text_key", ""))), LAYOUT_TEXT, 40, p)
			"hint":
				if active:
					_banner(_locale(String(payload.get("text_key", ""))), LAYOUT_HINT, 28, p)
			"levelup":
				if active:
					_banner("LEVEL UP", LAYOUT_LEVELUP, 46, p)
			"cta":
				if active:
					_draw_cta(_locale(String(payload.get("text_key", ""))), p)
			"coin_popup":
				if active:
					_popup("+%d" % int(payload.get("coin", 5)),
							Vector2(LAYOUT_COIN.get_center().x, 150.0 - 54.0 * p), 1.0 - p * 0.7)
			"star_fly":
				if active:
					# The star starts just above the board (never on top of it) and
					# lands on the top bar's star counter.
					var from := Vector2(_origin.x + _board_size.x * 0.5, _origin.y - 16.0)
					var to := LAYOUT_STAR.get_center()
					var pos2 := from.lerp(to, p)
					_star(pos2, 22.0 * (1.0 - 0.4 * p))
			"transition":
				if active:
					draw_rect(Rect2(Vector2.ZERO, _page), Color(0.06, 0.09, 0.13, 0.55 * (1.0 - p)), true)
	if sel.x >= 0:
		_selection_ring(sel, Color(0.35, 0.84, 0.42))
	if hl.x >= 0:
		_selection_ring(hl, _palette("star", COLOR_STAR))


func _payload_slot(payload: Dictionary) -> Vector2i:
	var raw = payload.get("slot", payload.get("target", null))
	if typeof(raw) == TYPE_DICTIONARY:
		raw = (raw as Dictionary).get("slot", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))


func _selection_ring(pos: Vector2i, color: Color) -> void:
	if pos.x < 0:
		return
	# §20.6 item 7: the themed select frame sits centred on the cell; the procedural
	# glow + white corner brackets are the fallback.
	var cell: Rect2 = _slot_rect(pos.x, pos.y)
	var select_tex := _ui("select")
	if select_tex != null:
		var frame_size := select_tex.get_size()
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			draw_texture_rect(select_tex,
					Rect2(cell.get_center() - frame_size * 0.5, frame_size), false)
			return
	var r := cell.grow(-float(_cell_gap) * 0.5)
	_rounded_outline(r.grow(6.0), 20, Color(color.r, color.g, color.b, 0.22), 8)
	_rounded_outline(r.grow(2.0), 18, Color(color.r, color.g, color.b, 0.55), 4)
	var arm := 26.0
	var w := 6.0
	var white := Color(1.0, 1.0, 1.0, 0.98)
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
		draw_polyline(corner, white, w, true)


func _banner(text: String, r: Rect2, size: int, progress: float) -> void:
	if text.is_empty():
		return
	var a := 1.0
	if progress < 0.12:
		a = progress / 0.12
	elif progress > 0.9:
		a = (1.0 - progress) / 0.1
	a = clampf(a, 0.0, 1.0)
	# The strip takes the theme ink (a dark capsule in both themes) and the label
	# takes the theme banner colour, so a re-skin moves the banner without dropping
	# the contrast that a light label needs.
	var ink: Color = _palette("ink", COLOR_INK)
	var label: Color = _palette("banner", COLOR_WHITE)
	_rounded(r, 26, Color(ink.r, ink.g, ink.b, 0.78 * a))
	_rounded_outline(r, 26, Color(label.r, label.g, label.b, 0.42 * a), 3)
	_text_in(r, text, size, Color(label.r, label.g, label.b, a))


func _draw_cta(text: String, progress: float) -> void:
	# §20.5: the CTA takes over the bottom items bar band, never the board.
	var r := LAYOUT_CTA
	var a := clampf(progress / 0.15, 0.0, 1.0)
	var accent: Color = _palette("accent", COLOR_CTA)
	_rounded(r, 34, Color(accent.r, accent.g, accent.b, a))
	_rounded_outline(r, 34, Color(1.0, 1.0, 1.0, 0.55 * a), 4)
	_text_in(r, "PLAY NOW" if text.is_empty() else text, 48, Color(1.0, 1.0, 1.0, a))


func _popup(text: String, pos: Vector2, alpha: float) -> void:
	var f := _font_en if _font_en != null else _font_zh
	if f == null:
		return
	var size := 40
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := Rect2(pos - Vector2(w * 0.5 + 18.0, 30.0), Vector2(w + 36.0, 60.0))
	_rounded(r, 22, Color(0.08, 0.12, 0.18, 0.55 * alpha))
	var coin: Color = _palette("coin", COLOR_COIN)
	_text_in(r, text, size, Color(coin.r, coin.g, coin.b, alpha))


# ------------------------------------------------------------------- prompt bar

## §7 item 4 in the delivered film. The prompt window is counted from the sim
## clock that produced it, never from wall time, so two takes stay identical.
func _prompt_board_full(at: float) -> void:
	var text := _locale("board.full")
	if text.is_empty():
		text = "Board full"
	_toast_text = text
	_toast_at = at


func _toast_alpha() -> float:
	if _toast_text.is_empty():
		return 0.0
	var age := _t - _toast_at
	if age < 0.0 or age >= TOAST_SECONDS:
		return 0.0
	var remaining := TOAST_SECONDS - age
	if remaining < TOAST_FADE:
		return clampf(remaining / TOAST_FADE, 0.0, 1.0)
	return 1.0


func _draw_toast() -> void:
	var alpha := _toast_alpha()
	if alpha <= 0.0:
		return
	var bar := TOAST_RECT
	_rounded(bar, 24, Color(TOAST_COLOR.r, TOAST_COLOR.g, TOAST_COLOR.b, TOAST_COLOR.a * alpha))
	_rounded_outline(bar, 24, Color(1.0, 1.0, 1.0, 0.55 * alpha), 2)
	_text_in(bar, _toast_text, INK_FONT, Color(1.0, 1.0, 1.0, alpha))


# ------------------------------------------------------------------ theme lookup

func _palette(key: String, fallback: Color) -> Color:
	var value = _colors.get(key, null)
	if value is Color:
		return value
	return fallback


func _metric(key: String, fallback: float) -> float:
	var value = _metrics.get(key, null)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


func _card_radius() -> int:
	return int(round(_metric("card_radius", 22.0)))


func _hud_radius() -> int:
	return int(round(_metric("hud_radius", 26.0)))


func _board_radius() -> int:
	return int(round(_metric("board_radius", 28.0)))


# ---------------------------------------------------------------- primitives

func _hud_pill(r: Rect2, fill: Color, edge: Color = Color(0, 0, 0, 0), radius: int = -1) -> void:
	var used := radius if radius >= 0 else int(minf(42.0, r.size.y * 0.5))
	used = int(clampf(float(used), 0.0, minf(r.size.x, r.size.y) * 0.5))
	_rounded(r, used, fill)
	if edge.a > 0.0:
		_rounded_outline(r, used, edge, 3)


func _rounded(r: Rect2, radius: int, color: Color) -> void:
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var key := "f|%d|%d|%s" % [radius, int(color.a * 255.0), color.to_html(false)]
	var sb: StyleBoxFlat = _sb_cache.get(key, null)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.corner_radius_top_left = radius
		sb.corner_radius_top_right = radius
		sb.corner_radius_bottom_left = radius
		sb.corner_radius_bottom_right = radius
		sb.anti_aliasing = true
		_sb_cache[key] = sb
	draw_style_box(sb, r)


func _rounded_outline(r: Rect2, radius: int, color: Color, width: int) -> void:
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var key := "o|%d|%d|%d|%s" % [radius, width, int(color.a * 255.0), color.to_html(false)]
	var sb: StyleBoxFlat = _sb_cache.get(key, null)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.draw_center = false
		sb.border_color = color
		sb.border_width_left = width
		sb.border_width_top = width
		sb.border_width_right = width
		sb.border_width_bottom = width
		sb.corner_radius_top_left = radius
		sb.corner_radius_top_right = radius
		sb.corner_radius_bottom_left = radius
		sb.corner_radius_bottom_right = radius
		sb.anti_aliasing = true
		_sb_cache[key] = sb
	draw_style_box(sb, r)


func _text_in(r: Rect2, text: String, size: int, color: Color) -> void:
	var f := _pick_font(text)
	if f == null:
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + float(size) * 0.36)
	draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_left_font(f: Font, r: Rect2, text: String, size: int, color: Color) -> void:
	if f == null or text.is_empty():
		return
	var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size) * 0.36)
	draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_left(r: Rect2, text: String, size: int, color: Color) -> void:
	var f := _pick_font(text)
	if f == null:
		return
	var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size) * 0.36)
	draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Centred label with an optional outline, for text drawn on top of art: the reward
## number on the green coin button has to stay readable whatever the plate colour is,
## so it gets a 1-pass outline of its own (outline_color.a == 0 skips that pass).
func _text_center_font(f: Font, r: Rect2, text: String, size: int, color: Color,
		outline_color: Color = Color(0, 0, 0, 0)) -> void:
	if f == null or text.is_empty():
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + float(size) * 0.36)
	if outline_color.a > 0.0:
		draw_string_outline(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				int(maxf(2.0, float(size) * 0.16)), outline_color)
	draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_right(r: Rect2, text: String, size: int, color: Color) -> void:
	var f := _pick_font(text)
	if f == null:
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := r.position + Vector2(r.size.x - w, r.size.y * 0.5 + float(size) * 0.36)
	draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Latin labels always use the English font so digits never fall back to tofu if
## the CJK font ships without Latin glyphs.
func _pick_font(text: String) -> Font:
	for i in range(text.length()):
		if text.unicode_at(i) > 127:
			return _font_zh if _font_zh != null else _font_en
	return _font_en if _font_en != null else _font_zh


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out


func _bolt(c: Vector2, s: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-0.35, -1.0) * s, c + Vector2(0.45, -1.0) * s, c + Vector2(0.05, -0.15) * s,
		c + Vector2(0.5, -0.15) * s, c + Vector2(-0.25, 1.0) * s, c + Vector2(0.0, 0.12) * s,
		c + Vector2(-0.5, 0.12) * s,
	])
	draw_colored_polygon(pts, color)


func _coin(c: Vector2, r: float) -> void:
	draw_circle(c, r, _palette("coin", COLOR_COIN), true, -1.0, true)
	draw_circle(c, r, Color(0.72, 0.50, 0.12), false, 3.0, true)
	draw_circle(c, r * 0.45, Color(0.94, 0.79, 0.42), true, -1.0, true)


func _star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + float(i) * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.46
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, _palette("star", COLOR_STAR))


func _gem(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.0, -r), c + Vector2(r, -r * 0.15), c + Vector2(0.0, r), c + Vector2(-r, -r * 0.15),
	])
	draw_colored_polygon(pts, _palette("gem", COLOR_GEM))
	draw_polyline(_closed(pts), Color(1.0, 1.0, 1.0, 0.5), 2.0, true)


func _check_dot(c: Vector2, done: bool) -> void:
	if done:
		draw_circle(c, 18.0, _palette("done", COLOR_DONE), true, -1.0, true)
		var mark := PackedVector2Array([c + Vector2(-8.0, 0.0), c + Vector2(-2.0, 7.0), c + Vector2(9.0, -7.0)])
		draw_polyline(mark, COLOR_WHITE, 5.0, true)
	else:
		draw_circle(c, 16.0, Color(1, 1, 1, 0.55), false, 3.0, true)


func _character_badge(r: Rect2, who: String, done: bool) -> void:
	# Small portrait chip in the card's top-right corner: the character's skin tone
	# plus the first glyphs of its display name. (The full character art sits behind
	# the card, so this chip only has to carry the name.)
	_rounded(r, 18, Color("#B8E39A") if done else Color("#F2C6A0"))
	_rounded(Rect2(r.position + Vector2(6.0, 6.0), Vector2(r.size.x - 12.0, r.size.y * 0.36)), 12,
			Color("#3A2A22"))
	_text_in(Rect2(r.position.x, r.position.y + r.size.y * 0.34, r.size.x, r.size.y * 0.66),
			who.substr(0, 2), 22, _palette("ink", COLOR_INK))


func _short_label(entity_id: String) -> String:
	var ent: Dictionary = _model.entity(entity_id)
	var family := String(ent.get("family", ""))
	var chain := String(ent.get("chain", ""))
	# Two characters max: a 140 px cell (128 px chip) holds two glyphs at 36 pt,
	# not a family name. "Clean/Ca" becomes "Ca" so nothing ever clips.
	if not family.is_empty():
		return family.substr(0, 1) + chain.substr(0, 1)
	var cut := entity_id.find("_")
	var base := entity_id.substr(0, cut) if cut > 0 else entity_id
	return base.substr(0, 4)


func _hue(entity_id: String) -> Color:
	if _hue_cache.has(entity_id):
		return _hue_cache[entity_id]
	var palette := [
		Color("#5B8DEF"), Color("#8B5CF6"), Color("#F59E0B"),
		Color("#10B981"), Color("#EF4444"), Color("#06B6D4"),
	]
	var h := absi(entity_id.hash())
	var c: Color = palette[h % palette.size()]
	_hue_cache[entity_id] = c
	return c


func _locale(key: String) -> String:
	if key.is_empty():
		return ""
	var locales = _model.project.get("locales", {})
	if typeof(locales) != TYPE_DICTIONARY:
		return key
	var loc := "zh"
	var meta = _model.project.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY:
		loc = String((meta as Dictionary).get("locale", "zh"))
	var table = (locales as Dictionary).get(loc, {})
	if typeof(table) != TYPE_DICTIONARY:
		return key
	var val = (table as Dictionary).get(key, "")
	if typeof(val) != TYPE_STRING:
		return key
	return String(val)


## 最上层绘制层：手型光标等"必须在所有托管组件之上"的东西。
class FilmOverlay extends Control:
	var host = null

	func _draw() -> void:
		if host == null:
			return
		host._paint_drag(self)
		host._paint_cursor(self)
