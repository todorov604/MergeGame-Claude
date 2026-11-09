extends RefCounted
## 实机（src/view/order_panel.gd）与成片（src/render/movie_scene.gd）共用的订单带几何。
## 2026-11-06：两边各写一份常量导致"实机改了、成片没改"，这里收敛成唯一来源；
## 任何一端的新布局都必须先进本文件，再被 t_layout_parity 断言两端一致。

const QUEUE_ORIGIN_X := 250.0
const QUEUE_CARD_W := 250.0
const CARD_GAP_X := 18.0
const CARD_H := 140.0
const PORTRAIT_H := 210.0
const PORTRAIT_SINK := 26.0
## 库存面板矩形（任务带左侧红框区）。
const STOCKPILE_RECT := Rect2(40.0, 248.0, 156.0, 156.0)


## 第 i 张卡的矩形（横向队列，左对齐起点，等间距）。
static func card_rect(index: int) -> Rect2:
	if index < 0:
		return Rect2()
	var top := BAND_Y + CARD_LOCAL_Y
	return Rect2(QUEUE_ORIGIN_X + float(index) * (QUEUE_CARD_W + CARD_GAP_X), top,
			QUEUE_CARD_W, CARD_H)


## Portrait bottom edge = card top + PORTRAIT_SINK（立绘压在卡片上沿）。
static func portrait_bottom() -> float:
	return BAND_Y + CARD_LOCAL_Y + PORTRAIT_SINK


## 订单带在页面上的 y（实机 order_panel.position.y = 210）。
const BAND_Y := 210.0
## 卡在面板局部坐标里的 y：面板高 250、卡高 140 -> 居中 55。
const CARD_LOCAL_Y := 55.0


static func card_rects(count: int) -> Array:
	var out: Array = []
	for i in maxi(count, 0):
		out.append(card_rect(i))
	return out


## 某张卡上方的立绘矩形：宽度按贴图比例，底边压卡片 26px。
static func portrait_rect(card: Rect2, texture_size: Vector2) -> Rect2:
	var w := PORTRAIT_H
	if texture_size.y > 0.0:
		w = PORTRAIT_H * (texture_size.x / texture_size.y)
	return Rect2(card.get_center().x - w * 0.5,
			card.position.y + PORTRAIT_SINK - PORTRAIT_H, w, PORTRAIT_H)