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
## 2026-11-10：交付前把目标卡"弹"进可见槽位（橡皮筋），交付必须在画面里发生。
var _pinned_id: String = ""
## 最近一次被 reveal_card 提到最前的卡；屏上的卡不会被记录（原地收集）
var _promoted_id: String = ""
var _pinned_until: float = -1.0
## 立绘是否由本组件绘制（成片端关掉，改由成片自己画，好保持"顶栏压在立绘上"的层级）。
var draw_portraits: bool = true
## 是否铺不透明底条：实机需要（盖住棋盘标题行），成片不用（成片自己画背景）。
var draw_page_strip: bool = true
## 卡片上的绿色对号（可交付/已完成确认标）。2026-11-09 操作者要求**先隐藏**；
## 留成开关而不是删代码，随时能开回来。顶层开关，实机与成片共用同一份。
## 2026-11-10：大绿底对号 = 唯一的交付按钮；只在**整卡全满**时出现。
var draw_confirm_badge: bool = true
## 任务带左侧的库存面板状态（-1 表示本关没有库存）。
## 队列重排：每张卡的目标 x 和当前 x（换位时用 0.25s 缓动滑过去）。
var _target_x: Dictionary = {}
var _x_now: Dictionary = {}
## Claimed cards shrink away before the queue closes the gap.
const CompletedCells = preload("res://src/core/completed_cells.gd")
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
## 2026-11-10：库存投的是棋子还是生成器（生成器用高级生成器图标）。
var _stockpile_kind: String = "chip"
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


## 2026-11-10（交付改版）：角标数字**只认棋盘**。
## 每个子任务各算各的（entity@level），允许盈余、允许回退；被冰/网/盒子盖住的不算。
## 面板不再依赖"行数据里带的 board"（那条路会被 done/claim_pending 冻住）。
var _board_counts: Dictionary = {}


func set_board_snapshot(snap: Dictionary) -> void:
	# 2026-11-10（交付改版，第三版）：
	# 数字 = **棋盘上露在外面的该 entity@level 棋子数量**，与"这一行是否收满、是否已交"无关。
	# 早先借 CompletedCells（绿勾）来数，行一旦满足就不再数，导致 3 枚 lv2 只显示 1/1。
	var counts := {}
	var board = snap.get("board", null)
	if typeof(board) == TYPE_DICTIONARY:
		var blocked := {}
		for row in (board as Dictionary).get("obstacles", []):
			if typeof(row) == TYPE_ARRAY and (row as Array).size() >= 2:
				blocked["%d@%d" % [int((row as Array)[0]), int((row as Array)[1])]] = true
		for raw in (board as Dictionary).get("cells", []):
			if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
				continue
			var c: Array = raw
			if blocked.has("%d@%d" % [int(c[0]), int(c[1])]):
				continue
			var key := "%s@%d" % [String(c[2]), int(c[3])]
			counts[key] = int(counts.get(key, 0)) + 1
	if counts != _board_counts:
		_board_counts = counts
		queue_redraw()


func board_count(entity: String, level: int) -> int:
	return int(_board_counts.get("%s@%d" % [entity, level], 0))


func set_clock(t: float) -> void:
	_clock_now = t
	# 2026-11-11（排序重写）：只保留**一套**排序 —— 绿底大对号（整卡全满）靠前，
	# 组内按"谁先满"（FIFO），非绿组保持原有相对顺序；动画期间完全冻结。
	_sort_queue()
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




## 这张卡当前排第几（0 = 最左边）。找不到返回 -1。
func card_index(order_id: String) -> int:
	for i in cards.size():
		if String((cards[i] as Dictionary).get("id", "")) == order_id:
			return i
	return -1


