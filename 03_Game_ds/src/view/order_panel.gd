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
const MAX_CARDS := 6
const MARGIN := 18.0
const Layout := preload("res://src/view/layout_shared.gd")
const MAX_CARD_W := Layout.QUEUE_CARD_W
const CARD_GAP_X := Layout.CARD_GAP_X
const VISIBLE_CARDS := 2
## The queue starts where level 1's single card does (portrait centre 393 - card/2), so
## the left side of the band stays free for other UI.
const QUEUE_ORIGIN_X := Layout.QUEUE_ORIGIN_X

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
## Horizontal offset of the whole queue while the player drags it (rubber band).
var _row_offset: float = 0.0
## 立绘是否由本组件绘制（成片端关掉，改由成片自己画，好保持"顶栏压在立绘上"的层级）。
var draw_portraits: bool = true
## 是否铺不透明底条：实机需要（盖住棋盘标题行），成片不用（成片自己画背景）。
var draw_page_strip: bool = true
## 卡片上的绿色对号（可交付/已完成确认标）。2026-11-09 操作者要求**先隐藏**；
## 留成开关而不是删代码，随时能开回来。顶层开关，实机与成片共用同一份。
var draw_confirm_badge: bool = false
## 任务带左侧的库存面板状态（-1 表示本关没有库存）。
## 队列重排：每张卡的目标 x 和当前 x（换位时用 0.25s 缓动滑过去）。
var _target_x: Dictionary = {}
var _x_now: Dictionary = {}
## Claimed cards shrink away before the queue closes the gap.
const DONE_SHRINK := 0.35
var _clock_now: float = 0.0
var _done_at: Dictionary = {}
## Claimed orders stay visible until their chip lands: id -> time the done state shows.
var _hold: Dictionary = {}
## 库存面板（任务带左侧那块）的运行时状态：实机每帧推进来，画由本面板负责。
## 2026-11-06: 从 game_screen 的 Chrome 搬进来，成片端实例化本面板就自动带上。
var _stockpile_on: bool = false
var _stockpile_count: int = 0
var _stockpile_entity: String = ""
var _stockpile_level: int = 0


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


## Portrait for a card's character (the same art the chrome used to draw).
func _portrait_texture(character: String) -> Texture2D:
	if character.is_empty():
		return null
	var key := "char_" + character.replace("char_", "")
	return _ui_texture(key)


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


## Keep a claimed card (and its character) on screen until the delivery flight lands.
func hold_done(order_id: String, seconds: float) -> void:
	_hold[order_id] = _clock_now + maxf(seconds, 0.0)


func release_hold(order_id: String) -> void:
	_hold.erase(order_id)


func is_holding(order_id: String) -> bool:
	return _hold.has(order_id) and _clock_now < float(_hold[order_id])


func set_clock(t: float) -> void:
	_clock_now = t
	_reorder_cards()
	var moving := false
	for cid in _target_x.keys():
		var target := float(_target_x[cid])
		var now := float(_x_now.get(cid, target))
		if absf(now - target) <= 0.5:
			_x_now[cid] = target
			continue
		# 0.25 s ease at 60 fps — the same hand as the row rubber band
		_x_now[cid] = lerpf(now, target, 0.22)
		moving = true
	if moving:
		_layout()
		queue_redraw()
	# a held claim lands now: flip the card to done so the shrink starts
	for cid in _hold.keys():
		if t < float(_hold[cid]):
			continue
		var held := _card(String(cid))
		if not held.is_empty() and bool(held.get("claim_pending", false)):
			held["done"] = true
			held["claim_pending"] = false
			if not _done_at.has(String(cid)):
				_done_at[String(cid)] = t
		_hold.erase(cid)
	var retiring := false
	for cid in _done_at.keys():
		if t - float(_done_at[cid]) < DONE_SHRINK:
			retiring = true
			break
	if retiring or not _done_at.is_empty():
		queue_redraw()


## True while a claimed card is still shrinking (the chrome redraws each frame then).
func is_animating() -> bool:
	for cid in _done_at.keys():
		if _clock_now - float(_done_at[cid]) < DONE_SHRINK + 0.05:
			return true
	return false




func set_row_offset(dx: float) -> void:
	_row_offset = dx
	_layout()
	queue_redraw()


