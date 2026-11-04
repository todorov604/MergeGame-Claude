extends RefCounted

## P0 剩余能力验收：validator 订单可达性、BoardView 提示槽、
## ViewLayer 棋盘已满 toast / hint、HUDView 数值与计时文本。

const BoardView = preload("res://game/board_view.gd")
const HUDView = preload("res://game/hud_view.gd")
const ManifestDoc = preload("res://core/manifest_doc.gd")
const OrderView = preload("res://game/order_view.gd")
const ProjectDoc = preload("res://core/project_doc.gd")
const SimState = preload("res://core/sim/sim_state.gd")
const Validator = preload("res://core/validator.gd")
const ViewLayer = preload("res://game/view_layer.gd")

const REACH_MESSAGE := "订单物品不可达"


func run(r) -> void:
	var sample = ProjectDoc.new()
	r.check(sample.load_file("res://data/projects/sample_30s.json"), "样例项目应能加载: " + str(sample.parse_error))
	var data: Dictionary = sample.data.duplicate(true)

	var manifest_path := (ProjectSettings.globalize_path("res://") + "/../00_design/resource_manifest.json").simplify_path()
	var manifest = ManifestDoc.new()
	r.check(manifest.load_file(manifest_path), "真实 manifest 应能加载: " + str(manifest.parse_error))

	_check_reachability_failure(r, manifest, data)
	_check_reachability_success(r, manifest, data)
	_check_board_hint(r, data)
	_check_view_layer_toast_and_hint(r, data)
	_check_hud(r, data)


# ---------------------------------------------------------------- 1) 可达性-失败
## 单枚 CleanSet_Ca Lv1、无生成器，却要求 Lv3：两枚同级才能合成一枚高级，必然不可达。
func _check_reachability_failure(r, manifest, sample_data: Dictionary) -> void:
	var v = _validate_mutant(manifest, sample_data, func(d):
		d["levels"][0]["board"]["slots"] = [{"x": 2, "y": 3, "entity": "CleanSet_Ca", "level": 1}]
		d["levels"][0]["orders"][0]["mission"] = [{"entity": "CleanSet_Ca", "level": 3}]
		d["generators"].erase("CleanBox_C")
	)
	r.check(not _reach_errors(v.errors).is_empty(), "单枚 Lv1 且无生成器时订单物品应报不可达: " + _join(v.errors))
	r.check(_has_error_at(v.errors, "levels[0].orders[0].mission"), "不可达错误路径应为 levels[0].orders[0].mission[MI]: " + _join(v.errors))
	var others: Array = []
	for e in v.errors:
		if not _is_reach_error(e):
			others.append(e)
	r.check(others.is_empty(), "除可达性外其余校验应通过: " + _join(others))


# ---------------------------------------------------------------- 2) 可达性-成功
## 四枚 CleanSet_Ca Lv1 可合成 Lv3（4 → 2 → 1），即使没有生成器也应判为可达。
func _check_reachability_success(r, manifest, sample_data: Dictionary) -> void:
	var v = _validate_mutant(manifest, sample_data, func(d):
		d["levels"][0]["board"]["slots"] = [
			{"x": 2, "y": 3, "entity": "CleanSet_Ca", "level": 1},
			{"x": 3, "y": 3, "entity": "CleanSet_Ca", "level": 1},
			{"x": 4, "y": 3, "entity": "CleanSet_Ca", "level": 1},
			{"x": 5, "y": 3, "entity": "CleanSet_Ca", "level": 1},
		]
		d["levels"][0]["orders"][0]["mission"] = [{"entity": "CleanSet_Ca", "level": 3}]
		d["generators"].erase("CleanBox_C")
	)
	r.check(_reach_errors(v.errors).is_empty(), "四枚 Lv1 可合成 Lv3，订单物品不应报不可达: " + _join(v.errors))
	r.check(v.errors.is_empty(), "可达且结构合法时不应有其他校验错误: " + _join(v.errors))


