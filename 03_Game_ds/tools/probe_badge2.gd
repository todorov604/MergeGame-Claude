extends SceneTree
## 探针：3 枚 lv2（都在外面）+ 5 枚 lv1（2 枚在冰/网下），看面板自己算出几比几。
func _init() -> void:
	var Panel = load("res://src/view/order_panel.gd")
	var p = Panel.new()
	var snap := {
		"orders": [{
			"id": "o1", "character": "", "coin": 0, "gem": 0, "energy": 0, "done": false,
			"mission": [["CleanSet_Ca", 2, 0, 1], ["CleanSet_Ca", 1, 0, 4]],
		}],
		"board": {
			"cells": [[1, 1, "CleanSet_Ca", 2], [2, 1, "CleanSet_Ca", 2], [3, 1, "CleanSet_Ca", 2],
					[1, 2, "CleanSet_Ca", 1], [2, 2, "CleanSet_Ca", 1], [3, 2, "CleanSet_Ca", 1],
					[4, 2, "CleanSet_Ca", 1], [5, 2, "CleanSet_Ca", 1]],
			"obstacles": [[4, 2, ["ice"]], [5, 2, ["web"]]],
		},
	}
	p.set_board_snapshot(snap)
	print("RESULT lv2=", p.board_count("CleanSet_Ca", 2), " lv1=", p.board_count("CleanSet_Ca", 1))
	p.free()
	quit()