func row_offset() -> float:
	return _row_offset


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


## Live progress from a sim snapshot. Rows come from src/view/order_rows.gd, the one
## builder the live screen and the film share: a mission entry is
## {entity, level, have, need, ready, hue, label}. The legacy array form
## [entity, level, have, ready] still reads the same way, so probes and older callers
## keep working; unknown fields are ignored, so a partial row is safe.
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
		var was_done := bool(card.get("done", false))
		var claim := bool(row.get("done", false))
		if claim and is_holding(String(row.get("id", ""))):
			claim = false  # the flight is still in the air
			card["claim_pending"] = true
		card["done"] = claim
		# 钻石奖励跟着行数据走（实机与成片同一份快照；老行没有这个键就保留原值）。
		card["gem"] = int(row.get("gem", card.get("gem", 0)))
		card["energy"] = int(row.get("energy", card.get("energy", 0)))
		if card["done"] and not was_done and not _done_at.has(String(card.get("id", ""))):
			_done_at[String(card.get("id", ""))] = _clock_now
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
			var item: Dictionary = items[i]
			_sync_mission_item(item, (mission_rows as Array)[i])
	if is_inside_tree():
		queue_redraw()


## One mission entry of the snapshot -> the card's item (dicts carry the shared row
## shape from OrderRows; the array form [entity, level, have, ready] still works).
func _sync_mission_item(item: Dictionary, m) -> void:
	if typeof(m) == TYPE_DICTIONARY:
		var row: Dictionary = m
		item["have"] = int(row.get("have", item.get("have", 0)))
		item["need"] = maxi(int(row.get("need", item.get("need", 1))), 1)
		item["ready"] = bool(row.get("ready", false))
		var hue = row.get("hue", null)
		if hue is Color:
			item["hue"] = hue
		var label = row.get("label", null)
		if label is String and not (label as String).is_empty():
			item["label"] = String(label)
		return
	if typeof(m) == TYPE_ARRAY and (m as Array).size() >= 3:
		item["have"] = int((m as Array)[2])
		item["ready"] = bool((m as Array)[3]) if (m as Array).size() >= 4 else false


func set_order_done(order_id: String, done: bool) -> bool:
	# 2026-11-06: a direct done flip (tests, probes, single-card levels) must start the
	# same shrink animation the snapshot path uses.
	if done and not _done_at.has(order_id):
		_done_at[order_id] = _clock_now
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


## 库存面板的实时状态（次数 + 面板里那枚棋子）。启用库存就画，次数为 0 也照画。
func set_stockpile(count: int, entity: String, level: int) -> void:
	var changed := (not _stockpile_on) or _stockpile_count != count \
			or _stockpile_entity != entity or _stockpile_level != level
	_stockpile_on = true
	_stockpile_count = count
	_stockpile_entity = entity
	_stockpile_level = level
	if changed and is_inside_tree():
		queue_redraw()


## 本关没有启用库存：整块控件收起来（和"次数归零"不是一回事）。
func clear_stockpile() -> void:
	if not _stockpile_on:
		return
	_stockpile_on = false
	_stockpile_count = 0
	_stockpile_entity = ""
	_stockpile_level = 0
	if is_inside_tree():
		queue_redraw()


