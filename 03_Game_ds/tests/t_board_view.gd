extends RefCounted
## Static board view tests: §20.5 geometry (棋盘.psd), parsing, view state, the
## theme-wired chip/UI textures, the no-theme degraded path, and the copyright red
## line (no banned manifest literal may appear in the view sources).
##
## Headless-safe: nothing here renders. `build_from_project` only parses JSON;
## fonts and the optional PLACEHOLDER branch live in _ready(), which never runs for
## an instance that is not added to the tree.

const BoardView = preload("res://src/view/board_view.gd")
const ThemeLoader = preload("res://src/theme/theme_loader.gd")
const AssetGuard = preload("res://src/assets/asset_guard.gd")

const SAMPLE := "res://data/sample_project.json"
const INDEX := "res://data/manifest_index.json"
const DEFAULT_THEME := "themes/default"
const VIEW_DIR := "res://src/view"
const BANNED := ["chip_clean", "obstacle_web", "board_bg", "slot_empty", "char_order", "ui_topbar"]
## The five §20.6 layers the board container itself paints.
const UI_KEYS := ["bg_bottom", "bg_top", "board_frame", "cell", "select"]

## §20.5, verbatim: board container 983x1263 at (48,466) inside a 1080x1920 canvas,
## 7 columns x 9 rows -> 983/7 x 1263/9 per cell.
const CONTAINER := Rect2(48, 466, 983, 1263)
const CELL_W := 983.0 / 7.0
const CELL_H := 1263.0 / 9.0
const ITEMS_BAR_Y := 1731.0


func run(t) -> void:
	_constants(t)
	_geometry(t)
	_parsing(t)
	_state(t)
	_red_line(t)
	_labels(t)
	_scene(t)
	_chip_icons(t)
	_ui_theme(t)
	_degraded(t)
	_box_ice(t)
	_box_flash(t)


## The numbers themselves, so a future edit that rounds them "to taste" fails here
## before it fails a pixel comparison.
func _constants(t) -> void:
	t.eq(BoardView.COLS, 7, "COLS is 7")
	t.eq(BoardView.ROWS, 9, "ROWS is 9")
	t.eq(BoardView.PAGE_SIZE, Vector2(1080, 1920), "canvas is 1080x1920")
	t.eq(BoardView.BOARD_ORIGIN, Vector2(48, 466), "board container origin is (48,466)")
	t.eq(BoardView.BOARD_SIZE, Vector2(983, 1263), "board container is 983x1263")
	t.ok(absf(BoardView.CELL_W - CELL_W) < 1e-9, "CELL_W is exactly 983/7",
			str(BoardView.CELL_W))
	t.ok(absf(BoardView.CELL_H - CELL_H) < 1e-9, "CELL_H is exactly 1263/9",
			str(BoardView.CELL_H))
	t.ok(absf(BoardView.CELL_W - 140.428571) < 1e-6, "CELL_W is 140.428571", str(BoardView.CELL_W))
	t.ok(absf(BoardView.CELL_H - 140.333333) < 1e-6, "CELL_H is 140.333333", str(BoardView.CELL_H))
	# movie_scene.gd does float(BoardView.CELL) and derives every cell from it, and
	# the cell-index math here stays integer: CELL must keep answering as 140 int.
	t.eq(BoardView.CELL, 140, "CELL still answers 140 for movie_scene")
	t.eq(typeof(BoardView.CELL), TYPE_INT, "CELL keeps its int type")
	t.eq(BoardView.CELL_GAP, 4, "CELL_GAP is still 4")
	t.eq(BoardView.PAGE_SIZE.x - BoardView.BOARD_ORIGIN.x, 1032.0,
			"the container keeps a 48 px margin on the right")
	# §20.6 item 1: the two background layers and the chip art size band.
	t.eq(BoardView.BG_BOTTOM_RECT, Rect2(0, 384, 1080, 1536), "bg_bottom is 1080x1536 at (0,384)")
	t.eq(BoardView.BG_TOP_RECT, Rect2(0, 0, 1080, 400), "bg_top is 1080x400 at (0,0)")
	t.eq(BoardView.BG_BOTTOM_RECT.end.y, 1920.0, "bg_bottom fills to the bottom of the canvas")
	t.ok(BoardView.CHIP_DRAW_SIZE >= 132.0 and BoardView.CHIP_DRAW_SIZE <= 140.0,
			"chip art is drawn inside the 132-140 px band", str(BoardView.CHIP_DRAW_SIZE))