## 把目标卡**提到最前**（橡皮筋效果由 _x_now 的缓动给出：所有卡从旧位置滑到新位置）。
## 已经在首位就返回 0；否则返回滑行需要的秒数，调用方据此延迟飞行/落袋。
func reveal_card(order_id: String, seconds: float = 0.26) -> float:
	# 2026-11-11（排序重写）：**不再为了交付把卡提到最前** —— 顺序只由"绿/非绿"决定。
	# 保留签名（调用方还在用它算延迟），返回值恒 0 表示没有滑行延迟。
	return 0.0


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
		# 2026-11-09：交任务那一刻起（含交付动画的 hold 期）角标就要读成 1/1 绿，
		# 所以 claim_pending 也算"已交付"；sim 里的 have 仍是 0，这里只是显示推导。
		# 2026-11-10（交付改版）：**不再因为 done/claim_pending 就冻结任务行**。
		# 数字永远跟棋盘走（允许 6/4、也允许从 6/4 掉回 2/4）；
		# 只有"正在缩卡结算"（claim_pending）时才把 have 顶到 need 给一次完成观感。
		var claiming := bool(card["done"]) or bool(card.get("claim_pending", false))
		# 2026-11-11（操作者要求）：点大对号提交的**那一瞬**，任务栏对应行要锁住当时的
		# 状态和数字（4/4 就一直是 4/4），不能因为棋子飞走、棋盘变少就当场掉数变色。
		if claiming and not bool(card.get("display_locked", false)):
			var frozen: Array = []
			for i in range(items.size()):
				var it: Dictionary = (items as Array)[i]
				var shown := int(it.get("board", -1))
				if shown < 0:
					shown = board_count(String(it.get("entity", "")), int(it.get("level", 1)))
				frozen.append(shown)
			card["display_locked"] = true
			card["locked_board"] = frozen
		for i in range(items.size()):
			if typeof(mission_rows) != TYPE_ARRAY or i >= (mission_rows as Array).size():
				continue
			var item: Dictionary = items[i]
			_sync_mission_item(item, (mission_rows as Array)[i])
			if claiming:
				item["have"] = int(item.get("need", 1))
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
		# 2026-11-10：角标数字读的是**棋盘上的枚数**（允许 6/4 盈余），必须跟着行数据一起转，
		# 漏这一行就会出现"棋盘明明有一堆，面板还写 0/4"（操作者截图报的）。
		item["board"] = int(row.get("board", item.get("board", 0)))
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
func set_stockpile(count: int, entity: String, level: int, kind: String = "chip") -> void:
	var changed := (not _stockpile_on) or _stockpile_count != count \
			or _stockpile_entity != entity or _stockpile_level != level \
			or _stockpile_kind != kind
	_stockpile_on = true
	_stockpile_count = count
	_stockpile_entity = entity
	_stockpile_level = level
	_stockpile_kind = kind
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


## ---------------------------------------------------------------- 顺序（唯一实现）
##
## 2026-11-11 重写。口径（操作者原话）：
##   「排序主要看绿底大对号显示不显示，显示就排到前面；前面也是绿的，就顺延。
##     绿的变成不显示，后面的向前补。绿的靠前，但是不插队。」
##   → 两张表：**绿组（整卡全满）按"谁先满"FIFO** + **非绿组保持原有相对顺序**。
##   「交付动画期间不允许重新排，动画缩卡结束后重新算。」
var _full_seq: Dictionary = {}   # order_id -> 首次"整卡全满"的流水号（越小越靠前）
var _seq_counter: int = 0

## 纯函数：给一组 id 和"是否全满 / 首次满分序号"，返回排好的顺序。可单测。
static func queue_order(ids: Array, is_full: Dictionary, full_seq: Dictionary) -> Array:
	var green: Array = []
	var rest: Array = []
	for raw in ids:
		var id := String(raw)
		if bool(is_full.get(id, false)):
			green.append(id)
		else:
			rest.append(id)
	green.sort_custom(func(a, b):
		var sa := int(full_seq.get(a, 0))
		var sb := int(full_seq.get(b, 0))
		if sa != sb:
			return sa < sb
		return String(a) < String(b))
	return green + rest


## 每次状态变化刷新"首次变满"的流水号：变满时发号，掉出全满时作废（再满就罚到绿组末尾）。
func _refresh_full_stamps() -> void:
	for raw in cards:
		var card: Dictionary = raw
		var id := String(card.get("id", ""))
		if id.is_empty():
			continue
		var full := _card_full(card)
		if full and not _full_seq.has(id):
			_seq_counter += 1
			_full_seq[id] = _seq_counter
		elif not full and _full_seq.has(id):
			_full_seq.erase(id)


