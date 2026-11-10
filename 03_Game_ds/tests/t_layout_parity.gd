extends RefCounted
## 对拍护栏（2026-11-06）：实机订单带、成片订单带、库存面板必须共用同一套几何。
## 不渲染像素，只断言"同一个数字" —— 几何漂移一发生就红。

const Layout = preload("res://src/view/layout_shared.gd")
const OrderPanel = preload("res://src/view/order_panel.gd")
const MovieScene = preload("res://src/render/movie_scene.gd")
const GameScreen = preload("res://src/view/game_screen.gd")
const TopBar = preload("res://src/view/top_bar.gd")

const COUNTS := [1, 2, 3, 5]


func run(t) -> void:
	_shared_constants(t)
	_panel_constants(t)
	_film_constants(t)
	_rects_match(t)
	_stockpile_matches(t)
	_top_bar_matches(t)
	_coin_anchor_matches(t)
	_card_decor_matches(t)


func _shared_constants(t) -> void:
	t.eq(Layout.QUEUE_ORIGIN_X, 208.0, "队列起点 208（两张 424 宽的卡都完整落在 1080 内）")
	t.eq(Layout.QUEUE_CARD_W, 424.0, "卡宽 424（容纳 4 枚任务图标）")
	t.eq(Layout.CARD_GAP_X, 18.0, "卡间距 18")
	t.eq(Layout.CARD_H, 140.0, "卡高 140")
	t.eq(Layout.PORTRAIT_H, 300.3, "立绘高 210")
	t.eq(Layout.PORTRAIT_TOP_ABOVE_CARD, 160.0, "立绘压卡片 26")
	t.eq(Layout.BAND_Y, 210.0, "订单带 y=210")
	t.eq(Layout.CARD_LOCAL_Y, 55.0, "卡在带内 y=55")


func _panel_constants(t) -> void:
	t.eq(OrderPanel.QUEUE_ORIGIN_X, Layout.QUEUE_ORIGIN_X, "面板起点来自共享布局")
	t.eq(OrderPanel.MAX_CARD_W, Layout.QUEUE_CARD_W, "面板卡宽来自共享布局")
	t.eq(OrderPanel.CARD_GAP_X, Layout.CARD_GAP_X, "面板间距来自共享布局")
	t.eq(OrderPanel.PORTRAIT_H, Layout.PORTRAIT_H, "面板立绘高来自共享布局")


func _film_constants(t) -> void:
	t.eq(MovieScene.CARD_H, Layout.CARD_H, "成片卡高来自共享布局")
	t.eq(MovieScene.CARD_GAP, Layout.CARD_GAP_X, "成片间距来自共享布局")
	t.eq(MovieScene.QUEUE_ORIGIN_X, Layout.QUEUE_ORIGIN_X, "成片起点来自共享布局")
	t.eq(MovieScene.QUEUE_CARD_W, Layout.QUEUE_CARD_W, "成片卡宽来自共享布局")
	t.eq(MovieScene.PORTRAIT_HEIGHT, Layout.PORTRAIT_H, "成片立绘高来自共享布局")
	t.eq(MovieScene.PORTRAIT_SINK, Layout.PORTRAIT_SINK, "成片立绘压卡来自共享布局")


func _rects_match(t) -> void:
	for count in COUNTS:
		var film = MovieScene.new()
		var snap := {"orders": []}
		for i in count:
			snap["orders"].append({"id": "o%d" % i, "character": "char_blonde",
					"mission": [], "done": false})
		var cards: Array = film._order_cards(snap)
		t.eq(cards.size(), count, "成片为 %d 张卡算出矩形" % count)
		var shared := Layout.card_rects(count)
		for i in mini(cards.size(), shared.size()):
			t.eq(cards[i], shared[i], "成片第 %d 张卡矩形一致（%d 张时）" % [i, count])
		film.free()

		var panel = OrderPanel.new()
		panel.size = Vector2(1080.0, 250.0)
		panel.cards = []
		for i in count:
			panel.cards.append({"id": "o%d" % i, "character": "char_blonde", "coin": 0,
					"star": 0, "done": false, "mission": []})
		panel._layout()
		for i in count:
			var local: Rect2 = panel.card_rect("o%d" % i)
			var page := Rect2(local.position + Vector2(0.0, Layout.BAND_Y), local.size)
			t.eq(page, Layout.card_rect(i), "实机第 %d 张卡矩形一致（%d 张时）" % [i, count])
		panel.free()