func _geometry(t) -> void:
	var v = BoardView.new()
	var c00: Rect2 = v.cell_rect(0, 0)
	t.eq(c00, Rect2(48, 466, 140.428571, 140.333333),
			"cell_rect(0,0) == Rect2(48,466,140.428571,140.333333)")
	t.eq(v.cell_rect(6, 0).end.x, 1031.0, "last column right edge is 1031")
	t.eq(v.cell_rect(0, 8).end.y, 1729.0, "last row bottom edge is 1729")
	t.eq(v.cell_rect(6, 8).end, Vector2(1031, 1729), "cell_rect(6,8) ends at (1031,1729)")
	t.eq(v.cell_rect(0, 0).position, Vector2(48, 466), "the grid starts at the container origin")
	t.eq(v.cell_rect(3, 3).position.y, 887.0, "cell_rect(3,3).y is 466 + 3*1263/9 = 887")
	t.ok(v.cell_rect(3, 3).position.is_equal_approx(
			Vector2(48.0 + 983.0 * 3.0 / 7.0, 887.0)), "cell_rect(3,3) sits at the demo cell",
			str(v.cell_rect(3, 3).position))

	# Neighbours share their edge: Rect2 stores 32-bit floats, so the shared edge is
	# one ulp apart (~6e-5 px) rather than bit-identical. Anything larger is a seam.
	var seam := 0.0
	for x in BoardView.COLS - 1:
		seam = maxf(seam, absf(v.cell_rect(x, 2).end.x - v.cell_rect(x + 1, 2).position.x))
	for y in BoardView.ROWS - 1:
		seam = maxf(seam, absf(v.cell_rect(4, y).end.y - v.cell_rect(4, y + 1).position.y))
	t.ok(seam < 1e-3, "neighbouring cells meet with no seam (<= 1e-3 px)", str(seam))

	# 7x9 cells exactly fill the container
	var union: Rect2 = v.cell_rect(0, 0)
	var cells := 0
	for y in BoardView.ROWS:
		for x in BoardView.COLS:
			union = union.merge(v.cell_rect(x, y))
			cells += 1
	t.eq(cells, 63, "the grid has 63 cells")
	t.eq(union, CONTAINER, "the 63 cells exactly fill the 983x1263 container")
	t.eq(v.cell_rect(6, 0).end.x - v.cell_rect(0, 0).position.x, 983.0,
			"7 cell widths add up to 983 exactly")
	t.eq(v.cell_rect(0, 8).end.y - v.cell_rect(0, 0).position.y, 1263.0,
			"9 cell heights add up to 1263 exactly")
	v.free()


