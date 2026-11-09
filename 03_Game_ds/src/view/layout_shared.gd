extends RefCounted
## 实机（src/view/order_panel.gd）与成片（src/render/movie_scene.gd）共用的订单带几何。
## 2026-11-06：两边各写一份常量导致"实机改了、成片没改"，这里收敛成唯一来源；
## 任何一端的新布局都必须先进本文件，再被 t_layout_parity 断言两端一致。

## 2026-11-09：订单任务改成 4 个图标（同卡内不重复），卡片跟着拉宽，
## 可见张数从 3 收到 2（4 枚图标 + 2 张卡 = 参考图那种密度）。
## 424 = 4 枚棋子 89px + 3 个 12px 间隙 + 两侧 16px 内边距；起点 208 让两张卡都完整落在 1080 内。
const QUEUE_ORIGIN_X := 208.0
const QUEUE_CARD_W := 424.0
const CARD_GAP_X := 18.0
## 一张卡最多摆几枚任务棋子（数据侧由 sample_project.json 保证，这里只做布局上限）。
const MAX_MISSION_ICONS := 4
const CARD_H := 140.0
## 2026-11-09（操作者红框图为准）：立绘等比放大到 1.43 倍（210 -> 300），
## **头顶落在顶栏下沿**（卡片上沿往上 160px），**下沿压到卡片底边**（多出的部分被卡面盖住）。
## 层级：背景 -> 立绘（由订单带画，位于顶栏之上，避免脸被药丸挡住）-> 卡面 -> 光标/飞行。
const PORTRAIT_BASE_H := 210.0
const PORTRAIT_GROW := 1.43
const PORTRAIT_H := PORTRAIT_BASE_H * PORTRAIT_GROW
## 立绘顶离卡片上沿多少（= 顶栏下沿 ~ page 105，卡片上沿 265）。
const PORTRAIT_TOP_ABOVE_CARD := 160.0
## 因此压进卡片的高度 = 立绘高 - 上面那段；压进去的部分由卡面覆盖。
const PORTRAIT_SINK := PORTRAIT_H - PORTRAIT_TOP_ABOVE_CARD
## 2026-11-09：订单卡底部蓝条占卡高的比例。贴图上分界在 124/178 = 0.697，
## 九宫格（角 26 不缩放）铺到 250x140 后实测蓝条 = 39px / 140 = 0.279（见 AGENTS §6.13）。
## 蓝条放钻石奖励（图标 + 数字），棋子排在蓝条以上。实机与成片都读这里。
const GEM_STRIP_RATIO := 0.279
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