## 动画期间冻结：缩卡（is_animating）、交付 hold（飞行/落袋/奖励）、结算中都不许动。
func _sort_frozen() -> bool:
	if is_animating():
		return true
	for cid in _hold.keys():
		if _clock_now < float(_hold[cid]):
			return true
	for raw in cards:
		if bool((raw as Dictionary).get("claim_pending", false)):
			return true
	return false


func _sort_queue() -> void:
	if cards.size() < 2 or _sort_frozen():
		return
	_refresh_full_stamps()
	var ids: Array = []
	var is_full: Dictionary = {}
	for raw in cards:
		var id := String((raw as Dictionary).get("id", ""))
		ids.append(id)
		is_full[id] = _card_full(raw)
	var want := queue_order(ids, is_full, _full_seq)
	var changed := false
	for i in ids.size():
		if String(ids[i]) != String(want[i]):
			changed = true
			break
	if not changed:
		return
	var by_id: Dictionary = {}
	for raw in cards:
		by_id[String((raw as Dictionary).get("id", ""))] = raw
	var ordered: Array = []
	for id in want:
		ordered.append(by_id[String(id)])
	cards = ordered
	_layout()
	queue_redraw()


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
		# 2026-11-10：角标看**棋盘枚数**（允许 6/4 这种盈余），不看已交付数。
		var board_n := _row_board(card, i, item)
		var need_n := int(item.get("need", 1))
		var ready := board_n >= need_n
		# 2026-11-05: the mission slot shows the real chip icon when the loader can
		# resolve it; the procedural tile stays as the no-asset fallback.
		var icon := _chip_texture(String(item.get("entity", "")), int(item.get("level", 1)))
		# 2026-11-11（操作者口径）：只有**收满**才算完成态；3/4 这种未满的一律按 0/1 显示
		# （米色底板 + 米白字/暖棕描边），不再"棋盘上有货就变绿"。
		var done_chip := mission_row_done(board_n, need_n)
		# 2026-11-09：底板改成贴图（九宫格，倒角不缩放）：完成 = 浅绿框，未完成 = 米色框。
		var plate_rect := mission_plate_rect(chip)
		# 交付成功那一刻底板"吞一下"（以底板中心为锚点缩放）
		var punch := _punch_scale(String(card.get("id", "")), i)
		# 拖拽悬停在可交付行上：底板再放大一点，给"松手就落这儿"的反馈
		if _hover_hit(String(card.get("id", "")), i):
			punch = maxf(punch, 1.04)
		if punch > 1.0:
			var c := plate_rect.get_center()
			plate_rect = Rect2(c - plate_rect.size * punch * 0.5, plate_rect.size * punch)
		var frame := _ui_texture("mission_frame_done" if done_chip else "mission_frame_todo")
		if frame != null:
			_draw_nine(frame, plate_rect, minf(14.0, plate_rect.size.x * 0.28))
		else:
			_rounded(plate_rect, int(round(plate_rect.size.x * 0.22)),
					MISSION_DONE_PLATE if done_chip else MISSION_TODO_PLATE)
		if icon != null:
			draw_texture_rect(icon, chip, false)
		else:
			_rounded(chip, 14, hue if ready else hue.lerp(Color(1.0, 1.0, 1.0), 0.28))
			_rounded_outline(chip, 14, hue.darkened(0.22), 2)
			_text_center(chip, String(item.get("label", "?")), 24, Color.WHITE)
		# 2026-11-09：**只有真正收齐**（1/1、2/2）才加叹号；棋盘上刚合出来的 0/1 不给。
		if board_n >= need_n:
			_draw_mission_bang(chip)
		# 每个任务棋子右下角带 "已收集/需要" 角标，完成时整块换成绿色。
		_draw_mission_badge(chip, board_n, need_n, mission_row_done(board_n, need_n))


	_draw_reward_row(r, int(card.get("coin", 0)), 0.0)
	if int(card.get("star", 0)) > 0:
		_draw_star_row(r, int(card.get("star", 0)))
	_draw_reward_strip(r, card)

	# 2026-11-06: the badge stays put once shown — it rides the shrink instead of
	# blinking out on click and popping back during the animation.
	# 2026-11-09: 操作者要求先隐藏（draw_confirm_badge=false）；开关在文件顶部。
	if draw_confirm_badge and (bool(card.get("done", false)) \
			or bool(card.get("claim_pending", false)) or _card_full(card)):
		# 2026-11-05: no green rim, no small check — one confirm badge centred on the card.
		var confirm := _ui_texture("confirm")
		var size := Vector2(126.0, 74.0)
		# 2026-11-10：大对号挂到卡片**上沿**，不再压住两行任务的角标。
		var at := Rect2(Vector2(r.get_center().x - size.x * 0.5, r.position.y - size.y * 0.62), size)
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
## 2026-11-09：任务棋子右下角的 "已收集/需要" 角标。颜色取自操作者给的参考图：
## 未完成 = 米白字 + 暖棕描边（#FCFCFC / #947450）；完成 = 亮绿字 + 深绿描边（#B0FC74 / #508018）。
const MISSION_BADGE_PX := 28
const MISSION_BADGE_STROKE_PX := 2.0
const MISSION_BADGE_FILL_OPEN := Color("#FCFCFC")
const MISSION_BADGE_STROKE_OPEN := Color("#947450")
const MISSION_BADGE_FILL_DONE := Color("#B0FC74")
const MISSION_BADGE_STROKE_DONE := Color("#508018")
## 2026-11-09：任务收齐时棋子换成浅绿底板 + 左上角一枚绿色叹号（取色自操作者参考图）。
const MISSION_DONE_PLATE := Color("#ACC08C")
## 未完成底板的兜底色（有贴图时用 mission_frame_todo）。
const MISSION_TODO_PLATE := Color("#E8D5C0")
## 叹号贴在棋子的哪个角：参考图是左上角（false）；改 true 就跑到右上角。
const MISSION_BANG_TOP_RIGHT := false
## 叹号占棋子宽度的比例（参考图里它比底板还大，故意溢出）。
const MISSION_BANG_SCALE := 0.40
## 角标离棋子右下角的留白：往内缩一点，别压在卡片蓝条的分界线上。
const MISSION_BADGE_PAD := 4.0
const MISSION_BADGE_INSET := 6.0
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
## 整卡全满：每一行棋盘上都凑够了需求枚数（允许盈余 6/4）。
## 某一行任务当前该显示的"棋盘枚数"。
## 卡一旦进入结算（点大对号之后），这里返回**提交瞬间锁住的值**，直到卡被移除。
func _row_board(card: Dictionary, row: int, item: Dictionary) -> int:
	if bool(card.get("display_locked", false)):
		var frozen = card.get("locked_board", [])
		if typeof(frozen) == TYPE_ARRAY and row < (frozen as Array).size():
			return int((frozen as Array)[row])
	return board_count(String(item.get("entity", "")), int(item.get("level", 1)))


