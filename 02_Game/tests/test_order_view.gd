extends RefCounted

## 第 4 步验收：OrderView（订单/角色显示）与 BoardView 新增的 refresh/格心坐标 API。

const OrderView = preload("res://game/order_view.gd")
const BoardView = preload("res://game/board_view.gd")
const ProjectDoc = preload("res://core/project_doc.gd")
const SimState = preload("res://core/sim/sim_state.gd")


func run(r) -> void:
	# ---------------------------------------------------------------- 准备
	var doc = ProjectDoc.new()
	r.check(doc.load_file("res://data/projects/sample_30s.json"), "样例项目应能加载: " + str(doc.parse_error))
	var data: Dictionary = doc.data.duplicate(true)

	var state = SimState.new()
	state.setup(data, 12345)

	# ---------------------------------------------------------------- 订单待交付
	state.board.set_cell(4, 3, "CleanSet_Ca", 2)
	var deliver_res: Dictionary = state.orders.deliver(state.board, "order_1")
	r.check(bool(deliver_res.get("ok", false)), "订单物品齐备时 deliver 应成功: " + str(deliver_res.get("message", "")))
	var snapshot: Dictionary = state.snapshot()

	var view = OrderView.new()
	view.setup(data, snapshot, true)
	r.eq(view.active_order_id(), "order_1", "待交付订单应为 order_1")
	r.eq(view.get_character_id(), "char_01", "order_1 的角色应为 char_01")
	r.eq(view.mission_count(), 1, "order_1 的 mission 数量应为 1")
	r.check(view.is_ready(), "订单待交付时 is_ready 应为 true")
	r.eq(view.get_order_state(), "ready", "订单待交付时状态应为 ready")
	var center_v: Variant = view.character_center()
	r.check(typeof(center_v) == TYPE_VECTOR2, "character_center() 应返回 Vector2")
	if typeof(center_v) == TYPE_VECTOR2:
		var center: Vector2 = center_v
		r.check(is_finite(center.x) and is_finite(center.y), "character_center() 分量应有限")

	# ---------------------------------------------------------------- 领取后无剩余订单
	var hud: Dictionary = {"coin": 0, "star": 0}
	var claim_res: Dictionary = state.orders.claim(state.board, "order_1", hud)
	r.check(bool(claim_res.get("ok", false)), "ready 订单应可领取: " + str(claim_res.get("message", "")))
	var snapshot2: Dictionary = state.snapshot()
	view.refresh(snapshot2)
	r.eq(view.active_order_id(), "", "订单全部领取后 active_order_id 应为空")
	r.eq(view.mission_count(), 0, "订单全部领取后 mission_count 应为 0")
	r.check(not view.is_ready(), "无剩余订单时 is_ready 应为 false")

	# ---------------------------------------------------------------- 切到 level_2 后新角色新订单
	var state2 = SimState.new()
	state2.setup(data, 12345)
	state2.board.set_cell(4, 3, "CleanSet_Ca", 2)
	var deliver_res2: Dictionary = state2.orders.deliver(state2.board, "order_1")
	r.check(bool(deliver_res2.get("ok", false)), "level_1 订单应可交付: " + str(deliver_res2.get("message", "")))
	var hud2: Dictionary = {"coin": 0, "star": 0}
	var claim_res2: Dictionary = state2.orders.claim(state2.board, "order_1", hud2)
	r.check(bool(claim_res2.get("ok", false)), "level_1 订单应可领取: " + str(claim_res2.get("message", "")))
	r.check(bool(claim_res2.get("level_complete", false)), "领取 level_1 全部订单后应标记 level_complete")
	r.check(state2.advance_level(), "level_1 完成后 advance_level 应成功")
	var snapshot3: Dictionary = state2.snapshot()
	view.refresh(snapshot3)
	r.eq(view.active_order_id(), "order_2", "level_2 的当前订单应为 order_2")
	r.eq(view.get_character_id(), "char_02", "order_2 的角色应为 char_02")
	r.eq(view.mission_count(), 1, "order_2 的 mission 数量应为 1")
	r.eq(view.get_order_state(), "pending", "order_2 初始状态应为 pending")
	r.check(not view.is_ready(), "order_2 未交付时 is_ready 应为 false")
	view.free()

	# ---------------------------------------------------------------- 空数据防御
	var empty_view = OrderView.new()
	empty_view.setup({}, {}, true)
	r.eq(empty_view.active_order_id(), "", "空数据时 active_order_id 应为空")
	r.eq(empty_view.mission_count(), 0, "空数据时 mission_count 应为 0")
	r.check(not empty_view.is_ready(), "空数据时 is_ready 应为 false")
	empty_view.free()

	# ---------------------------------------------------------------- BoardView 新方法
	var bv = BoardView.new()
	bv.setup(data, snapshot, [], [], true)
	var c0_v: Variant = bv.cell_center(0, 0)
	r.check(typeof(c0_v) == TYPE_VECTOR2, "cell_center(0,0) 应返回 Vector2")
	if typeof(c0_v) == TYPE_VECTOR2:
		var c0: Vector2 = c0_v
		r.check(c0.x > 0.0, "cell_center(0,0).x 应大于 0")
		r.check(c0.y > 0.0, "cell_center(0,0).y 应大于 0")

	# level_2 初始快照（order_2 pending）：两枚 CleanSet_Cb + 生成器，共 3 格。
	bv.refresh(snapshot3)
	r.eq(bv.cell_count(), 3, "refresh 到 level_2 初始快照后格子数应为 3")

	# 完成 level_2（等价于合并两枚 CleanSet_Cb 后交付/领取），得到只剩生成器的快照。
	state2.board.set_cell(4, 4, "CleanSet_Cb", 2)
	state2.board.remove_cell(2, 4)
	var deliver_res3: Dictionary = state2.orders.deliver(state2.board, "order_2")
	r.check(bool(deliver_res3.get("ok", false)), "level_2 订单应可交付: " + str(deliver_res3.get("message", "")))
	var hud3: Dictionary = {"coin": 0, "star": 0}
	var claim_res3: Dictionary = state2.orders.claim(state2.board, "order_2", hud3)
	r.check(bool(claim_res3.get("ok", false)), "level_2 订单应可领取: " + str(claim_res3.get("message", "")))
	r.check(bool(claim_res3.get("level_complete", false)), "领取 level_2 全部订单后应标记 level_complete")
	var snapshot4: Dictionary = state2.snapshot()
	bv.refresh(snapshot4)
	r.eq(bv.cell_count(), 1, "level_2 完成后应只剩生成器格")

	var cg_v: Variant = bv.cell_center_global(0, 0)
	r.check(typeof(cg_v) == TYPE_VECTOR2, "cell_center_global(0,0) 应返回 Vector2")
	if typeof(cg_v) == TYPE_VECTOR2:
		var cg: Vector2 = cg_v
		r.check(is_finite(cg.x) and is_finite(cg.y), "cell_center_global(0,0) 分量应有限")
	bv.free()
