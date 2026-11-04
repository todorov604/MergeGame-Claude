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

const FPS := 60
const MANIFEST_INDEX := "res://data/manifest_index.json"
const DEFAULT_PROJECT := "res://data/sample_project.json"
const OUT_DIR := "res://output"
const OUT_MANIFEST := "res://output/render_manifest.json"
const FONT_ZH := "res://assets/fonts/font_zh.otf"
const FONT_EN := "res://assets/fonts/font_en.ttf"
const FRAME_ID := "board_frame"
const FRAME_TEXTURE := "res://assets/ui/board_frame.png"

## §7 item 4 prompt in the film: same geometry and fade curve as board_view, so a
## preview screenshot and the delivered frame cannot disagree about the prompt.
const TOAST_SECONDS := 1.5
const TOAST_FADE := 0.25
const TOAST_RECT := Rect2(190.0, 1802.0, 700.0, 84.0)
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
## frame. `--probe-ref=chip_clean_ca_lv01` must abort the render, which is how the
## REFERENCE_ONLY red line gets an end-to-end check instead of only a unit test.
var probe_refs: Array = []

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
var _origin := Vector2(50.0, 450.0)
var _board_size := Vector2(980.0, 1260.0)
var _cell := 140.0
var _cell_gap := 4
var _font_zh: Font = null
var _font_en: Font = null
var _frame_tex: Texture2D = null
var _sb_cache: Dictionary = {}
var _hue_cache: Dictionary = {}
var _snap: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = _page
	_parse_args()
	_page = BoardView.PAGE_SIZE
	_origin = BoardView.BOARD_ORIGIN
	_board_size = BoardView.BOARD_SIZE
	_cell = float(BoardView.CELL)
	_cell_gap = int(BoardView.CELL_GAP)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_font_zh = _load_font(FONT_ZH)
	_font_en = _load_font(FONT_EN)

	var model = ProjectModel.new()
	if not model.load_file(project_path):
		_fail("project load failed: " + String(model.load_error))
		return
	_model = model

	_evaluator = EventEvaluator.new()
	_evaluator.setup(_model, seed_value, self)
	var loaded: Dictionary = _evaluator.load_timeline(_model.project.get("timeline", []))
	if not bool(loaded.get("ok", false)):
		_fail("timeline resolve failed: " + str(loaded.get("errors", [])))
		return
	_end_time = float(loaded.get("end_time", 0.0))

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

	var refs: Array = ["font_en", "font_zh"]
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
		elif arg.begins_with("--probe-ref="):
			probe_refs.append(arg.substr(12))


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
		if channel == "sim":
			if not bool(r.get("ok", false)):
				_rejected.append({"id": String(r.get("id", "")), "code": String(r.get("code", ""))})
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
	if _snap.is_empty():
		return
	_draw_band()
	_draw_hud(_snap)
	_draw_orders(_snap)
	_draw_board(_snap)
	_draw_view_layer()
	_draw_toast()


## Bottom band: metrics.band_height is the one theme knob with no other consumer, so
## the band is what makes "thicker band" a visible property of the film.
func _draw_band() -> void:
	var height := _metric("band_height", 0.0)
	if height <= 0.0:
		return
	draw_rect(Rect2(0.0, _page.y - height, _page.x, height), _palette("band", COLOR_BAND), true)


