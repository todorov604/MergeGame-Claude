extends SceneTree
## 直接验证：带 icon 的 item 取到的贴图，是否等于被选系列那张。

const Model := preload("res://src/core/project_model.gd")
const Guard := preload("res://src/assets/asset_guard.gd")
const Loader := preload("res://src/theme/theme_loader.gd")
const BoardView := preload("res://src/view/board_view.gd")


func _hash(tex) -> String:
	if tex == null:
		return "null"
	return str(tex.get_image().get_data().hash())


func _init() -> void:
	var m = Model.new()
	if not m.load_file("res://output/probe/icon_project.json"):
		print("[probe] load fail"); quit(1); return
	var guard = Guard.new()
	if not guard.load_from("res://data/manifest_index.json", false):
		print("[probe] guard fail ", guard.load_error); quit(1); return
	var loader = Loader.new()
	loader.guard = guard
	var ok: Dictionary = loader.load_theme("themes/default", m.project)
	print("[probe] theme ok=", ok.get("ok"), " err=", str(ok.get("errors", [])).substr(0, 120))

	var v = BoardView.new()
	v.build_from_level_data(m.level(0), m.project.get("entities", {}), m.project.get("generators", {}))
	v.set_asset_theme(loader, m.project)

	var item: Dictionary = (v._items as Dictionary).get(Vector2i(1, 1), {})
	print("[probe] gen item=", item)
	print("[probe] gen texture=", _hash(v._chip_texture(item)))
	print("[probe] ref Ca5     =", _hash(v.item_texture("chip", "CleanSet_Ca", 5)))
	print("[probe] ref Cb1     =", _hash(v.item_texture("chip", "CleanSet_Cb", 1)))
	var chip_item: Dictionary = (v._items as Dictionary).get(Vector2i(3, 1), {})
	print("[probe] chip item=", chip_item)
	print("[probe] chip texture=", _hash(v._chip_texture(chip_item)))
	v.free()
	quit(0)
