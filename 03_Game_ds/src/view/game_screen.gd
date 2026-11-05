extends Control
## Main screen for M0 step 4: board + HUD + order cards + presentation layer,
## driven by the shared event evaluator (no private timeline parsing here).
##
##   godot --path . --script res://tools/shot_game_screen.gd -- --t=6.2
##   godot --path . -- --autoplay               (real-time playback)
##   godot --path . -- --theme=themes/pet_shop  (data-only re-skin)
##
## The screen owns three things and nothing else:
##   1. wiring views to the evaluator's single resolved event stream
##   2. mirroring sim snapshots into the views (board / hud / order progress)
##   3. presentation time (clock -> FlyAnim), which never feeds back into the sim

const BoardScene := preload("res://src/view/board_view.tscn")
const BoardView := preload("res://src/view/board_view.gd")
const HudView := preload("res://src/view/hud_view.gd")
const OrderPanel := preload("res://src/view/order_panel.gd")
const FlyAnim := preload("res://src/view/fly_anim.gd")
const ProjectModel := preload("res://src/core/project_model.gd")
const EventEvaluator := preload("res://src/core/event_evaluator.gd")
const AssetGuardScript := preload("res://src/assets/asset_guard.gd")
const ThemeLoader := preload("res://src/theme/theme_loader.gd")
## §20.5 棋盘.psd layout. The film (movie_scene.gd) owns the numbers — both screens
## must agree pixel for pixel — so the live screen reads the same table instead of
## keeping a second copy that can drift. The board rect comes from BoardView, whose
## container is the 983x1263 at (48,466) the layout is built around.
const FilmLayout := preload("res://src/render/movie_scene.gd")

const SAMPLE_PROJECT := "res://data/sample_project.json"
const MANIFEST_INDEX := "res://data/manifest_index.json"
const PAGE := Vector2(1080.0, 1920.0)
const BOARD_RECT := Rect2(BoardView.BOARD_ORIGIN, BoardView.BOARD_SIZE)
const LAYOUT_BG_BOTTOM := FilmLayout.LAYOUT_BG_BOTTOM
const LAYOUT_BG_TOP := FilmLayout.LAYOUT_BG_TOP
const LAYOUT_PART1 := FilmLayout.LAYOUT_PART1
const LAYOUT_PART2 := FilmLayout.LAYOUT_PART2
const LAYOUT_ITEMS := FilmLayout.LAYOUT_ITEMS
const LAYOUT_EXIT := FilmLayout.LAYOUT_EXIT
const LAYOUT_BAG := FilmLayout.LAYOUT_BAG
const LAYOUT_SHOP := FilmLayout.LAYOUT_SHOP
const LAYOUT_LEVEL_BADGE := FilmLayout.LAYOUT_LEVEL_BADGE
const LAYOUT_LEVEL_BADGE_BG := FilmLayout.LAYOUT_LEVEL_BADGE_BG
const LAYOUT_ENERGY := FilmLayout.LAYOUT_ENERGY
const LAYOUT_COIN := FilmLayout.LAYOUT_COIN
const LAYOUT_STAR := FilmLayout.LAYOUT_STAR
const LAYOUT_GEM := FilmLayout.LAYOUT_GEM
## The order band sits between the money bar and the board: 210..460, i.e. above the
## 466 container top and below the y≈0..120 money bar.
const ORDER_RECT := Rect2(0.0, 210.0, 1080.0, 250.0)
## hud_view.gd draws a 1080x185 layout with hardcoded local pill rects. Scaling the
## control 0.8 keeps that view untouched while making the bar 864x148, which leaves
## the top-right corner free for the §20.5 shop button at x=930.
const HUD_SCALE := 0.8
const HUD_RECT := Rect2(0.0, 0.0, 864.0, 148.0)
## §20.5 logical ui slots the live screen draws itself (the board slots belong to
## board_view.gd and are logged there).
const UI_KEYS := [
	"bg_bottom", "bg_top", "level_badge", "level_badge_bg", "energy_timer",
	"money_bg", "part1", "part2", "items", "exit", "bag", "shop",
]
const DEFAULT_SEED := 7
## §7 item 4 inbox prompt window; kept in sync with BoardView.TOAST_SECONDS.
const TOAST_SECONDS := 1.5