func _draw_hud(snap: Dictionary) -> void:
	var hud: Dictionary = snap.get("hud", {})
	var y := 44.0
	_hud_pill(Rect2(28.0, y, 186.0, 84.0), _palette("accent", COLOR_ACCENT),
			Color(0, 0, 0, 0), _hud_radius())
	_text_in(Rect2(28.0, y, 186.0, 84.0), "LV %d" % int(hud.get("level", 1)), HUD_FONT, COLOR_WHITE)

	var er := Rect2(226.0, y, 250.0, 84.0)
	_hud_pill(er, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	_bolt(Vector2(er.position.x + 34.0, er.position.y + er.size.y * 0.5), 22.0, COLOR_ENERGY)
	_text_left(Rect2(er.position.x + 66.0, er.position.y, 170.0, 84.0), str(int(hud.get("energy", 0))), HUD_FONT, _palette("ink", COLOR_INK))

	var cr := Rect2(488.0, y, 240.0, 84.0)
	_hud_pill(cr, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	_coin(Vector2(cr.position.x + 34.0, cr.position.y + cr.size.y * 0.5), 20.0)
	_text_left(Rect2(cr.position.x + 66.0, cr.position.y, 160.0, 84.0), str(int(hud.get("coin", 0))), HUD_FONT, _palette("ink", COLOR_INK))

	var sr := Rect2(740.0, y, 168.0, 84.0)
	_hud_pill(sr, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	_star(Vector2(sr.position.x + 32.0, sr.position.y + cr.size.y * 0.5), 20.0)
	_text_left(Rect2(sr.position.x + 62.0, sr.position.y, 100.0, 84.0), str(int(hud.get("star", 0))), HUD_FONT, _palette("ink", COLOR_INK))

	var gr := Rect2(920.0, y, 132.0, 84.0)
	_hud_pill(gr, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), _hud_radius())
	_gem(Vector2(gr.position.x + 30.0, gr.position.y + gr.size.y * 0.5), 18.0)
	_text_left(Rect2(gr.position.x + 56.0, gr.position.y, 70.0, 84.0), str(int(hud.get("gem", 0))), HUD_FONT, _palette("ink", COLOR_INK))


func _draw_orders(snap: Dictionary) -> void:
	var orders: Array = snap.get("orders", [])
	var card_radius := _card_radius()
	var card_gap := _metric("card_gap", 14.0)
	for i in range(mini(orders.size(), 2)):
		var o: Dictionary = orders[i]
		var done := bool(o.get("done", false))
		var r := Rect2(40.0 + float(i) * (500.0 + card_gap), 170.0, 500.0, 214.0)
		if done:
			_hud_pill(r, _palette("done", COLOR_DONE), Color("#5FA83F"), card_radius)
		else:
			_hud_pill(r, _palette("card", COLOR_PILL), _palette("card_edge", COLOR_PILL_EDGE), card_radius)
		_text_left(Rect2(r.position.x + 20.0, r.position.y + 10.0, 300.0, 40.0),
			"ORDER " + String(o.get("id", "")), SMALL_FONT, _palette("ink", COLOR_INK))
		var who := String(o.get("character", ""))
		_character_badge(Rect2(r.position.x + r.size.x - 108.0, r.position.y + 16.0, 88.0, 88.0), who, done)
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
			_text_left(Rect2(r.position.x + 24.0, row_y, 300.0, 44.0), label, 26, _palette("ink", COLOR_INK))
			_check_dot(Vector2(r.position.x + 352.0, row_y + 22.0), done or have >= 1)
			row_y += 56.0


func _draw_board(snap: Dictionary) -> void:
	var panel := Rect2(_origin - Vector2(12.0, 12.0), _board_size + Vector2(24.0, 24.0))
	_hud_pill(panel, _palette("panel", BoardView.COLOR_PANEL),
			_palette("panel_edge", BoardView.COLOR_PANEL_EDGE), _board_radius())
	if _frame_tex != null:
		draw_texture_rect(_frame_tex, Rect2(_origin, _board_size), false)

	var board: Dictionary = snap.get("board", {})
	var width := int(board.get("width", 7))
	var height := int(board.get("height", 9))
	for y in range(height):
		for x in range(width):
			_cell_rect(x, y, false)

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

	var caption := "LEVEL %d / %s" % [int(snap.get("level_index", 0)) + 1, String(snap.get("level_id", ""))]
	_text_left(Rect2(_origin.x, _origin.y - 52.0, 700.0, 40.0), caption, INK_FONT,
			_palette("ink_dim", COLOR_INK_DIM))


func _cell_rect(x: int, y: int, filled: bool) -> void:
	var r := Rect2(_origin + Vector2(float(x) * _cell, float(y) * _cell), Vector2(_cell, _cell))
	r = r.grow(-float(_cell_gap) * 0.5)
	var cell: Color = _palette("cell", BoardView.COLOR_CELL)
	_rounded(r, 14, cell)
	if not filled:
		# cell_lip is not a palette key of its own: derive it from the theme cell so a
		# re-skin moves the lip with the tile instead of leaving a stale blue line.
		var lip: Color = _palette("cell_lip", cell.lightened(0.12))
		_rounded(Rect2(r.position + Vector2(3.0, 3.0), Vector2(r.size.x - 6.0, 5.0)), 3, lip)


func _draw_item(pos: Vector2i, entity_id: String, level: int) -> void:
	var r := Rect2(_origin + Vector2(float(pos.x) * _cell, float(pos.y) * _cell), Vector2(_cell, _cell)).grow(-6.0)
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
	var hue := _hue(entity_id)
	_rounded(r, 18, hue)
	_rounded(Rect2(r.position + Vector2(8.0, 8.0), Vector2(r.size.x - 16.0, 34.0)), 12, Color(1, 1, 1, 0.18))
	_text_in(Rect2(r.position, Vector2(r.size.x, r.size.y - 18.0)), _short_label(entity_id), CHIP_FONT, COLOR_WHITE)
	_level_capsule(r, level)


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
	var r := Rect2(_origin + Vector2(float(pos.x) * _cell, float(pos.y) * _cell), Vector2(_cell, _cell)).grow(-float(_cell_gap) * 0.5)
	match kind:
		"lock":
			_rounded(r, 14, Color(0.05, 0.09, 0.15, 0.55))
			var c := r.get_center()
			var metal := Color(0.91, 0.94, 0.97)
			draw_arc(c + Vector2(0.0, -6.0), 17.0, PI, TAU, 28, metal, 7.0, true)
			_rounded(Rect2(c + Vector2(-26.0, -4.0), Vector2(52.0, 40.0)), 7, metal)
			draw_circle(c + Vector2(0.0, 10.0), 5.5, Color(0.16, 0.22, 0.30), true, -1.0, true)
		"web":
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
			var c2 := r.get_center()
			draw_circle(c2, 56.0, Color(0.72, 0.86, 1.0, 0.32), true, -1.0, true)
			draw_circle(c2, 56.0, Color(1.0, 1.0, 1.0, 0.85), false, 6.0, true)
			draw_circle(c2 + Vector2(-21.0, -21.0), 13.0, Color(1.0, 1.0, 1.0, 0.75), true, -1.0, true)
		"ice":
			var inner := r.grow(-4.0)
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
					_banner(_locale(String(payload.get("text_key", ""))), Rect2(100.0, 742.0, 880.0, 118.0), 44, p)
			"hint":
				if active:
					_banner(_locale(String(payload.get("text_key", ""))), Rect2(190.0, 640.0, 700.0, 92.0), 32, p)
			"levelup":
				if active:
					_banner("LEVEL UP", Rect2(240.0, 560.0, 600.0, 110.0), 52, p)
			"cta":
				if active:
					_draw_cta(_locale(String(payload.get("text_key", ""))), p)
			"coin_popup":
				if active:
					_popup("+%d" % int(payload.get("coin", 5)), Vector2(560.0, 176.0 - 54.0 * p), 1.0 - p * 0.7)
			"star_fly":
				if active:
					var from := Vector2(540.0, 1100.0)
					var to := Vector2(824.0, 86.0)
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
	var r := Rect2(_origin + Vector2(float(pos.x) * _cell, float(pos.y) * _cell), Vector2(_cell, _cell)).grow(-float(_cell_gap) * 0.5)
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
	var r := Rect2(150.0, 1732.0, 780.0, 132.0)
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
	_rounded(r, 22, Color("#F2C6A0") if not done else Color("#B8E39A"))
	_rounded(Rect2(r.position + Vector2(6.0, 6.0), Vector2(r.size.x - 12.0, r.size.y * 0.42)), 18, Color("#3A2A22"))
	draw_circle(r.get_center() + Vector2(0.0, 14.0), 16.0, Color("#3A2A22"), true, -1.0, true)
	var tag := who.replace("char_", "C")
	_text_in(Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, r.size.y * 0.58), tag, 26,
			_palette("ink", COLOR_INK))


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
