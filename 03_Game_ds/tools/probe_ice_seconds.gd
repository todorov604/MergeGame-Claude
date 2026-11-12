extends SceneTree
## 自造关卡：两块冰不同秒数 + 网下指定棋子 —— 验证 sim 与快照都按 JSON 走。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var project := {
		"version": 2,
		"hud": {"level": 1, "energy": 50, "energyTickSeconds": 120, "energyTickMode": "decrement",
			"coin": 0, "gem": 0, "exp": 0},
		"entities": {
			"CleanSet_Ca": {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 10},
			"CleanSet_Cb": {"kind": "chip", "family": "F", "chain": "b", "maxLevel": 10},
		},
		"generators": {}, "characters": {"CH": {"display": "T"}},
		"levels": [{
			"id": "ice_probe", "ice_seconds": 45,
			"board": {"width": 4, "height": 3, "slots": []},
			"obstacles": [
				{"slot": [0, 0], "type": "ice", "seconds": 10},
				{"slot": [1, 0], "type": "ice", "seconds": 90},
				{"slot": [2, 0], "type": "web", "chip": {"entity": "CleanSet_Cb", "level": 3}},
			],
			"orders": [{"id": "o1", "character": "CH", "coin": 1,
				"mission": [{"entity": "CleanSet_Ca", "level": 1, "count": 1}]}],
		}],
	}
	var m = PM.new()
	var ok: bool = m.load_data(project)
	print("RESULT load=", ok)
	var s = Sim.new(); s.setup(m, 7)
	for t in [0.0, 5.0, 11.0, 60.0]:
		s.tick_to(t)
		print("RESULT t=", t, " iceA=", s.ice_remaining(Vector2i(0,0)),
				" iceB=", s.ice_remaining(Vector2i(1,0)),
				" cellA=", s.board.obstacle_types(Vector2i(0,0)),
				" cellB=", s.board.obstacle_types(Vector2i(1,0)))
	var snap: Dictionary = s.snapshot()
	print("RESULT trapped=", snap["board"].get("trapped", {}))
	print("RESULT webbed_item=", s.board.item(Vector2i(2,0)))
	quit()