## 每帧按“能交的排前面”做稳定分区：不插队、不改变各自相对顺序；
## 正在缩小消失的卡（done）钉在原位，等缩完再补位。
func _reorder_cards() -> void:
	# 2026-11-06: no reshuffling while a claimed card is still shrinking — the queue
	# waits for it to be gone, then the survivors slide forward in one go.
	if is_animating():
		return
	if cards.size() < 2:
		return
	var slots: Array = []
	for i in cards.size():
		if not bool((cards[i] as Dictionary).get("done", false)):
			slots.append(i)
	if slots.size() < 2:
		return
	var ready_cards: Array = []
	var rest: Array = []
	for i in slots:
		if _card_ready(cards[i]):
			ready_cards.append(cards[i])
		else:
			rest.append(cards[i])
	var ordered: Array = ready_cards + rest
	var changed := false
	for k in slots.size():
		if cards[int(slots[k])] != ordered[k]:
			changed = true
			break
	if not changed:
		return
	for k in slots.size():
		cards[int(slots[k])] = ordered[k]
	_layout()


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
	# 2026-11-06: 一直左对齐 —— 只剩一张卡时也停在队列起点，不再居中
	var start_x := QUEUE_ORIGIN_X
	# 2026-11-05: compact card — content only (mission + rewards), centred in the band.
	var card_h := minf(total_h - 8.0, 140.0)
	var start_y := Layout.CARD_LOCAL_Y
	if n > 1:
		# 2026-11-06: queue layout — equal gaps in one row, only the first three cards
		# are on screen; the row itself slides with _row_offset.
		# 2026-11-06: the queue starts at the left margin, so the first three cards read
		# left-to-right instead of being centred (which pushed #1 off screen).
		var origin := QUEUE_ORIGIN_X + _row_offset
		for i in n:
			var cid := String(cards[i]["id"])
			var target := QUEUE_ORIGIN_X + float(i) * (MAX_CARD_W + CARD_GAP_X)
			_target_x[cid] = target
			if not _x_now.has(cid):
				_x_now[cid] = target
			_rects[cid] = Rect2(float(_x_now[cid]) + _row_offset, start_y, MAX_CARD_W, card_h)
		return
	for i in n:
		var cid1 := String(cards[i]["id"])
		_target_x[cid1] = start_x + float(i) * (card_w + gap)
		if not _x_now.has(cid1):
			_x_now[cid1] = float(_target_x[cid1])
		# 2026-11-09：**单卡不再有任何特殊路径**。操作者的口径是"第 1 关和第 2 关的任务栏
		# 是同一套设计，只是配置了 1 张卡 + 1 个任务"，所以宽/高/位置/间距全部走同一公式；
		# set_card_anchors 保留 API 但不再参与几何（它只会让第 1 关和别的关长得不一样）。
		_rects[String(cards[i]["id"])] = Rect2(float(_x_now[cid1]) + _row_offset,
				start_y, card_w, card_h)


# --------------------------------------------------------------------- drawing

