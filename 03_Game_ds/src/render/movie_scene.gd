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

const FPS := 60
const MANIFEST_INDEX := "res://data/manifest_index.json"
const DEFAULT_PROJECT := "res://data/sample_project.json"
const OUT_DIR := "res://output"
const OUT_MANIFEST := "res://output/render_manifest.json"
const FONT_ZH := "res://assets/fonts/font_zh.otf"
const FONT_EN := "res://assets/fonts/font_en.ttf"
const FRAME_ID := "board_frame"
const FRAME_TEXTURE := "res://assets/ui/board_frame.png"
## Free-mode cursor overlay: same 64x64 CC0 hand the live window uses, same hotspot.
## The film only draws it when the take carries a cursor track (`--take=<file>`).
const CURSOR_ID := "ui_cursor_hand"
const CURSOR_TEXTURE := "res://assets/ui/cursor_hand.png"
const CURSOR_HOTSPOT := Vector2(10.0, 8.0)
const CURSOR_SIZE := 64.0

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
	"bg_bottom", "bg_top", "board_frame", "cell", "select", "level_badge",
	"level_badge_bg", "energy_timer", "money_bg", "finish", "ice", "bubble",
	"lock", "web", "exit", "bag", "items", "part1", "part2", "plus", "shop",
]

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
var _guard_blocked: Array = []
var _rejected: Array = []
var _colors: Dictionary = {}
var _metrics: Dictionary = {}
var _toast_text := ""
var _toast_at := -1.0e9
var _frame := 0
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
	if no_cursor or _take.is_empty() or _cursor_tex == null:
		return
	var pos: Dictionary = TakeIo.cursor_at(_take, _t)
	if not bool(pos.get("visible", false)):
		return
	var press := 1.0
	if not TakeIo.click_at(_take, _t).is_empty():
		press = TakeIo.PRESS_SCALE
	var size := Vector2(CURSOR_SIZE, CURSOR_SIZE) * press
	var origin := Vector2(float(pos["x"]), float(pos["y"])) - CURSOR_HOTSPOT * press
	draw_texture_rect(_cursor_tex, Rect2(origin, size), false)


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
	if _frame >= _total_frames:
		_finish()


## Feeds every event whose resolved time is <= t. The evaluator does the ordering
## and the sim mutation; this scene only reads the resulting snapshot.
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
			_rejected.append({
				"id": String(r.get("id", "")),
				"channel": channel,
				"code": String(r.get("code", "")),
			})
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
	_draw_characters()
	_draw_topbar(_snap)
	_draw_orders(_snap)
	_draw_board(_snap)
	_draw_bottom_bar(_snap)
	_draw_view_layer()
	_draw_toast()
	_draw_cursor()


## Bottom band: metrics.band_height is the one theme knob with no other consumer, so
## the band is what makes a "thicker band" a visible property of the film. It is
## clamped to start at the board's bottom edge, so the band never paints on the
## §20.5 board container; with the two background textures present it sits
## underneath them and is only visible in the no-asset fallback.
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
	_draw_ui_region("part1", PART1_CHAR_SRC, PART1_CHAR_RECT)
	_draw_ui_region("part2", PART2_CHAR_SRC, PART2_CHAR_RECT)


