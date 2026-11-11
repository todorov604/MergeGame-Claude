extends RefCounted
## 任务栏排序（2026-11-11 重写）的唯一规则：
##   绿组（整卡全满 = 大对号显示）按"谁先满"FIFO 排前面；
##   非绿组保持原有相对顺序；绿的掉出绿组 → 排到所有绿卡后面；不插队。
## 这里只测纯函数 queue_order()，不碰场景。

const OrderQueue := preload("res://src/view/order_panel.gd")


func run(t) -> void:
	_fifo_among_green(t)
	_late_green_goes_last(t)
	_lost_green_drops_behind(t)
	_rest_keeps_relative_order(t)
	_no_green_keeps_everything(t)
	_empty_and_single(t)


func _fifo_among_green(t) -> void:
	var ids := ["a", "b", "c"]
	var full := {"a": true, "b": true, "c": false}
	var seq := {"a": 1, "b": 2}
	t.eq(OrderQueue.queue_order(ids, full, seq), ["a", "b", "c"], "两张绿：先满的在前（FIFO），非绿跟在后面")

	# 顺序反过来喂，结果必须一样（不依赖输入顺序）
	var ids2 := ["c", "b", "a"]
	t.eq(OrderQueue.queue_order(ids2, full, seq), ["a", "b", "c"], "绿的排序只看'谁先满'，与数组原顺序无关")


func _late_green_goes_last(t) -> void:
	# a 先满；c 后满 → c 排在绿组末尾（顺延，不插队）
	var ids := ["a", "c", "b"]
	var full := {"a": true, "c": true, "b": false}
	var seq := {"a": 1, "c": 3}
	t.eq(OrderQueue.queue_order(ids, full, seq), ["a", "c", "b"], "后满的接在绿组末尾，不越过先满的")


func _lost_green_drops_behind(t) -> void:
	# a、b 都绿（a 先满）；b 掉出全满 → 排到所有绿卡后面，且保留它在非绿组里的相对位置
	var ids := ["a", "b", "c"]
	var full := {"a": true, "b": true, "c": false}
	var seq := {"a": 1, "b": 2}
	t.eq(OrderQueue.queue_order(ids, full, seq), ["a", "b", "c"], "两张绿 + 一张非绿")

	var full2 := {"a": true, "b": false, "c": false}
	var seq2 := {"a": 1}
	t.eq(OrderQueue.queue_order(ids, full2, seq2), ["a", "b", "c"], "b 掉出绿组 → 排在 a 后面，c 仍在它后面")

	# 掉出去的卡再变满时拿到新序号 → 罚到绿组末尾
	var seq3 := {"a": 1, "b": 9}
	var full3 := {"a": true, "b": true, "c": false}
	t.eq(OrderQueue.queue_order(ids, full3, seq3), ["a", "b", "c"], "重新变满的卡按新序号排在绿组末尾")


func _rest_keeps_relative_order(t) -> void:
	# 非绿组不按任何分数重排：即使 b 交得更多，也不能越过 a
	var ids := ["a", "b"]
	var full := {"a": false, "b": false}
	t.eq(OrderQueue.queue_order(ids, full, {}), ["a", "b"], "全非绿：保持原顺序，不按任何分数插队")


func _no_green_keeps_everything(t) -> void:
	var ids := ["x", "y", "z", "w"]
	var full := {"x": false, "y": false, "z": false, "w": false}
	t.eq(OrderQueue.queue_order(ids, full, {}), ids, "一张绿的都没有 → 完全不动")


func _empty_and_single(t) -> void:
	t.eq(OrderQueue.queue_order([], {}, {}), [], "空队列")
	t.eq(OrderQueue.queue_order(["a"], {"a": true}, {"a": 1}), ["a"], "单卡")
