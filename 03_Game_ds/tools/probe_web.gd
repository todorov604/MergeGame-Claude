extends SceneTree
## 探针：蜘蛛网规则（2026-11-11）
##   1) 合并爆炸不再炸开网；
##   2) 拖一枚**同款**棋子压到网上 → 网解锁 + 合成高一级；
##   3) 不同款拖上去 → 拒绝，网还在。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	m.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_project.json")))

	# 第 1 关找一个被网盖住的格子
	var s = Sim.new(); s.setup(m, 20261111)
	var web_cell := Vector2i(-1, -1)
	for ob in m.level(0).get("obstacles", []):
		if String((ob as Dictionary).get("type", "")) != "web":
			continue
		var slot: Array = (ob as Dictionary).get("slot", [])
		web_cell = Vector2i(int(slot[0]), int(slot[1]))
		break
	print("RESULT web_cell=", web_cell, " obstacle=", s.board.obstacle_types(web_cell),
			" item=", s.board.item(web_cell))

	# 2) 造一枚同款棋子放到相邻空格，拖上去
	var hidden: Dictionary = s.board.item(web_cell)
	var ent := String(hidden.get("entity", ""))
	var lv := int(hidden.get("level", 1))
	var src := Vector2i(-1, -1)
	for y in s.board.height:
		for x in s.board.width:
			var c := Vector2i(x, y)
			if s.board.is_blocked(c) or s.board.has_item(c) or c == web_cell:
				continue
			src = c
			break
		if src.x >= 0:
			break
	s.board.put(src, ent, lv)
	# 走**实机那条路**：先问 FreeMode 拖拽判定，再用判定给的 payload 发事件
	var FM = load("res://src/core/free_mode.gd")
	var act: Dictionary = FM.drag_action(src, web_cell, s, m, Vector2i(-1, -1))
	print("RESULT drag_action kind=", act.get("kind", ""), " payload=", act.get("payload", {}))
	var ev_type := "drag" if String(act.get("kind", "")) == "merge" else String(act.get("kind", ""))
	var r: Dictionary = s.apply({"type": ev_type, "payload": act.get("payload", {})})
	print("RESULT merge ok=", r.get("ok", false), " web_unlocked=", r.get("web_unlocked", false),
			" code=", r.get("code", ""))
	print("RESULT after obstacle=", s.board.obstacle_types(web_cell),
			" item=", s.board.item(web_cell), " expect lv=", lv + 1)

	# 3) 不同款压上去
	var s2 = Sim.new(); s2.setup(m, 20261111)
	var other := "CleanSet_Cd" if ent != "CleanSet_Cd" else "CleanSet_Cb"
	s2.board.put(src, other, lv)
	var r2: Dictionary = s2.apply({"type": "merge", "payload": {"from": [src.x, src.y], "to": [web_cell.x, web_cell.y]}})
	print("RESULT mismatch ok=", r2.get("ok", false), " code=", r2.get("code", ""),
			" web still=", s2.board.obstacle_types(web_cell))
	quit()