## 点大对号的那一瞬调用：把这张卡各行**当前显示的数字**锁住。
## 之后棋子飞走、棋盘变少，任务栏都不会掉数/变色，直到卡被移除。
func lock_row_display(order_id: String) -> void:
	var card := _card_by_id(order_id)
	if card.is_empty() or bool(card.get("display_locked", false)):
		return
	var items: Array = card.get("mission", [])
	var frozen: Array = []
	for i in range(items.size()):
		var it: Dictionary = (items as Array)[i]
		frozen.append(board_count(String(it.get("entity", "")), int(it.get("level", 1))))
	card["display_locked"] = true
	card["locked_board"] = frozen
	queue_redraw()


## 测试/探针用：某张卡某一行现在显示的数字（锁定期返回提交瞬间的值）。
func row_board_for(order_id: String, row: int) -> int:
	var card := _card_by_id(order_id)
	if card.is_empty():
		return -1
	var items: Array = card.get("mission", [])
	if row < 0 or row >= items.size():
		return -1
	return _row_board(card, row, (items as Array)[row])


func _card_full(card: Dictionary) -> bool:
	var items: Array = card.get("mission", [])
	if items.is_empty():
		return false
	for i in range(items.size()):
		var item: Dictionary = (items as Array)[i]
		var have := _row_board(card, i, item)
		var need := int(item.get("need", 1))
		if have < need:
			return false
	return true