func _stockpile_matches(t) -> void:
	t.eq(GameScreen.STOCKPILE_RECT, Layout.STOCKPILE_RECT, "库存面板矩形来自共享布局")
	t.eq(OrderPanel.STOCKPILE_RECT, Layout.STOCKPILE_RECT, "面板库存矩形来自共享布局")

## 顶栏几何是实机/成片的公共契约：这里是本轮实测的黄金值。
func _top_bar_matches(t) -> void:
	var bar = TopBar.new()
	var rects: Dictionary = bar.bar_rects()
	# float32 精度：用 0.01 容差比较
	var win: Rect2 = rects["energy"]
	t.ok(absf(win.position.x - 195.1575) < 0.01 and absf(win.size.x - 199.7883) < 0.01,
			"体力条矩形", str(win))
	var coin: Rect2 = rects["coin"]
	t.ok(absf(coin.position.x - 424.9458) < 0.01 and absf(coin.size.x - 230.1085) < 0.01,
			"金币条矩形", str(coin))
	var gem: Rect2 = rects["gem"]
	t.ok(absf(gem.position.x - 685.0543) < 0.01 and absf(gem.size.x - 240.9457) < 0.01,
			"钻石条矩形", str(gem))
	t.eq(TopBar.SHOP, Rect2(930.0, 8.0, 142.0, 132.0), "商店按钮矩形")
	t.eq(TopBar.LEVEL_BADGE, Rect2(16.0, 16.0, 96.0, 67.2), "等级爪印矩形")
	t.ok(absf(rects["coin"].get_center().x - 540.0) < 0.5, "金币条居中在 540")
	bar.free()


## 金币螺旋的落点（2026-11-09）：成片必须问顶栏组件要坐标，不许自己写死。
## 反面证据：写死值 (473.6,49.6) 是已退役 hud_view 的公式（(552+40)*0.8, (20+42)*0.8），
## 比金币图标的真实中心偏右 15px、偏上 6px。
func _coin_anchor_matches(t) -> void:
	var bar = TopBar.new()
	var coin: Vector2 = bar.counter_center("coin")
	var rect: Rect2 = bar.bar_rects()["coin"]
	# 黄金值 = coin_bar.png 里金币圆盘 bbox(3,2)-(72,73) 的中心 (37.5,37.5)/255x82，
	# 等比映射进金币条矩形后的页面坐标（成片帧 00040.png 实测 (459.0,56.5)，差 1.7px）。
	t.ok(absf(coin.x - 458.785) < 0.1 and absf(coin.y - 54.841) < 0.1,
		"金币落点 = 图标中心", str(coin))
	t.ok(rect.has_point(coin), "落点在金币条内", str(coin))
	t.ok(coin.x < rect.get_center().x - 40.0, "落点在数字左侧（不是条中心）", str(coin))
	t.ok(coin.distance_to(Vector2(473.6, 49.6)) > 10.0,
		"不再是退役 hud_view 的硬编码", str(coin))

	# 成片：同一个函数，不许另算一份
	var film = MovieScene.new()
	film._live_top = bar
	t.eq(film._hud_coin_anchor(), coin, "成片落点来自顶栏组件")
	film._live_top = null
	t.eq(film._hud_coin_anchor(), Vector2.ZERO, "没有顶栏时不猜坐标")
	film.free()

	# 实机：也必须问顶栏组件，不能继续用那个隐藏 hud_view 的换算
	var screen = GameScreen.new()
	screen.top_bar = bar
	t.eq(screen._coin_anchor(Vector2(592.0, 62.0)), coin, "实机落点来自顶栏组件")
	screen.top_bar = null
	t.eq(screen._coin_anchor(Vector2(592.0, 62.0)), Vector2(592.0, 62.0), "无顶栏时退回原坐标")

	# 2026-11-09：钻石落点同样问顶栏组件（gem_bar 里那颗粉钻的中心）
	var gem_pt: Vector2 = bar.counter_center("gem")
	var gem_rect: Rect2 = bar.bar_rects()["gem"]
	t.ok(gem_rect.has_point(gem_pt), "钻石落点在钻石条内", str(gem_pt))
	t.ok(gem_pt.x < gem_rect.get_center().x, "钻石落点在数字左侧", str(gem_pt))
	t.ok(gem_pt.distance_to(bar.counter_center("coin")) > 100.0, "钻石与金币落点不重叠", str(gem_pt))
	screen.top_bar = bar   # 上一步为了测兜底把它置空了，这里放回来
	t.eq(screen._gem_anchor(Vector2(700.0, 62.0)), gem_pt, "实机钻石落点来自顶栏组件")
	var film2 = MovieScene.new()
	film2._live_top = bar
	t.eq(film2._hud_gem_anchor(), gem_pt, "成片钻石落点来自顶栏组件")
	film2._live_top = null
	film2.free()
	screen.free()
	bar.free()


