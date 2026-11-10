extends SceneTree
## 纯数据探针：OrderRows.build 的角标数字（隔离面板/场景，秒回）。
func _init() -> void:
	var Rows = load("res://src/view/order_rows.gd")
	var snap := {
		"orders": [{
			"id": "order_1", "character": "", "coin": 5, "gem": 2, "energy": 3, "done": false,
			"mission": [["CleanSet_Ca", 2, 0, 1], ["CleanSet_Ca", 1, 0, 4]],
		}],
		"board": {
			"cells": [[1, 1, "CleanSet_Ca", 1], [2, 1, "CleanSet_Ca", 1], [3, 1, "CleanSet_Ca", 1],
					[4, 1, "CleanSet_Ca", 1], [5, 1, "CleanSet_Ca", 1], [1, 2, "CleanSet_Ca", 2]],
			"obstacles": [],
		},
	}
	var rows: Array = Rows.build(snap, null)
	for m in (rows[0]["mission"] as Array):
		print("row ", m.get("entity"), " lv", m.get("level"), " board=", m.get("board"), " need=", m.get("need"))
	quit()
