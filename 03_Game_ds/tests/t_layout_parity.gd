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
	t.eq(Layout.QUEUE_ORIGIN_X, 250.0, "队列起点 250")
	t.eq(Layout.QUEUE_CARD_W, 250.0, "卡宽 250")
	t.eq(Layout.CARD_GAP_X, 18.0, "卡间距 18")
	t.eq(Layout.CARD_H, 140.0, "卡高 140")
	t.eq(Layout.PORTRAIT_H, 210.0, "立绘高 210")
	t.eq(Layout.PORTRAIT_SINK, 26.0, "立绘压卡片 26")
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