## §20.5/§20.6 top money bar, in the band above the characters: level badge over
## main_bar_level_bg, the energy pill with the 52x52 countdown icon and mm:ss, the
## coin / star / gem pills, and the shop button in the top-right corner. Every
## value comes from the current sim snapshot, and every panel keeps its procedural
## fallback when the theme has no art for it.
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
func _draw_orders(snap: Dictionary) -> void:
	var orders: Array = snap.get("orders", [])
	var cards := [LAYOUT_CARD1, LAYOUT_CARD2]
	var card_radius := _card_radius()
	for i in range(mini(orders.size(), cards.size())):
		var o: Dictionary = orders[i]
		var done := bool(o.get("done", false))
		var r: Rect2 = cards[i]
		if done:
			_hud_pill(r, _palette("done", COLOR_DONE), Color("#5FA83F"), card_radius)
		else:
			_hud_pill(r, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), card_radius)
		_text_left(Rect2(r.position.x + 16.0, r.position.y + 2.0, 240.0, 34.0),
			"ORDER " + String(o.get("id", "")), SMALL_FONT, _palette("ink_dim", COLOR_INK_DIM))
		var who := String(o.get("character", ""))
		var who_name := String((_model.character(who) as Dictionary).get("display", ""))
		if who_name.is_empty():
			who_name = who.replace("char_", "C")
		var lv := int(snap.get("level_index", 0)) + 1
		_text_left(Rect2(r.position.x + 16.0, r.position.y + 30.0, 250.0, 38.0),
			"%s  Lv.%d" % [who_name, lv], 26, _palette("ink", COLOR_INK))
		_character_badge(Rect2(r.position.x + r.size.x - 66.0, r.position.y + 10.0, 56.0, 56.0),
				who_name, done)
		var mission: Array = o.get("mission", [])
		var row_y := r.position.y + 74.0
		for m in mission:
			var ent := String((m as Array)[0]) if typeof(m) == TYPE_ARRAY else ""
			var lvl := int((m as Array)[1]) if typeof(m) == TYPE_ARRAY else 1
			var have := int((m as Array)[2]) if typeof(m) == TYPE_ARRAY else 0
			# A claimed order resets `have` to 0 in the sim (the units were consumed).
			# The card keeps showing 1/1 for a finished order, otherwise a green
			# done card would read "0/1" on screen.
			var shown := 1 if done else mini(have, 1)
			var label := "%s Lv.%d  %d/%d" % [ent, lvl, shown, 1]
			var pill := Rect2(r.position.x + 12.0, row_y - 4.0, 300.0, 38.0)
			_hud_pill(pill, _palette("card_edge", COLOR_PILL_EDGE).lightened(0.22),
					Color(0, 0, 0, 0), 19)
			_text_left(Rect2(pill.position.x + 12.0, pill.position.y, 270.0, pill.size.y),
					label, 24, _palette("ink", COLOR_INK))
			_check_dot(Vector2(r.position.x + 330.0, row_y + 15.0), done or have >= 1)
			row_y += 46.0
		if done:
			# §20.6 item 8: main_icon_finish over the completed card. Text fallback
			# keeps the state readable when the theme has no finish art.
			var finish_rect := Rect2(Vector2(r.position.x + r.size.x - 92.0,
					r.position.y + r.size.y - 66.0), Vector2(52.0, 52.0))
			if not _draw_ui_fit("finish", finish_rect):
				_rounded(finish_rect, 26, Color("#5FA83F"))
				_text_in(finish_rect, "OK", 26, COLOR_WHITE)


func _draw_board(snap: Dictionary) -> void:
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
	var cell_tex := _ui("cell")
	for y in range(mini(height, _rows)):
		for x in range(mini(width, _cols)):
			_cell_rect(x, y, cell_tex)

	# metrics.tint_alpha washes the board base in palette.board_tint; at the default
	# 0.0 nothing is painted, so the default film keeps its flat board.
	var tint := _metric("tint_alpha", 0.0)
	if tint > 0.0:
		var tint_color: Color = _palette("board_tint", COLOR_WHITE)
		draw_rect(Rect2(_origin, _board_size), Color(tint_color.r, tint_color.g, tint_color.b, tint), true)

	var cells: Array = board.get("cells", [])
	for raw in cells:
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 4:
			_draw_item(Vector2i(int((raw as Array)[0]), int((raw as Array)[1])),
				String((raw as Array)[2]), int((raw as Array)[3]))

	var obstacles: Array = board.get("obstacles", [])
	for raw in obstacles:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
			continue
		var pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
		for kind in (raw as Array)[2]:
			_draw_obstacle(pos, String(kind))


