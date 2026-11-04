extends RefCounted
## Static board view tests: parsing, geometry, view state, and the copyright red
## line (no REFERENCE_ONLY asset id may appear in the view sources).
##
## Headless-safe: nothing here renders or loads a texture. `build_from_project`
## only parses JSON; fonts and the optional PLACEHOLDER branch live in _ready(),
## which never runs for an instance that is not added to the tree.

const BoardView = preload("res://src/view/board_view.gd")

const SAMPLE := "res://data/sample_project.json"
const VIEW_DIR := "res://src/view"
const BANNED := ["chip_clean", "obstacle_web", "board_bg", "slot_empty", "char_order", "ui_topbar"]


func run(t) -> void:
	_geometry(t)
	_parsing(t)
	_state(t)
	_red_line(t)
	_scene(t)


func _geometry(t) -> void:
	var v = BoardView.new()
	t.eq(v.cell_rect(0, 0), Rect2(50, 450, 140, 140), "cell_rect(0,0) == Rect2(50,450,140,140)")
	t.eq(v.cell_rect(6, 8), Rect2(890, 1570, 140, 140), "cell_rect(6,8) == Rect2(890,1570,140,140)")
	t.eq(v.cell_rect(6, 0).position.x + v.cell_rect(6, 0).size.x, 1030.0, "board right edge is 1030")
	t.eq(v.cell_rect(0, 8).position.y + v.cell_rect(0, 8).size.y, 1710.0, "board bottom edge is 1710")
	t.eq(v.cell_rect(3, 3), Rect2(470, 870, 140, 140), "cell_rect(3,3) is the demo selection cell")
	v.free()


func _parsing(t) -> void:
	var v = BoardView.new()
	var r: Dictionary = v.build_from_project(SAMPLE, 0)
	t.ok(bool(r.get("ok", false)), "level 1 builds", String(r.get("error", "")))
	t.eq(int(r.get("cells", 0)), 63, "7x9 board = 63 cells")
	t.eq(int(r.get("items", 0)), 6, "level 1 has 6 items")
	t.eq(int(r.get("obstacles", 0)), 4, "level 1 has 4 obstacles")
	t.eq(String(r.get("level_id", "")), "level_1", "level id comes from the project")

	var types: Array = r.get("obstacle_types", [])
	types.sort()
	t.eq(types, ["bubble", "ice", "lock", "web"], "obstacle types == {lock,web,bubble,ice}")
	t.ok(v.debug_summary().begins_with("board=7x9 items=6 obstacles=4"), "summary matches level 1",
			v.debug_summary())
	var first: String = v.debug_summary()
	v.build_from_project(SAMPLE, 0)
	t.eq(v.debug_summary(), first, "rebuilding the same level is deterministic")

	var r2: Dictionary = v.build_from_project(SAMPLE, 1)
	t.ok(bool(r2.get("ok", false)), "level 2 builds", String(r2.get("error", "")))
	t.eq(int(r2.get("items", 0)), 8, "level 2 has 8 items")
	t.eq(int(r2.get("obstacles", 0)), 2, "level 2 has 2 obstacles")
	t.eq(String(r2.get("level_id", "")), "level_2", "level 2 id")

	var missing: Dictionary = v.build_from_project("res://data/does_not_exist.json", 0)
	t.ok(not bool(missing.get("ok", true)), "missing project is rejected")
	t.ok(not String(missing.get("error", "")).is_empty(), "missing project reports an error",
			String(missing.get("error", "")))
	t.ok(_is_ascii(String(missing.get("error", ""))), "error text is ASCII")

	var oob: Dictionary = v.build_from_project(SAMPLE, 99)
	t.ok(not bool(oob.get("ok", true)), "level index out of range is rejected")
	v.free()


func _state(t) -> void:
	var v = BoardView.new()
	v.build_from_project(SAMPLE, 0)
	t.ok(v.debug_summary().contains("selected=(3,3)"), "default demo selection is (3,3)",
			v.debug_summary())
	t.ok(v.debug_summary().contains("complete=1"), "default demo has 1 completed cell",
			v.debug_summary())

	v.apply_state({"selected": [3, 3], "completed": [[1, 4]]})
	var s: String = v.debug_summary()
	t.ok(s.contains("selected=(3,3)"), "apply_state selects (3,3)", s)
	t.ok(s.contains("complete=1"), "apply_state keeps 1 completed cell", s)
	t.ok(_is_ascii(s), "debug_summary is ASCII", s)

	v.apply_state({"selected": [5, 5], "completed": [[1, 4], [2, 3], [6, 8]]})
	s = v.debug_summary()
	t.ok(s.contains("selected=(5,5)"), "apply_state moves the selection", s)
	t.ok(s.contains("complete=3"), "apply_state counts 3 completed cells", s)

	v.apply_state({"selected": [9, 9], "completed": [[7, 0], [0, 9]]})
	s = v.debug_summary()
	t.ok(s.contains("selected=none"), "out of range selection is ignored", s)
	t.ok(s.contains("complete=0"), "out of range completed cells are ignored", s)

	v.apply_state({})
	t.ok(v.debug_summary().contains("selected=none"), "empty state clears the selection",
			v.debug_summary())
	v.free()


func _red_line(t) -> void:
	var dir := DirAccess.open(VIEW_DIR)
	t.ok(dir != null, "src/view is readable")
	if dir == null:
		return
	var files := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var is_source := not dir.current_is_dir() and (name.ends_with(".gd") or name.ends_with(".tscn"))
		if is_source:
			files += 1
			var path := VIEW_DIR + "/" + name
			var text := FileAccess.get_file_as_string(path)
			t.ok(not text.is_empty(), "view source is readable: " + name)
			for banned in BANNED:
				t.ok(not text.contains(String(banned)),
						"%s does not mention %s" % [name, String(banned)])
		name = dir.get_next()
	dir.list_dir_end()
	t.ok(files >= 2, "view sources scanned", str(files))

	var view_script := FileAccess.get_file_as_string(VIEW_DIR + "/board_view.gd")
	t.ok(view_script.contains("--allow-placeholders"), "placeholder opt-in reads the CLI flag")
	t.ok(view_script.contains("if allow_placeholders"), "placeholder branch is gated by the flag")
	t.ok(view_script.contains("check_ref"), "placeholder branch asks the asset guard")


func _scene(t) -> void:
	var packed = load("res://src/view/board_view.tscn")
	t.ok(packed != null, "board_view.tscn loads")
	if packed == null:
		return
	var instance = packed.instantiate()
	t.ok(instance != null, "board_view.tscn instantiates")
	if instance != null:
		t.ok(instance.has_method("build_from_project"), "scene root exposes build_from_project")
		t.ok(instance.has_method("apply_state"), "scene root exposes apply_state")
		t.ok(instance.has_method("debug_summary"), "scene root exposes debug_summary")
		t.ok(instance.has_method("cell_rect"), "scene root exposes cell_rect")
		instance.free()


func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 126:
			return false
	return true
