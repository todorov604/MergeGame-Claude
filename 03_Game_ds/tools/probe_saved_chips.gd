extends SceneTree
## 校验"编辑器保存的 chip / seconds 是否真的被 sim 吃到"。
func _init() -> void:
	var PM = load("res://src/core/project_model.gd")
	var Sim = load("res://src/core/sim.gd")
	var m = PM.new()
	m.load_file("res://data/sample_project.json")
	var s = Sim.new(); s.setup(m, 7)
	print("RESULT trapped=", s.trapped_chips)
	print("RESULT ice_lengths=", s.ice_lengths)
	for cell in [Vector2i(2, 5), Vector2i(3, 6)]:
		print("RESULT cell=", cell, " kinds=", s.board.obstacle_types(cell),
				" item=", s.board.item(cell), " left=", s.ice_remaining(cell))
	var snap: Dictionary = s.snapshot()
	print("RESULT snap.trapped=", snap["board"].get("trapped", {}))
	quit()