# ---------------------------------------------------------------- 3) BoardView 提示槽
func _check_board_hint(r, data: Dictionary) -> void:
	var state = SimState.new()
	state.setup(data, 12345)
	var view = BoardView.new()
	view.setup(data, state.snapshot(), [], [], true)

	r.check(not view.hint_active(), "初始不应有提示槽")
	r.eq(view.hint_slot_count(), 0, "初始提示槽数量应为 0")

	view.set_hint_slots([[2, 3], [4, 3]])
	r.check(view.hint_active(), "set_hint_slots 后 hint_active 应为 true")
	r.eq(view.hint_slot_count(), 2, "set_hint_slots 后提示槽数量应为 2")

	view.clear_hint()
	r.check(not view.hint_active(), "clear_hint 后 hint_active 应为 false")
	r.eq(view.hint_slot_count(), 0, "clear_hint 后提示槽数量应为 0")

	view.free()


# ---------------------------------------------------------------- 4) ViewLayer toast / hint
func _check_view_layer_toast_and_hint(r, data: Dictionary) -> void:
	var state = SimState.new()
	state.setup(data, 12345)
	var board = BoardView.new()
	board.setup(data, state.snapshot(), [], [], true)
	var order = OrderView.new()
	var layer = ViewLayer.new()
	layer.setup(data, board, order)

	layer.show_board_full()
	r.check(layer.board_full_visible(), "show_board_full 后棋盘已满 toast 应可见")
	layer.tick(10.0)
	r.check(not layer.board_full_visible(), "超过 1.5s 后 tick 应隐藏棋盘已满 toast")

	layer.on_event({"type": "hint", "payload": {"slots": [[2, 3]]}, "duration": 2.0}, {}, 0.0)
	r.check(board.hint_active(), "hint 事件后 board_view.hint_active 应为 true")
	r.eq(board.hint_slot_count(), 1, "hint 事件应下发 1 个提示槽")
	layer.tick(3.0)
	r.check(not board.hint_active(), "hint 超过 duration 后 tick 应清除棋盘提示")

	board.free()
	order.free()
	layer.free()


# ---------------------------------------------------------------- 5) HUDView
func _check_hud(r, data: Dictionary) -> void:
	var hud = HUDView.new()
	hud.setup(data, null, true)
	var state = SimState.new()
	state.setup(data, 12345)
	hud.refresh(state.snapshot(), 0.0)

	r.contains(hud.level_text(), "2", "level_text 应含关卡等级 2（实际=%s）" % hud.level_text())
	r.eq(hud.energy_text(), "88", "energy_text 应为 88")
	var timer := hud.timer_text().replace(" ", "")
	r.check(timer.find("02:00") != -1, "timer_text 应匹配 02:00（实际=%s）" % hud.timer_text())
	r.eq(hud.coin_text(), "9", "coin_text 应为 9")
	r.eq(hud.star_text(), "0", "star_text 应为 0")
	r.eq(hud.gem_text(), "50", "gem_text 应为 50")

	hud.refresh({}, 5.0)
	r.check(true, "refresh 空快照不应崩溃")

	hud.free()


# ---------------------------------------------------------------- 工具
func _validate_mutant(manifest, sample_data: Dictionary, mutate: Callable):
	var d: Dictionary = sample_data.duplicate(true)
	mutate.call(d)
	var p = ProjectDoc.new()
	p.from_dict(d, "<p0_features>")
	var v = Validator.new()
	v.validate_manifest(manifest)
	v.validate_project(p, manifest, true)
	return v


func _reach_errors(errors: Array) -> Array:
	var hits: Array = []
	for e in errors:
		if _is_reach_error(e):
			hits.append(e)
	return hits


func _is_reach_error(e) -> bool:
	return str(e.get("message", "")).find(REACH_MESSAGE) != -1


func _has_error_at(errors: Array, path_prefix: String) -> bool:
	for e in errors:
		if str(e.get("path", "")).begins_with(path_prefix):
			return true
	return false


func _join(errors: Array) -> String:
	var parts: Array = []
	for e in errors:
		parts.append("%s: %s" % [str(e.get("path", "")), str(e.get("message", ""))])
	return " | ".join(parts)
