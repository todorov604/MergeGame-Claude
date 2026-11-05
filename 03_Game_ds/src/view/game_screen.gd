extends Control
## Main screen for M0 step 4: board + HUD + order cards + presentation layer,
## driven by the shared event evaluator (no private timeline parsing here).
##
##   godot --path . --script res://tools/shot_game_screen.gd -- --t=6.2
##   godot --path .                              (F5: free mode, click to play)
##   godot --path . -- --demo                    (autoplay preview of the timeline)
##   godot --path . -- --theme=themes/pet_shop   (data-only re-skin)
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
const TakeIo := preload("res://src/core/take_io.gd")
const FreeMode := preload("res://src/core/free_mode.gd")
const CompletedCells := preload("res://src/core/completed_cells.gd")
## Free-mode takes land in output/mov/ (gitignored): `take_<stamp>.take.json`
## next to the film it produced, `take_<stamp>.mp4`.
const MOV_DIR := "res://output/mov"
const TAKE_FPS := 60
## White 3D glove cursor (北京Icon 资产汇总 · 棋盘界面拆解/手指.png, processed to a
## 256x256 transparent PNG). The hotspot is the fingertip and is stored as a ratio of
## the source square, so the OS cursor, the window overlay and the film all agree for
## any source size.
const CURSOR_ID := "ui_cursor_hand"
const CURSOR_TEXTURE := "res://assets/ui/cursor_hand.png"
const PAGE := Vector2(1080.0, 1920.0)
## Interactive window size. The design surface stays 1080x1920 (project.godot
## viewport_width/height, stretch canvas_items+keep); only the *real window* is
## halved so F5 fits a 1080p desktop. This is applied at runtime from this scene on
## purpose: `window/size/window_width_override` in project.godot would also shrink
## the root viewport of Movie Maker takes (measured: AVI 540x960), which trips
## render.sh's 1080x1920 gate. The movie scene never loads this script, and
## shot_*.gd render into their own 1080x1920 SubViewports, so evidence is untouched.
## Override per run: `-- --window=native` (engine default) or `-- --window=648x1152`.
const PREVIEW_WINDOW := Vector2i(540, 960)
const BOARD_RECT := Rect2(BoardView.BOARD_ORIGIN, BoardView.BOARD_SIZE)
const LAYOUT_BG_BOTTOM := FilmLayout.LAYOUT_BG_BOTTOM
const LAYOUT_BG_TOP := FilmLayout.LAYOUT_BG_TOP
const LAYOUT_PART1 := FilmLayout.LAYOUT_PART1
const LAYOUT_PART2 := FilmLayout.LAYOUT_PART2
const LAYOUT_ITEMS := FilmLayout.LAYOUT_ITEMS
const FONT_DISPLAY_BOLD := FilmLayout.FONT_DISPLAY_BOLD
const FONT_DISPLAY_REGULAR := FilmLayout.FONT_DISPLAY_REGULAR
const FONT_DISPLAY_NUM := FilmLayout.FONT_DISPLAY_NUM
## Third bottom-bar label (reward count on the green coin button). Value + font both
## live in the film's table so a preview shot and a delivered frame agree.
const BAR_COIN_REWARD := FilmLayout.BAR_COIN_REWARD
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
	"money_bg", "part1", "part2", "items", "bar_board", "reminder", "coin_reward", "line",
	"exit", "bag", "shop", "energy_bar", "coin_bar", "gem_bar",
	"char_waitress", "char_technician", "char_customer", "char_police", "char_blonde", "char_racer", "char_manager", "char_glasses", "char_worker",
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
	## Standalone customer portraits are full busts (330x454 for the blonde), so they sit
	## a bit lower and narrower than the baked head crop.
	## Portraits keep a fixed height; their width follows the art's aspect, and the
	## order card borrows that width so the two read as one block.
	const ORDER_BAND_Y := 210.0
	const PORTRAIT_TOP := 18.0
	const PORTRAIT_HEIGHT := 394.0
	const PORTRAIT_CENTER_LEFT := 393.0
	const PORTRAIT_CENTER_RIGHT := 800.0

	func _portrait_rect(texture: Texture2D, center_x: float) -> Rect2:
		var w := PORTRAIT_HEIGHT * (texture.get_width() / maxf(texture.get_height(), 1.0))
		return Rect2(center_x - w * 0.5, PORTRAIT_TOP, w, PORTRAIT_HEIGHT)

	func _portrait_center_for(character: String) -> float:
		return PORTRAIT_CENTER_RIGHT if character == "char_02" else PORTRAIT_CENTER_LEFT

	func _portrait_for(character: String) -> Texture2D:
		var key := "char_glasses" if character == "char_02" else "char_blonde"
		return host._ui(key)
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
		# 2026-11-05: each portrait is its own texture, so only the characters that
		# actually own an order in this level are drawn (a level with one order shows
		# one character; no order list at all keeps both, as before).
		var used := {}
		var orders_raw = snap.get("orders", [])
		if typeof(orders_raw) == TYPE_ARRAY:
			for raw in orders_raw:
				if typeof(raw) == TYPE_DICTIONARY:
					used[String((raw as Dictionary).get("character", ""))] = true
		if used.is_empty() or used.has("char_01"):
			# 2026-11-05: level 1 uses the standalone blonde customer art (05_blonde),
			# so the baked part1 sheet (which carries the +100 badges) is only a fallback.
			var blonde: Texture2D = host._ui("char_blonde")
			if blonde != null:
				draw_ui_fit("char_blonde", _portrait_rect(blonde, PORTRAIT_CENTER_LEFT))
			else:
				draw_ui_region("part1", PART1_CHAR_SRC, PART1_CHAR_RECT)
		if used.is_empty() or used.has("char_02"):
			# 2026-11-05: level 2 uses 08_glasses (char_glasses) instead of the baked part2.
			var glasses: Texture2D = host._ui("char_glasses")
			if glasses != null:
				draw_ui_fit("char_glasses", _portrait_rect(glasses, PORTRAIT_CENTER_RIGHT))
			else:
				draw_ui_region("part2", PART2_CHAR_SRC, PART2_CHAR_RECT)
		_sync_card_anchors(used)
		_draw_topbar(snap)
		_draw_bottom_bar(snap)

	## Card anchors in order-band local space (the panel sits at ORDER_BAND_Y).
	func _sync_card_anchors(used: Dictionary) -> void:
		if host.orders == null:
			return
		var rows: Array = []
		var orders_raw = host._snapshot().get("orders", [])
		if typeof(orders_raw) == TYPE_ARRAY:
			for raw in orders_raw:
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var who := String((raw as Dictionary).get("character", ""))
				if not used.is_empty() and not used.has(who):
					continue
				var tex := _portrait_for(who)
				var width := 286.0
				if tex != null:
					width = PORTRAIT_HEIGHT * (tex.get_width() / maxf(tex.get_height(), 1.0))
				rows.append({
					"center": _portrait_center_for(who),
					"bottom": PORTRAIT_TOP + PORTRAIT_HEIGHT - ORDER_BAND_Y,
					"width": width,
				})
		host.orders.set_card_anchors(rows)

	func _draw_topbar(snap: Dictionary) -> void:
		var values: Dictionary = host._hud_values(snap)
		# The HUD (hud_view.gd) keeps its own pill rects; the chrome paints the §20.5
		# plates underneath them instead of moving its numbers around, and the
		# transparent pill palette in the screen leaves the fills to this layer.
		# 2026-11-05: the pills are real bar art now; the star counter is gone.
		var bars := {"energy": "energy_bar", "coin": "coin_bar", "gem": "gem_bar"}
		for key in bars.keys():
			var bar_rect: Rect2 = host._hud_pill_page(String(key))
			if not draw_ui_fit(String(bars[key]), bar_rect):
				rounded(bar_rect, 22, Color(1, 1, 1, 0.82))
		var level_rect: Rect2 = host._hud_pill_page("level")
		var badge_drawn := draw_ui_fit("level_badge_bg", level_rect)
		badge_drawn = draw_ui_fit("level_badge", level_rect) or badge_drawn
		if not badge_drawn:
			rounded(level_rect, 22, Color("#5B8DEF"))
		# 2026-11-05: the old money_bg plates are gone — each bar art carries its own
		# icon and plus button, and the star counter was removed.
		# 2026-11-05: the hourglass icon next to the shop is gone (operator request).
		# Digits live here in chrome mode (hud_view is hidden): level inside the badge,
		# the four counters inside their pills, mm:ss under the energy timer.
		var level_font: Font = host._font_display_bold
		if level_font == null:
			level_font = host._font
		text_center_font(level_font, level_rect.grow(-6.0), str(int(values.get("level", 1))), 40,
				Color(1, 1, 1, 0.98))
		# 2026-11-05: numbers sit centred and bold inside each bar; the energy bar also
		# carries a 30-minute countdown pressed onto its top edge.
		var num_color := Color("#3B5C8F")
		var energy_rect: Rect2 = host._hud_pill_page("energy")
		text_center_font(level_font, energy_rect, str(int(values.get("energy", 0))), 40, num_color)
		var clock: String = host._mmss(host._energy_countdown())
		var clock_rect := Rect2(energy_rect.position.x, energy_rect.position.y - 8.0,
				energy_rect.size.x, 26.0)
		for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
			text_center_font(level_font, Rect2(clock_rect.position + offset, clock_rect.size),
					clock, 22, Color(0.12, 0.22, 0.40, 0.85))
		text_center_font(level_font, clock_rect, clock, 22, Color(1.0, 1.0, 1.0))
		for key3 in ["coin", "gem"]:
			var counter_rect: Rect2 = host._hud_pill_page(key3)
			text_center_font(level_font, counter_rect, str(int(values.get(key3, 0))), 40, num_color)
		if not draw_ui_fit("shop", LAYOUT_SHOP):
			rounded(LAYOUT_SHOP, 30, Color("#5B8DEF"))
			draw_rect(Rect2(LAYOUT_SHOP.position + Vector2(26.0, 34.0),
					Vector2(LAYOUT_SHOP.size.x - 52.0, 46.0)), Color(1, 1, 1, 0.85), true)

	const BAR_TITLE := FilmLayout.BAR_TITLE
	const BAR_SUBTITLE := FilmLayout.BAR_SUBTITLE
	const BAR_COIN_REWARD := FilmLayout.BAR_COIN_REWARD
	const FONT_DISPLAY_NUM := FilmLayout.FONT_DISPLAY_NUM
	# 2026-11-05 底栏版式：几何/文案/颜色全部读成片表，两端口径一致。
	const BAR_ICON_OFFSET := FilmLayout.BAR_ICON_OFFSET
	const BAR_ICON_SIZE := FilmLayout.BAR_ICON_SIZE
	const BAR_TITLE_OFFSET := FilmLayout.BAR_TITLE_OFFSET
	const BAR_TITLE_SIZE := FilmLayout.BAR_TITLE_SIZE
	const BAR_SUB_OFFSET := FilmLayout.BAR_SUB_OFFSET
	const BAR_SUB_SIZE := FilmLayout.BAR_SUB_SIZE
	const BAR_LINE_OFFSET_Y := FilmLayout.BAR_LINE_OFFSET_Y
	const BAR_LINE_H := FilmLayout.BAR_LINE_H
	const BAR_LINE_GAP := FilmLayout.BAR_LINE_GAP
	const BAR_LINE_COLOR := FilmLayout.BAR_LINE_COLOR
	const BAR_COIN_OFFSET_Y := FilmLayout.BAR_COIN_OFFSET_Y
	const BAR_BUY := FilmLayout.BAR_BUY
	const BAG_GROW := FilmLayout.BAG_GROW
	const BAR_BUY_OFFSET_Y := FilmLayout.BAR_BUY_OFFSET_Y
	const BAR_BUY_SIZE_Y := FilmLayout.BAR_BUY_SIZE_Y
	const BAR_BUY_COLOR := FilmLayout.BAR_BUY_COLOR

	func _draw_bottom_bar(snap: Dictionary) -> void:
		# 2026-11-05: layered bar instead of the flattened PSD slice.
		# 1) 任务背景板 (9-sliced)  2) 提醒 icon  3) 奖励金币 button  + labels.
		if not draw_plate("bar_board", LAYOUT_ITEMS, 28.0):
			if not draw_ui_stretch("items", LAYOUT_ITEMS):
				rounded(LAYOUT_ITEMS, 24, Color(1, 1, 1, 0.92))
		var coin_size := 124.0
		var coin_rect := Rect2(
				LAYOUT_ITEMS.position.x + LAYOUT_ITEMS.size.x - 24.0 - coin_size,
				LAYOUT_ITEMS.position.y + BAR_COIN_OFFSET_Y,
				coin_size, coin_size)
		# ① ⓘ 上移：顶部与标题同高。
		draw_ui_fit("reminder", Rect2(LAYOUT_ITEMS.position + BAR_ICON_OFFSET, BAR_ICON_SIZE))
		# ② label1（标题）。
		text_left_font(host._font_display_bold,
				Rect2(LAYOUT_ITEMS.position + BAR_TITLE_OFFSET, BAR_TITLE_SIZE),
				BAR_TITLE, 38, Color("#2E4157"))
		# ③ 分隔线：common_line 10×4 白色，调制到参考图取样色 #C4D7E2。
		var line_left: float = LAYOUT_ITEMS.position.x + BAR_TITLE_OFFSET.x
		var line_rect := Rect2(line_left, LAYOUT_ITEMS.position.y + BAR_LINE_OFFSET_Y,
				maxf(coin_rect.position.x - BAR_LINE_GAP - line_left, 0.0), BAR_LINE_H)
		if not draw_ui_tint("line", line_rect, BAR_LINE_COLOR):
			rounded(line_rect, 2, BAR_LINE_COLOR)
		# ④ label2 左移：ⓘ 下方左缘。
		text_left_font(host._font_display_regular,
				Rect2(LAYOUT_ITEMS.position + BAR_SUB_OFFSET, BAR_SUB_SIZE),
				BAR_SUBTITLE, 28, Color("#4B6076"))
		# ⑤ 金币按钮下移，上方放 "Buy" 标题。
		draw_ui_fit("coin_reward", coin_rect)
		text_center_font(host._font_display_num,
				Rect2(coin_rect.position.x, LAYOUT_ITEMS.position.y + BAR_BUY_OFFSET_Y,
						coin_rect.size.x, BAR_BUY_SIZE_Y),
				BAR_BUY, 30, BAR_BUY_COLOR)
		# ⑥ 第 3 个 label：奖励数量。
		text_center_font(host._font_display_num,
				Rect2(coin_rect.position.x, coin_rect.position.y + 76.0,
						coin_rect.size.x, 40.0),
				str(BAR_COIN_REWARD), 36, Color(1.0, 1.0, 1.0, 1.0), Color("#2F6B1E"))
		if not draw_ui_fit("exit", LAYOUT_EXIT):
			rounded(LAYOUT_EXIT.grow(-8.0), 30, Color(1, 1, 1, 0.92))
		if not draw_ui_fit("bag", LAYOUT_BAG.grow(BAG_GROW)):
			rounded(LAYOUT_BAG.grow(-6.0), 18, Color(1, 1, 1, 0.92))

	## Stretch a ui slot to the exact rect with a tint (the common_line rule).
	func draw_ui_tint(key: String, r: Rect2, tint: Color) -> bool:
		var texture: Texture2D = host._ui(key)
		if texture == null:
			return false
		draw_texture_rect(texture, r, false, tint)
		return true

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

	## 9-slice draw for a rounded plate: corners 1:1, edges/centre stretched.
	func draw_plate(key: String, r: Rect2, corner: float) -> bool:
		var texture: Texture2D = host._ui(key)
		if texture == null:
			return false
		var source := texture.get_size()
		var c := minf(corner, minf(source.x, source.y) * 0.5)
		if c <= 0.0:
			draw_texture_rect(texture, r, false)
			return true
		var inner_w := maxf(r.size.x - c * 2.0, 0.0)
		var inner_h := maxf(r.size.y - c * 2.0, 0.0)
		var src_w := source.x - c * 2.0
		var src_h := source.y - c * 2.0
		draw_texture_rect_region(texture, Rect2(r.position.x, r.position.y, c, c), Rect2(0, 0, c, c))
		draw_texture_rect_region(texture, Rect2(r.end.x - c, r.position.y, c, c), Rect2(source.x - c, 0, c, c))
		draw_texture_rect_region(texture, Rect2(r.position.x, r.end.y - c, c, c), Rect2(0, source.y - c, c, c))
		draw_texture_rect_region(texture, Rect2(r.end.x - c, r.end.y - c, c, c),
				Rect2(source.x - c, source.y - c, c, c))
		draw_texture_rect_region(texture, Rect2(r.position.x + c, r.position.y, inner_w, c),
				Rect2(c, 0, src_w, c))
		draw_texture_rect_region(texture, Rect2(r.position.x + c, r.end.y - c, inner_w, c),
				Rect2(c, source.y - c, src_w, c))
		draw_texture_rect_region(texture, Rect2(r.position.x, r.position.y + c, c, inner_h),
				Rect2(0, c, c, src_h))
		draw_texture_rect_region(texture, Rect2(r.end.x - c, r.position.y + c, c, inner_h),
				Rect2(source.x - c, c, c, src_h))
		draw_texture_rect_region(texture, Rect2(r.position.x + c, r.position.y + c, inner_w, inner_h),
				Rect2(c, c, src_w, src_h))
		return true

	func text_left_font(font: Font, r: Rect2, text: String, size_px: int, color: Color) -> void:
		if font == null or text.is_empty():
			return
		var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size_px) * 0.36)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	func text_left(r: Rect2, text: String, size_px: int, color: Color) -> void:
		if host._font == null or text.is_empty():
			return
		var baseline := r.position + Vector2(0.0, r.size.y * 0.5 + float(size_px) * 0.36)
		draw_string(host._font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	## Centred label with an optional outline, for text on top of art (the reward
	## count on the green coin button). Mirrors movie_scene._text_center_font.
	func text_center_font(font: Font, r: Rect2, text: String, size_px: int, color: Color,
			outline_color: Color = Color(0, 0, 0, 0)) -> void:
		if font == null or text.is_empty():
			return
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var baseline := r.position + Vector2((r.size.x - width) * 0.5, r.size.y * 0.5 + float(size_px) * 0.36)
		if outline_color.a > 0.0:
			draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
					int(maxf(2.0, float(size_px) * 0.16)), outline_color)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	func text_center(r: Rect2, text: String, size_px: int, color: Color) -> void:
		if host._font == null or text.is_empty():
			return
		var width: float = host._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var baseline := r.position + Vector2((r.size.x - width) * 0.5, r.size.y * 0.5 + float(size_px) * 0.36)
		draw_string(host._font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

## The in-window hand. Separate Control on purpose: it must paint above the HUD, the
## order cards and the fly layer, and it must not swallow clicks (mouse_filter is
## IGNORE, the screen itself owns input).
class Cursor extends Control:
	## Fingertip position as a fraction of the square texture, plus the drawn size in
	## page pixels. Ratios keep this correct if the cursor art is replaced again.
	const HOTSPOT := Vector2(0.135, 0.004)
	const SIZE := 96.0
	const PRESS_SECONDS := 0.10
	const PRESS_SCALE := 0.92

	var host = null

	func _draw() -> void:
		if host == null or host._cursor_tex == null:
			return
		if host._freeze or not host._free_mode:
			return
		var point: Vector2 = host.get_local_mouse_position()
		var press := 1.0
		if host._clock - float(host._last_click_at) <= PRESS_SECONDS:
			press = PRESS_SCALE
		var size := Vector2(SIZE, SIZE) * press
		draw_texture_rect(host._cursor_tex, Rect2(point - HOTSPOT * size, size), false)


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
var _font_display_bold: Font = null
var _font_display_regular: Font = null
var _font_display_num: Font = null

var _clock: float = 0.0
var _seed: int = DEFAULT_SEED
var _autoplay: bool = false
var _freeze: bool = false
var _t_target: float = -1.0
var _selected := Vector2i(-1, -1)
var _level_index: int = 0
var _level_static: Dictionary = {}
var _end_time: float = 0.0
var _event_count: int = 0
var _last_code: String = ""
var _preview_window: Vector2i = PREVIEW_WINDOW
var _preview_window_enabled: bool = true
## F5 default is free mode (the player clicks); `-- --demo` replays the sample
## timeline instead. `_autoplay` keeps its old meaning: drain evaluator events.
var _free_mode: bool = true
var _cursor_tex: Texture2D = null
var _recording: bool = false
var _rec_start: float = 0.0
var _rec_cursor: Array = []
var _rec_clicks: Array = []
var _rec_events: Array = []
var _rec_last: Vector2 = Vector2(-1.0e9, -1.0e9)
var _take_path: String = ""
var _cursor_layer = null
var _last_click_at: float = -1000.0
## 2026-11-05: a finished level holds for 0.5 s (so the confirm badge is readable)
## before the next level is applied. -1 means "not scheduled".
const LEVEL_NEXT_DELAY := 1.0
var _level_next_at: float = -1.0
## Last whole second the chrome painted; drives the per-second countdown repaint.
var _last_chrome_second: int = -1
## Gesture state: press -> (move > DRAG_THRESHOLD) drag -> release. A press without
## movement is still a click, so both interaction styles coexist.
const DRAG_THRESHOLD := 10.0
var _pressing := false
var _dragging := false
var _press_point := Vector2.ZERO
var _press_cell := Vector2i(-1, -1)
var _drag_from := Vector2i(-1, -1)
var _drag_grab := Vector2.ZERO
## A generator tap fires on press, so moving the pointer out of the cell afterwards
## cannot cancel it; the matching release must not fire a second click.
var _press_tapped := false
## `--no-render` records the take without starting the film (debug / test runs).
var _auto_render: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = PAGE
	_parse_args()
	_fit_preview_window()

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
	_font_display_bold = _load_dynamic_font(FONT_DISPLAY_BOLD)
	_font_display_regular = _load_dynamic_font(FONT_DISPLAY_REGULAR)
	_font_display_num = _load_dynamic_font(FONT_DISPLAY_NUM)
	# §20.5 layout art, resolved once before the first paint (textures are cached by
	# ThemeLoader.texture_for, so no frame touches the disk).
	_resolve_ui_art()
	_setup_cursor()

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
	orders.set_asset_theme(theme_loader, model.project)
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

	# Topmost layer: the hand has to paint over every panel and card.
	_cursor_layer = Cursor.new()
	_cursor_layer.host = self
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.position = Vector2.ZERO
	_cursor_layer.size = PAGE
	add_child(_cursor_layer)

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
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
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
	print("[game] freeze=%s autoplay=%s free_mode=%s rec=%s clock=%.2f t=%.2f" % [
		str(_freeze), str(_autoplay), str(_free_mode), str(_recording), _clock, _t_target,
	])


# ------------------------------------------------------------------- arguments

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--demo" or text == "--autoplay":
			_autoplay = true
			_free_mode = false
		elif text == "--no-autoplay":
			_autoplay = false
			_free_mode = true
		elif text.begins_with("--t="):
			_freeze = true
			_t_target = maxf(0.0, float(text.substr(4)))
		elif text.begins_with("--theme="):
			theme_name = text.substr(8)
		elif text.begins_with("--seed="):
			_seed = int(text.substr(7))
		elif text == "--allow-placeholders":
			allow_placeholders = true
		elif text == "--no-render":
			_auto_render = false
		elif text == "--window=native":
			_preview_window_enabled = false
		elif text.begins_with("--window="):
			var parts := text.substr(9).split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				var want := Vector2i(int(parts[0]), int(parts[1]))
				if want.x > 0 and want.y > 0:
					_preview_window = want


## Halve the real window for interactive runs. No-op under --headless (tests) and
## when the caller asked for the native size; never touches the viewport size, so
## every 1080x1920 coordinate in this screen and in the film stays valid.
func _fit_preview_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _preview_window_enabled:
		print("[game] preview window=native (engine default)")
		return
	DisplayServer.window_set_size(_preview_window)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(usable.position + (usable.size - _preview_window) / 2)
	print("[game] preview window=%dx%d design=%dx%d scale=%.2f screen=%dx%d" % [
		_preview_window.x, _preview_window.y, int(PAGE.x), int(PAGE.y),
		float(_preview_window.x) / PAGE.x, usable.size.x, usable.size.y,
	])


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
## 30-minute energy refill countdown, one second per tick, wrapping for the preview.
const ENERGY_CYCLE := 1800


func _energy_countdown() -> int:
	var elapsed := int(floor(_clock)) % ENERGY_CYCLE
	return ENERGY_CYCLE - elapsed


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


## User-supplied display fonts live under res://font/源字体 (not assets/): they are
## loaded straight off disk so no import cache is needed and the big TTFs are not
## duplicated into the payload folder.
func _load_dynamic_font(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return null
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		return null
	return file


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
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
	hud.build_from_hud(_as_dict(snap.get("hud", {})))
	orders.sync_orders(_as_array(snap.get("orders", [])))
	# 2026-11-05: the chrome draws the character portraits from the order list, so it
	# must repaint whenever the snapshot changes — otherwise the old level's character
	# stays on screen after a level switch.
	if chrome != null:
		chrome.queue_redraw()
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
	return CompletedCells.from_snapshot(snap)


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
	_tick_level_next()
	# The chrome draws the energy countdown, so it has to repaint when the second
	# changes — otherwise the number only moves when a click triggers _sync_from_sim.
	var second := int(floor(_clock))
	if second != _last_chrome_second:
		_last_chrome_second = second
		if chrome != null:
			chrome.queue_redraw()


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
	# The clock always runs: free mode needs it for the toast/fly animation, and the
	# sim needs a real `at` for cooldowns. Only `--demo` drains the timeline.
	_clock += delta
	if board != null and board.has_method("set_ice_elapsed"):
		board.set_ice_elapsed(_clock)
	if _autoplay:
		while evaluator.cursor < evaluator.events.size():
			var ev: Dictionary = evaluator.events[evaluator.cursor]
			if float(ev.get("at", 0.0)) > _clock:
				break
			_note_sim_result(evaluator.step())
	if _recording:
		_sample_cursor()
	if _cursor_layer != null:
		_cursor_layer.queue_redraw()
	board.set_clock(_clock)
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
	fly.set_clock(_clock)
	_tick_level_next()
	# The chrome draws the energy countdown, so it has to repaint when the second
	# changes — otherwise the number only moves when a click triggers _sync_from_sim.
	var second := int(floor(_clock))
	if second != _last_chrome_second:
		_last_chrome_second = second
		if chrome != null:
			chrome.queue_redraw()


## A completed level waits LEVEL_NEXT_DELAY before advancing; the scheduled command is
## applied through _apply_free so the take replays it at the same moment.
func _tick_level_next() -> void:
	if evaluator == null or evaluator.sim == null:
		return
	if not bool(evaluator.sim.level_complete_pending):
		_level_next_at = -1.0
		return
	if _level_next_at < 0.0:
		_level_next_at = _clock + LEVEL_NEXT_DELAY
		return
	if _clock < _level_next_at:
		return
	_level_next_at = -1.0
	var result: Dictionary = _apply_free("level_next", {})
	if not bool(result.get("ok", false)):
		# No next level: stay put instead of retrying every frame.
		_level_next_at = -1.0


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
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			get_tree().quit(0)
			return
		if key_event.keycode == KEY_R and _free_mode and not _freeze:
			# R = record: first press restarts the level clean and starts a take,
			# second press writes output/take_<stamp>.json for render.sh.
			if _recording:
				_stop_recording()
			else:
				_start_recording()
			return
	# High-rate motion events (typically 125-1000 Hz) make the recorded path smoother
	# than a per-frame sample; TakeIo stores time-ordered points, the film interpolates.
	if event is InputEventMouseMotion and _recording:
		_sample_cursor()
	if not _free_mode or _freeze:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_begin_press(mouse.position)
		else:
			_end_press(mouse.position)
	elif event is InputEventMouseMotion and _pressing:
		_maybe_start_drag(event.position)
		_update_drag(event.position)


# ------------------------------------------------------------------ free mode

## Press starts either a click or a drag. Nothing is applied until release, so a
## gesture never both selects and merges by accident.
func _begin_press(point: Vector2) -> void:
	_press_point = point
	_press_cell = _cell_at(_press_point)
	_pressing = true
	_dragging = false
	_press_tapped = false
	_drag_from = Vector2i(-1, -1)
	# 2026-11-05: a generator spawns on a plain click and moves on a drag, so the spawn
	# can no longer fire on press (a press that crosses DRAG_THRESHOLD is a move).


## A press on a chip that moves more than DRAG_THRESHOLD becomes a drag: the chip and
## its white frame follow the pointer (board_view renders both), selection is dropped.
func _maybe_start_drag(point: Vector2) -> void:
	if not _pressing or _dragging:
		return
	if _press_point.distance_to(point) < DRAG_THRESHOLD:
		return
	if evaluator == null or evaluator.sim == null or evaluator.sim.board == null:
		return
	if _press_cell.x < 0 or not evaluator.sim.board.has_item(_press_cell):
		return
	var item: Dictionary = evaluator.sim.board.item(_press_cell)
	var entity_id := String(item.get("entity", ""))
	# 2026-11-05: generators are draggable too — releasing on a free cell moves them.
	var kind := String(model.entity(entity_id).get("kind", ""))
	if kind != "chip" and kind != "generator":
		return
	_dragging = true
	_drag_from = _press_cell
	var centre: Vector2 = board.cell_rect(_drag_from.x, _drag_from.y).get_center()
	_drag_grab = centre - _press_point
	_selected = Vector2i(-1, -1)
	_sync_from_sim()
	board.set_drag_state({"from": _drag_from, "pos": centre})


func _update_drag(point: Vector2) -> void:
	if not _dragging:
		return
	board.set_drag_state({"from": _drag_from, "pos": point + _drag_grab})


## Release: a drag either merges (same entity+level) or cancels; a press without
## movement stays the old click semantics (select / tap / claim / next).
func _end_press(release_point: Vector2) -> void:
	if not _pressing:
		return
	if _press_tapped:
		_press_tapped = false
		_pressing = false
		return
	var point := release_point
	if _dragging:
		var to := _cell_at(point)
		var action: Dictionary = FreeMode.drag_action(_drag_from, to, evaluator.sim, model,
				Vector2i(-1, -1))
		board.set_drag_state({})
		_dragging = false
		var from := _drag_from
		_drag_from = Vector2i(-1, -1)
		var kind := String(action.get("kind", ""))
		if kind == FreeMode.ACTION_MERGE or kind == FreeMode.ACTION_SWAP \
				or kind == FreeMode.ACTION_MOVE:
			_last_click_at = _clock
			var event_type := "drag" if kind == FreeMode.ACTION_MERGE else "swap"
			if kind == FreeMode.ACTION_MOVE:
				event_type = "move"
			var result: Dictionary = _apply_free(event_type, action.get("payload", {}))
			if bool(result.get("ok", false)):
				# merge pops (0.4 s up/down), a move/swap lands with a short shrink
				if kind != FreeMode.ACTION_MOVE:
					board.pulse(to, "merge" if kind == FreeMode.ACTION_MERGE else "settle", _clock)
			print("[game] drag %s %s -> %s ok=%s" % [event_type, str(from), str(to),
					str(result.get("ok", false))])
			_record_click(point, {"kind": event_type, "ok": bool(result.get("ok", false)),
					"cell": [to.x, to.y]})
		else:
			_sync_from_sim()
	else:
		_free_click_at(_press_point)
	_pressing = false

## One click: board first (tap a generator / select+merge a chip), then an order
## card (claim it), then "level complete → click to continue". Anything else drops
## the selection. Every click is logged for the take (so the film shows the hand
## pressing even when the click changed nothing); only accepted clicks become sim
## events, all through the same `sim.apply` the replay uses.
func _free_click() -> void:
	if evaluator == null or evaluator.sim == null:
		return
	_free_click_at(get_global_mouse_position())


## Same click, at an explicit page-space point. Split out so a headless probe can
## exercise the real click path (the window mouse position is not available there).
## Returns {"kind", "ok", "cell"} — the entry written to the take's click log.
func _free_click_at(point: Vector2) -> Dictionary:
	if evaluator == null or evaluator.sim == null:
		return {"kind": "none", "ok": false, "cell": null}
	_last_click_at = _clock
	var out := {"kind": "none", "ok": false, "cell": null}
	var cell := _cell_at(point)
	if cell.x >= 0:
		out["cell"] = [cell.x, cell.y]
		var action: Dictionary = FreeMode.board_click(cell, evaluator.sim, model, _selected)
		var kind := String(action.get("kind", ""))
		_selected = action.get("selected", _selected)
		out["kind"] = kind
		if kind == FreeMode.ACTION_TAP:
			out["ok"] = bool(_apply_free("tap", action.get("payload", {})).get("ok", false))
			if out["ok"]:
				board.start_fly(evaluator.sim.last_spawn, _clock)
		elif kind == FreeMode.ACTION_MERGE:
			out["ok"] = bool(_apply_free("merge", action.get("payload", {})).get("ok", false))
			if out["ok"]:
				board.pulse(cell, "merge", _clock)
		elif kind == FreeMode.ACTION_SELECT or kind == FreeMode.ACTION_CLEAR:
			_sync_from_sim()
			out["ok"] = true
		_record_click(point, out)
		return out
	var order_id := _order_card_at(point)
	if not order_id.is_empty():
		out["kind"] = "order_claim"
		out["ok"] = bool(_apply_free("order_claim", {"order": order_id}).get("ok", false))
		_record_click(point, out)
		return out
	if bool(evaluator.sim.level_complete_pending):
		out["kind"] = "level_next"
		out["ok"] = bool(_apply_free("level_next", {}).get("ok", false))
		_record_click(point, out)
		return out
	if _selected.x >= 0:
		_selected = Vector2i(-1, -1)
		_sync_from_sim()
	_record_click(point, out)
	return out


## Click log entry (position + what it hit + whether the sim accepted it). Recorded
## for every click while a take is running, not only for accepted ones.
func _record_click(point: Vector2, out: Dictionary) -> void:
	if not _recording:
		return
	_rec_clicks.append({
		"t": _rec_offset(),
		"x": int(round(point.x)),
		"y": int(round(point.y)),
		"type": String(out.get("kind", "")),
		"cell": out.get("cell", null),
		"ok": bool(out.get("ok", false)),
	})
	_sample_cursor(true)


## Page-space point -> board cell, or (-1,-1) outside the 983x1263 container. The
## rule itself lives in free_mode.gd; the screen only supplies BoardView's geometry.
func _cell_at(point: Vector2) -> Vector2i:
	if board == null:
		return Vector2i(-1, -1)
	return FreeMode.cell_at(point, BoardView.BOARD_ORIGIN, BoardView.BOARD_SIZE,
			int(BoardView.COLS), int(BoardView.ROWS))


## Order id whose card covers `point` (page space), or "". Done cards are skipped:
## the sim would refuse them anyway and a dead click should not look live.
func _order_card_at(point: Vector2) -> String:
	if orders == null:
		return ""
	for raw_card in orders.cards:
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw_card
		if bool(card.get("done", false)):
			continue
		var order_id := String(card.get("id", ""))
		if order_id.is_empty():
			continue
		var rect: Rect2 = orders.card_rect(order_id)
		if Rect2(rect.position + orders.position, rect.size).has_point(point):
			return order_id
	return ""


## The only write path for a free-mode click: sim verdict -> views -> optional
## take record. `at` is take time while recording (0-based) and scene clock
## otherwise, so a take replays from its own first frame.
func _apply_free(type: String, payload: Dictionary) -> Dictionary:
	var sim = evaluator.sim
	if sim == null:
		return {"ok": false, "code": "SIM_NO_SIM", "note": "no sim"}
	var at := _rec_offset() if _recording else _clock
	var event := {"id": "free_%03d" % _rec_events.size(), "type": type, "at": at,
			"payload": payload}
	var result: Dictionary = sim.apply(event)
	_note_sim_result(result)
	_sync_from_sim()
	# 2026-11-05: only accepted sim commands go into the take. A click the sim
	# refused live (cooldown, blocked cell, ...) stays in the click log for the cursor
	# but must not become a timeline event, or the replay would reject it and the
	# render would stop at exit 3 with only the .avi on disk.
	if _recording and bool(result.get("ok", false)):
		_rec_events.append({"id": String(event["id"]), "at": at, "type": type,
				"channel": "sim", "payload": payload.duplicate(true)})
	return result


## Cell a click event refers to (kept for callers that only have the payload).
func _payload_cell(payload: Dictionary) -> Variant:
	if payload.has("target"):
		var target := _as_dict(payload.get("target", {}))
		if target.has("slot"):
			return target["slot"]
	if payload.has("to"):
		return payload["to"]
	if payload.has("slot"):
		return payload["slot"]
	return null


# ------------------------------------------------------------------ recording

func _rec_offset() -> float:
	return maxf(0.0, _clock - _rec_start)


func _sample_cursor(force: bool = false) -> void:
	var point := get_global_mouse_position()
	if not force and _rec_last.x > -1.0e8 and point.distance_to(_rec_last) < 0.25:
		return
	_rec_cursor.append([snappedf(_rec_offset(), 0.001), int(round(point.x)), int(round(point.y))])
	_rec_last = point


func _start_recording() -> void:
	# A take has to start from the level's pristine state, otherwise replaying it
	# from frame 0 would begin on a different board than the one that was played.
	_reset_run()
	_rec_start = _clock
	_recording = true
	_rec_cursor = []
	_rec_clicks = []
	_rec_events = []
	_rec_last = Vector2(-1.0e9, -1.0e9)
	_sample_cursor(true)
	board.show_toast("REC", TOAST_SECONDS)
	print("[game] rec start level=%s seed=%d" % [String(_level_static.get("id", "")), _seed])


## Stop = save the take AND start the render, so "play, press R, the film is in
## output/mov/" is the whole workflow. The render runs in its own headless process
## (tools/render_take.gd), which waits for the Movie Maker child and then ffmpeg;
## this window keeps running and the player never waits on a modal dialog.
func _stop_recording() -> void:
	_recording = false
	_sample_cursor(true)
	var take := TakeIo.build(_seed, TAKE_FPS, _rec_offset(), _rec_cursor, _rec_clicks,
			_rec_events, SAMPLE_PROJECT)
	var check: Dictionary = TakeIo.validate(take)
	if not bool(check.get("ok", false)):
		print("[game] take invalid: " + str(check.get("errors", [])))
		return
	var stamp := Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace("-", "").replace(":", "").replace("T", "_")
	var base := MOV_DIR + "/take_" + stamp
	_take_path = base + ".take.json"
	if not TakeIo.save(take, _take_path):
		print("[game] take save FAILED " + _take_path)
		return
	print("[game] take saved %s %s" % [_take_path, TakeIo.summary(take)])
	if not _auto_render:
		print("[game] --no-render set; film not started")
		board.show_toast("take " + _take_path.get_file(), TOAST_SECONDS)
		return
	var movie_path := base + ".mp4"
	var pid := _spawn_render(_take_path, movie_path)
	if pid > 0:
		print("[game] rendering -> %s (pid %d)" % [movie_path, pid])
		print("[game] log -> %s.log" % base)
		board.show_toast("rendering " + movie_path.get_file(), TOAST_SECONDS)
	else:
		print("[game] FAIL cannot spawn the render process; run: bash tools/render.sh --take %s" % _take_path)
		board.show_toast("render failed: see console", TOAST_SECONDS)


## Detached headless child: `godot --headless --script tools/render_take.gd`.
## Returns the child pid, or 0 when the executable cannot be spawned.
func _spawn_render(take_path: String, movie_path: String) -> int:
	var args := PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/render_take.gd",
		"--",
		"--take=" + take_path,
		"--out=" + movie_path,
	])
	return OS.create_process(OS.get_executable_path(), args)


