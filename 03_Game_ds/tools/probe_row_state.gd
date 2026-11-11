extends SceneTree
## 探针：五张卡里，c5 要 Ca lv1 ×3、棋盘只有 2 枚 → 必须读成 2/3 且判定为"未满"（米色 + 棕字）。
func _init() -> void:
	var Panel = load("res://src/view/order_panel.gd")
	var p = Panel.new()
	p.build_from_level({"id": "st", "orders": [
		{"id": "a", "character": "char_blonde", "mission": [{"entity": "CleanSet_Ca", "level": 1, "count": 3}],
			"coin": 1, "gem": 1, "energy": 1},
		{"id": "b", "character": "char_worker", "mission": [{"entity": "CleanSet_Cd", "level": 1, "count": 1}],
			"coin": 1, "gem": 1, "energy": 1},
	]})
	p.size = Vector2(1080.0, 250.0)
	p.set_board_snapshot({"board": {"cells": [
			[1, 1, "CleanSet_Ca", 1], [2, 1, "CleanSet_Ca", 1], [3, 1, "CleanSet_Cd", 1]],
			"obstacles": []}})
	var card_a: Dictionary = p.cards[0]
	var card_b: Dictionary = p.cards[1]
	print("RESULT a board=", p.row_board_for("a", 0), " need=", int((card_a["mission"][0] as Dictionary)["need"]),
			" full=", p._card_full(card_a))
	print("RESULT b board=", p.row_board_for("b", 0), " need=", int((card_b["mission"][0] as Dictionary)["need"]),
			" full=", p._card_full(card_b))
	p.free()
	quit()
