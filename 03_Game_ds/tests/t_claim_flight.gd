extends RefCounted
## 交付飞行的**数量**（2026-11-09，AGENTS §6.8/§6.9）。
##
## 规矩：成片飞几枚 = sim 真正消耗了几格（`taken`），视图层不许自己数。
## 坑：`evaluator.step()` 的报告把 sim 的返回字典嵌在 `"sim"` 键下，顶层只有
## ok/code/id/type/channel/at。成片原来读 `r.get("taken")`，永远是空数组，
## 于是每次都走"飞被点击格"的兜底 —— 2 行任务的订单也只飞一枚（第 2 关 5 个订单里
## 有 3 个是 2 行任务，肉眼就是"只飞了一半"）。
##
## 这条测试抓的就是"读错层级"：把 claim_taken() 改回读顶层，它就红。

const ProjectModel := preload("res://src/core/project_model.gd")
const EventEvaluator := preload("res://src/core/event_evaluator.gd")
const MovieScene := preload("res://src/render/movie_scene.gd")


func run(t) -> void:
	_two_row_claim_reports_both_cells(t)
	_clicked_cell_comes_first(t)
	_single_row_claim_reports_one(t)
	_no_sim_block_means_no_flight(t)


## 2 行任务的订单：两枚棋子各被消耗一次 → 成片必须拿到两个格子。
func _two_row_claim_reports_both_cells(t) -> void:
	var report := _claim_report(_two_row_project(), "o1", Vector2i(2, 0))
	t.ok(bool(report.get("ok", false)), "two-row claim is accepted", str(report.get("code", "")))
	var taken: Array = MovieScene.claim_taken(report)
	t.eq(taken.size(), 2, "2 行任务交付 → 飞 2 枚")
	# 同一份报告里，sim 自己的 taken 就是视图层该用的那一份
	var sim_res: Dictionary = report.get("sim", {})
	t.eq(taken, (sim_res as Dictionary).get("taken", []), "成片取的就是 sim 的 taken")
	# 顶层确实没有 taken —— 这就是原来读空的地方
	t.eq((report.get("taken", []) as Array).size(), 0, "报告顶层没有 taken（读它就飞不出来）")
	# 两格都在棋盘的合法范围里，且不是同一格
	var a: Array = taken[0]
	var b: Array = taken[1]
	t.ok(Vector2i(int(a[0]), int(a[1])) != Vector2i(int(b[0]), int(b[1])), "两枚来自不同的格子")


## 被点击的那一格必须在 taken 里（AGENTS §6.9 钉死的行为）。
func _clicked_cell_comes_first(t) -> void:
	var report := _claim_report(_two_row_project(), "o1", Vector2i(2, 0))
	var taken: Array = MovieScene.claim_taken(report)
	var clicked_ok := false
	for raw in taken:
		if typeof(raw) == TYPE_ARRAY and int(raw[0]) == 2 and int(raw[1]) == 0:
			clicked_ok = true
	t.ok(clicked_ok, "被点击的格子出现在 taken 里", str(taken))


## 单行任务：只能飞一枚，别多飞（§6.8 的"凭空多一枚"）。
func _single_row_claim_reports_one(t) -> void:
	var report := _claim_report(_single_row_project(), "o1", Vector2i(0, 0))
	var taken: Array = MovieScene.claim_taken(report)
	t.eq(taken.size(), 1, "1 行任务交付 → 只飞 1 枚")
	t.eq(int(taken[0][0]), 0, "飞的就是被点击的那一格 x")
	t.eq(int(taken[0][1]), 0, "飞的就是被点击的那一格 y")


## 报告里没有 sim 块（比如 EV_CHANNEL 这种没走到 sim 的事件）→ 视图层不飞。
func _no_sim_block_means_no_flight(t) -> void:
	t.eq(MovieScene.claim_taken({}), [], "空报告 → 不飞")
	t.eq(MovieScene.claim_taken({"ok": true, "sim": {}}), [], "sim 块空 → 不飞")
	t.eq(MovieScene.claim_taken({"ok": false, "taken": [[1, 1]]}), [],
			"只把 taken 放在顶层不算数（旧写法读的就是这里）")


# ------------------------------------------------------------------ fixtures

func _claim_report(project: Dictionary, order_id: String, src: Vector2i) -> Dictionary:
	var model = ProjectModel.new()
	if not model.load_data(project):
		return {"ok": false, "code": "TEST_PROJECT_BAD"}
	var ev = EventEvaluator.new()
	ev.setup(model, 3, null)
	var loaded: Dictionary = ev.load_timeline([{
		"id": "e1", "at": 1.0, "type": "order_claim", "channel": "sim",
		"payload": {"order": order_id, "src": [src.x, src.y]},
	}])
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "code": "TEST_TIMELINE_BAD"}
	return ev.step()


func _two_row_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "two",
				"board": {"width": 3, "height": 1, "slots": [
					{"x": 0, "y": 0, "entity": "A", "level": 2},
					{"x": 2, "y": 0, "entity": "B", "level": 1},
				]},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "coin": 4, "star": 1,
						"mission": [{"entity": "A", "level": 2}, {"entity": "B", "level": 1}]},
				],
			},
		],
		"timeline": [],
	}


func _single_row_project() -> Dictionary:
	return {
		"version": 2,
		"hud": _hud(),
		"entities": _entities(),
		"generators": {},
		"characters": {"CH": {"display": "T"}},
		"levels": [
			{
				"id": "one",
				"board": {"width": 3, "height": 1, "slots": [
					{"x": 0, "y": 0, "entity": "A", "level": 2},
					{"x": 2, "y": 0, "entity": "A", "level": 2},
				]},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "CH", "coin": 4, "star": 1,
						"mission": [{"entity": "A", "level": 2}]},
				],
			},
		],
		"timeline": [],
	}


func _entities() -> Dictionary:
	return {
		"A": {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 3},
		"B": {"kind": "chip", "family": "F", "chain": "b", "maxLevel": 10},
		"CH": {"kind": "character"},
	}


func _hud() -> Dictionary:
	return {
		"level": 1, "energy": 10, "energyTickSeconds": 120, "energyTickMode": "decrement",
		"coin": 0, "star": 0, "gem": 0, "exp": 0,
	}