## §20.5 bottom band: the items bar texture at (193,1731) 693x183 with the level and
## level-id text on a plate (items.png carries placeholder copy there), the exit
## button bottom-left, the bag bottom-right.
func _draw_bottom_bar(snap: Dictionary) -> void:
	if not _draw_ui_stretch("items", LAYOUT_ITEMS):
		_hud_pill(LAYOUT_ITEMS, _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), _card_radius())
	var plate := Rect2(LAYOUT_ITEMS.position + Vector2(46.0, 12.0), Vector2(548.0, 96.0))
	_hud_pill(plate, Color(0.98, 0.99, 1.0, 1.0), Color(0, 0, 0, 0), 18)
	var level_line := "LEVEL %d / %s" % [int(snap.get("level_index", 0)) + 1,
			String(snap.get("level_id", ""))]
	_text_left(Rect2(plate.position + Vector2(18.0, 6.0), Vector2(plate.size.x - 36.0, 40.0)), level_line, INK_FONT, _palette("ink", COLOR_INK))

	if not _draw_ui_fit("exit", LAYOUT_EXIT):
		_hud_pill(LAYOUT_EXIT.grow(-8.0), _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), _card_radius())
		var c := LAYOUT_EXIT.get_center()
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-26.0, 0.0), c + Vector2(2.0, -28.0), c + Vector2(2.0, -12.0),
			c + Vector2(28.0, -12.0), c + Vector2(28.0, 12.0), c + Vector2(2.0, 12.0),
			c + Vector2(2.0, 28.0),
		]), _palette("ink", COLOR_INK))
	if not _draw_ui_fit("bag", LAYOUT_BAG):
		_hud_pill(LAYOUT_BAG.grow(-6.0), _palette("card", COLOR_PILL),
				_palette("card_edge", COLOR_PILL_EDGE), 18)
		draw_rect(Rect2(LAYOUT_BAG.position + Vector2(22.0, 24.0),
				Vector2(LAYOUT_BAG.size.x - 44.0, LAYOUT_BAG.size.y - 48.0)),
				_palette("ink_dim", COLOR_INK_DIM), false, 4.0)


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
		_level_capsule(r, level)
		return
	var hue := _hue(entity_id)
	_rounded(r, 18, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 34.0)), 12, Color(1, 1, 1, 0.18))
	_text_in(Rect2(r.position, Vector2(r.size.x, r.size.y - 18.0)), _short_label(entity_id), CHIP_FONT, COLOR_WHITE)
	_level_capsule(r, level)


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
	var gs: Dictionary = (_snap.get("generators", {}) as Dictionary).get(entity_id, {})
	_text_right(Rect2(r.position, r.size - Vector2(10.0, 8.0)), "x%d" % int(gs.get("charges", 0)), 26, COLOR_WHITE)
	_level_capsule(r, level)


func _level_capsule(r: Rect2, level: int) -> void:
	var f := _font_en if _font_en != null else _font_zh
	if f == null:
		return
	var text := "Lv.%d" % level
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPS_FONT).x + 16.0
	var cap := Rect2(r.position + Vector2(8.0, r.size.y - 36.0), Vector2(w, 28.0))
	_rounded(cap, 14, COLOR_CAPSULE)
	_text_in(cap, text, CAPS_FONT, COLOR_WHITE)


func _draw_obstacle(pos: Vector2i, kind: String) -> void:
	var r: Rect2 = _slot_rect(pos.x, pos.y).grow(-float(_cell_gap) * 0.5)
	# §20.6 item 9: the PSD obstacle art when the theme resolves it, the procedural
	# art otherwise. The ice cell keeps its 19:28 countdown either way.
	match kind:
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
		"bubble":
			if _draw_ui_fit("bubble", r):
				return
			var c2 := r.get_center()
			draw_circle(c2, 56.0, Color(0.72, 0.86, 1.0, 0.32), true, -1.0, true)
			draw_circle(c2, 56.0, Color(1.0, 1.0, 1.0, 0.85), false, 6.0, true)
			draw_circle(c2 + Vector2(-21.0, -21.0), 13.0, Color(1.0, 1.0, 1.0, 0.75), true, -1.0, true)
		"ice":
			var inner := r.grow(-4.0)
			if not _draw_ui_fit("ice", r):
				_rounded(inner, 14, Color(1.0, 1.0, 1.0, 0.35))
				_rounded_outline(inner, 14, Color(1.0, 1.0, 1.0, 0.80), 3)
			_text_in(Rect2(inner.position, Vector2(inner.size.x, inner.size.y - 12.0)), "19:28", 24, Color(1, 1, 1, 0.96))
		_:
			_rounded(r, 14, Color(0.0, 0.0, 0.0, 0.25))


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


func _text_left(r: Rect2, text: String, size: int, color: Color) -> void:
	var f := _pick_font(text)
	if f == null:
		return
	var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size) * 0.36)
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