func _parsing(t) -> void:
	var v = BoardView.new()
	var r: Dictionary = v.build_from_project(SAMPLE, 0)
	t.ok(bool(r.get("ok", false)), "level 1 builds", String(r.get("error", "")))
	t.eq(int(r.get("cells", 0)), 63, "7x9 board = 63 cells")
	t.eq(int(r.get("items", 0)), 7, "level 1 has 7 items (6 chips + the generator)")
	t.eq(int(r.get("obstacles", 0)), 43, "level 1 has 43 obstacles (outer two rings + the four specials)")
	t.eq(String(r.get("level_id", "")), "level_1", "level id comes from the project")

	var types: Array = r.get("obstacle_types", [])
	types.sort()
	t.eq(types, ["bag", "ice", "lock", "web"], "obstacle types == {lock,web,bag,ice} for level 1")
	t.ok(v.debug_summary().begins_with("board=7x9 items=7 obstacles=43"), "summary matches level 1 (0/4 mission needs six Ca1 chips on the board)",
			v.debug_summary())
	var first: String = v.debug_summary()
	v.build_from_project(SAMPLE, 0)
	t.eq(v.debug_summary(), first, "rebuilding the same level is deterministic")

	var r2: Dictionary = v.build_from_project(SAMPLE, 1)
	t.ok(bool(r2.get("ok", false)), "level 2 builds", String(r2.get("error", "")))
	t.eq(int(r2.get("items", 0)), 16, "level 2 has 16 items (15 chips + the generator)")
	t.eq(int(r2.get("obstacles", 0)), 16, "level 2 has 16 obstacles（2 排冰块 14 + web + lock）")
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
	# The caption/legend are debug-only: a composed screen owns that space.
	t.ok(view_script.contains("if show_debug_labels"), "debug labels are gated by a flag")


## The caption/legend switch a composed screen flips; the standalone board keeps it on.
func _labels(t) -> void:
	var v = BoardView.new()
	t.eq(v.show_debug_labels, true, "debug labels default to on for a standalone board")
	v.show_debug_labels = false
	t.eq(v.show_debug_labels, false, "a caller can hide the caption and the legend")
	v.free()


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
		t.ok(instance.has_method("set_asset_theme"), "scene root exposes set_asset_theme")
		instance.free()


## chip_icons wire-up: the board draws the resolved texture when a theme maps the
## (entity, level) pair, and keeps the procedural chip when it does not.
func _chip_icons(t) -> void:
	var guard = AssetGuard.new()
	t.ok(guard.load_from(INDEX, false), "manifest index loads for the chip icon test")
	var loader = ThemeLoader.new()
	loader.setup(guard, false)
	var project := _project()
	var theme_result: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(theme_result.get("ok", false)), "themes/default loads for the board view",
			str(theme_result.get("errors", [])))

	var v = BoardView.new()
	v.build_from_project(SAMPLE, 0)
	t.ok(v.has_method("set_chip_icons"), "view keeps the M1 set_chip_icons entry point")
	if v.has_method("set_chip_icons"):
		v.set_chip_icons(loader, project)
	var resolved: int = v.chip_icon_count()
	t.eq(resolved, 6, "level 1 resolves a chip texture for its six chips")
	t.ok(v.debug_summary().begins_with("board=7x9 items=7 obstacles=43"),
			"summary prefix is unchanged with chip icons", v.debug_summary())
	t.ok(resolved <= v.item_count(), "chip_icon_count never exceeds the item count",
			"%d of %d" % [resolved, v.item_count()])
	v.free()


## (b) The board container's own art comes from the theme: the default theme must
## resolve the five §20.6 layers to real manifest ids and real textures.
func _ui_theme(t) -> void:
	t.ok(ThemeLoader.new().has_method("resolve_ui"), "ThemeLoader exposes resolve_ui")
	t.ok(ThemeLoader.new().has_method("texture_for"), "ThemeLoader exposes texture_for")

	var guard = AssetGuard.new()
	t.ok(guard.load_from(INDEX, false), "manifest index loads for the ui theme test")
	var loader = ThemeLoader.new()
	loader.setup(guard, false)
	var project := _project()
	var result: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(result.get("ok", false)), "themes/default loads for the ui theme test",
			str(result.get("errors", [])))
	if not (loader.has_method("resolve_ui") and loader.has_method("texture_for")):
		return

	for key in UI_KEYS:
		var resolved = loader.resolve_ui(String(key), project)
		var id := ""
		if typeof(resolved) == TYPE_DICTIONARY:
			id = String((resolved as Dictionary).get("id", ""))
		t.ok(not id.is_empty(), "default theme resolves ui.%s to an id" % String(key), str(resolved))
		if id.is_empty():
			continue
		var texture = loader.texture_for(id)
		t.ok(texture is Texture2D, "texture_for(%s) returns a texture" % id, str(texture))
		if texture is Texture2D:
			t.ok((texture as Texture2D).get_width() > 0 and (texture as Texture2D).get_height() > 0,
					"ui texture %s has a real size" % id,
					"%dx%d" % [(texture as Texture2D).get_width(), (texture as Texture2D).get_height()])

	var v = BoardView.new()
	v.build_from_project(SAMPLE, 0)
	t.ok(v.has_method("set_asset_theme"), "view exposes set_asset_theme")
	if not v.has_method("set_asset_theme"):
		v.free()
		return
	v.set_asset_theme(loader, project)
	var ids: Dictionary = v.ui_ids()
	for key in UI_KEYS:
		t.ok(not String(ids.get(String(key), "")).is_empty(),
				"view resolves ui.%s through set_asset_theme" % String(key), str(ids))
	var summary: String = v.ui_summary()
	t.ok(summary.begins_with("bg_bottom="), "ui_summary starts with bg_bottom", summary)
	t.ok(not summary.contains("= "), "ui_summary prints no empty id", summary)
	t.ok(v.chip_icon_count() > 0, "set_asset_theme also wires the chip icons",
			str(v.chip_icon_count()))
	v.free()


