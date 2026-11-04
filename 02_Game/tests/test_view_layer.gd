extends RefCounted

## 第 5 步验收：ViewLayer（缓入横幅 text / cta / levelup、棋盘选中、清空）。

const ViewLayer = preload("res://game/view_layer.gd")
const BoardView = preload("res://game/board_view.gd")
const OrderView = preload("res://game/order_view.gd")
const ProjectDoc = preload("res://core/project_doc.gd")


func run(r) -> void:
	var doc = ProjectDoc.new()
	r.check(doc.load_file("res://data/projects/sample_30s.json"), "样例项目应能加载: " + str(doc.parse_error))
	var data: Dictionary = doc.data.duplicate(true)

	# Control 不必入树：ViewLayer 只操作注入的 board / order 与自建 Label。
	var layer = ViewLayer.new()
	var board = BoardView.new()
	var order = OrderView.new()
	layer.setup(data, board, order)

	# ---------------------------------------------------------------- text 横幅
	layer.on_event({"type": "text", "payload": {"text_key": "hook.question"}, "duration": 2.0}, {}, 0.0)
	r.eq(layer.current_text(), "你能合出来吗？", "text 事件应显示本地化文案")
	r.eq(layer.active_text_key(), "hook.question", "text 事件应记录 text_key")
	layer.tick(3.0)
	r.eq(layer.current_text(), "", "text 横幅到期后 tick 应清空")

	# ---------------------------------------------------------------- cta 横幅
	layer.on_event({"type": "cta", "payload": {"text_key": "cta.play"}, "duration": 2.0}, {}, 10.0)
	r.eq(layer.current_text(), "立即游玩", "cta 事件应显示本地化文案")

	# ---------------------------------------------------------------- select 选中
	layer.on_event({"type": "select", "payload": {"slot": [2, 3]}}, {}, 11.0)
	r.eq(board.selection, [[2, 3]], "select 事件应更新棋盘 selection")

	# ---------------------------------------------------------------- levelup 横幅
	# 样例 locales 无 levelup 键，回退文案为 "LEVEL UP"；这里只断言非空。
	layer.on_event({"type": "levelup", "payload": {}}, {}, 12.0)
	r.check(not layer.current_text().is_empty(), "levelup 事件应显示非空文案")

	# ---------------------------------------------------------------- clear
	layer.clear()
	r.eq(layer.current_text(), "", "clear 后 current_text 应为空")

	# ---------------------------------------------------------------- 释放
	board.free()
	order.free()
	layer.free()
