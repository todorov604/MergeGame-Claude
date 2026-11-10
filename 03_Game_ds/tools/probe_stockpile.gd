extends SceneTree
## 探针：合成关卡里点一次库存，打印落到哪格、什么实体、几级；再点它一次看产出级别。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	var js := FileAccess.get_file_as_string("res://output/probe/project.json")
	m.load_data(JSON.parse_string(js))
	var s = Sim.new()
	s.setup(m, 20261110)
	print("preview=", s.stockpile_preview())
	var r: Dictionary = s.apply({"type": "stockpile_tap", "payload": {}, "at": 4.4})
	print("tap ok=", r.get("ok", false), " code=", r.get("code", ""), " spawn=", s.last_spawn)
	var cell := Vector2i(int(s.last_spawn["to"][0]), int(s.last_spawn["to"][1]))
	print("cell entity=", s.board.item(cell))
	print("tap generator:", s.apply({"type": "tap", "payload": {"target": {"slot": [cell.x, cell.y]}}, "at": 5.0}))
	print("spawned=", s.last_spawn)
	quit()