## (c) No theme at all: the view still builds, keeps every procedural fallback and
## resolves nothing, which is what a relocated copy without the copies relies on.
func _degraded(t) -> void:
	var v = BoardView.new()
	var built: Dictionary = v.build_from_project(SAMPLE, 0)
	t.ok(bool(built.get("ok", false)), "level 1 builds without a chip loader",
			String(built.get("error", "")))
	t.eq(v.chip_icon_count(), 0, "no loader -> chip_icon_count() is 0")
	t.eq(v.ui_ids().size(), 0, "no loader -> ui_ids() is empty")
	t.eq(v.ui_summary(), "", "no loader -> ui_summary() is empty")
	t.ok(v.debug_summary().begins_with("board=7x9 items=7 obstacles=43"),
			"summary keeps its prefix without a chip loader", v.debug_summary())
	t.eq(v.cell_rect(0, 0), Rect2(48, 466, 140.428571, 140.333333),
			"the geometry stays the §20.5 geometry without a theme")
	v.free()


func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 126:
			return false
	return true


func _project() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


## 2026-11-10：蓝盒子开出来的 `icebox` 必须被视图认下来 ——
## 否则 sim 里那一格已经挡住了，画面上却什么都没有（操作者报"炸开之后什么都没有、还拖不进去"）。
func _box_ice(t) -> void:
	t.ok(BoardView.OBSTACLE_TYPES.has("icebox"), "OBSTACLE_TYPES 认识 icebox")
	var v = BoardView.new()
	var level := {
		"id": "bv",
		"board": {"width": 3, "height": 3, "slots": []},
		"obstacles": [
			{"slot": [0, 0], "type": "icebox"},
			{"slot": [1, 1], "type": "web"},
			{"slot": [2, 2], "type": "lock"},
		],
	}
	var out: Dictionary = v.build_from_level_data(level, {}, {})
	t.eq(int(out.get("obstacles", 0)), 3, "三种障碍都被接受（含 icebox）")
	t.ok(v.obstacles_has_kind(Vector2i(0, 0), "icebox"), "icebox 落到格子上")
	t.ok(not v.obstacles_has_kind(Vector2i(0, 0), "ice"), "icebox 不会误判成普通 ice")


## 2026-11-10：蓝盒子砸开时闪的图标 = 它变成的东西，不能是问号袋子。
func _box_flash(t) -> void:
	var v = BoardView.new()
	v.unlock(Vector2i(1, 1), "box", 0.0, "icebox")
	v.unlock(Vector2i(2, 2), "box", 0.0, "web")
	var shown: Array = []
	for row in v.unlock_rows():
		shown.append(String((row as Dictionary).get("shown", "")))
	t.eq(str(shown), str(["icebox", "web"]), "盒子炸开闪的是冰/网，不是问号")
