extends SceneTree
## 2026-11-12：确认 12 套 x 10 级棋子都能解析成真实贴图（含 Ca/Cb 的 7~10 级别名）。

const Model := preload("res://src/core/project_model.gd")
const Guard := preload("res://src/assets/asset_guard.gd")
const Loader := preload("res://src/theme/theme_loader.gd")


func _init() -> void:
	var m = Model.new()
	if not m.load_file("res://data/sample_project.json"):
		print("[chips] load fail")
		quit(1)
		return
	var guard = Guard.new()
	if not guard.load_from("res://data/manifest_index.json", false):
		print("[chips] guard fail ", guard.load_error)
		quit(1)
		return
	var loader = Loader.new()
	loader.guard = guard
	var loaded: Dictionary = loader.load_theme("themes/default", m.project)
	print("[chips] theme ok=", loaded.get("ok"), " series=", (loaded.get("chip_icons", {}) as Dictionary).size(), " errors=", str(loaded.get("errors", [])).substr(0, 400))

	var chips: Array = []
	for id in m.project.get("entities", {}):
		var ent: Dictionary = m.project["entities"][id]
		if String(ent.get("kind", "chip")) == "chip":
			chips.append(String(id))
	chips.sort()
	print("[chips] entities=", chips.size())

	var missing: Array = []
	var ok_count := 0
	for id in chips:
		for lv in range(1, 11):
			var tex = loader.chip_texture(id, lv, m.project)
			if tex == null:
				missing.append("%s@%d" % [id, lv])
			else:
				ok_count += 1
	print("[chips] textures ok=", ok_count, " missing=", missing.size())
	if not missing.is_empty():
		print("[chips] MISSING ", missing.slice(0, 12))
	print("[chips] RESULT ", "PASS" if missing.is_empty() and ok_count == chips.size() * 10 else "FAIL")
	quit(0 if missing.is_empty() else 1)