## 对号贴图的矩形（订单带控件内的局部坐标；调用方自己处理 position）。
func confirm_badge_rect(order_id: String) -> Rect2:
	var r := card_rect(order_id)
	if r.size.x <= 0.0:
		return Rect2()
	var size := Vector2(126.0, 74.0)
	return Rect2(Vector2(r.get_center().x - size.x * 0.5, r.position.y - size.y * 0.62), size)


## 这张卡现在能不能点对号交付（整卡全满、且没在结算/已完成）。
func card_awaiting_confirm(order_id: String) -> bool:
	for card in cards:
		if String(card.get("id", "")) != order_id:
			continue
		if bool(card.get("done", false)) or bool(card.get("claim_pending", false)):
			return false
		return _card_full(card)
	return false


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
	var chip: Texture2D = null
	if _stockpile_kind == "generator":
		chip = _ui_texture("generator_premium")
	if chip == null:
		chip = _chip_texture(_stockpile_entity, _stockpile_level)
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
				# 2026-11-10：一行可以要多枚（JSON 的 count），角标分母就是它
				"need": maxi(int((m as Dictionary).get("count", 1)), 1),
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


## 完成态底板：比棋子小一圈，**底边贴着蓝条**，只从上方和两侧收缩（操作者参考图口径）。
static func mission_plate_rect(chip: Rect2) -> Rect2:
	var inset_x := chip.size.x * 0.06
	var inset_top := chip.size.y * 0.10
	return Rect2(chip.position + Vector2(inset_x, inset_top),
			chip.size - Vector2(inset_x * 2.0, inset_top))


## 完成叹号的矩形：**以叹号的右下角为锚点**挂在底板左上角，所以会溢出底板。
static func mission_bang_rect(chip: Rect2) -> Rect2:
	var side := chip.size.x * MISSION_BANG_SCALE
	var plate := mission_plate_rect(chip)
	# 向中心收：右下角落在底板左上角往里 55% 叹号边长处，约等于"叹号中心压角"
	var inset := side * 0.55
	var anchor := plate.position + Vector2(inset, inset)
	if MISSION_BANG_TOP_RIGHT:
		anchor = Vector2(plate.end.x - inset, plate.position.y + inset)
	# 右下角落在 anchor 上 -> 左上角 = anchor - side
	return Rect2(anchor - Vector2(side, side), Vector2(side, side))


## 叹号什么时候出现：**只认真正收齐**（1/1、2/2…）。棋盘上合出来了但还没交（0/1 绿）不给，
## 这是操作者 2026-11-09 补的口径——和底板/角标的绿色判定是两件事。
static func mission_bang_visible(have: int, need: int) -> bool:
	return have >= maxi(need, 1)


## 角标什么时候算"完成态（绿色）"：棋盘上已经有这枚棋子（ready），或已经交付（have >= need）。
## 2026-11-11：任务行的"完成态"只有一个判据 —— **收满**（棋盘枚数 ≥ 需求）。
## 3/4 这类未满的，底板与字体颜色全部按 0/1 处理（操作者口径）。
static func mission_row_done(board: int, need: int) -> bool:
	return board >= maxi(need, 1)


static func mission_badge_done(have: int, need: int, ready: bool) -> bool:
	return ready or have >= maxi(need, 1)


## 交付成功时让那一行底板"吞一下"（1.10 → 1.0，0.18s）。实机与成片共用。
var _punch: Dictionary = {}
## 拖拽时指针落在哪一行上（只记可交付的那一行），画一层高亮。
var _hover: Dictionary = {}

func set_hover_row(order_id: String, row: int) -> void:
	var next := {} if order_id.is_empty() else {"order": order_id, "row": row}
	if next != _hover:
		_hover = next
		queue_redraw()


func _hover_hit(order_id: String, row: int) -> bool:
	return not _hover.is_empty() and String(_hover.get("order", "")) == order_id 			and int(_hover.get("row", -1)) == row

func punch_row(order_id: String, row: int, delay: float = 0.0) -> void:
	# delay：飞过来的那枚要等它落到才"吞一下"（拖拽交付同类传 0）
	_punch = {"order": order_id, "row": row, "started": _clock_now + maxf(delay, 0.0)}