## 卡面装饰（2026-11-09 操作者要求）：绿对号先隐藏、任务棋子缩到正常尺寸。
## 两条都在 order_panel 里 -> 实机与成片一起吃（§8 双画面同步）。
func _card_decor_matches(t) -> void:
	# 绿对号：默认隐藏，但开关还在（随时能开回来）
	var panel = OrderPanel.new()
	t.eq(panel.draw_confirm_badge, false, "卡片绿对号默认隐藏")
	panel.draw_confirm_badge = true
	t.eq(panel.draw_confirm_badge, true, "开关可以打开（不是删代码）")
	panel.free()

	# 任务棋子尺寸：必须整整齐齐落在卡片里，不能再糊到卡片边上
	var card := Rect2(0.0, 0.0, Layout.QUEUE_CARD_W, Layout.CARD_H)
	t.eq(OrderPanel.CHIP_SIZE, 96.0, "任务棋子 96 见方")
	t.ok(OrderPanel.CHIP_SIZE < Layout.CARD_H - 40.0, "棋子高度给卡片上下留够留白",
			str(OrderPanel.CHIP_SIZE))

	var one: Array = OrderPanel.mission_chip_rects(card, 1)
	t.eq(one.size(), 1, "一枚任务棋子算出一个矩形")
	t.eq((one[0] as Rect2).size, Vector2(96.0, 96.0), "棋子矩形 96x96")
	t.ok(card.encloses(one[0]), "单枚棋子不越出卡片", str(one[0]))
	t.eq((one[0] as Rect2).get_center().x, card.get_center().x, "单枚水平居中")
	t.eq((one[0] as Rect2).get_center().y, card.get_center().y, "单枚垂直居中")

	var two: Array = OrderPanel.mission_chip_rects(card, 2)
	t.eq(two.size(), 2, "两行任务算出两个矩形")
	t.ok(card.encloses(two[0]) and card.encloses(two[1]), "两枚都不越出卡片",
			str(two))
	t.ok((two[0] as Rect2).end.x <= (two[1] as Rect2).position.x, "两枚不重叠", str(two))
	t.eq((two[0] as Rect2).get_center().x + (two[1] as Rect2).get_center().x,
			card.get_center().x * 2.0, "两枚整体居中")

	t.eq(OrderPanel.mission_chip_rects(card, 0), [], "没有任务行就没有棋子")

	# 2026-11-09：新任务栏底图底部蓝条 = 钻石奖励行（操作者要求"蓝条居中放钻石 + 数字"）
	# 0.279 是九宫格铺到 250x140 后**实测**的蓝条比例（贴图分界 124/178，角 26 不缩放）。
	t.eq(Layout.GEM_STRIP_RATIO, 0.279, "蓝条占卡高 27.9%（实测，贴图分界 124/178）")
	t.eq(OrderPanel.GEM_STRIP_RATIO, Layout.GEM_STRIP_RATIO, "面板的蓝条比例来自共享布局")

	var strip: Rect2 = OrderPanel.gem_strip_rect(card)
	t.ok(absf(strip.size.y - card.size.y * 0.279) < 0.01, "蓝条高度 = 卡高 × 0.279",
			str(strip.size.y))
	t.eq(strip.end.y, card.end.y, "蓝条贴卡片底边")
	t.eq(strip.size.x, card.size.x, "蓝条横跨整张卡片")

	var area: Rect2 = OrderPanel.mission_area_rect(card)
	t.ok(absf(area.size.y + strip.size.y - card.size.y) < 0.01, "蓝条之上正好是任务区",
			"%.3f" % (area.size.y + strip.size.y))
	var chips_in_area: Array = OrderPanel.mission_chip_rects(area, 2)
	for k in chips_in_area.size():
		t.ok(area.encloses(chips_in_area[k]), "第 %d 枚棋子不越出任务区（不进蓝条）" % k,
				str(chips_in_area[k]))

	# 2026-11-09：蓝条里是**两组**奖励 —— 闪电在前、钻石在后，各组一个数字，两组一起居中
	# 2026-11-09：单卡（第 1 关）必须和队列里其它卡**同宽**。
	# 原来单卡走 anchor 分支按"跟角色一样宽"算，导致第 1 关的卡比第 2 关窄一截。
	var solo = OrderPanel.new()
	solo.set_metrics({"card_gap": 18.0, "card_radius": 22.0})
	solo.build_from_level({"id": "solo_lv", "orders": [
		{"id": "solo_1", "character": "char_blonde", "mission": [{"entity": "CleanSet_Ca", "level": 1}],
			"coin": 5, "star": 0, "gem": 1, "energy": 10}]})
	solo.size = Vector2(1080.0, 250.0)
	# 单卡和第 2 关的卡必须是**同一套几何**（操作者：只是配置了 1 张卡 + 1 个任务）。
	# 就算调用方塞了 anchor，也不再影响宽高和位置。
	solo.set_card_anchors([{"width": 190.0, "bottom": 195.0, "center": 420.0}])
	var solo_rect: Rect2 = solo.card_rect("solo_1")
	# 面板内部是局部坐标：y 就是 CARD_LOCAL_Y，页面坐标要 +BAND_Y（与队列一致）
	t.eq(solo_rect, Rect2(Layout.QUEUE_ORIGIN_X, Layout.CARD_LOCAL_Y,
			Layout.QUEUE_CARD_W, Layout.CARD_H),
			"单卡矩形 == 队列卡矩形（同宽同高同位置）")
	t.eq(Layout.PORTRAIT_TOP_ABOVE_CARD, 160.0, "立绘下缘与卡片上沿齐平")
	t.eq(Layout.PORTRAIT_H, 300.3, "立绘随卡宽放大到 1.25 倍")
	solo.free()

	# 2026-11-09：每个任务棋子右下角带 have/need 角标；完成前后两套颜色（取色自参考图）
	# 2026-11-10：交付命中区 = **底板矩形**，且只认绿色（可交付）的行。
	# 用独立的 panel 夹具，别碰上面已经 free() 掉的那个。
	var hit_panel = OrderPanel.new()
	hit_panel.set_metrics({"card_gap": 18.0, "card_radius": 22.0})
	hit_panel.build_from_level({"id": "hit_lv", "orders": [
		{"id": "hit_1", "character": "char_blonde",
			"mission": [{"entity": "CleanSet_Ca", "level": 2}, {"entity": "CleanSet_Ca", "level": 1}],
			"coin": 5, "star": 0, "gem": 1, "energy": 10}]})
	hit_panel.size = Vector2(1080.0, 250.0)
	hit_panel.sync_orders([{
		"id": "hit_1", "character": "char_blonde", "coin": 5, "star": 0, "gem": 1, "energy": 10,
		"done": false,
		"mission": [
			{"entity": "CleanSet_Ca", "level": 2, "have": 0, "need": 1, "ready": false},
			{"entity": "CleanSet_Ca", "level": 1, "have": 0, "need": 4, "ready": true},
		]}])
	var hit_card: Rect2 = hit_panel.card_rect("hit_1")
	var hit_chips := OrderPanel.mission_chip_rects(OrderPanel.mission_area_rect(hit_card), 2)
	var plate0: Rect2 = OrderPanel.mission_plate_rect(hit_chips[0])
	var plate1: Rect2 = OrderPanel.mission_plate_rect(hit_chips[1])
	var hit0: Dictionary = hit_panel.mission_row_at(plate0.get_center())
	t.ok(hit0.is_empty(), "棕色的行不接交付（只认底板里的绿色行）", str(hit0))
	var hit1: Dictionary = hit_panel.mission_row_at(plate1.get_center())
	t.eq(int(hit1.get("row", -1)), 1, "绿色底板命中第二行")
	t.eq(String(hit1.get("order", "")), "hit_1", "命中返回订单 id")
	var outside: Dictionary = hit_panel.mission_row_at(
			Vector2(plate1.position.x + 1.0, plate1.position.y - 6.0))
	t.ok(outside.is_empty(), "底板外面不算命中")
	t.eq(hit_panel.mission_row_center("hit_1", 1), plate1.get_center(), "飞行落点 = 那一行底板中心")
	hit_panel.free()

	# 叹号只认"真收齐"（操作者 2026-11-09 补的口径）：0/1 就绪也不给，1/1、2/2 才给
	t.ok(not OrderPanel.mission_bang_visible(0, 1), "0/1 不该出现叹号")
	t.ok(OrderPanel.mission_bang_visible(1, 1), "1/1 出现叹号")
	t.ok(not OrderPanel.mission_bang_visible(1, 2), "1/2 还没收齐，不给叹号")
	t.ok(OrderPanel.mission_bang_visible(2, 2), "2/2 收齐，给叹号")
	t.ok(OrderPanel.mission_bang_visible(3, 2), "超过 need 也算收齐")

	# 完成态：浅绿底板 + 左上角绿色叹号（参考图口径；常量可翻到右上角）
	t.eq(OrderPanel.MISSION_DONE_PLATE, Color("#ACC08C"), "完成底板的浅绿取自参考图")
	var chip1: Rect2 = (OrderPanel.mission_chip_rects(card, 1) as Array)[0]
	var bang: Rect2 = OrderPanel.mission_bang_rect(chip1)
	# 2026-11-09 操作者口径：以叹号**右下角**为锚点挂在底板左上角，故意溢出底板
	var plate: Rect2 = OrderPanel.mission_plate_rect(chip1)
	var bang_inset: float = bang.size.x * 0.55
	t.ok(absf(bang.end.x - (plate.position.x + bang_inset)) < 0.01, "叹号右边缘收进底板左上角", str(bang))
	t.ok(absf(bang.end.y - (plate.position.y + bang_inset)) < 0.01, "叹号下边缘收进底板左上角")
	t.ok(not chip1.encloses(bang), "叹号溢出棋子（参考图里它比底板还大）")
	t.ok(absf(bang.size.x - chip1.size.x * OrderPanel.MISSION_BANG_SCALE) < 0.01,
			"叹号大小 = 棋子宽度 × MISSION_BANG_SCALE")
	t.ok(OrderPanel.mission_plate_rect(chip1).size.x < chip1.size.x, "底板比棋子小一圈")

	# 三态：0/1 棕（还没有）→ 0/1 绿（棋盘上合出来了）→ 1/1 绿（交任务之后）
	t.ok(not OrderPanel.mission_badge_done(0, 1, false), "0/1 未就绪 = 棕色")
	t.ok(OrderPanel.mission_badge_done(0, 1, true), "0/1 但棋盘上已有 = 绿色（多出来的一步）")
	t.ok(OrderPanel.mission_badge_done(1, 1, false), "1/1 已交付 = 绿色")
	t.ok(not OrderPanel.mission_badge_done(0, 1, false) == OrderPanel.mission_badge_done(0, 1, true),
			"就绪与否决定颜色，跟数字无关")
	t.eq(OrderPanel.MISSION_BADGE_FILL_OPEN, Color("#FCFCFC"), "未完成角标是米白字")
	t.eq(OrderPanel.MISSION_BADGE_STROKE_OPEN, Color("#947450"), "未完成角标是暖棕描边")
	t.eq(OrderPanel.MISSION_BADGE_FILL_DONE, Color("#B0FC74"), "完成角标换成亮绿字")
	t.eq(OrderPanel.MISSION_BADGE_STROKE_DONE, Color("#508018"), "完成角标换成深绿描边")
	t.ok(OrderPanel.MISSION_BADGE_FILL_OPEN != OrderPanel.MISSION_BADGE_FILL_DONE,
			"完成时字色确实变了")
	t.ok(OrderPanel.MISSION_BADGE_STROKE_OPEN != OrderPanel.MISSION_BADGE_STROKE_DONE,
			"完成时描边色也变了")
	var chip96: Rect2 = (OrderPanel.mission_chip_rects(card, 1) as Array)[0]
	var badge: Rect2 = OrderPanel.mission_badge_rect(chip96, 34.0)
	t.ok(chip96.encloses(badge), "角标落在棋子矩形内（右下角）", str(badge))
	t.ok(absf(badge.end.x - (chip96.end.x - OrderPanel.MISSION_BADGE_INSET)) < 0.01,
			"角标右边贴着棋子右内边")
	t.ok(absf(badge.end.y - (chip96.end.y - OrderPanel.MISSION_BADGE_INSET)) < 0.01,
			"角标下边贴着棋子下内边")

	t.eq(OrderPanel.REWARD_ICON_H, 32.0, "两种奖励图标统一按高 32 画")
	var origin := OrderPanel.reward_row_rects(card, 50.0, 20.0)
	var e_icon: Rect2 = origin["energy_icon"]
	var e_label: Rect2 = origin["energy_label"]
	var g_icon: Rect2 = origin["gem_icon"]
	var g_label: Rect2 = origin["gem_label"]
	t.eq(e_icon.size.y, OrderPanel.REWARD_ICON_H, "闪电图标高 32")
	t.eq(g_icon.size.y, OrderPanel.REWARD_ICON_H, "钻石图标高 32")
	t.ok(absf(g_icon.size.x - OrderPanel.REWARD_ICON_H * 39.0 / 32.0) < 0.01,
			"钻石图标按贴图比例 39:32", str(g_icon.size))
	t.ok(absf(e_icon.size.x - OrderPanel.REWARD_ICON_H * 39.0 / 53.0) < 0.01,
			"闪电图标按贴图比例 39:53", str(e_icon.size))
	t.ok(e_icon.end.x <= e_label.position.x, "闪电图标在它的数字左边")
	t.ok(e_label.end.x <= g_icon.position.x, "闪电这一组在钻石这一组左边（闪电在前）")
	t.ok(g_icon.end.x <= g_label.position.x, "钻石图标在它的数字左边")
	for pair in [["闪电图标", e_icon], ["闪电数字", e_label], ["钻石图标", g_icon], ["钻石数字", g_label]]:
		t.ok(card.encloses(pair[1]), "%s 不越出卡片" % String(pair[0]), str(pair[1]))
		t.ok(card.end.y - (pair[1] as Rect2).end.y >= 5.0,
				"%s 底边留白 >= 5px" % String(pair[0]),
				"%.1f" % (card.end.y - (pair[1] as Rect2).end.y))
	var row_mid := (e_icon.position.x + g_label.end.x) * 0.5
	t.ok(absf(row_mid - strip.get_center().x) < 0.5, "闪电+钻石**两组一起**水平居中",
			"%.2f vs %.2f" % [row_mid, strip.get_center().x])
	t.eq(OrderPanel.REWARD_ROW_RISE, 4.0, "整组上抬 4px（操作者：往上挪几个像素）")
	t.ok(absf(e_icon.get_center().y - (strip.get_center().y - OrderPanel.REWARD_ROW_RISE)) < 0.5,
			"图标中心 = 蓝条中心 - 上抬量")

	var only_gem: Dictionary = OrderPanel.reward_row_rects(card, 0.0, 20.0)
	t.eq((only_gem["energy_icon"] as Rect2), Rect2(), "没有体力奖励就不排闪电")
	t.ok(absf(((only_gem["gem_icon"] as Rect2).position.x
			+ (only_gem["gem_label"] as Rect2).end.x) * 0.5 - strip.get_center().x) < 0.5,
			"只有钻石时它自己居中")