## Draws the chrome (characters, money bar, bottom bar) above the board but below
## the HUD / order cards. A plain child Control cannot do that from game_screen's
## own _draw(): a parent CanvasItem paints before all of its children, and
## board_view paints an opaque page over the whole canvas. The drawing has to run on
## *this* CanvasItem (draw_* is node-scoped), so the whole chrome painter lives here
## and reads its data/textures from the screen it belongs to.
class Chrome extends Control:
	## One source of truth for the §20.5 numbers: the film's own layout table. The
	## inner class cannot read the enclosing script's constants, so it preloads the
	## same table itself.
	const FilmLayout := preload("res://src/render/movie_scene.gd")
	const PAGE := Vector2(1080.0, 1920.0)
	const LAYOUT_BG_BOTTOM := FilmLayout.LAYOUT_BG_BOTTOM
	const LAYOUT_BG_TOP := FilmLayout.LAYOUT_BG_TOP
	const LAYOUT_PART1 := FilmLayout.LAYOUT_PART1
	const LAYOUT_PART2 := FilmLayout.LAYOUT_PART2
	const PART1_CHAR_SRC := FilmLayout.PART1_CHAR_SRC
	const PART2_CHAR_SRC := FilmLayout.PART2_CHAR_SRC
	const PART1_CHAR_RECT := FilmLayout.PART1_CHAR_RECT
	const PART2_CHAR_RECT := FilmLayout.PART2_CHAR_RECT
	const LAYOUT_LEVEL_BADGE_BG := FilmLayout.LAYOUT_LEVEL_BADGE_BG
	const LAYOUT_LEVEL_BADGE := FilmLayout.LAYOUT_LEVEL_BADGE
	const LAYOUT_SHOP := FilmLayout.LAYOUT_SHOP
	const LAYOUT_ITEMS := FilmLayout.LAYOUT_ITEMS
	const LAYOUT_EXIT := FilmLayout.LAYOUT_EXIT
	const LAYOUT_BAG := FilmLayout.LAYOUT_BAG

	var host = null
	var _boxes: Dictionary = {}

	func _draw() -> void:
		if host == null:
			return
		var snap: Dictionary = host._snapshot()
		draw_ui_region("part1", PART1_CHAR_SRC, PART1_CHAR_RECT)
		draw_ui_region("part2", PART2_CHAR_SRC, PART2_CHAR_RECT)
		_draw_topbar(snap)
		_draw_bottom_bar(snap)

	func _draw_topbar(snap: Dictionary) -> void:
		var values: Dictionary = host._hud_values(snap)
		# The HUD (hud_view.gd) keeps its own pill rects; the chrome paints the §20.5
		# plates underneath them instead of moving its numbers around, and the
		# transparent pill palette in the screen leaves the fills to this layer.
		for key in ["energy", "coin", "gem", "star"]:
			rounded(host._hud_pill_page(key), 22, Color(1, 1, 1, 0.82))
		var level_rect: Rect2 = host._hud_pill_page("level")
		var badge_drawn := draw_ui_fit("level_badge_bg", level_rect)
		badge_drawn = draw_ui_fit("level_badge", level_rect) or badge_drawn
		if not badge_drawn:
			rounded(level_rect, 22, Color("#5B8DEF"))
		# main_money_bg is the PSD currency base: a 68x66 plate behind each icon,
		# shrunk to the HUD's own pill height.
		for key2 in ["energy", "coin", "star", "gem"]:
			var centre: Vector2 = host._hud_counter_page(key2)
			draw_ui_stretch("money_bg", Rect2(centre - Vector2(27.0, 26.0), Vector2(54.0, 52.0)))
		if host._ui("energy_timer") != null:
			draw_ui_stretch("energy_timer", Rect2(Vector2(856.0, 12.0), Vector2(52.0, 52.0)))
		# Digits live here in chrome mode (hud_view is hidden): level inside the badge,
		# the four counters inside their pills, mm:ss under the energy timer.
		text_center(level_rect.grow(-6.0), str(int(values.get("level", 1))), 36, Color("#22303F") if badge_drawn else Color(1, 1, 1, 0.96))
		var energy_rect: Rect2 = host._hud_pill_page("energy")
		text_left(Rect2(energy_rect.position.x + 58.0, energy_rect.position.y + 10.0,
				energy_rect.size.x - 74.0, 34.0), str(int(values.get("energy", 0))), 30, Color("#22303F"))
		text_left(Rect2(energy_rect.position.x + 58.0, energy_rect.position.y + 42.0,
				energy_rect.size.x - 74.0, 24.0),
				host._mmss(int(values.get("energyTickSeconds", 0))), 18, Color("#5C6B7D"))
		for key3 in ["coin", "star", "gem"]:
			var counter_rect: Rect2 = host._hud_pill_page(key3)
			text_left(Rect2(counter_rect.position.x + 58.0, counter_rect.position.y,
					counter_rect.size.x - 66.0, counter_rect.size.y),
					str(int(values.get(key3, 0))), 30, Color("#22303F"))
		if not draw_ui_fit("shop", LAYOUT_SHOP):
			rounded(LAYOUT_SHOP, 30, Color("#5B8DEF"))
			draw_rect(Rect2(LAYOUT_SHOP.position + Vector2(26.0, 34.0),
					Vector2(LAYOUT_SHOP.size.x - 52.0, 46.0)), Color(1, 1, 1, 0.85), true)

	func _draw_bottom_bar(snap: Dictionary) -> void:
		if not draw_ui_stretch("items", LAYOUT_ITEMS):
			rounded(LAYOUT_ITEMS, 24, Color(1, 1, 1, 0.92))
		# items.png carries placeholder copy from the PSD; the live level/id text goes
		# on a small plate that covers that copy instead of doubling it.
		var plate := Rect2(LAYOUT_ITEMS.position + Vector2(52.0, 18.0), Vector2(470.0, 62.0))
		rounded(plate, 18, Color(0.98, 0.99, 1.0, 1.0))
		var level_line := "LEVEL %d / %s" % [int(snap.get("level_index", host._level_index)) + 1,
				String(snap.get("level_id", host._level_static.get("id", "")))]
		text_left(Rect2(plate.position + Vector2(18.0, 6.0), Vector2(plate.size.x - 36.0, 40.0)), level_line, 28, Color("#22303F"))
		if not draw_ui_fit("exit", LAYOUT_EXIT):
			rounded(LAYOUT_EXIT.grow(-8.0), 30, Color(1, 1, 1, 0.92))
		if not draw_ui_fit("bag", LAYOUT_BAG):
			rounded(LAYOUT_BAG.grow(-6.0), 18, Color(1, 1, 1, 0.92))

	func draw_ui_stretch(key: String, r: Rect2) -> bool:
		var texture: Texture2D = host._ui(key)
		if texture == null:
			return false
		draw_texture_rect(texture, r, false)
		return true

	func draw_ui_region(key: String, src: Rect2, r: Rect2) -> bool:
		var texture: Texture2D = host._ui(key)
		if texture == null:
			return false
		draw_texture_rect_region(texture, r, src)
		return true

	func draw_ui_fit(key: String, r: Rect2) -> bool:
		var texture: Texture2D = host._ui(key)
		if texture == null:
			return false
		var source := texture.get_size()
		if source.x <= 0.0 or source.y <= 0.0:
			return false
		var used := minf(r.size.x / source.x, r.size.y / source.y)
		var drawn := source * used
		draw_texture_rect(texture, Rect2(r.position + (r.size - drawn) * 0.5, drawn), false)
		return true

	func rounded(r: Rect2, radius: int, color: Color) -> void:
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			return
		var box: StyleBoxFlat = _boxes.get(radius)
		if box == null:
			box = StyleBoxFlat.new()
			box.set_corner_radius_all(radius)
			box.anti_aliasing = true
			_boxes[radius] = box
		box.bg_color = color
		box.border_color = Color(0, 0, 0, 0)
		box.set_border_width_all(0)
		draw_style_box(box, r)

	func text_left(r: Rect2, text: String, size_px: int, color: Color) -> void:
		if host._font == null or text.is_empty():
			return
		var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size_px) * 0.36)
		draw_string(host._font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	func text_center(r: Rect2, text: String, size_px: int, color: Color) -> void:
		if host._font == null or text.is_empty():
			return
		var width: float = host._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var baseline := r.position + Vector2((r.size.x - width) * 0.5, r.size.y * 0.5 + float(size_px) * 0.36)
		draw_string(host._font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

var board
var hud
var orders
var fly
var chrome
var model
var evaluator
var guard
var theme_loader
var _chrome_owns_hud: bool = false

var allow_placeholders: bool = false
var theme_name: String = ""
var theme_ok: bool = false
var sim_rejected: int = 0
var view_events: Dictionary = {}

## "bg_bottom" -> Texture2D or null, resolved once in _ready(). _draw_chrome() only
## reads this cache: no frame does IO.
var _ui_tex: Dictionary = {}
var _ui_ids: Array = []
var _ui_id_by_key: Dictionary = {}
var _font: Font = null

var _clock: float = 0.0
var _seed: int = DEFAULT_SEED
var _autoplay: bool = true
var _freeze: bool = false
var _t_target: float = -1.0
var _selected := Vector2i(-1, -1)
var _level_index: int = 0
var _level_static: Dictionary = {}
var _end_time: float = 0.0
var _event_count: int = 0
var _last_code: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = PAGE
	_parse_args()

	model = ProjectModel.new()
	if not model.load_file(SAMPLE_PROJECT):
		push_error("[game] cannot load " + SAMPLE_PROJECT + ": " + String(model.load_error))
		return

	guard = AssetGuardScript.new()
	if not guard.load_from(MANIFEST_INDEX, allow_placeholders):
		push_warning("[game] asset index: " + String(guard.load_error))

	theme_loader = ThemeLoader.new()
	theme_loader.setup(guard, allow_placeholders)
	if theme_name.is_empty():
		theme_name = String(model.project.get("theme", "themes/default"))
	var theme_result: Dictionary = theme_loader.load_theme(theme_name, model.project)
	theme_ok = bool(theme_result.get("ok", false))
	var colors: Dictionary = theme_loader.colors()
	var metrics: Dictionary = theme_loader.metrics
	_font = _load_font()
	# §20.5 layout art, resolved once before the first paint (textures are cached by
	# ThemeLoader.texture_for, so no frame touches the disk).
	_resolve_ui_art()

	board = BoardScene.instantiate()
	board.position = Vector2.ZERO
	add_child(board)
	# The theme is already loaded above, so the board can draw real chip icons on
	# its very first paint instead of flashing procedural chips.
	board.set_chip_icons(theme_loader, model.project)

	# Chrome (background characters, money bar, bottom items bar) has to paint above
	# the board but below the HUD and the order cards, so it is its own child added
	# right after the board instead of being drawn by this control's _draw().
	chrome = Chrome.new()
	chrome.host = self
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.position = Vector2.ZERO
	chrome.size = PAGE
	add_child(chrome)

	hud = HudView.new()
	hud.position = HUD_RECT.position
	hud.size = Vector2(1080.0, 185.0)
	# hud_view.gd keeps its own 1080-wide pill layout; scaling it down 0.8 is what
	# makes room for the top-right shop button without editing that view.
	hud.scale = Vector2(HUD_SCALE, HUD_SCALE)
	add_child(hud)
	# The §20.5 art draws the pills, so the HUD keeps only its numbers/icons: a
	# transparent panel colour erases its procedural pill fills.
	hud.set_palette(_transparent_pills(colors))
	# §20.5 chrome paints the whole money row (plates + digits). Leaving hud_view visible
	# would double-draw translucent pills and a second set of numbers over the art, so it
	# is hidden in chrome mode; its rects still feed the chrome.
	_chrome_owns_hud = _ui("items") != null and _ui("part1") != null
	if _chrome_owns_hud:
		hud.visible = false
		board.show_debug_labels = false

	orders = OrderPanel.new()
	orders.position = ORDER_RECT.position
	orders.size = ORDER_RECT.size
	# order_panel paints an opaque page-coloured strip behind its cards; the §20.5
	# band sits on top of the order characters, so that strip goes transparent and
	# lets the part1/part2 art show between the cards.
	orders.set_palette(_transparent_page(colors))
	orders.set_metrics(metrics)
	orders.set_project(model.project)
	add_child(orders)

	fly = FlyAnim.new()
	fly.position = Vector2.ZERO
	fly.size = PAGE
	fly.set_palette(colors)
	# fly_anim's backdrop paints an opaque band at the bottom of the page; the §20.5
	# items bar owns that band now, so the flight layer keeps only its board outline
	# and the moving coins/stars.
	fly.set_metrics(_flight_metrics(metrics))
	add_child(fly)

	_apply_static_level(0)
	evaluator = EventEvaluator.new()
	evaluator.setup(model, _seed, Callable(self, "_on_event"))
	var loaded: Dictionary = evaluator.load_timeline(_as_array(model.project.get("timeline", [])))
	_event_count = int(loaded.get("count", 0))
	_end_time = float(loaded.get("end_time", 0.0))
	if not bool(loaded.get("ok", false)):
		push_warning("[game] timeline rejected: " + str(loaded.get("errors", [])))

	_sync_from_sim()

	if _t_target >= 0.0:
		# clock first: a toast raised while draining the preview window must start
		# at the frozen time, otherwise it would expire before the screen is shot
		_clock = _t_target
		board.set_clock(_clock)
		while evaluator.cursor < evaluator.events.size():
			var ev: Dictionary = evaluator.events[evaluator.cursor]
			if float(ev.get("at", 0.0)) > _t_target:
				break
			_note_sim_result(evaluator.step())
		fly.set_clock(_clock)
	else:
		fly.set_clock(0.0)

	print("[game] project=%s levels=%d events=%d end=%.2f theme=%s ok=%s" % [
		SAMPLE_PROJECT.get_file(), model.level_count(), _event_count, _end_time,
		theme_name, str(theme_ok),
	])
	print("[game] " + String(theme_loader.summary()))
	print("[game] chip icons resolved=%d of %d items" % [int(board.chip_icon_count()), int(board.item_count())])
	print("[game] ui " + String(ui_summary()))
	print("[game] " + String(hud.debug_summary()))
	print("[game] " + String(orders.debug_summary()))
	print("[game] freeze=%s autoplay=%s clock=%.2f t=%.2f" % [
		str(_freeze), str(_autoplay), _clock, _t_target,
	])


# ------------------------------------------------------------------- arguments

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--autoplay":
			_autoplay = true
		elif text == "--no-autoplay":
			_autoplay = false
		elif text.begins_with("--t="):
			_freeze = true
			_t_target = maxf(0.0, float(text.substr(4)))
		elif text.begins_with("--theme="):
			theme_name = text.substr(8)
		elif text.begins_with("--seed="):
			_seed = int(text.substr(7))
		elif text == "--allow-placeholders":
			allow_placeholders = true


# ------------------------------------------------------------------- view sync

func _apply_static_level(index: int) -> void:
	_level_index = index
	_level_static = _as_dict(model.level(index))
	_selected = Vector2i(-1, -1)
	orders.build_from_level(_level_static)
	fly.set_backdrop({
		"board": BOARD_RECT,
		"level": index + 1,
		"level_id": String(_level_static.get("id", "")),
		"title": String(_as_dict(model.project.get("meta", {})).get("title", "")),
		"order": _first_order_id(_level_static),
	})


func _first_order_id(level: Dictionary) -> String:
	for raw in _as_array(level.get("orders", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			return String((raw as Dictionary).get("id", ""))
	return ""


# --------------------------------------------------------------- §20.5 chrome

## Background layers behind the board (the board view paints the same two layers;
## this keeps the live screen's own stacking complete if the board is ever shown
## without its background). Drawn before every child, i.e. under the board.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PAGE), Color("#E6EDF6"), true)
	_draw_ui_stretch("bg_bottom", LAYOUT_BG_BOTTOM)
	_draw_ui_stretch("bg_top", LAYOUT_BG_TOP)


## The HUD dictionary as plain values (the rail the chrome reads its text from).
func _hud_values(snap: Dictionary) -> Dictionary:
	var values: Dictionary = _as_dict(snap.get("hud", {}))
	if values.is_empty() and hud != null:
		values = hud.values
	return values


## hud_view.gd's own pill rect, mapped from its local space into page space through
## the 0.8 scale. The chrome paints the §20.5 plates *under* those rects, so the HUD
## keeps its numbers and the layout keeps one source of truth for the text.
func _hud_pill_page(key: String) -> Rect2:
	var local = hud._pill_rect(key)
	if typeof(local) != TYPE_RECT2:
		return Rect2()
	var rect: Rect2 = local
	return Rect2(rect.position * hud.scale + hud.position, rect.size * hud.scale)


## Where the HUD thinks one counter's icon sits, in page space.
func _hud_counter_page(key: String) -> Vector2:
	return hud.counter_center(key) * hud.scale + hud.position


# ------------------------------------------------------------------ ui lookups

## Resolves every §20.5 slot once. The ids that produced a texture are what
## ui_summary() prints and what the screenshot log names.
func _resolve_ui_art() -> void:
	_ui_tex = {}
	_ui_ids = []
	_ui_id_by_key = {}
	for raw_key in UI_KEYS:
		var key := String(raw_key)
		var id := ""
		if theme_loader != null and theme_loader.has_method("resolve_ui"):
			var resolved = theme_loader.resolve_ui(key, model.project)
			if typeof(resolved) == TYPE_DICTIONARY:
				id = String((resolved as Dictionary).get("id", ""))
		var texture: Texture2D = null
		if not id.is_empty() and theme_loader != null and theme_loader.has_method("texture_for"):
			var loaded = theme_loader.texture_for(id)
			if loaded is Texture2D:
				texture = loaded
		_ui_tex[key] = texture
		if texture != null:
			_ui_ids.append(id)
			_ui_id_by_key[key] = id


func _ui(key: String) -> Texture2D:
	var value = _ui_tex.get(key, null)
	return value if value is Texture2D else null


## key -> manifest id, only for the slots whose texture really loaded.
func ui_ids() -> Dictionary:
	return _ui_id_by_key.duplicate(true)


## "[game] ui resolved=N of M key=id ..." naming the layout art this screen drew.
func ui_summary() -> String:
	var parts: Array = []
	for raw_key in UI_KEYS:
		var key := String(raw_key)
		parts.append("%s=%s" % [key, String(_ui_id_by_key.get(key, "-"))])
	return "resolved=%d of %d %s" % [_ui_ids.size(), UI_KEYS.size(), " ".join(parts)]


func _draw_ui_stretch(key: String, r: Rect2) -> bool:
	var texture := _ui(key)
	if texture == null:
		return false
	draw_texture_rect(texture, r, false)
	return true


## Palette copy with invisible pill fills: the §20.5 art is the pill background now.
func _transparent_pills(colors: Dictionary) -> Dictionary:
	var out := colors.duplicate(true)
	out["panel"] = Color(0, 0, 0, 0)
	out["panel_edge"] = Color(0, 0, 0, 0)
	return out


## order_panel's own background strip goes transparent so the characters show.
func _transparent_page(colors: Dictionary) -> Dictionary:
	var out := colors.duplicate(true)
	out["page"] = Color(0, 0, 0, 0)
	return out


## fly_anim's backdrop band would cover the §20.5 items bar; zero it so the flight
## layer only draws its board outline and the moving coins/stars.
func _flight_metrics(metrics: Dictionary) -> Dictionary:
	var out := metrics.duplicate(true)
	out["band_height"] = 0.0
	return out


func _snapshot() -> Dictionary:
	if evaluator == null or evaluator.sim == null:
		return {}
	return evaluator.sim.snapshot()


func _mmss(seconds: int) -> String:
	var total := maxi(0, seconds)
	return "%02d:%02d" % [total / 60, total % 60]


# -------------------------------------------------------------------- text/box

func _load_font() -> Font:
	var bytes := FileAccess.get_file_as_bytes("res://assets/fonts/font_zh.otf")
	if bytes.size() > 0:
		var file := FontFile.new()
		file.data = bytes
		if file.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > 0.0:
			return file
	return ThemeDB.fallback_font


func _sync_from_sim() -> void:
	if evaluator == null or evaluator.sim == null:
		return
	var snap: Dictionary = evaluator.sim.snapshot()
	var index := int(snap.get("level_index", 0))
	if index != _level_index:
		_apply_static_level(index)
	var level := _level_from_snapshot(snap)
	board.build_from_level_data(level, _as_dict(model.project.get("entities", {})),
			_generators_live(snap))
	board.apply_state({"selected": _to_array(_selected), "completed": _completed_cells(snap)})
	board.set_clock(_clock)
	hud.build_from_hud(_as_dict(snap.get("hud", {})))
	orders.sync_orders(_as_array(snap.get("orders", [])))
	_refresh_anchors()


func _level_from_snapshot(snap: Dictionary) -> Dictionary:
	var board_snap := _as_dict(snap.get("board", {}))
	var slots: Array = []
	for row in _as_array(board_snap.get("cells", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 4:
			continue
		slots.append({
			"x": int((row as Array)[0]),
			"y": int((row as Array)[1]),
			"entity": String((row as Array)[2]),
			"level": int((row as Array)[3]),
		})
	var obstacles: Array = []
	for row in _as_array(board_snap.get("obstacles", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 3:
			continue
		for kind in _as_array((row as Array)[2]):
			obstacles.append({
				"slot": [int((row as Array)[0]), int((row as Array)[1])],
				"type": String(kind),
			})
	return {
		"id": String(snap.get("level_id", "")),
		"board": {
			"width": int(board_snap.get("width", 7)),
			"height": int(board_snap.get("height", 9)),
			"slots": slots,
		},
		"obstacles": obstacles,
		"orders": _as_array(_level_static.get("orders", [])),
	}


## View-only derivation: a cell that satisfies an open mission item is marked as
## ready (green) so the delivery beat reads without extra art.
func _completed_cells(snap: Dictionary) -> Array:
	var wanted := {}
	for raw in _as_array(snap.get("orders", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = raw
		if bool(order.get("done", false)):
			continue
		var mission := _as_array(order.get("mission", []))
		for i in range(mission.size()):
			var item = mission[i]
			if typeof(item) != TYPE_ARRAY or (item as Array).size() < 3:
				continue
			if int((item as Array)[2]) >= 1:
				continue
			var key := "%s@%d" % [String((item as Array)[0]), int((item as Array)[1])]
			wanted[key] = true
	var out: Array = []
	for row in _as_array(_as_dict(snap.get("board", {})).get("cells", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 4:
			continue
		var key := "%s@%d" % [String((row as Array)[2]), int((row as Array)[3])]
		if wanted.has(key):
			out.append([int((row as Array)[0]), int((row as Array)[1])])
	return out


## Generator charges live in the sim, not in project.json; hand the board a copy
## with the current counts so its x<charges> badge matches the simulation.
func _generators_live(snap: Dictionary) -> Dictionary:
	var out := _as_dict(model.project.get("generators", {})).duplicate(true)
	var live := _as_dict(snap.get("generators", {}))
	for gid in live.keys():
		if not out.has(gid):
			continue
		var cfg := _as_dict(out[gid])
		cfg["charges"] = int(_as_dict(live[gid]).get("charges", cfg.get("charges", 0)))
		out[String(gid)] = cfg
	return out


func _refresh_anchors() -> void:
	var table := {}
	var width := 7
	var height := 9
	if evaluator != null and evaluator.sim != null and evaluator.sim.board != null:
		width = int(evaluator.sim.board.width)
		height = int(evaluator.sim.board.height)
	for y in height:
		for x in width:
			table["cell:%d,%d" % [x, y]] = board.cell_rect(x, y).get_center()
	for card in orders.cards:
		var id := String(card.get("id", ""))
		table["order:" + id] = orders.portrait_center(id) + orders.position
		table["card:" + id] = orders.card_rect(id).get_center() + orders.position
	table["order:default"] = table.get("order:default", Vector2(540.0, 300.0))
	if not orders.cards.is_empty():
		var first := String((orders.cards[0] as Dictionary).get("id", ""))
		table["order:default"] = table.get("order:" + first, Vector2(540.0, 300.0))
	var coin_local: Vector2 = hud.counter_center("coin")
	var star_local: Vector2 = hud.counter_center("star")
	var gem_local: Vector2 = hud.counter_center("gem")
	# The HUD is scaled down to make room for the §20.5 shop button, so its local
	# anchors reach page space through the same scale.
	table["hud:coin"] = coin_local * hud.scale + hud.position
	table["hud:star"] = star_local * hud.scale + hud.position
	table["hud:gem"] = gem_local * hud.scale + hud.position
	fly.set_anchors(table)
	fly.set_clock(_clock)


# --------------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	var type := String(ev.get("type", ""))
	var channel := String(ev.get("channel", ""))
	view_events[channel + ":" + type] = int(view_events.get(channel + ":" + type, 0)) + 1
	if channel == "sim":
		_sync_from_sim()
	elif type == "select":
		var payload := _as_dict(ev.get("payload", {}))
		var cell := _to_cell(payload.get("slot", null))
		if cell.x >= 0:
			_selected = cell
			board.apply_state({"selected": _to_array(_selected),
					"completed": _completed_cells(evaluator.sim.snapshot())})
	fly.play_event(_with_hue(ev))


## Item flights borrow the mission item's hue, so the thing flying to the card
## looks like the chip that was consumed. Presentation only: the event the sim
## received is untouched (the evaluator copied nothing).
func _with_hue(ev: Dictionary) -> Dictionary:
	var type := String(ev.get("type", ""))
	if type != "deliver" and type != "order_claim":
		return ev
	var out := ev.duplicate(true)
	var payload := _as_dict(out.get("payload", {}))
	payload["hue"] = _mission_hue(String(payload.get("order", "")))
	out["payload"] = payload
	return out


func _mission_hue(order_id: String) -> String:
	for card in orders.cards:
		if String(card.get("id", "")) != order_id:
			continue
		var items: Array = card.get("mission", [])
		if not items.is_empty():
			var hue: Color = items[0].get("hue", Color.WHITE)
			return hue.to_html(false)
	return ""


func _process(delta: float) -> void:
	if _freeze or evaluator == null:
		return
	if not _autoplay:
		board.set_clock(_clock)
		fly.set_clock(_clock)
		return
	_clock += delta
	while evaluator.cursor < evaluator.events.size():
		var ev: Dictionary = evaluator.events[evaluator.cursor]
		if float(ev.get("at", 0.0)) > _clock:
			break
		_note_sim_result(evaluator.step())
	board.set_clock(_clock)
	fly.set_clock(_clock)


## One place for the sim's verdict: the counters stay as they were (sim_rejected /
## _last_code are part of the debug summary), and §7 item 4's prompt is raised when
## the sim says the board is full.
func _note_sim_result(report: Dictionary) -> void:
	if bool(report.get("ok", true)):
		return
	sim_rejected += 1
	_last_code = String(report.get("code", ""))
	if _last_code == "SIM_BOARD_FULL":
		board.show_toast(_board_full_text(), TOAST_SECONDS)


## board.full from the project locale (meta.locale), falling back to the key and
## then to plain English so the prompt is never empty.
func _board_full_text() -> String:
	var text := _locale_text("board.full")
	if text.is_empty():
		text = "Board full"
	return text


func _locale_text(key: String) -> String:
	var project: Dictionary = _as_dict(model.project) if model != null else {}
	var locales := _as_dict(project.get("locales", {}))
	if locales.is_empty():
		return ""
	var locale := String(_as_dict(project.get("meta", {})).get("locale", "zh"))
	var table := _as_dict(locales.get(locale, {}))
	if table.is_empty():
		table = _as_dict(locales.get("en", {}))
	var value = table.get(key, "")
	if typeof(value) != TYPE_STRING:
		return ""
	return String(value)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().quit(0)


func debug_summary() -> String:
	return "game level=%d/%s events=%d clock=%.2f selected=%s sim_rejected=%d view=%d" % [
		_level_index + 1, String(_level_static.get("id", "")), _event_count, _clock,
		str(_selected), sim_rejected, view_events.size(),
	]


# -------------------------------------------------------------------- helpers

func _to_array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


func _to_cell(raw) -> Vector2i:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	return Vector2i(-1, -1)


func _as_dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