func _punch_scale(order_id: String, row: int) -> float:
	if _punch.is_empty():
		return 1.0
	if String(_punch.get("order", "")) != order_id or int(_punch.get("row", -1)) != row:
		return 1.0
	var p: float = clampf((_clock_now - float(_punch.get("started", 0.0))) / 0.18, 0.0, 1.0)
	if p >= 1.0:
		_punch = {}
		return 1.0
	return 1.0 + 0.10 * (1.0 - p)


## 奖励飞行的**起点**：金币取卡片上方"+N"那个药丸里的金币图标中心；
## 闪电 / 钻石取卡片蓝条里各自图标中心。订单卡是哪张就取哪张 —— 起点是动态的。
## 返回**页面坐标**（卡片矩形本身就是页面坐标）。
## 交付动画还在跑的时候别排序：把这张卡钉在第一位的时长往后延。
## 顺序永远是「提到第一位 → 棋子飞 → 落袋 → **再**按完成度排序」。
func hold_sort(order_id: String, seconds: float) -> void:
	# 2026-11-11：排序不再有"钉住某张卡"的概念，保留空实现兼容调用方。
	pass


## 这张卡的**稳定位置**（滑行结束后停在哪儿）。交付飞行、奖励起点都用它，
## 不能用 card_rect() 的动画中 x —— 卡片刚被"提到最前"时还在滑动，
## 用中间值会让飞行/奖励从**原来的地方**出发（操作者报过两次）。
func settled_rect(order_id: String) -> Rect2:
	if not _rects.has(order_id) or not _target_x.has(order_id):
		_layout()
	var r: Rect2 = card_rect(order_id)
	if r.size.x <= 0.0:
		return r
	var settled_x = _target_x.get(order_id, null)
	if settled_x != null:
		r.position.x = float(settled_x) + _row_offset
	return r


func reward_origin(order_id: String, kind: String) -> Vector2:
	var card: Dictionary = _card_by_id(order_id)
	if card.is_empty():
		return Vector2.ZERO
	var r: Rect2 = settled_rect(order_id)
	if r.size.x <= 0.0:
		return Vector2.ZERO
	if kind == "coin":
		var icon_size := Vector2(132.0, 49.0)
		var icon_rect := Rect2(Vector2(r.end.x - icon_size.x, r.position.y - 54.0), icon_size)
		var coin_at: Vector2 = icon_rect.position + Vector2(24.0, icon_size.y * 0.5)
		coin_at.x = clampf(coin_at.x, 24.0, 1080.0 - 24.0)
		return coin_at
	var energy := int(card.get("energy", 0))
	var gems := int(card.get("gem", 0))
	var font: Font = _font_display()
	if font == null:
		font = _font
	var energy_w := _text_width(font, str(energy), REWARD_LABEL_PX) if energy > 0 else 0.0
	var gem_w := _text_width(font, str(gems), REWARD_LABEL_PX) if gems > 0 else 0.0
	var rects := reward_row_rects(r, energy_w, gem_w)
	var key := kind + "_icon"
	var rect: Rect2 = rects.get(key, Rect2())
	var out: Vector2 = rect.get_center() if rect.size.x > 0.0 else r.get_center()
	# 2026-11-10：奖励起点必须落在**画面内**（卡片被排到屏外时也不能从屏幕外冒出来）
	out.x = clampf(out.x, 24.0, 1080.0 - 24.0)
	out.y = clampf(out.y, 24.0, 1920.0 - 24.0)
	return out


## 某张卡第 row 个任务格子的**底板中心**（面板局部坐标）。飞行落点用它，
## 让棋子飞进"那一行"而不是卡片中心。
func mission_row_center(order_id: String, row: int) -> Vector2:
	# 落点用**稳定位置**：棋子是等卡片滑到位之后才起飞的
	var rect: Rect2 = settled_rect(order_id)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	var card: Dictionary = _card_by_id(order_id)
	var items: Array = card.get("mission", [])
	if row < 0 or row >= items.size():
		row = clampi(row, 0, maxi(items.size() - 1, 0))
	var chips := mission_chip_rects(mission_area_rect(rect), items.size())
	if chips.is_empty():
		return rect.get_center()
	return mission_plate_rect(chips[row]).get_center()


