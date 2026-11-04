extends RefCounted

## 合并门禁回归（P1-2 merge kind / P2-1 等级上限）。
## 权威规格：00_design/M0-冻结规格.md v0.20 §2.1.9 / §2.1.6。
## 覆盖：
##   - special / generator / character 不可合成（SIM_NOT_MERGEABLE，失败零状态变化）
##   - chip 对照：同实体同等级可合成
##   - 等级上限：maxLevel=11 时两枚 Lv10 不得合出 Lv11

const SimRunner = preload("res://core/sim/sim_runner.gd")
const ProjectDoc = preload("res://core/project_doc.gd")

const NON_MERGEABLE_KINDS := ["special", "generator", "character"]


func run(r) -> void:
	for kind in NON_MERGEABLE_KINDS:
		_test_non_chip_rejected(r, kind)
	_test_chip_control(r)
	_test_level_cap_eleven(r)


# ---------------------------------------------------------------- P1-2

func _test_non_chip_rejected(r, kind: String) -> void:
	var res: Dictionary = _run_merge(_doc(kind, 10, 1, 1))
	var event: Dictionary = _find_event(res.get("events", []), "m1")
	r.check(not bool(event.get("ok", true)), "kind=%s 不应可合成" % kind)
	r.contains(str(event.get("message", "")), "SIM_NOT_MERGEABLE", "kind=%s 拒绝文案" % kind)
	r.eq(
		JSON.stringify(res.get("initial_snapshot", {})),
		JSON.stringify(res.get("snapshot", {})),
		"kind=%s 合并失败应零状态变化（棋盘与快照不变）" % kind
	)


func _test_chip_control(r) -> void:
	var res: Dictionary = _run_merge(_doc("chip", 10, 1, 1))
	var event: Dictionary = _find_event(res.get("events", []), "m1")
	r.check(bool(event.get("ok", false)), "chip 同实体同等级应可合成: " + str(event.get("message", "")))
	r.eq(int(_cell_at(res["snapshot"]["board"], 1, 0).get("level", 0)), 2, "chip 合成后目标格 Lv2")
	r.eq(_cell_at(res["snapshot"]["board"], 0, 0), {}, "chip 合成后来源格应清空")


# ---------------------------------------------------------------- P2-1

func _test_level_cap_eleven(r) -> void:
	var res: Dictionary = _run_merge(_doc("chip", 11, 10, 10))
	var event: Dictionary = _find_event(res.get("events", []), "m1")
	r.check(not bool(event.get("ok", true)), "maxLevel=11 时两枚 Lv10 不应可合成")
	r.contains(str(event.get("message", "")), "达到等级上限", "等级上限拒绝文案")
	var cells: Array = res["snapshot"]["board"]["cells"]
	r.eq(cells.size(), 2, "等级上限拒绝后棋盘应保留两枚 Lv10")
	var has_level_11 := false
	for cell in cells:
		if int(cell.get("level", 0)) >= 11:
			has_level_11 = true
	r.check(not has_level_11, "棋盘不应存在 Lv11")


# ---------------------------------------------------------------- helpers

func _doc(kind: String, max_level: int, from_level: int, to_level: int) -> ProjectDoc:
	var doc = ProjectDoc.new()
	doc.from_dict({
		"entities": {
			"E": {"kind": kind, "maxLevel": max_level},
		},
		"levels": [{
			"id": "l1",
			"board": {"width": 3, "height": 1, "slots": [
				{"x": 0, "y": 0, "entity": "E", "level": from_level},
				{"x": 1, "y": 0, "entity": "E", "level": to_level},
			]},
			"orders": [],
		}],
		"timeline": [
			{"id": "m1", "channel": "sim", "type": "merge", "at": 1.0, "payload": {"from": [0, 0], "to": [1, 0]}},
		],
	}, "<merge-gate-test>")
	return doc


func _run_merge(doc) -> Dictionary:
	return SimRunner.new().run(doc, 1)


func _find_event(events: Array, event_id: String) -> Dictionary:
	for event in events:
		if str(event.get("id", "")) == event_id:
			return event
	return {}


func _cell_at(board_snapshot: Dictionary, x: int, y: int) -> Dictionary:
	for cell in board_snapshot.get("cells", []):
		if int(cell.get("x", -1)) == x and int(cell.get("y", -1)) == y:
			return cell
	return {}