## Fresh evaluator + board, clock back to 0: what R-recording and the film both
## assume as frame 0.
func _reset_run() -> void:
	_clock = 0.0
	_selected = Vector2i(-1, -1)
	evaluator = EventEvaluator.new()
	evaluator.setup(model, _seed, Callable(self, "_on_event"))
	evaluator.load_timeline(_as_array(model.project.get("timeline", [])))
	_sync_from_sim()
	board.set_clock(_clock)
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
	fly.set_clock(_clock)
	_tick_level_next()
	# The chrome draws the energy countdown, so it has to repaint when the second
	# changes — otherwise the number only moves when a click triggers _sync_from_sim.
	var second := int(floor(_clock))
	if second != _last_chrome_second:
		_last_chrome_second = second
		if chrome != null:
			chrome.queue_redraw()


# -------------------------------------------------------------------- cursor

## The 64x64 outline hand is drawn *inside* the window (the OS arrow is hidden), not
## installed with Input.set_custom_mouse_cursor: that path makes DisplayServer hold a
## texture RID past RenderingServer shutdown and the engine then reports a leaked
## resource at quit. Drawing it ourselves also gives the window the same press
## feedback (0.92 scale for 100 ms) that the film renders, so preview == film.
## The texture itself still goes through ThemeLoader/AssetGuard (ui_cursor_hand).
func _setup_cursor() -> void:
	if theme_loader != null:
		var loaded = theme_loader.texture_for(CURSOR_ID)
		if loaded is Texture2D:
			_cursor_tex = loaded
	if DisplayServer.get_name() == "headless":
		return
	var interactive := _free_mode and not _freeze and _cursor_tex != null
	if interactive:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	print("[game] cursor=%s drawn=%s os_hidden=%s" % [
		CURSOR_ID, str(_cursor_tex != null), str(interactive),
	])


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


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