## 命中测试：面板**局部**坐标点在哪一行的**底板**里。只认绿色（可交付）的行，
## 棕色的（棋盘上还不够数）一律当没点到 —— 操作者要求"范围就是底色的范围"。
func mission_row_at(local_point: Vector2) -> Dictionary:
	for raw in cards:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw
		if bool(card.get("done", false)):
			continue
		var id := String(card.get("id", ""))
		var rect: Rect2 = card_rect(id)
		if rect.size == Vector2.ZERO:
			continue
		var items: Array = card.get("mission", [])
		var chips := mission_chip_rects(mission_area_rect(rect), items.size())
		for i in range(mini(items.size(), chips.size())):
			if not mission_plate_rect(chips[i]).has_point(local_point):
				continue
			var item: Dictionary = items[i]
			var have := int(item.get("have", 0))
			var need := maxi(int(item.get("need", 1)), 1)
			# 只有"可交付"（绿色）的行才接单：棋盘上不够数的行一律当没点到
			if not (bool(item.get("ready", false)) or have >= need):
				return {}
			return {
				"order": id, "row": i, "ready": true,
				"center": mission_plate_rect(chips[i]).get_center(),
			}
	return {}


func _card_by_id(order_id: String) -> Dictionary:
	for raw in cards:
		if typeof(raw) == TYPE_DICTIONARY and String((raw as Dictionary).get("id", "")) == order_id:
			return raw
	return {}


## 任务棋子右下角的 "have/need" 角标矩形（右下角对齐，宽按文字量出来）。
static func mission_badge_rect(chip: Rect2, text_w: float) -> Rect2:
	var box := Vector2(maxf(text_w, 1.0) + MISSION_BADGE_PAD, float(MISSION_BADGE_PX) * 1.3)
	return Rect2(chip.end - box - Vector2(MISSION_BADGE_INSET, MISSION_BADGE_INSET), box)


## 画"任务完成"的小叹号：有贴图就用贴图，没有就画同色的程序化叹号。
func _draw_mission_bang(chip: Rect2) -> void:
	var box := mission_bang_rect(chip)
	var icon := _ui_texture("exclamation")
	if icon != null:
		draw_texture_rect(icon, box, false)
		return
	var w := box.size.x
	_rounded(Rect2(box.position + Vector2(w * 0.38, w * 0.16), Vector2(w * 0.24, w * 0.46)),
			8, Color("#98DC18"))
	draw_circle(box.position + Vector2(w * 0.5, w * 0.80), w * 0.14, Color("#98DC18"))


## 画一枚角标：描边（8 方向 + 4 对角）压正文，颜色随"是否收齐"切换。
## 三态（2026-11-09 操作者口径）：
##   0/1 棕色  = 还没有这枚棋子
##   0/1 绿色  = 棋盘上已经合成出来了（多出来的一步）
##   1/1 绿色  = 已经交付给订单
func _draw_mission_badge(chip: Rect2, have: int, need: int, ready: bool) -> void:
	var font: Font = _font_display()
	if font == null:
		font = _font
	if font == null:
		return
	var want := maxi(need, 1)
	# 2026-11-10：不封顶 —— 棋盘上 5 枚就写 5/4、3 枚就写 3/1（操作者明确要求）。
	var text := "%d/%d" % [maxi(have, 0), want]
	var done := mission_badge_done(have, want, ready)
	var text_w := _text_width(font, text, MISSION_BADGE_PX)
	var label := mission_badge_rect(chip, text_w)
	var stroke: Color = MISSION_BADGE_STROKE_DONE if done else MISSION_BADGE_STROKE_OPEN
	var fill: Color = MISSION_BADGE_FILL_DONE if done else MISSION_BADGE_FILL_OPEN
	var r := MISSION_BADGE_STROKE_PX
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
		_text_center_font(font, Rect2(label.position + off, label.size), text,
				MISSION_BADGE_PX, stroke)
	_text_center_font(font, label, text, MISSION_BADGE_PX, fill)


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
