extends SceneTree
## case8 的文字证据：锁盒 / 问号袋炸开后，那一格到底是什么棋子。

const ProjectModel := preload("res://src/core/project_model.gd")
const Sim := preload("res://src/core/sim.gd")


func _init() -> void:
	var m = ProjectModel.new()
	if not m.load_file("res://output/probe/case8_unlock_pool.json"):
		print("[unlock] load fail"); quit(1); return
	var sim = Sim.new()
	sim.setup(m, 7)
	print("[unlock] pool=", sim.random_pool())
	var r: Dictionary = sim.apply({"type": "merge", "payload": {"from": [2, 4], "to": [3, 4]}})
	print("[unlock] merge ok=", r.get("ok"), " unlocks=", r.get("unlocks"))
	for cell in [Vector2i(2, 5), Vector2i(2, 3), Vector2i(4, 4)]:
		print("[unlock] ", cell, " obstacles=", sim.board.obstacle_types(cell),
				" item=", sim.board.item(cell))
	quit(0)