func _draw() -> void:
	if _rects.size() != cards.size() or _layout_size != Vector2(size.x, size.y):
		_layout()
	# Opaque page strip: the panel sits on top of the board's own caption row, and
	# the sim owns the playfield below it, so the panel paints its own background.
	if draw_page_strip:
		draw_rect(Rect2(Vector2.ZERO, Vector2(maxf(size.x, WIDTH), maxf(size.y, HEIGHT))),
				_c("page", Color("#E6EDF6")), true)
	var shown := 0
	var keep: Array = []
	for card in cards:
		var cid := String(card.get("id", ""))
		var retiring := bool(card.get("done", false))
		if retiring:
			var started := float(_done_at.get(cid, _clock_now))
			var t := (_clock_now - started) / DONE_SHRINK
			if t >= 1.0:
				continue  # gone: the queue closes the gap on the next layout pass
			var r := card_rect(cid)
			var scale: float = clampf(1.0 - t, 0.0, 1.0)
			draw_set_transform(r.get_center(), 0.0, Vector2(scale, scale))
			_draw_card(card, Rect2(-r.size * 0.5, r.size), true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			keep.append(card)
			continue
		keep.append(card)
		# 2026-11-06: draw every card — the ones past the third sit outside the page
		# until the row is dragged left, which is how #4 and #5 come into view.
		_draw_card(card, card_rect(cid))
		shown += 1
	if keep.size() != cards.size():
		cards = keep
		_layout()
	_draw_stockpile()


const PORTRAIT_H := Layout.PORTRAIT_H


func _draw_card(card: Dictionary, r: Rect2, retiring: bool = false) -> void:
	if r.size.x <= 0.0:
		return
	# 2026-11-06: the portrait belongs to the card now, so a retiring card takes its
	# character with it instead of the art blinking out first.
	var portrait := _portrait_texture(String(card.get("character", ""))) if draw_portraits else null
	if portrait != null:
		var source := portrait.get_size()
		var w: float = PORTRAIT_H * (source.x / maxf(source.y, 1.0))
		# 2026-11-09：头顶落在顶栏下沿（卡片上沿往上 PORTRAIT_TOP_ABOVE_CARD），
		# 下沿压进卡片、被卡面覆盖。别再写死像素。
		draw_texture_rect(portrait, Rect2(Vector2(r.get_center().x - w * 0.5,
				r.position.y - Layout.PORTRAIT_TOP_ABOVE_CARD), Vector2(w, PORTRAIT_H)), false)
	var radius := int(round(float(metrics.get("card_radius", 22.0))))
	var card_bg: Color = _c("card", Color.WHITE)
	var card_edge: Color = _c("card_edge", Color("#BACCE0"))
	var ink: Color = _c("ink", Color("#22303F"))
	var dim: Color = _c("ink_dim", Color("#5C6B7D"))

	# 2026-11-05: the card plate is 任务背景板 (九宫格) instead of the flat white box.
	# 2026-11-09: 换成操作者给的 `order_card_bar`（任务栏完整）：贴上浅下蓝，蓝条放钻石奖励。
	# 老主题没有这张图时退回 bar_board，再没有就画程序化白卡 —— 三级兜底。
	var plate := _ui_texture("order_card")
	if plate == null:
		plate = _ui_texture("bar_board")
	if plate != null:
		_draw_nine(plate, r, 26.0)
	else:
		_rounded(r, radius, card_bg)
		_rounded_outline(r, radius, card_edge, 2)

	# 2026-11-05: the avatar circle, the display name and the character id are gone —
	# the card is just the mission slot plus the reward column.
	# 2026-11-09: 任务棋子排在**蓝条以上**的区域里（蓝条归钻石奖励）。
	var items: Array = card.get("mission", [])
	var chips := mission_chip_rects(mission_area_rect(r), items.size())
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var chip: Rect2 = chips[i]
		var hue: Color = item.get("hue", Color("#94A3B8"))
		var ready := int(item.get("have", 0)) >= int(item.get("need", 1))
		# 2026-11-05: the mission slot shows the real chip icon when the loader can
		# resolve it; the procedural tile stays as the no-asset fallback.
		var icon := _chip_texture(String(item.get("entity", "")), int(item.get("level", 1)))
		if icon != null:
			draw_texture_rect(icon, chip, false)
		else:
			_rounded(chip, 14, hue if ready else hue.lerp(Color(1.0, 1.0, 1.0), 0.28))
			_rounded_outline(chip, 14, hue.darkened(0.22), 2)
			_text_center(chip, String(item.get("label", "?")), 24, Color.WHITE)


	_draw_reward_row(r, int(card.get("coin", 0)), 0.0)
	if int(card.get("star", 0)) > 0:
		_draw_star_row(r, int(card.get("star", 0)))
	_draw_reward_strip(r, card)

	# 2026-11-06: the badge stays put once shown — it rides the shrink instead of
	# blinking out on click and popping back during the animation.
	# 2026-11-09: 操作者要求先隐藏（draw_confirm_badge=false）；开关在文件顶部。
	if draw_confirm_badge and (bool(card.get("done", false)) \
			or bool(card.get("claim_pending", false)) or _card_ready(card)):
		# 2026-11-05: no green rim, no small check — one confirm badge centred on the card.
		var confirm := _ui_texture("confirm")
		var size := Vector2(126.0, 74.0)
		var at := Rect2(r.get_center() - size * 0.5, size)
		if confirm != null:
			draw_texture_rect(confirm, at, false)
		else:
			_rounded(at, 20, _c("done", COLOR_DONE))


## 任务行里棋子贴图的位置（卡片局部坐标，返回页面坐标）。
## 2026-11-09 操作者要求"缩小到正常尺寸"：原来 125 + grow(6) = 137 高，
## 而卡片只有 140 高 —— 图标顶到卡片上下边、左右溢出，看着像贴纸糊上去的。
## 现在 96 见方、垂直居中、两枚时按 gap 排开；单测 t_layout_parity 断言不越界。
const CHIP_SIZE := 96.0
## 4 枚挤一张卡时的下限（正常只用到 89）。
const CHIP_MIN_SIZE := 56.0
## 棋子行两侧的内边距。
const CHIP_SIDE_PAD := 16.0
const CHIP_GAP := 14.0

## 2026-11-09：蓝条比例的唯一来源是 layout_shared（实机/成片共用），这里只做别名。
const GEM_STRIP_RATIO := Layout.GEM_STRIP_RATIO
## 2026-11-09：蓝条里放**两组奖励** —— 闪电在前、钻石在后，各自跟一个数字。
## 两个图标统一按高度 32 画（钻石贴图 39×32 正好 1:1；闪电贴图 39×53 等比缩到 24×32）。
const REWARD_ICON_H := 32.0
const ENERGY_ICON_ASPECT := 39.0 / 53.0
const GEM_ICON_ASPECT := 39.0 / 32.0
const REWARD_LABEL_PX := 28
## 两个数字**同一套字**（2026-11-09 操作者：闪电后面的数字也要和钻石一样，别带黄）：
## 白字 + 深蓝描边。描边色 #304870 是从操作者给的参考图上采样出来的主色。
const REWARD_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const REWARD_LABEL_STROKE := Color("#304870")
const REWARD_LABEL_STROKE_PX := 2.0
const REWARD_ICON_TEXT_GAP := 6.0
## 两组之间的间距（比组内的图标-数字间距大，读起来才是两组）
const REWARD_PAIR_GAP := 16.0
## 整组上抬量：蓝条下沿就是卡片底边，居中时图标离底只有 3~4px，看着像被裁
## （2026-11-09 操作者反馈"卡住下面了"）。上抬 4px 后底边留白 ~7px，顶部刚好贴齐蓝条。
const REWARD_ROW_RISE := 4.0


## 卡片放任务棋子的区域 = 卡片去掉底部蓝条。
static func mission_area_rect(card_rect: Rect2) -> Rect2:
	var strip := card_rect.size.y * GEM_STRIP_RATIO
	return Rect2(card_rect.position, Vector2(card_rect.size.x, card_rect.size.y - strip))


## 卡片底部蓝条（钻石奖励行）。
static func gem_strip_rect(card_rect: Rect2) -> Rect2:
	var strip := card_rect.size.y * GEM_STRIP_RATIO
	return Rect2(card_rect.position + Vector2(0.0, card_rect.size.y - strip),
			Vector2(card_rect.size.x, strip))


## 奖励行的几何：["闪电" 数字] ["钻石" 数字]，整组在蓝条里水平居中、上抬 REWARD_ROW_RISE。
## text 宽度由调用方按字体量（视图层自己量字宽是既有做法，见 _text_center_font）。
## 返回 {"strip", "energy_icon", "energy_label", "gem_icon", "gem_label"}；
## 某一组数值为 0 时它的矩形是空的 Rect2（不画）。
static func reward_row_rects(card_rect: Rect2, energy_w: float, gem_w: float) -> Dictionary:
	var strip := gem_strip_rect(card_rect)
	var out := {
		"strip": strip,
		"energy_icon": Rect2(), "energy_label": Rect2(),
		"gem_icon": Rect2(), "gem_label": Rect2(),
	}
	var pairs: Array = []
	if energy_w > 0.0:
		pairs.append(["energy", REWARD_ICON_H * ENERGY_ICON_ASPECT, energy_w])
	if gem_w > 0.0:
		pairs.append(["gem", REWARD_ICON_H * GEM_ICON_ASPECT, gem_w])
	if pairs.is_empty():
		return out
	var total := 0.0
	for i in pairs.size():
		total += float(pairs[i][1]) + REWARD_ICON_TEXT_GAP + float(pairs[i][2])
		if i < pairs.size() - 1:
			total += REWARD_PAIR_GAP
	# 闪电 + 钻石**两组一起**在蓝条里居中：total 不含最后一组后面的间距
	var x := strip.position.x + (strip.size.x - total) * 0.5
	var y := strip.position.y + (strip.size.y - REWARD_ICON_H) * 0.5 - REWARD_ROW_RISE
	for pair in pairs:
		var kind := String(pair[0])
		var icon_w := float(pair[1])
		var text_w := float(pair[2])
		out[kind + "_icon"] = Rect2(Vector2(x, y), Vector2(icon_w, REWARD_ICON_H))
		x += icon_w + REWARD_ICON_TEXT_GAP
		out[kind + "_label"] = Rect2(Vector2(x, y), Vector2(maxf(text_w, 1.0), REWARD_ICON_H))
		x += text_w + REWARD_PAIR_GAP
	return out


## 2026-11-09：一张卡最多 4 枚任务棋子。CHIP_SIZE(96) 是**上限**：
## 4 枚时按卡片宽度自动缩到 ~89px，2~3 枚时仍是 96，看起来和以前一样。
static func chip_size_for(card_rect: Rect2, count: int) -> float:
	if count <= 0:
		return CHIP_SIZE
	var room := card_rect.size.x - CHIP_SIDE_PAD * 2.0 - CHIP_GAP * float(maxi(count - 1, 0))
	return clampf(room / float(count), CHIP_MIN_SIZE, CHIP_SIZE)


static func mission_chip_rects(card_rect: Rect2, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var size := chip_size_for(card_rect, count)
	var row := size * float(count) + CHIP_GAP * float(maxi(count - 1, 0))
	var x := (card_rect.size.x - row) * 0.5
	for i in count:
		out.append(Rect2(
				card_rect.position + Vector2(x + (size + CHIP_GAP) * float(i),
						(card_rect.size.y - size) * 0.5),
				Vector2(size, size)))
	return out


## Ready = the board already holds a chip that satisfies this card (or it was claimed).
## 2026-11-06: a card is only ready when EVERY mission row can be paid right now.
## Returning true on the first satisfiable row lit up cards whose other row was still
## missing (the "last card is green but cannot be claimed" bug).
func _card_ready(card: Dictionary) -> bool:
	var items := _as_mission(card)
	if items.is_empty():
		return false
	for item in items:
		var have := int((item as Dictionary).get("have", 0))
		var need := maxi(int((item as Dictionary).get("need", 1)), 1)
		if have >= need:
			continue
		if bool((item as Dictionary).get("ready", false)):
			continue
		return false
	return true


func _as_mission(card: Dictionary) -> Array:
	var items = card.get("mission", [])
	return items if typeof(items) == TYPE_ARRAY else []


const STOCKPILE_RECT := Layout.STOCKPILE_RECT


## 任务带左侧的库存面板：底板 + 内部棋子 + 红点次数 + 右下箭头。
## 2026-11-06: 从 game_screen 的 Chrome 搬过来 —— 实例化本面板的界面（含成片）自带
## 这块控件。几何仍然只有 Layout 一个来源（页面坐标），画之前换成局部坐标。
func _draw_stockpile() -> void:
	if not _stockpile_on:
		return
	# 次数归零也挂在原位，只有整关没启用库存时才收起来。
	var rect := _stockpile_local_rect()
	if not _draw_ui_fit("stockpile_frame", rect):
		draw_rect(rect, Color("#DCE6F2"), true)
	var chip := _chip_texture(_stockpile_entity, _stockpile_level)
	if chip != null:
		draw_texture_rect(chip, rect.grow(-10.0), false)
	# 参照设计图：绿箭头 46×56 贴右下，红点 62×62 压在面板上沿并往内收。
	var arrows := _ui_texture("stockpile_arrows")
	if arrows != null:
		draw_texture_rect(arrows, Rect2(
				rect.position + Vector2(rect.size.x - 54.0, rect.size.y - 48.0),
				Vector2(46.0, 56.0)), false)
	var dot := _ui_texture("red_dot")
	var drect := Rect2(rect.position + Vector2(rect.size.x - 54.0, -8.0), Vector2(62.0, 62.0))
	if dot != null:
		draw_texture_rect(dot, drect, false)
	var num_font := _font_display()
	if num_font == null:
		num_font = _font
	_text_center_font(num_font, drect.grow(-4.0), str(_stockpile_count), 36, Color.WHITE)


## 页面坐标 -> 本控件局部坐标。页面左上角就是画布原点，面板自己的页内偏移
## （实机是订单带 (0,210)，成片放哪儿算哪儿）由画布变换给出，不写死数字。
func _stockpile_local_rect() -> Rect2:
	var page: Rect2 = STOCKPILE_RECT
	var origin := get_global_transform_with_canvas().origin
	return Rect2(page.position - origin, page.size)


## 保持比例放进矩形（和实机 chrome 的 draw_ui_fit 同一口径，含留白居中）。
func _draw_ui_fit(key: String, r: Rect2) -> bool:
	var texture := _ui_texture(key)
	if texture == null:
		return false
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return false
	var used := minf(r.size.x / source.x, r.size.y / source.y)
	var drawn := source * used
	draw_texture_rect(texture, Rect2(r.position + (r.size - drawn) * 0.5, drawn), false)
	return true


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
		# 2026-11-09：订单的钻石奖励（卡片底部蓝条里的图标 + 数字）。
		"gem": int(raw.get("gem", 0)),
		"energy": int(raw.get("energy", 0)),
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


## 2026-11-09：卡片底部蓝条里的奖励 —— 闪电（体力）在前、钻石在后，各自一个数字。
## 数字来自订单数据（sample_project.json 的 orders[].energy / orders[].gem），实机与成片读同一份快照。
## 某一项 <= 0 就只画另一项；两项都没有就整个不画（老数据保持原样）。
func _draw_reward_strip(r: Rect2, card: Dictionary) -> void:
	var energy := int(card.get("energy", 0))
	var gems := int(card.get("gem", 0))
	if energy <= 0 and gems <= 0:
		return
	var font: Font = _font_display()
	if font == null:
		font = _font
	var energy_w := _text_width(font, str(energy), REWARD_LABEL_PX) if energy > 0 else 0.0
	var gem_w := _text_width(font, str(gems), REWARD_LABEL_PX) if gems > 0 else 0.0
	var rects := reward_row_rects(r, energy_w, gem_w)
	if energy > 0:
		_draw_reward_pair(rects, "energy", str(energy), font)
	if gems > 0:
		_draw_reward_pair(rects, "gem", str(gems), font)


## 一组 [图标 + 数字]：图标取主题槽位（energy / gem），没贴图就画程序化形状，位置不变。
func _draw_reward_pair(rects: Dictionary, kind: String, text: String, font: Font) -> void:
	var icon_rect: Rect2 = rects[kind + "_icon"]
	var label_rect: Rect2 = rects[kind + "_label"]
	var icon := _ui_texture(kind)
	if icon != null:
		draw_texture_rect(icon, icon_rect, false)
	elif kind == "gem":
		var pts := PackedVector2Array([
			icon_rect.position + Vector2(icon_rect.size.x * 0.5, 0.0),
			icon_rect.position + Vector2(icon_rect.size.x, icon_rect.size.y * 0.42),
			icon_rect.position + Vector2(icon_rect.size.x * 0.5, icon_rect.size.y),
			icon_rect.position + Vector2(0.0, icon_rect.size.y * 0.42),
		])
		draw_colored_polygon(pts, Color("#E85FD8"))
	else:
		var mid := icon_rect.get_center()
		var bolt := PackedVector2Array([
			mid + Vector2(2.0, -icon_rect.size.y * 0.5),
			mid + Vector2(-icon_rect.size.x * 0.38, icon_rect.size.y * 0.08),
			mid + Vector2(0.0, icon_rect.size.y * 0.08),
			mid + Vector2(-2.0, icon_rect.size.y * 0.5),
			mid + Vector2(icon_rect.size.x * 0.38, -icon_rect.size.y * 0.08),
			mid + Vector2(0.0, -icon_rect.size.y * 0.08),
		])
		draw_colored_polygon(bolt, Color("#FFC53D"))
	if font != null:
		# 先铺描边（同一段字偏移画一圈），再压白字，得到参考图那种"白字深蓝边"
		var r := REWARD_LABEL_STROKE_PX
		var ring: Array = []
		for i in 8:
			var a := TAU * float(i) / 8.0
			ring.append(Vector2(cos(a), sin(a)) * r)
		var d := r * 0.7071
		ring.append(Vector2(d, d))
		ring.append(Vector2(-d, d))
		ring.append(Vector2(d, -d))
		ring.append(Vector2(-d, -d))
		for off in ring:
			_text_center_font(font, Rect2(label_rect.position + off, label_rect.size), text,
					REWARD_LABEL_PX, REWARD_LABEL_STROKE)
		_text_center_font(font, label_rect, text, REWARD_LABEL_PX, REWARD_LABEL_COLOR)


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


## 量一段文字在当前显示字体下的宽度（布局要先知道宽度才好居中）。
func _text_width(font: Font, text: String, size_px: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x


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


## 指定字体的居中标签：基线和实机 chrome 的 text_center_font 同一套算式，
## 所以库存红点里的数字搬过来以后位置一像素都不动。
func _text_center_font(font: Font, r: Rect2, text: String, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var baseline := r.position + Vector2((r.size.x - width) * 0.5,
			r.size.y * 0.5 + float(size_px) * 0.36)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


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
