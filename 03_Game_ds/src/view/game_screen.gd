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
const OrderRows := preload("res://src/view/order_rows.gd")
const TopBarScene := preload("res://src/view/top_bar.gd")
const BottomBarScene := preload("res://src/view/bottom_bar.gd")
const ShopCopy := preload("res://src/core/shop_copy.gd")
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
const LAYOUT_GEM := FilmLayout.LAYOUT_GEM
## The order band sits between the money bar and the board: 210..460, i.e. above the
## 466 container top and below the y≈0..120 money bar.
const ORDER_RECT := Rect2(0.0, 210.0, 1080.0, 250.0)
## 任务带左侧的库存面板（红框那块）：底板 156、只吃自己的点击。
const Layout := preload("res://src/view/layout_shared.gd")
const STOCKPILE_RECT := Layout.STOCKPILE_RECT
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
	"stockpile_frame", "stockpile_arrows", "red_dot",
	"gem",  # 2026-11-09：钻石奖励飞行用的贴图
	"energy",  # 2026-11-09：体力（闪电）奖励飞行用的贴图
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
## Top-most layer: the chip in hand. The board hides its own copy while this is active,
## so a chip dragged onto an order card is never painted under the card plate.
class DragGhost extends Control:
	var host = null
	var _cell := Vector2i(-1, -1)
	var _pos := Vector2.ZERO
	var _texture: Texture2D = null
	var _frame: Texture2D = null
	var _started := 0.0

	func set_state(cell: Vector2i, at: Vector2, texture: Texture2D, started: float) -> void:
		_cell = cell
		_pos = at
		_texture = texture
		if host != null and host.board != null:
			_frame = host.board.drag_frame_texture()
		if _cell.x >= 0 and started != _started:
			_started = started
		visible = texture != null
		queue_redraw()

	func clear() -> void:
		_texture = null
		_cell = Vector2i(-1, -1)
		visible = false
		queue_redraw()

	func _draw() -> void:
		if _texture == null or host == null:
			return
		var scale: float = host.board.drag_scale_now() if host.board != null else 1.0
		var size: Vector2 = _texture.get_size()
		var side: float = 132.0 * scale
		draw_set_transform(_pos, 0.0, Vector2(side / maxf(size.x, 1.0), side / maxf(size.x, 1.0)))
		draw_texture_rect(_texture, Rect2(-size * 0.5, size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 2026-11-06: the white frame is part of the ghost so it covers the order card.
		if _frame != null:
			var fsize: Vector2 = _frame.get_size() * 1.14
			draw_texture_rect(_frame, Rect2(_pos - fsize * 0.5, fsize), false)


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
		# 2026-11-06: every level places its character on the left anchor, so level 2 no
		# longer jumps to the right slot.
		return PORTRAIT_CENTER_LEFT

	var _char_gone_at: float = -1.0

	## 角色跟着任务走：本关还有未完成的订单就站着，全部交付后缩小消失。
	func _character_scale() -> float:
		var alive := false
		if host.orders != null:
			for card in host.orders.cards:
				if not bool((card as Dictionary).get("done", false)):
					alive = true
					break
		if alive:
			_char_gone_at = -1.0
			return 1.0
		if _char_gone_at < 0.0:
			_char_gone_at = float(host._clock)
		var t := (float(host._clock) - _char_gone_at) / 0.35
		return clampf(1.0 - t, 0.0, 1.0)

	func _portrait_for(character: String) -> Texture2D:
		return host._ui(_portrait_key(character))

	func _portrait_key(character: String) -> String:
		# 旧数据里的 char_01/char_02 仍然映射到金发/眼镜两张图
		if character == "char_01":
			return "char_blonde"
		if character == "char_02":
			return "char_glasses"
		return "char_" + character.replace("char_", "")
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
		# 2026-11-06: every visible queue card carries its own character. No orders ->
		# nobody on screen (the baked part1 granny is never used as a fallback again).
		# 2026-11-06: portraits are drawn by the order panel now (they must shrink with
		# their card), so the chrome no longer paints them.
		_sync_card_anchors(used)
		# 2026-11-09：顶栏由 TopBar 组件绘制，这里不再画第二份。


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

	## Three bars on one row: widths follow each art's aspect at a fixed height, the
	## coin bar is centred on the page, and the two gaps are identical.
	const BAR_HEIGHT := 76.0
	const BAR_GAP := 30.0
	## Paw badge ends near x=115 and the shop starts near x=935, so the row may use 760.
	const BAR_ROW_MAX_W := 760.0
	## Hard edges: the paw badge ends near 118, the shop button starts near 928.
	const BAR_LEFT_LIMIT := 120.0
	const BAR_RIGHT_LIMIT := 926.0
	## Aspect-true widths (art size / art height), so every bar fills its rect exactly and
	## the visible gaps really are the same on both sides of the coin bar.
	const BAR_ASPECTS := {"energy": 243.0 / 90.0, "coin": 255.0 / 82.0, "gem": 246.0 / 67.0}
	const BAR_CENTER_X := 540.0
	const BAR_CENTER_Y := 58.0

	func _bar_rects() -> Dictionary:
		# Equal slot widths: the art keeps its own aspect inside (draw_ui_fit letterboxes),
		# so the three bars read as one evenly spaced row.
		# Fit the whole row into the free span between the paw badge and the shop button,
		# keeping the aspect ratios and the two gaps identical.
		var h := BAR_HEIGHT
		var wide: float = h * (float(BAR_ASPECTS["energy"]) + float(BAR_ASPECTS["coin"])
				+ float(BAR_ASPECTS["gem"])) + BAR_GAP * 2.0
		if wide > BAR_ROW_MAX_W:
			h *= BAR_ROW_MAX_W / wide
		var top := BAR_CENTER_Y - h * 0.5
		var coin_w: float = h * float(BAR_ASPECTS["coin"])
		var energy_w: float = h * float(BAR_ASPECTS["energy"])
		var gem_w: float = h * float(BAR_ASPECTS["gem"])
		var coin := Rect2(BAR_CENTER_X - coin_w * 0.5, top, coin_w, h)
		# The two side bars may not run into the paw badge or the shop button; when the
		# natural width would, the side bar is narrowed (its art keeps its aspect).
		energy_w = minf(energy_w, coin.position.x - BAR_GAP - BAR_LEFT_LIMIT)
		gem_w = minf(gem_w, BAR_RIGHT_LIMIT - coin.end.x - BAR_GAP)
		var energy := Rect2(coin.position.x - BAR_GAP - energy_w, top, energy_w, h)
		var gem := Rect2(coin.end.x + BAR_GAP, top, gem_w, h)
		return {"energy": energy, "coin": coin, "gem": gem}

	## One portrait above each of the first three queue cards, bottom-anchored to its card.
	func _draw_queue_portraits() -> void:
		if host.orders == null:
			return
		var shown := 0
		for card in host.orders.cards:
			if bool((card as Dictionary).get("done", false)):
				continue
			if shown >= 3:
				break
			shown += 1
			var cid := String((card as Dictionary).get("id", ""))
			var who := String((card as Dictionary).get("character", ""))
			var key := _portrait_key(who)
			var texture: Texture2D = host._ui(key)
			if texture == null:
				continue
			var local: Rect2 = host.orders.card_rect(cid)
			var page := Rect2(local.position + host.orders.position, local.size)
			var h := 210.0
			var w := h * (texture.get_width() / maxf(texture.get_height(), 1.0))
			var rect := Rect2(page.get_center().x - w * 0.5, page.position.y + 26.0 - h, w, h)
			draw_ui_fit(key, rect)


	func _draw_topbar(snap: Dictionary) -> void:
		var values: Dictionary = host._hud_values(snap)
		# The HUD (hud_view.gd) keeps its own pill rects; the chrome paints the §20.5
		# plates underneath them instead of moving its numbers around, and the
		# transparent pill palette in the screen leaves the fills to this layer.
		# 2026-11-05: the pills are real bar art now; the star counter is gone.
		# 2026-11-06: coin sits dead centre with equal gaps to energy and gem.
		var bar_rects := _bar_rects()
		var bars := {"energy": "energy_bar", "coin": "coin_bar", "gem": "gem_bar"}
		for key in bars.keys():
			var bar_rect: Rect2 = bar_rects[key]
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
		var energy_rect: Rect2 = bar_rects["energy"]
		text_center_font(level_font, energy_rect, str(int(values.get("energy", 0))), 40, num_color)
		var clock: String = host._mmss(host._energy_countdown())
		var clock_rect := Rect2(energy_rect.position.x, energy_rect.position.y - 8.0,
				energy_rect.size.x, 26.0)
		for offset in [Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(0.0, -1.5), Vector2(0.0, 1.5)]:
			text_center_font(level_font, Rect2(clock_rect.position + offset, clock_rect.size),
					clock, 22, Color(0.12, 0.22, 0.40, 0.85))
		text_center_font(level_font, clock_rect, clock, 22, Color(1.0, 1.0, 1.0))
		for key3 in ["coin", "gem"]:
			var counter_rect: Rect2 = bar_rects[key3]
			var shown := int(round(float(host._coin_display))) if key3 == "coin" and float(host._coin_display) >= 0.0 else int(values.get(key3, 0))
			var pop := 1.0
			if key3 == "coin":
				var since: float = float(host._clock) - float(host._coin_pop_at)
				if since >= 0.0 and since < 0.35:
					pop = 1.0 + 0.38 * sin(PI * since / 0.35)
			if pop > 1.001:
				draw_set_transform(counter_rect.get_center(), 0.0, Vector2(pop, pop))
				text_center_font(level_font, Rect2(-counter_rect.size * 0.5, counter_rect.size),
						str(shown), 40, num_color)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				text_center_font(level_font, counter_rect, str(shown), 40, num_color)
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
	const PRESS_SECONDS := TakeIo.PRESS_SECONDS
	const PRESS_SCALE := TakeIo.PRESS_SCALE

	var host = null

	func _draw() -> void:
		if host == null or host._cursor_tex == null:
			return
		if host._freeze or not host._free_mode:
			return
		var point := _canvas_point()
		# 2026-11-10：按下状态 = "拖拽中 / 鼠标按住 / 刚点过 0.22s 内"，
		# 幅度放大（0.80 + 下沉 7px），右键也能看清"下去再上来"。
		var pressed: bool = bool(host._pressing) or bool(host._dragging) 				or host._clock - float(host._last_click_at) <= PRESS_SECONDS
		var press := PRESS_SCALE if pressed else 1.0
		var dip := (7.0 if pressed else 0.0)
		var size := Vector2(SIZE, SIZE) * press
		# 涟漪画在**手之上** —— 右键交付时指针压在卡片上，
		# 画在手下面会被手和卡片盖掉，看着像"没有这个特效"。
		draw_texture_rect(host._cursor_tex,
				Rect2(point - HOTSPOT * size + Vector2(0.0, dip), size), false)
		_draw_press_ring()


	## 按下白环：与成片同一套参数（0.25s，18 -> 150px）。
	func _draw_press_ring() -> void:
		var age: float = float(host._clock) - float(host._last_click_at)
		if age < 0.0 or age > TakeIo.RING_SECONDS:
			return
		var p := age / TakeIo.RING_SECONDS
		var centre: Vector2 = host._last_click_point
		var radius := lerpf(18.0, TakeIo.RING_RADIUS, p)
		var alpha := 0.75 * (1.0 - p)
		draw_arc(centre, radius, 0.0, TAU, 48, Color(1, 1, 1, alpha), 8.0, true)
		draw_arc(centre, radius * 0.62, 0.0, TAU, 48, Color(1, 1, 1, alpha * 0.5), 4.0, true)


	## 窗口像素 -> 画布像素：viewport 拉伸下窗口 540x960、画布 1080x1920。
	func _canvas_point() -> Vector2:
		var win := Vector2(DisplayServer.window_get_size())
		var vp := get_viewport().get_visible_rect().size
		if win.x <= 0.0 or win.y <= 0.0:
			return Vector2.ZERO
		var raw: Vector2 = Vector2(DisplayServer.mouse_get_position()) \
				- Vector2(DisplayServer.window_get_position())
		return Vector2(raw.x * vp.x / win.x, raw.y * vp.y / win.y)


var board
var hud
var orders
var fly
func _board_item(cell: Vector2i) -> Dictionary:
	if evaluator == null or evaluator.sim == null or not evaluator.sim.board.has_item(cell):
		return {}
	return evaluator.sim.board.item(cell)


## Dragged chip drawn above the order cards (the board's copy is hidden meanwhile).
var ghost
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
## 2026-11-10：左键点订单卡会**整单结算**（一次把这一单的行全收掉）。操作者要求先屏蔽——
## 交付要一枚一枚来（右键棋子 / 拖到卡上 / 右键卡上任务格子），点卡不再结算。
## 想恢复把这里改回 true。
const CLICK_CARD_CLAIMS := false
var _level_index: int = 0
var _level_static: Dictionary = {}
var _end_time: float = 0.0
var _event_count: int = 0
var _last_code: String = ""
var _preview_window: Vector2i = PREVIEW_WINDOW
var _preview_window_enabled: bool = true
## Frames left to keep forcing the preview size (see _fit_preview_window).
var _window_fix_frames: int = 0
## F5 default is free mode (the player clicks); `-- --demo` replays the sample
## timeline instead. `_autoplay` keeps its old meaning: drain evaluator events.
var _free_mode: bool = true
var _cursor_tex: Texture2D = null
var _recording: bool = false
var _rec_start: float = 0.0
var _rec_cursor: Array = []
var _rec_clicks: Array = []
var _rec_events: Array = []
## 拖动轨迹：[[t, from_x, from_y, pos_x, pos_y], ...]，成片按它回放"手拖着棋子走"。
var _rec_drag: Array = []
## 2026-11-10：订单带拖拽的**真实偏移**（成片直接回放，不再靠光标猜手势）
var _rec_band: Array = []
var _rec_last: Vector2 = Vector2(-1.0e9, -1.0e9)
var _take_path: String = ""
var _cursor_layer = null
var _last_click_at: float = -1000.0
## 最近一次点击的画布坐标（按下白环画在它上面）。
var _last_click_point: Vector2 = Vector2.ZERO
## Coin-bar number pop after a reward lands.
var _coin_pop_at: float = -1000.0
## 顶栏组件（与成片共用同一实现）。
var top_bar = null
var bottom_bar = null
## 启动参数 --preview=<scale>：工程里的 window_*_override 会盖掉 --resolution，
## 所以 100% 预览必须由代码在启动后自己改窗口尺寸。
var _preview_pending: float = 0.0
## 顶栏金币显示值：交付时按飞出的金币数量分批上涨，而不是一次跳到目标。
var _coin_display: float = -1.0
var _coin_ticks: Array = []
## 顶栏钻石显示值（2026-11-09）：和金币同一套 —— 交付后钻石飞上去，数字分批涨 + 弹跳。
var _gem_display: float = -1.0
var _gem_ticks: Array = []
var _gem_pop_at: float = -1000.0
## 顶栏体力显示值（2026-11-09）：和金币/钻石同一套 tick + lerp + 弹跳。
var _energy_display: float = -1.0
var _energy_ticks: Array = []
var _energy_pop_at: float = -1000.0
## Double-click bookkeeping on a green (completed) cell: second tap claims the order.
const DOUBLE_CLICK := 0.35
var _last_cell := Vector2i(-1, -1)
## Order-queue drag: the whole row slides with the pointer, then springs back.
const ROW_DRAG_THRESHOLD := 24.0
## 拖动整排的生效区域：整条订单带 + 立绘所在的顶部区域（红框范围）。
const ROW_DRAG_AREA := Rect2(0.0, 60.0, 1080.0, 400.0)
const ROW_RUBBER := 0.55
const ROW_SPRING := 12.0
var _row_pressing := false
var _row_dragging := false
var _row_press_x: float = 0.0
var _row_dx: float = 0.0
var _last_cell_at: float = -1000.0
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
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--preview="):
			_preview_pending = float(arg.substr(10))
	# 2026-11-09：默认"玩"是 50%（540x960）；出片（--write-movie）保持 1080x1920。
	if _preview_pending <= 0.0 and not _is_movie_run():
		_preview_pending = 0.5
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
	_top_bar_setup()
	_bottom_bar_setup()
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

	ghost = DragGhost.new()
	ghost.host = self
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = Vector2.ZERO
	ghost.size = PAGE
	add_child(ghost)

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
	# A maximised / fullscreen window ignores set_size, so force windowed first.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_preview_window)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(usable.position + (usable.size - _preview_window) / 2)
	# 2026-11-06: the editor (or the OS) can restore a saved window size right after the
	# first frame, which made the preview open at 100% after a reboot. Keep re-applying
	# for a few frames until the window really is PREVIEW_WINDOW.
	_window_fix_frames = 180
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


## 把每格冰的剩余秒数推给棋盘（每帧调用；融化后该格自然消失）。
func _push_ice_countdown() -> void:
	if board == null or evaluator == null or evaluator.sim == null:
		return
	if not board.has_method("set_ice_remaining_map"):
		return
	var left := {}
	var sim = evaluator.sim
	for cell in sim.board.obstacles.keys():
		var kinds: Array = sim.board.obstacle_types(cell)
		if not kinds.has("ice"):
			continue
		left[cell] = sim.ice_remaining(cell)
	board.set_ice_remaining_map(left)
	# 2026-11-11：网/冰下压的棋子来自 JSON（`obstacle.chip`），每帧从 sim 取，不自己猜。
	board.set_trapped_chips(evaluator.sim.trapped_chips)


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
	_push_ice_countdown()
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
	hud.build_from_hud(_as_dict(snap.get("hud", {})))
	# 2026-11-06: one row builder, shared with the film (src/view/order_rows.gd).
	orders.sync_orders(OrderRows.build(snap, model))
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
			"icon": String((row as Array)[4]) if (row as Array).size() > 4 else "",
			"iconLevel": int((row as Array)[5]) if (row as Array).size() > 5 else 0,
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
	var gem_local: Vector2 = hud.counter_center("gem")
	# The HUD is scaled down to make room for the §20.5 shop button, so its local
	# anchors reach page space through the same scale.
	table["hud:coin"] = _coin_anchor(hud.counter_center("coin"))
	table["hud:gem"] = _gem_anchor(gem_local)
	table["hud:energy"] = _energy_anchor(hud.counter_center("energy"))
	fly.set_anchors(table)
	fly.set_clock(_clock)
	_tick_level_next()
	_tick_coin_pending()
	_refresh_order_ready()
	_push_stockpile()
	_tick_coin_display()
	_push_top_bar()
	if orders != null and orders.has_method("set_clock"):
		orders.set_clock(_clock)
	if orders != null and orders.has_method("is_animating") and orders.is_animating():
		# keep both layers painting while a card (and its character) shrinks away
		if chrome != null:
			chrome.queue_redraw()
	if not _row_dragging and absf(_row_dx) > 0.5 and orders != null:
		# rubber band: the row eases back to its home position in ~0.25 s at 60 fps
		_row_dx = lerpf(_row_dx, 0.0, 0.22)
		orders.set_row_offset(_row_dx)
		_record_band(_row_dx)
	elif not _row_dragging and not is_zero_approx(_row_dx) and orders != null:
		# 2026-11-10：回弹收尾必须**归零并记一行**，否则 take 最后一条是 0.4~0.6 的残余，
		# 成片会一直停在偏一点的位置。
		_row_dx = 0.0
		orders.set_row_offset(0.0)
		_record_band(0.0)
	# 2026-11-10：兜底 —— 每帧把**画面上真正用的偏移**记一次，不管是谁改的
	# （拖动 / 回弹 / 以后新增的路径），成片永远和实机同拍。
	if _recording and orders != null:
		_record_band(orders.row_offset())
	if _preview_pending > 0.0 and _window_fix_frames < 176:
		_cycle_preview(_preview_pending)
		_preview_pending = 0.0
	if _window_fix_frames > 0 and DisplayServer.get_name() != "headless":
		_window_fix_frames -= 1
		if _window_fix_frames == 179:
			print("[game] window now=%s target=%s mode=%d" % [str(DisplayServer.window_get_size()),
					str(_preview_window), DisplayServer.window_get_mode()])
		if DisplayServer.window_get_size() != _preview_window and _preview_window_enabled:
			DisplayServer.window_set_size(_preview_window)
			var usable := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(
					usable.position + (usable.size - _preview_window) / 2)
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


## Claim timeline: chip flies (0.55 s) -> coins spiral -> 1 s later the card and its
## character shrink away. Everything is scheduled, nothing pops at once.
const CLAIM_CHIP_SECONDS := 0.55
const CLAIM_COIN_DELAY := 1.0
var _coin_pending: Array = []


## Only the visual hold: the card must not flip to done before the chip lands.
func _arm_claim_hold(order_id: String) -> void:
	if orders != null:
		orders.hold_done(order_id, CLAIM_CHIP_SECONDS + CLAIM_COIN_DELAY)


## Coins fly only after a accepted claim.
## 点库存：sim 扣次数并在随机空位落一枚，棋子在页面层从面板飞过去。
func _stockpile_tap() -> bool:
	if evaluator == null or evaluator.sim == null:
		return false
	if evaluator.sim.stockpile_remaining() <= 0:
		return false
	var preview: Dictionary = evaluator.sim.stockpile_preview()
	var result: Dictionary = _apply_free("stockpile_tap", {})
	if not bool(result.get("ok", false)):
		return false
	var spawn: Dictionary = evaluator.sim.last_spawn
	if spawn.is_empty():
		return false
	var to_ref = spawn.get("to", [])
	if typeof(to_ref) != TYPE_ARRAY or (to_ref as Array).size() < 2:
		return false
	var cell := Vector2i(int((to_ref as Array)[0]), int((to_ref as Array)[1]))
	var page := Rect2(board.position + board.cell_rect(cell.x, cell.y).position,
			board.cell_rect(cell.x, cell.y).size)
	# 2026-11-06: 当成固定生成器 —— 走棋盘自己的飞行，落地之前不显示落点棋子。
	var spawn2: Dictionary = spawn.duplicate(true)
	spawn2["from_page"] = [STOCKPILE_RECT.get_center().x, STOCKPILE_RECT.get_center().y]
	board.start_fly(spawn2, _clock)
	return true


func _schedule_coin(order_id: String) -> void:
	_coin_pending.append({"id": order_id, "at": _clock + CLAIM_CHIP_SECONDS})
	var amount := _order_coin_amount(order_id)
	if amount > 0:
		_queue_coin_ticks(amount, clampi(amount / 5, 3, 8))
	var gems := _order_gem_amount(order_id)
	if gems > 0:
		_queue_gem_ticks(gems)
	var stamina := _order_energy_amount(order_id)
	if stamina > 0:
		_queue_energy_ticks(stamina)


## 订单卡底部蓝条上写的钻石数（卡片数据来自 OrderRows，实机与成片同一份）。
func _order_gem_amount(order_id: String) -> int:
	if orders == null:
		return 0
	for card in orders.cards:
		if String((card as Dictionary).get("id", "")) == order_id:
			return int((card as Dictionary).get("gem", 0))
	return 0


## 订单卡蓝条上的体力（闪电）数。
func _order_energy_amount(order_id: String) -> int:
	if orders == null:
		return 0
	for card in orders.cards:
		if String((card as Dictionary).get("id", "")) == order_id:
			return int((card as Dictionary).get("energy", 0))
	return 0


## 体力是 30~100 的量级：按每 ~10 一跳拆，最多 10 跳，和金币同一个手感。
func _queue_energy_ticks(amount: int) -> void:
	if amount <= 0:
		return
	var n: int = clampi(int(round(float(amount) / 10.0)), 3, 10)
	var start := _clock + CLAIM_CHIP_SECONDS
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		_energy_ticks.append({"at": start + gap * float(i), "amount": base + (1 if i < rest else 0)})


## 钻石数量小（1-5），按"每颗一跳"拆；跳完弹一下，和金币一个手感。
func _queue_gem_ticks(amount: int) -> void:
	if amount <= 0:
		return
	var n: int = clampi(amount, 1, 5)
	var start := _clock + CLAIM_CHIP_SECONDS
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		_gem_ticks.append({"at": start + gap * float(i), "amount": base + (1 if i < rest else 0)})


func _order_coin_amount(order_id: String) -> int:
	if orders == null:
		return 0
	for card in orders.cards:
		if String((card as Dictionary).get("id", "")) == order_id:
			return int((card as Dictionary).get("coin", 0))
	return 0


## Split a reward into one tick per flying coin: 5 coins -> +1 each, 10 coins -> +2 each.
func _queue_coin_ticks(amount: int, count: int) -> void:
	if amount <= 0:
		return
	var n: int = maxi(count, 1)
	var start := _clock + CLAIM_CHIP_SECONDS
	var gap := 0.85 / float(n)
	var base := amount / n
	var rest := amount - base * n
	for i in n:
		var step: int = base + (1 if i < rest else 0)
		_coin_ticks.append({"at": start + gap * float(i), "amount": step})


func _tick_coin_pending() -> void:
	if _coin_pending.is_empty():
		return
	var keep: Array = []
	for row in _coin_pending:
		if _clock >= float((row as Dictionary).get("at", 0.0)):
			_play_coin_reward(String((row as Dictionary).get("id", "")))
		else:
			keep.append(row)
	_coin_pending = keep


## The sim reports which obstacles a merge broke; the board animates them away.
func _play_unlocks() -> void:
	if evaluator == null or evaluator.sim == null or board == null:
		return
	for row in evaluator.sim.last_unlocks:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var cell_ref = (row as Dictionary).get("cell", [])
		if typeof(cell_ref) != TYPE_ARRAY or (cell_ref as Array).size() < 2:
			continue
		board.unlock(Vector2i(int((cell_ref as Array)[0]), int((cell_ref as Array)[1])),
				String((row as Dictionary).get("kind", "")), _clock,
				String((row as Dictionary).get("became", "")))


## The ready badge must follow the board, not a stale snapshot: after a claim eats the
## shared chip, the other cards have to lose their green check immediately.
func _top_bar_setup() -> void:
	top_bar = TopBarScene.new()
	top_bar.name = "TopBar"
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(1080.0, 150.0)
	add_child(top_bar)
	# 2026-11-09：订单带（含立绘）提到顶栏之上，立绘放大后头顶才不会被药丸挡住。
	if orders != null:
		move_child(orders, top_bar.get_index() + 1)
	top_bar.font_bold = _font_display_bold
	top_bar.font_fallback = _font
	if theme_loader != null:
		top_bar.set_asset_theme(theme_loader, model.project if model != null else {})


func _bottom_bar_setup() -> void:
	bottom_bar = BottomBarScene.new()
	bottom_bar.name = "BottomBar"
	add_child(bottom_bar)
	bottom_bar.font_bold = _font_display_bold
	bottom_bar.font_regular = _font_display_regular
	bottom_bar.font_num = _font_display_num
	if theme_loader != null:
		bottom_bar.set_asset_theme(theme_loader, model.project if model != null else {})
	# 2026-11-11：底栏文案与金币数量来自 JSON 的 shop 节点（ShopCopy 是唯一来源）。
	bottom_bar.set_state(ShopCopy.from_project(model.project if model != null else {}))


func _push_top_bar() -> void:
	if top_bar == null or evaluator == null or evaluator.sim == null:
		return
	var snap: Dictionary = evaluator.sim.snapshot()
	var hud: Dictionary = snap.get("hud", {})
	var since: float = _clock - _coin_pop_at
	var pop := 0.0
	if since >= 0.0 and since < 0.35:
		pop = 0.38 * sin(PI * since / 0.35)
	var gem_since: float = _clock - _gem_pop_at
	var gem_pop := 0.0
	if gem_since >= 0.0 and gem_since < 0.35:
		gem_pop = 0.38 * sin(PI * gem_since / 0.35)
	var energy_since: float = _clock - _energy_pop_at
	var _energy_pop := 0.0
	if energy_since >= 0.0 and energy_since < 0.35:
		_energy_pop = 0.38 * sin(PI * energy_since / 0.35)
	top_bar.set_state({
		"level": int(hud.get("level", 1)),
		"energy": int(hud.get("energy", 0)),
		"coin": int(hud.get("coin", 0)),
		"gem": int(hud.get("gem", 0)),
		"clock": _mmss(_energy_countdown()),
		"coin_display": _coin_display,
		"pop": pop,
		# 2026-11-09：钻石与金币同款 —— 显示值 + 弹跳（订单奖励落上去时用）
		"gem_display": _gem_display,
		"gem_pop": gem_pop,
		# 2026-11-09：体力同样有显示值与弹跳
		"energy_display": _energy_display,
		"energy_pop": _energy_pop,
	})


## 金币落点必须是**真正画顶栏的那个组件**给的（TopBar）：hud_view 在 chrome 模式下是
## 隐藏的，2026-11-09 之前金币正是飞向那个看不见的控件（偏右 15px、偏上 6px）。
## hud_local 是 hud_view 坐标（它被缩放到 0.8 给商店按钮腾位置），只作兜底。
func _coin_anchor(hud_local: Vector2) -> Vector2:
	if top_bar != null and top_bar.has_method("counter_center"):
		return top_bar.counter_center("coin")
	if hud == null:
		return hud_local
	return hud_local * hud.scale + hud.position


## 体力落点同理：问顶栏组件要。
func _energy_anchor(hud_local: Vector2) -> Vector2:
	if top_bar != null and top_bar.has_method("counter_center"):
		return top_bar.counter_center("energy")
	if hud == null:
		return hud_local
	return hud_local * hud.scale + hud.position


## 钻石落点同理（2026-11-09）：问了顶栏组件要，别再读那个隐藏的 hud_view。
func _gem_anchor(hud_local: Vector2) -> Vector2:
	if top_bar != null and top_bar.has_method("counter_center"):
		return top_bar.counter_center("gem")
	if hud == null:
		return hud_local
	return hud_local * hud.scale + hud.position


func _refresh_order_ready() -> void:
	if orders == null or evaluator == null or evaluator.sim == null:
		return
	if not orders.has_method("sync_orders"):
		return
	var snap: Dictionary = evaluator.sim.snapshot()
	# 2026-11-10：角标数字由面板自己从这份棋盘快照算（每帧一份，绝对不冻）。
	if orders.has_method("set_board_snapshot"):
		orders.set_board_snapshot(snap)
	orders.sync_orders(OrderRows.build(snap, model))


## 库存面板的数据管道。2026-11-06：绘制搬到 order_panel 了（成片实例化同一控件即自带），
## 这里只负责把 sim 的状态推下去 —— 启用库存就画（次数归零也画），没启用才收起来。
func _push_stockpile() -> void:
	if orders == null or evaluator == null or evaluator.sim == null:
		return
	if not orders.has_method("set_stockpile"):
		return
	var cfg: Dictionary = evaluator.sim.stockpile_config()
	if cfg.is_empty() or not bool(cfg.get("enabled", false)):
		if orders.has_method("clear_stockpile"):
			orders.clear_stockpile()
		return
	var preview: Dictionary = evaluator.sim.stockpile_preview()
	orders.set_stockpile(int(evaluator.sim.stockpile_remaining()),
			String(preview.get("entity", "")), int(preview.get("level", 0)),
			String(preview.get("kind", "generator")),
			String(cfg.get("icon", "")), int(cfg.get("iconLevel", 0)))


## Advance the displayed coin number by one tick at a time; snap when ticks run dry.
## 顶栏数值跳动：金币与钻石同一套（分批 tick + 末段 lerp 追赶 + 弹一下）。
func _tick_coin_display() -> void:
	var hud_coin := int(evaluator.sim.hud.get("coin", 0)) if evaluator != null else 0
	if _coin_display < 0.0:
		_coin_display = float(hud_coin)
		return
	if not _coin_ticks.is_empty():
		var keep: Array = []
		for row in _coin_ticks:
			if _clock >= float((row as Dictionary).get("at", 0.0)):
				_coin_display = minf(_coin_display + float((row as Dictionary).get("amount", 0)),
						float(hud_coin))
				_coin_pop_at = _clock
			else:
				keep.append(row)
		_coin_ticks = keep
		if chrome != null:
			chrome.queue_redraw()
	elif _coin_pending.is_empty() and absf(_coin_display - float(hud_coin)) > 0.01:
		# safety net: anything the ticks did not cover catches up smoothly
		_coin_display = lerpf(_coin_display, float(hud_coin), 0.25)
		if absf(_coin_display - float(hud_coin)) < 1.0:
			_coin_display = float(hud_coin)
		if chrome != null:
			chrome.queue_redraw()
	_tick_energy_display()
	_tick_gem_display()


## 体力数字：同一套 tick + 追赶 lerp。
func _tick_energy_display() -> void:
	var hud_energy := int(evaluator.sim.hud.get("energy", 0)) if evaluator != null else 0
	if _energy_display < 0.0:
		_energy_display = float(hud_energy)
		return
	if not _energy_ticks.is_empty():
		var keep: Array = []
		for row in _energy_ticks:
			if _clock >= float((row as Dictionary).get("at", 0.0)):
				_energy_display = minf(_energy_display + float((row as Dictionary).get("amount", 0)),
						float(hud_energy))
				_energy_pop_at = _clock
			else:
				keep.append(row)
		_energy_ticks = keep
	elif absf(_energy_display - float(hud_energy)) > 0.01:
		_energy_display = lerpf(_energy_display, float(hud_energy), 0.25)
		if absf(_energy_display - float(hud_energy)) < 0.5:
			_energy_display = float(hud_energy)


## 钻石数字：和金币逐字对齐的实现（tick 逐个跳 + 追赶 lerp）。
func _tick_gem_display() -> void:
	var hud_gem := int(evaluator.sim.hud.get("gem", 0)) if evaluator != null else 0
	if _gem_display < 0.0:
		_gem_display = float(hud_gem)
		return
	if not _gem_ticks.is_empty():
		var keep: Array = []
		for row in _gem_ticks:
			if _clock >= float((row as Dictionary).get("at", 0.0)):
				_gem_display = minf(_gem_display + float((row as Dictionary).get("amount", 0)),
						float(hud_gem))
				_gem_pop_at = _clock
			else:
				keep.append(row)
		_gem_ticks = keep
	elif absf(_gem_display - float(hud_gem)) > 0.01:
		_gem_display = lerpf(_gem_display, float(hud_gem), 0.25)
		if absf(_gem_display - float(hud_gem)) < 0.5:
			_gem_display = float(hud_gem)


## Reward coins: spiral from the card up to the coin bar, then pop the number.
func _play_coin_reward(order_id: String) -> void:
	if fly == null or orders == null:
		return
	var amount := 0
	for card in orders.cards:
		if String((card as Dictionary).get("id", "")) == order_id:
			amount = int((card as Dictionary).get("coin", 0))
			break
	if amount <= 0:
		return
	# 起点 = 这张卡上方"+N"药丸里的**金币图标**中心（不是卡片中心）
	var centre: Vector2 = orders.position + orders.reward_origin(order_id, "coin")
	var count := clampi(amount / 5, 3, 8)
	fly.play_event({
		"type": "coin_spiral",
		"at": _clock,
		"payload": {
			"from_point": [centre.x, centre.y],
			"amount": amount,
			"count": count,
			"texture": _ui("coin_big"),
		},
	})
	_coin_pop_at = _clock + 0.55
	_play_energy_reward(order_id)
	_play_gem_reward(order_id)


## 2026-11-09：订单卡的体力（闪电）奖励 —— 和金币同一个方向（正螺旋），飞向顶栏体力条。
func _play_energy_reward(order_id: String) -> void:
	if fly == null or orders == null:
		return
	var amount := _order_energy_amount(order_id)
	if amount <= 0:
		return
	# 起点 = 这张卡蓝条里的**闪电图标**中心
	var origin: Vector2 = orders.position + orders.reward_origin(order_id, "energy")
	fly.play_event({
		"type": "coin_spiral",
		"at": _clock + 0.06,
		"payload": {
			"from_point": [origin.x, origin.y],
			"amount": amount,
			"count": clampi(int(round(float(amount) / 10.0)), 3, 10),
			"texture": _ui("energy"),
			"anchor": "energy",
			"spin": 1.0,
		},
	})
	_energy_pop_at = _clock + 0.06 + 0.55


## 2026-11-09：订单卡的钻石奖励 —— 同一套螺旋，只是贴着钻石图标、飞向顶栏钻石条。
## 起点用卡片蓝条的中心（不是整张卡中心），落点由 fly_anim 的 "gem" 锚点决定。
func _play_gem_reward(order_id: String) -> void:
	if fly == null or orders == null:
		return
	var amount := _order_gem_amount(order_id)
	if amount <= 0:
		return
	# 起点 = 这张卡蓝条里的**钻石图标**中心（哪张卡结算就从哪张卡飞）
	var origin: Vector2 = orders.position + orders.reward_origin(order_id, "gem")
	fly.play_event({
		"type": "coin_spiral",
		"at": _clock + 0.12,
		"payload": {
			"from_point": [origin.x, origin.y],
			"amount": amount,
			"count": clampi(amount, 1, 5),
			"texture": _ui("gem"),
			"anchor": "gem",
			"spin": -1.0,   # 逆时针，和金币的顺时针岔开
		},
	})
	_gem_pop_at = _clock + 0.12 + 0.55


## The claimed chip arcs from its board cell to the order card, growing to 2.5x and
## vanishing on arrival (fly_anim's "deliver_chip" motion owns the curve).
func _play_claim_flight(order_id: String, cell: Vector2i, item: Dictionary, delay: float = 0.0) -> void:
	if fly == null:
		return
	# 2026-11-12：这一枚如果被编辑器改过图标，飞的就是改过的那张
	var tex_entity := String(item.get("icon", ""))
	var tex_level := int(item.get("level", 1))
	if tex_entity.is_empty():
		tex_entity = String(item.get("entity", ""))
	elif int(item.get("icon_level", 0)) > 0:
		tex_level = int(item.get("icon_level", 0))
	var texture: Texture2D = board.chip_texture(tex_entity, tex_level)
	if texture == null:
		return
	var card: Rect2 = orders.card_rect(order_id)
	var target: Vector2 = orders.position + card.get_center()
	# FlyAnim takes the source as a board cell and the target as the order anchor, so a
	# synthetic "deliver_chip" event carries the texture and the drop point.
	fly.play_event({
		"type": "deliver_chip",
		"at": _clock + delay,
		"payload": {
			"from": [cell.x, cell.y],
			"order": order_id,
			"to_point": [target.x, target.y],
			"texture": texture,
		},
	})


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
	# 2026-11-10：冰到点自己化掉（唯一的解锁方式）。先推进 sim，再播"扩大消失"。
	# 2026-11-10：倒计时数字每帧都推给视图（不点鼠标也要跳字）。
	_push_ice_countdown()
	if evaluator != null and evaluator.sim != null:
		var melts: Array = evaluator.sim.tick_to(_clock)
		if not melts.is_empty():
			for row in melts:
				var mc = (row as Dictionary).get("cell", [])
				if typeof(mc) == TYPE_ARRAY and (mc as Array).size() >= 2:
					board.melt(Vector2i(int((mc as Array)[0]), int((mc as Array)[1])),
							String((row as Dictionary).get("kind", "ice")), _clock)
			_sync_from_sim()
	if _autoplay:
		while evaluator.cursor < evaluator.events.size():
			var ev: Dictionary = evaluator.events[evaluator.cursor]
			if float(ev.get("at", 0.0)) > _clock:
				break
			_note_sim_result(evaluator.step())
	if _recording:
		_sample_cursor()
		_process_drag_sample()   # 拖动轨迹按帧率(60Hz)补采样
	if _cursor_layer != null:
		_cursor_layer.queue_redraw()
	board.set_clock(_clock)
	if board.has_method("set_safeboxes") and evaluator != null and evaluator.sim != null:
		board.set_safeboxes(evaluator.sim.safeboxes)
	fly.set_clock(_clock)
	_tick_level_next()
	_tick_coin_pending()
	_refresh_order_ready()
	_push_stockpile()
	_tick_coin_display()
	_push_top_bar()
	if orders != null and orders.has_method("set_clock"):
		orders.set_clock(_clock)
	if orders != null and orders.has_method("is_animating") and orders.is_animating():
		# keep both layers painting while a card (and its character) shrinks away
		if chrome != null:
			chrome.queue_redraw()
	if not _row_dragging and absf(_row_dx) > 0.5 and orders != null:
		# rubber band: the row eases back to its home position in ~0.25 s at 60 fps
		_row_dx = lerpf(_row_dx, 0.0, 0.22)
		orders.set_row_offset(_row_dx)
		_record_band(_row_dx)
	elif not _row_dragging and not is_zero_approx(_row_dx) and orders != null:
		# 2026-11-10：回弹收尾必须**归零并记一行**，否则 take 最后一条是 0.4~0.6 的残余，
		# 成片会一直停在偏一点的位置。
		_row_dx = 0.0
		orders.set_row_offset(0.0)
		_record_band(0.0)
	# 2026-11-10：兜底 —— 每帧把**画面上真正用的偏移**记一次，不管是谁改的
	# （拖动 / 回弹 / 以后新增的路径），成片永远和实机同拍。
	if _recording and orders != null:
		_record_band(orders.row_offset())
	if _preview_pending > 0.0 and _window_fix_frames < 176:
		_cycle_preview(_preview_pending)
		_preview_pending = 0.0
	if _window_fix_frames > 0 and DisplayServer.get_name() != "headless":
		_window_fix_frames -= 1
		if _window_fix_frames == 179:
			print("[game] window now=%s target=%s mode=%d" % [str(DisplayServer.window_get_size()),
					str(_preview_window), DisplayServer.window_get_mode()])
		if DisplayServer.window_get_size() != _preview_window and _preview_window_enabled:
			DisplayServer.window_set_size(_preview_window)
			var usable := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(
					usable.position + (usable.size - _preview_window) / 2)
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


## F9 = 50% (540x960), F11 = 100% (1080x1920). Both keep the 1080x1920 design
## resolution, so layout, hit-testing and rendering stay identical.
## 是否在 Movie Maker 录制：录制时不允许改窗口尺寸。
func _is_movie_run() -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("--write-movie"):
			return true
	return false


func _cycle_preview(scale: float) -> void:
	var target := Vector2i(int(round(1080.0 * scale)), int(round(1920.0 * scale)))
	if DisplayServer.get_name() == "headless" or _is_movie_run():
		return
	get_window().size = target
	var screen := DisplayServer.screen_get_size()
	get_window().position = Vector2i(
			maxi((screen.x - target.x) / 2, 0), maxi((screen.y - target.y) / 2, 0))
	print("[game] preview window=", target.x, "x", target.y, " scale=", scale)


## 窗口像素 -> 画布像素（viewport 拉伸下窗口 540x960、画布 1080x1920）。
## 录制、点击、自绘光标都用它，保证三者坐标同一套。
func _mouse_canvas_point() -> Vector2:
	var win := Vector2(DisplayServer.window_get_size())
	var vp := get_viewport().get_visible_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector2.ZERO
	var raw: Vector2 = Vector2(DisplayServer.mouse_get_position()) \
			- Vector2(DisplayServer.window_get_position())
	return Vector2(raw.x * vp.x / win.x, raw.y * vp.y / win.y)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			get_tree().quit(0)
			return
		if key_event.keycode == KEY_F9:
			_cycle_preview(0.5)
			return
		if key_event.keycode == KEY_F11:
			_cycle_preview(1.0)
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
	if event is InputEventMouseMotion and _row_pressing:
		var motion := event as InputEventMouseMotion
		var dx := motion.position.x - _row_press_x
		if not _row_dragging and absf(dx) >= ROW_DRAG_THRESHOLD:
			_row_dragging = true
		if _row_dragging and orders != null:
			_row_dx = dx * ROW_RUBBER
			orders.set_row_offset(_row_dx)
			# 2026-11-10：**跟手这一段必须进 take**。之前只在回弹里 record，
			# 成片要等松手后才看到任务栏动（操作者："鼠标飞出去老远才跟着动"）。
			_record_band(_row_dx)
	if not _free_mode or _freeze:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			# 2026-11-06: right-click on a green chip delivers it too.
			if mouse.pressed:
				# 2026-11-10（交付改版）：**右键点任务行交付已废除**，保留代码备查。
				# if _deliver_from_card(mouse.position):
				# 	return
				var rcell := _cell_at(mouse.position)
				# 2026-11-10（交付改版）：**右键点 clip 交付已废除**，保留代码备查。
				rcell = Vector2i(-1, -1)
				if false and rcell.x >= 0:
					var ritem: Dictionary = evaluator.sim.board.item(rcell) 							if evaluator.sim.board.has_item(rcell) else {}
					var rtarget := _deliver_target_for(ritem)
					if not rtarget.is_empty() 							and _deliver_to(String(rtarget["order"]), int(rtarget["row"]), rcell):
						_last_click_at = _clock
						_last_click_point = _mouse_canvas_point()
			return
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			if ROW_DRAG_AREA.has_point(mouse.position):
				_row_pressing = true
				_row_press_x = mouse.position.x
			_begin_press(mouse.position)
		else:
			# 2026-11-06: keep _row_dragging until _end_press sees it, otherwise a row
			# drag is read as a click on whatever card sits under the pointer.
			_row_pressing = false
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
## 记一帧拖动位置（时间 + 起点格 + 当前中心点）。
## 订单带偏移取样：只在录制中、且值真的变了才记一行。
func _record_band(dx: float) -> void:
	if not _recording:
		return
	var at := _rec_offset()
	if not _rec_band.is_empty():
		var last: Array = _rec_band[_rec_band.size() - 1]
		if absf(float(last[1]) - dx) < 0.05 and at - float(last[0]) < 0.008:
			return
	_rec_band.append([snappedf(at, 0.001), snappedf(dx, 0.1)])


func _rec_drag_sample(at: Vector2) -> void:
	if not _recording or not _dragging:
		return
	_rec_drag.append([snappedf(_rec_offset(), 0.001), _drag_from.x, _drag_from.y,
			snappedf(at.x, 0.1), snappedf(at.y, 0.1)])


func _maybe_start_drag(point: Vector2) -> void:
	if not _pressing or _dragging:
		return
	if _press_point.distance_to(point) < DRAG_THRESHOLD:
		return
	if evaluator == null or evaluator.sim == null or evaluator.sim.board == null:
		return
	if _press_cell.x < 0 or not evaluator.sim.board.has_item(_press_cell):
		return
	# 2026-11-11：**被障碍盖住的棋子不能拖**（网 / 冰 / 锁盒 / 柜子）。
	# 网下面那枚棋子是"被扣住"的，只能靠拖一枚同款过来解锁；
	# 以前这里没判断，能把它拖出来，看起来还把蜘蛛网一起拽走了。
	if evaluator.sim.board.is_blocked(_press_cell):
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
	_rec_drag_sample(centre)
	var drag_tex: Texture2D = board.chip_texture(
			String(_board_item(_drag_from).get("entity", "")),
			int(_board_item(_drag_from).get("level", 1)))
	# 2026-11-06: generators have no chip art — the ghost layer would draw nothing and
	# the generator vanished mid-drag. Only hand the art to the ghost when it exists.
	board.drag_chip_visible = drag_tex == null
	if ghost != null:
		if drag_tex != null:
			ghost.set_state(_drag_from, centre, drag_tex, _clock)
		else:
			ghost.clear()


## 每帧采样：拖动时按渲染帧率（60Hz）记一次，避免快速拖动轨迹太稀。
func _process_drag_sample() -> void:
	if not _recording or not _dragging:
		return
	var point := _mouse_canvas_point()
	var at := point + _drag_grab
	if _rec_drag.is_empty():
		_rec_drag_sample(at)
		return
	var last: Array = _rec_drag[_rec_drag.size() - 1]
	if absf(float(last[3]) - at.x) < 0.05 and absf(float(last[4]) - at.y) < 0.05:
		return
	_rec_drag_sample(at)


func _update_drag(point: Vector2) -> void:
	if not _dragging:
		return
	var at := point + _drag_grab
	board.set_drag_state({"from": _drag_from, "pos": at})
	_rec_drag_sample(at)
	if ghost != null:
		var tex: Texture2D = board.chip_texture(
				String(_board_item(_drag_from).get("entity", "")),
				int(_board_item(_drag_from).get("level", 1)))
		if tex != null:
			ghost.set_state(_drag_from, at, tex, _clock)
		else:
			ghost.clear()


## Release: a drag either merges (same entity+level) or cancels; a press without
## movement stays the old click semantics (select / tap / claim / next).
func _end_press(release_point: Vector2) -> void:
	if _recording and _dragging:
		_rec_drag_sample(release_point + _drag_grab)
	if not _pressing:
		return
	# 2026-11-06: a row drag must never be read as a click on a card — otherwise
	# dragging level 1's only card claims it and the spring-back is never seen.
	if _row_dragging:
		_pressing = false
		_row_dragging = false
		_row_pressing = false
		return
	if _press_tapped:
		_press_tapped = false
		_pressing = false
		return
	var point := release_point
	if _dragging:
		var to := _cell_at(point)
		# Dropping a chip onto the order band delivers it instead of a board action.
		# 2026-11-10（交付改版）：**拖动到任务栏交付已废除**，保留代码备查。
		if false and _deliver_drop(point, _drag_from):
			board.set_drag_state({})
			if ghost != null:
				ghost.clear()
			_dragging = false
			_drag_from = Vector2i(-1, -1)
			_pressing = false
			board.drag_chip_visible = true
			_last_click_at = _clock
			_last_click_point = _mouse_canvas_point()
			_record_click(point, {"kind": "order_claim", "ok": true})
			return
		var action: Dictionary = FreeMode.drag_action(_drag_from, to, evaluator.sim, model,
				Vector2i(-1, -1))
		board.set_drag_state({})
		if ghost != null:
			ghost.clear()
		_dragging = false
		var from := _drag_from
		_drag_from = Vector2i(-1, -1)
		var kind := String(action.get("kind", ""))
		if kind == FreeMode.ACTION_MERGE or kind == FreeMode.ACTION_SWAP \
				or kind == FreeMode.ACTION_MOVE:
			_last_click_at = _clock
			_last_click_point = _mouse_canvas_point()
			var event_type := "drag" if kind == FreeMode.ACTION_MERGE else "swap"
			if kind == FreeMode.ACTION_MOVE:
				event_type = "move"
			var result: Dictionary = _apply_free(event_type, action.get("payload", {}))
			if bool(result.get("ok", false)):
				# merge pops (0.4 s up/down), a move/swap lands with a short shrink
				if kind != FreeMode.ACTION_MOVE:
					board.pulse(to, "merge" if kind == FreeMode.ACTION_MERGE else "settle", _clock)
				if kind == FreeMode.ACTION_MERGE:
					_play_unlocks()
			print("[game] drag %s %s -> %s ok=%s code=%s" % [event_type, str(from), str(to),
					str(result.get("ok", false)), String(result.get("code", ""))])
			# 2026-11-11：拖到蜘蛛网被拒时，把"网上压的是什么、你拖的是什么"打出来，
			# 免得操作者以为功能没生效（只有同款同级才解锁 + 升级）。
			if not bool(result.get("ok", false)) 					and evaluator.sim.board.obstacle_types(to).has("web"):
				var hidden: Dictionary = evaluator.sim.board.item(to)
				var dragged: Dictionary = evaluator.sim.board.item(from)
				print("[web] 网上压的是 %s lv%d，你拖的是 %s lv%d（必须同款同级）" % [
						String(hidden.get("entity", "?")), int(hidden.get("level", 0)),
						String(dragged.get("entity", "?")), int(dragged.get("level", 0))])
			_record_click(point, {"kind": event_type, "ok": bool(result.get("ok", false)),
					"cell": [to.x, to.y]})
		else:
			_sync_from_sim()
	else:
		_free_click_at(_press_point)
	_pressing = false

## The order whose mission this cell satisfies (empty when none).
func _order_id_for_cell(cell: Vector2i) -> String:
	if evaluator == null or evaluator.sim == null or not evaluator.sim.board.has_item(cell):
		return ""
	var item: Dictionary = evaluator.sim.board.item(cell)
	var entity := String(item.get("entity", ""))
	for card in orders.cards:
		if bool(card.get("done", false)):
			continue
		for m in _as_array(card.get("mission", [])):
			if String((m as Dictionary).get("entity", "")) != entity:
				continue
			if int((m as Dictionary).get("level", 1)) != int(item.get("level", 1)):
				continue
			return String(card.get("id", ""))
	return ""


## Deliver from a board cell: used by the double-click and the drag-onto-card paths.
func _claim_from_cell(cell: Vector2i) -> bool:
	var order_id := _order_id_for_cell(cell)
	if order_id.is_empty():
		return false
	var item: Dictionary = evaluator.sim.board.item(cell)
	# 交付会消耗若干枚棋子（2 行任务就 2 枚）；先记住它们交前的样子，交完逐枚播飞行。
	var before := {}
	for pos in evaluator.sim.board.cells.keys():
		before[pos] = (evaluator.sim.board.item(pos) as Dictionary).duplicate(true)
	_arm_claim_hold(order_id)
	var result: Dictionary = _apply_free("order_claim",
			{"order": order_id, "src": [cell.x, cell.y]})
	if not bool(result.get("ok", false)):
		if orders != null:
			orders.release_hold(order_id)
		return false
	_schedule_coin(order_id)
	var taken = result.get("taken", [])
	if typeof(taken) == TYPE_ARRAY and (taken as Array).size() > 0:
		for i in (taken as Array).size():
			var raw = (taken as Array)[i]
			if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
				continue
			var pos := Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
			var it: Dictionary = before.get(pos, {})
			_play_claim_flight(order_id, pos, it, 0.08 * float(i))
	else:
		_play_claim_flight(order_id, cell, item)
	return true


## 2026-11-10：**一枚一枚交**。三种入口（右键棋子 / 拖到卡上 / 右键卡上任务格子）
## 都落到这里：只推进一行的一枚，不再是"整单一次结算"。
func _deliver_to(order_id: String, row: int, cell: Vector2i,
		from_point: Vector2 = Vector2(-1, -1), dur: float = 0.0,
		via: String = "chip") -> bool:
	if evaluator == null or evaluator.sim == null:
		return false
	if not evaluator.sim.board.has_item(cell):
		return false
	var item: Dictionary = evaluator.sim.board.item(cell)
	# via 记录"从哪个入口交的"，成片据此决定飞行起点（拖拽=光标，其余=棋子所在格）。
	var result: Dictionary = _apply_free("deliver",
			{"order": order_id, "from": [cell.x, cell.y], "row": row, "via": via})
	if not bool(result.get("ok", false)):
		return false
	var taken_row := int(result.get("row", row))
	# 目标卡如果还在画面外，先把它弹进可见槽位 —— 交付必须在画面里发生。
	var reveal_delay: float = orders.reveal_card(order_id, 0.26) if orders != null else 0.0
	# 2026-11-10：拖拽交付时棋子已经在手上，"飞"是多余的 —— 直接落袋。
	# 只有右键棋子 / 右键任务格这两种"从棋盘起飞"的入口才播飞行。
	if via != "drag":
		_play_deliver_flight(order_id, taken_row, cell, item, from_point, dur, reveal_delay)
	# 到货反馈：那一行底板吞一下（"白圈扩散"是光标点击涟漪，不属于交付，别加到这里）
	if orders != null:
		orders.punch_row(order_id, taken_row, reveal_delay)
		# 动画全跑完再放开排序（操作者：先换位、再飞、动画完成之后才重排）
		orders.hold_sort(order_id, reveal_delay + 0.75)
	if bool(result.get("settled", false)):
		_after_settle(order_id)
	return true


## 这一枚该交给哪张卡哪一行：按卡的顺序找**还没收满、且有同款需求**的行。
func _deliver_target_for(item: Dictionary) -> Dictionary:
	var entity := String(item.get("entity", ""))
	var level := int(item.get("level", 1))
	for raw in orders.cards:
		var card: Dictionary = raw
		if bool(card.get("done", false)):
			continue
		var items: Array = card.get("mission", [])
		for i in items.size():
			var m: Dictionary = items[i]
			if String(m.get("entity", "")) != entity or int(m.get("level", 1)) != level:
				continue
			if int(m.get("have", 0)) >= maxi(int(m.get("need", 1)), 1):
				continue
			return {"order": String(card.get("id", "")), "row": i}
	return {}


## 棋盘上随机挑一枚符合这一行的棋子（右键点卡上任务格子时用）。
func _random_cell_for(order_id: String, row: int) -> Vector2i:
	var card: Dictionary = {}
	for raw in orders.cards:
		if String((raw as Dictionary).get("id", "")) == order_id:
			card = raw
			break
	if card.is_empty():
		return Vector2i(-1, -1)
	var items: Array = card.get("mission", [])
	if row < 0 or row >= items.size():
		return Vector2i(-1, -1)
	var m: Dictionary = items[row]
	var cells: Array = []
	for pos in evaluator.sim.board.sorted_cells():
		var it: Dictionary = evaluator.sim.board.item(pos)
		if String(it.get("entity", "")) == String(m.get("entity", "")) 				and int(it.get("level", 1)) == int(m.get("level", 1)):
			cells.append(pos)
	if cells.is_empty():
		return Vector2i(-1, -1)
	# 随机一枚（固定种子便于复现）；挑中的格子会写进 take，成片回放是确定的。
	var idx := int(abs(float(_clock) * 1000.0 + float(cells.size()))) % cells.size()
	return cells[idx]


## 交付一枚的飞行：起点 = 那一格，落点 = **那一行的底板中心**（不是卡中心）。
func _play_deliver_flight(order_id: String, row: int, cell: Vector2i, item: Dictionary,
		from_point: Vector2 = Vector2(-1, -1), dur: float = 0.0, delay: float = 0.0) -> void:
	if fly == null or orders == null:
		return
	# 2026-11-12：这一枚如果被编辑器改过图标，飞的就是改过的那张
	var tex_entity := String(item.get("icon", ""))
	var tex_level := int(item.get("level", 1))
	if tex_entity.is_empty():
		tex_entity = String(item.get("entity", ""))
	elif int(item.get("icon_level", 0)) > 0:
		tex_level = int(item.get("icon_level", 0))
	var texture: Texture2D = board.chip_texture(tex_entity, tex_level)
	if texture == null:
		return
	var target: Vector2 = orders.position + orders.mission_row_center(order_id, row)
	var payload := {"from": [cell.x, cell.y], "order": order_id,
			"to_point": [target.x, target.y], "texture": texture}
	# 2026-11-10：拖拽交付时棋子本来就跟着指针，**从松手点**吸进去（0.16s），
	# 不再从已经被拖空的那一格起飞。右键交付仍是"从格子飞"（0.55s）。
	if from_point.x >= 0.0:
		payload["from_point"] = [from_point.x, from_point.y]
		payload["dur"] = dur if dur > 0.0 else FlyAnim.deliver_duration(from_point, target)
	else:
		# 右键交付：起点是被点的那一格，时长同样按距离算（公式与成片共用）
		var cell_centre: Vector2 = board.cell_rect(cell.x, cell.y).get_center() 				+ board.position
		payload["dur"] = dur if dur > 0.0 else FlyAnim.deliver_duration(cell_centre, target)
	# at 加延迟：卡片先滑到位，棋子再起飞（操作者：先换位、再飞）
	fly.play_event({"type": "deliver_chip", "at": _clock + maxf(delay, 0.0), "payload": payload})


## 整单收满之后的结算表现（奖励飞行 + 卡片 hold 后缩掉），与点卡结算同一套。
func _after_settle(order_id: String) -> void:
	if orders == null:
		return
	_arm_claim_hold(order_id)
	_schedule_coin(order_id)
	_clear_drag_art()
	_last_click_at = _clock
	_last_click_point = _mouse_canvas_point()


## 右键点在订单带的某个任务格子上（只认绿色底板）：从棋盘随机挑一枚对应的，
## 飞进那一行。这是第三种交付入口。
func _deliver_from_card(point: Vector2) -> bool:
	if orders == null or evaluator == null or evaluator.sim == null:
		return false
	var hit: Dictionary = orders.mission_row_at(point - orders.position)
	if hit.is_empty() or not bool(hit.get("ready", false)):
		return false
	var cell := _random_cell_for(String(hit["order"]), int(hit["row"]))
	if cell.x < 0:
		return false
	if not _deliver_to(String(hit["order"]), int(hit["row"]), cell, Vector2(-1, -1), 0.0, "card"):
		return false
	_last_click_at = _clock
	_last_click_point = point
	_record_click(point, {"kind": "deliver", "ok": true})
	return true


## 拖拽落点在订单带上：只认**底板矩形**里、且已经变绿的行；否则当没交（棋子回原位）。
func _deliver_drop(point: Vector2, cell: Vector2i) -> bool:
	if orders == null or evaluator == null or evaluator.sim == null:
		return false
	if not evaluator.sim.board.has_item(cell):
		return false
	var hit: Dictionary = orders.mission_row_at(point - orders.position)
	if hit.is_empty() or not bool(hit.get("ready", false)):
		return false
	if not _deliver_to(String(hit["order"]), int(hit["row"]), cell, point, 0.16, "drag"):
		return false
	_clear_drag_art()
	_last_click_at = _clock
	_last_click_point = _mouse_canvas_point()
	_record_click(point, {"kind": "deliver", "ok": true})
	return true


## 交付/点卡之后统一清掉拖拽残留：ghost、拖拽层、选中框。
## 2026-11-10：以前只清了 ghost，`board.selected` 还指在被交走的那一格上，
## 棋盘上就会留一枚"飘着"的棋子（带四个选中角标）。
func _clear_drag_art() -> void:
	board.set_drag_state({})
	board.drag_chip_visible = true
	if ghost != null:
		ghost.clear()
	_dragging = false
	_drag_from = Vector2i(-1, -1)
	_pressing = false
	_selected = Vector2i(-1, -1)
	board.apply_state({"selected": _to_array(_selected),
			"completed": _completed_cells(evaluator.sim.snapshot())})


func _confirm_badge_hit(point: Vector2) -> bool:
	var local: Vector2 = point - orders.position
	for card in orders.cards:
		var oid := String(card.get("id", ""))
		if not orders.card_awaiting_confirm(oid):
			continue
		if not orders.confirm_badge_rect(oid).has_point(local):
			continue
		# 先锁住任务栏这一瞬的数字/颜色，再让棋子飞走（操作者要求）。
		if orders.has_method("lock_row_display"):
			orders.lock_row_display(oid)
		_confirm_order(oid)
		_last_click_at = _clock
		_last_click_point = _mouse_canvas_point()
		_record_click(point, {"kind": "confirm", "ok": true})
		return true
	return false


## 逐行把棋盘上属于该行的棋子飞过去（行里要几枚就飞几枚），sim 落地即记账。
func _confirm_order(order_id: String) -> void:
	var snap: Dictionary = evaluator.sim.snapshot()
	for raw_order in snap.get("orders", []):
		var order: Dictionary = raw_order
		if String(order.get("id", "")) != order_id:
			continue
		var mission: Array = order.get("mission", [])
		for i in mission.size():
			var row: Array = mission[i]
			var need := int(row[3]) if row.size() >= 4 else 1
			var k := 0
			while k < need:
				var cell := _random_cell_for(order_id, i)
				if cell.x < 0:
					break
				if not _deliver_to(order_id, i, cell, Vector2(-1, -1), 0.05 * float(k), "check"):
					break
				k += 1
		return


func _free_click_at(point: Vector2) -> Dictionary:
	if STOCKPILE_RECT.has_point(point) and _stockpile_tap():
		return {"ok": true, "type": "stockpile"}
	# 2026-11-10（交付改版）：点**大绿底对号**才交任务 —— 整卡全满才会出现这块。
	if orders != null and _confirm_badge_hit(point):
		return {"kind": "confirm", "ok": true, "cell": null}
	if evaluator == null or evaluator.sim == null:
		return {"kind": "none", "ok": false, "cell": null}
	_last_click_at = _clock
	_last_click_point = _mouse_canvas_point()
	var out := {"kind": "none", "ok": false, "cell": null}
	var cell := _cell_at(point)
	if cell.x >= 0:
		# 2026-11-06: the second tap on the same green chip delivers it. This has to run
		# before the board rule below, or the tap is consumed by "select" and the
		# double-click never fires.
		var doubled := cell == _last_cell and _clock - _last_cell_at <= DOUBLE_CLICK
		_last_cell = cell
		_last_cell_at = _clock
		# 同一个开关：双击棋子也不再整单结算（2026-11-10 屏蔽）
		if CLICK_CARD_CLAIMS and doubled and _claim_from_cell(cell):
			out["cell"] = [cell.x, cell.y]
			out["kind"] = "order_claim"
			out["ok"] = true
			_record_click(point, out)
			return out
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
				_play_unlocks()
		elif kind == FreeMode.ACTION_SELECT or kind == FreeMode.ACTION_CLEAR:
			_sync_from_sim()
			out["ok"] = true
		_record_click(point, out)
		return out
	var order_id := _order_card_at(point) if CLICK_CARD_CLAIMS else ""
	if not order_id.is_empty():
		out["kind"] = "order_claim"
		# Capture the delivered chip BEFORE the claim consumes it: the flight needs its
		# cell and its art.
		var src_cell := Vector2i(-1, -1)
		var src_item: Dictionary = {}
		for raw_cell in _completed_cells(evaluator.sim.snapshot()):
			# _completed_cells yields [x, y] arrays, the board wants Vector2i.
			var done_cell := _to_cell(raw_cell)
			if not evaluator.sim.board.in_bounds(done_cell):
				continue
			if evaluator.sim.board.has_item(done_cell):
				src_cell = done_cell
				src_item = evaluator.sim.board.item(done_cell)
				break
		_arm_claim_hold(order_id)
		out["ok"] = bool(_apply_free("order_claim",
				{"order": order_id, "src": [src_cell.x, src_cell.y]}).get("ok", false))
		if bool(out["ok"]):
			_schedule_coin(order_id)
		elif orders != null:
			orders.release_hold(order_id)
		if bool(out["ok"]) and src_cell.x >= 0:
			_play_claim_flight(order_id, src_cell, src_item)
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


func _rec_offset() -> float:
	return maxf(0.0, _clock - _rec_start)


func _sample_cursor(force: bool = false) -> void:
	var point := _mouse_canvas_point()
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
	_rec_drag = []
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
			_rec_events, SAMPLE_PROJECT, _rec_drag, _rec_band)
	var check: Dictionary = TakeIo.validate(take)
	if not bool(check.get("ok", false)):
		print("[game] take invalid: " + str(check.get("errors", [])))
		return
	var stamp := Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace("-", "").replace(":", "").replace("T", "_")
	# 2026-11-09：一次录制 = 一个时间戳目录（take / 成片 / PNG 序列都在里面）。
	var rec_dir := MOV_DIR + "/" + stamp
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rec_dir))
	var base := rec_dir + "/take_" + stamp
	_take_path = base + ".take.json"
	if not TakeIo.save(take, _take_path):
		print("[game] take save FAILED " + _take_path)
		return
	print("[game] take saved %s %s" % [_take_path, TakeIo.summary(take)])
	if not _auto_render:
		print("[game] --no-render set; film not started")
		board.show_toast("take " + _take_path.get_file(), TOAST_SECONDS)
		return
	var movie_path := rec_dir + "/film.mp4"
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
	_tick_coin_pending()
	_refresh_order_ready()
	_tick_coin_display()
	_push_top_bar()
	if orders != null and orders.has_method("set_clock"):
		orders.set_clock(_clock)
	if orders != null and orders.has_method("is_animating") and orders.is_animating():
		# keep both layers painting while a card (and its character) shrinks away
		if chrome != null:
			chrome.queue_redraw()
	if not _row_dragging and absf(_row_dx) > 0.5 and orders != null:
		# rubber band: the row eases back to its home position in ~0.25 s at 60 fps
		_row_dx = lerpf(_row_dx, 0.0, 0.22)
		orders.set_row_offset(_row_dx)
		_record_band(_row_dx)
	elif not _row_dragging and not is_zero_approx(_row_dx) and orders != null:
		# 2026-11-10：回弹收尾必须**归零并记一行**，否则 take 最后一条是 0.4~0.6 的残余，
		# 成片会一直停在偏一点的位置。
		_row_dx = 0.0
		orders.set_row_offset(0.0)
		_record_band(0.0)
	# 2026-11-10：兜底 —— 每帧把**画面上真正用的偏移**记一次，不管是谁改的
	# （拖动 / 回弹 / 以后新增的路径），成片永远和实机同拍。
	if _recording and orders != null:
		_record_band(orders.row_offset())
	if _preview_pending > 0.0 and _window_fix_frames < 176:
		_cycle_preview(_preview_pending)
		_preview_pending = 0.0
	if _window_fix_frames > 0 and DisplayServer.get_name() != "headless":
		_window_fix_frames -= 1
		if _window_fix_frames == 179:
			print("[game] window now=%s target=%s mode=%d" % [str(DisplayServer.window_get_size()),
					str(_preview_window), DisplayServer.window_get_mode()])
		if DisplayServer.window_get_size() != _preview_window and _preview_window_enabled:
			DisplayServer.window_set_size(_preview_window)
			var usable := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(
					usable.position + (usable.size - _preview_window) / 2)
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
