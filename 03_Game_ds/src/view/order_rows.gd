extends RefCounted
## snapshot -> OrderPanel.sync_orders 行数据的唯一转换处（2026-11-06）。
##
## 实机（src/view/game_screen.gd）与成片（src/render/movie_scene.gd）都调这里，行只造
## 一次，两边就不会各写一份后漂移。
##
## 行形状：
##   {"id": String, "character": String, "coin": int, "star": int, "gem": int, "done": bool,
##    "mission": [{"entity": String, "level": int, "have": int, "need": int,
##                 "ready": bool, "hue": Color, "label": String}]}
##
## * `have` / `done` / 奖励直接抄 sim 快照。
## * `need` 恒为 1：订单任务项在 have >= 1 时就付清 —— 这正是
##   src/core/completed_cells.gd 用的规则，也是 order_panel._make_card 的假设。
## * `ready` 是「棋盘此刻真的摆着一枚能付清这一项的棋子」的视图推导。候选格子来自
##   CompletedCells，所以压在 web / ice / box 下面的棋子绝不会点亮任务行（遮挡规则
##   只有一处实现）。
## * `hue` / `label` 来 entities 表（visual.hue / visual.label），兜底与 order_panel
##   一致，程序化棋子块的底色和首字不变。
##
## 纯数据进出：不碰 sim、不碰场景树、不读时钟。

const CompletedCells := preload("res://src/core/completed_cells.gd")
const DEFAULT_HUE := Color("#94A3B8")


static func build(snap: Dictionary, model) -> Array:
	var out: Array = []
	if typeof(snap) != TYPE_DICTIONARY:
		return out
	var orders = snap.get("orders", [])
	if typeof(orders) != TYPE_ARRAY:
		return out
	# 哪些 entity@level 当前真的摆在棋盘上（CompletedCells 已排除被遮挡的格子）。
	var ready_keys := _ready_keys(snap)
	for raw in orders:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = raw
		var mission: Array = []
		var raw_mission = order.get("mission", [])
		if typeof(raw_mission) == TYPE_ARRAY:
			for item in raw_mission:
				var slot := _mission_slot(item)
				if slot.is_empty():
					continue
				var entity_id := String(slot["entity"])
				var level := int(slot["level"])
				var visual := _visual(model, entity_id)
				mission.append({
					"entity": entity_id,
					"level": level,
					"have": int(slot["have"]),
					"need": 1,
					"ready": ready_keys.has("%s@%d" % [entity_id, level]),
					"hue": Color.from_string(String(visual.get("hue", "")), DEFAULT_HUE),
					"label": String(visual.get("label", entity_id.left(3))),
				})
		out.append({
			"id": String(order.get("id", "")),
			"character": String(order.get("character", "")),
			"coin": int(order.get("coin", 0)),
			"star": int(order.get("star", 0)),
			# 2026-11-09：钻石奖励跟着一起转，实机与成片的卡片蓝条读的是这一份。
			"gem": int(order.get("gem", 0)),
			"energy": int(order.get("energy", 0)),
			"done": bool(order.get("done", false)),
			"mission": mission,
		})
	return out


## One mission entry -> {"entity", "level", "have"}. The sim snapshot writes
## [entity, level, have]; project.json writes {entity, level}, so both shapes resolve
## here instead of in every caller. {} means "skip this entry".
static func _mission_slot(raw) -> Dictionary:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		var row: Array = raw
		return {
			"entity": String(row[0]),
			"level": int(row[1]),
			"have": int(row[2]) if row.size() >= 3 else 0,
		}
	if typeof(raw) == TYPE_DICTIONARY:
		var m: Dictionary = raw
		return {
			"entity": String(m.get("entity", "")),
			"level": int(m.get("level", 1)),
			"have": int(m.get("have", 0)),
		}
	return {}


## "entity@level" for every chip that pays an open mission right now. The cell list is
## CompletedCells' (obstacle-covered chips already dropped there); entity and level are
## read back from the snapshot's own board rows, the same way the live screen used to
## read them off the live board.
static func _ready_keys(snap: Dictionary) -> Dictionary:
	var by_pos := {}
	var board = snap.get("board", null)
	if typeof(board) == TYPE_DICTIONARY:
		var cells = (board as Dictionary).get("cells", [])
		if typeof(cells) == TYPE_ARRAY:
			for raw in cells:
				if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
					continue
				var row: Array = raw
				by_pos["%d@%d" % [int(row[0]), int(row[1])]] = "%s@%d" % [String(row[2]), int(row[3])]
	var keys := {}
	for raw_cell in CompletedCells.from_snapshot(snap):
		if typeof(raw_cell) != TYPE_ARRAY or (raw_cell as Array).size() < 2:
			continue
		var cell: Array = raw_cell
		var key := String(by_pos.get("%d@%d" % [int(cell[0]), int(cell[1])], ""))
		if not key.is_empty():
			keys[key] = true
	return keys


## entities.<id>.visual from whichever model the caller has (live screen, film, or a
## bare project dictionary in tests). An unknown id yields {} and the fallbacks above
## take over.
static func _visual(model, entity_id: String) -> Dictionary:
	if model == null:
		return {}
	var ent = {}
	if typeof(model) == TYPE_DICTIONARY:
		var table = (model as Dictionary).get("entities", {})
		if typeof(table) == TYPE_DICTIONARY:
			ent = (table as Dictionary).get(entity_id, {})
	elif model.has_method("entity"):
		ent = model.entity(entity_id)
	if typeof(ent) != TYPE_DICTIONARY:
		return {}
	var visual = (ent as Dictionary).get("visual", {})
	return visual if typeof(visual) == TYPE_DICTIONARY else {}
