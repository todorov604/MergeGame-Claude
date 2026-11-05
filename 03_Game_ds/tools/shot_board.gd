extends SceneTree
## Renders the static board to a real PNG with a real (non-headless) renderer.
##
##   godot --path . --script res://tools/shot_board.gd
##   godot --path . --script res://tools/shot_board.gd -- --theme=themes/pet_shop
##   godot --path . --script res://tools/shot_board.gd -- "--toast=Board is full"
##
## --theme=<name> picks the theme (the default is the one the sample project asks
## for); --toast=<text> paints the §7 board-full strip so its §20.5 position can be
## eyeballed.
## The capture goes through a fixed-size SubViewport instead of the window texture,
## so the PNG is always exactly 1080x1920 no matter how the OS resized the window.
## Writes res://output/board_1080x1920.png and prints an ASCII summary.
##
## The screenshot is the end-to-end proof that the asset theme reaches the live
## board: this tool wires the same AssetGuard + ThemeLoader + set_asset_theme path
## the game screen uses, prints how many chips actually resolved to a texture, and
## names the UI ids the board container itself drew (§20.5/§20.6 geometry).

const SCENE_PATH := "res://src/view/board_view.tscn"
const OUT_DIR := "res://output"
const OUT_PNG := "res://output/board_1080x1920.png"
const TARGET := Vector2i(1080, 1920)
const WARMUP_FRAMES := 6
const MANIFEST_INDEX := "res://data/manifest_index.json"
const SAMPLE_PROJECT := "res://data/sample_project.json"
const DEFAULT_THEME := "themes/default"
const ThemeLoader := preload("res://src/theme/theme_loader.gd")
const AssetGuardScript := preload("res://src/assets/asset_guard.gd")
const BoardView := preload("res://src/view/board_view.gd")

var _frames: int = 0
var _viewport: SubViewport = null
var _board: Control = null
var _done: bool = false
var _theme_name: String = DEFAULT_THEME
var _allow_placeholders: bool = false
var _theme_loader = null
var _project: Dictionary = {}
var _toast_text: String = ""


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_project = _load_json(SAMPLE_PROJECT)
	_theme_loader = _load_theme()
	var packed = load(SCENE_PATH)
	if packed == null:
		print("[shot] FAIL cannot load " + SCENE_PATH)
		_finish(1)
		return

	_viewport = SubViewport.new()
	_viewport.size = TARGET
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_board = packed.instantiate()
	if _board != null and _theme_loader != null:
		# set_asset_theme attaches the chips *and* the board's UI textures;
		# set_chip_icons is the M1 alias, kept as the fallback for older scenes.
		if _board.has_method("set_asset_theme"):
			_board.set_asset_theme(_theme_loader, _project)
		elif _board.has_method("set_chip_icons"):
			_board.set_chip_icons(_theme_loader, _project)
	_viewport.add_child(_board)
	if _board != null and not _toast_text.is_empty() and _board.has_method("show_toast"):
		# --toast=<text>: proves the strip position inside the §20.5 layout. The
		# view clock stays at 0, so the toast is opaque on every warmup frame.
		_board.set_clock(0.0)
		_board.show_toast(_toast_text)
	print("[shot] scene loaded, window=%dx%d viewport=%dx%d" % [
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		TARGET.x, TARGET.y,
	])
	print("[shot] board geometry origin=(%d,%d) size=(%d,%d) cell=%.6fx%.6f" % [
		int(BoardView.BOARD_ORIGIN.x), int(BoardView.BOARD_ORIGIN.y),
		int(BoardView.BOARD_SIZE.x), int(BoardView.BOARD_SIZE.y),
		BoardView.BOARD_SIZE.x / float(BoardView.COLS),
		BoardView.BOARD_SIZE.y / float(BoardView.ROWS),
	])


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--theme="):
			var value := arg.substr(8).strip_edges()
			if not value.is_empty():
				_theme_name = value
		elif arg == "--allow-placeholders":
			_allow_placeholders = true
		elif arg.begins_with("--toast="):
			_toast_text = arg.substr(8).strip_edges()


## Same construction the game screen uses: guard first, then the theme loader that
## asks it about every chip id it maps.
func _load_theme():
	var guard = AssetGuardScript.new()
	if not guard.load_from(MANIFEST_INDEX, _allow_placeholders):
		print("[shot] WARN asset index: " + String(guard.load_error))
	var loader = ThemeLoader.new()
	loader.setup(guard, _allow_placeholders)
	var result: Dictionary = loader.load_theme(_theme_name, _project)
	if not bool(result.get("ok", false)):
		print("[shot] WARN theme rejected: " + str(result.get("errors", [])))
		return loader
	print("[shot] theme %s ok chip_refs=%d" % [_theme_name, loader.chip_refs().size()])
	return loader


func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	_done = true
	_capture()
	return true


func _capture() -> void:
	var image: Image = null
	var source := "subviewport"
	var texture := _viewport.get_texture()
	if texture != null:
		image = texture.get_image()
	if image == null or image.is_empty():
		source = "window"
		image = root.get_texture().get_image()
	if image == null or image.is_empty():
		print("[shot] FAIL empty render target")
		_finish(1)
		return

	var size := image.get_size()
	if size != TARGET:
		var scaled := Image.new()
		scaled.copy_from(image)
		scaled.resize(TARGET.x, TARGET.y, Image.INTERPOLATE_BILINEAR)
		image = scaled
		print("[shot] WARN resized %dx%d -> %dx%d" % [size.x, size.y, TARGET.x, TARGET.y])

	var status := image.save_png(OUT_PNG)
	if status != OK:
		print("[shot] FAIL save_png code=" + str(status))
		_finish(1)
		return

	var summary := "(no summary)"
	if _board != null and _board.has_method("debug_summary"):
		summary = String(_board.call("debug_summary"))
	print("[shot] saved %dx%d source=%s bytes=%d" % [image.get_width(), image.get_height(), source,
			FileAccess.get_file_as_bytes(OUT_PNG).size()])
	print("[shot] board " + summary)
	if _board != null and _board.has_method("chip_icon_count"):
		print("[shot] theme=%s chip_icons resolved=%d of %d items" % [_theme_name,
				int(_board.call("chip_icon_count")), int(_board.call("item_count"))])
	if _board != null and _board.has_method("ui_summary"):
		var ui := String(_board.call("ui_summary"))
		print("[shot] ui " + (ui if not ui.is_empty() else "(none: procedural board)"))
	print("[shot] sample pixels " + _sample(image))
	_finish(0)


func _sample(image: Image) -> String:
	# §20.5 anchors: page corner, top band, container corner, demo cell (3,3),
	# bottom-right container corner at (1031,1729), toast strip centre.
	var points := [
		Vector2i(4, 4), Vector2i(540, 200), Vector2i(60, 480), Vector2i(539, 957),
		Vector2i(1020, 1718), Vector2i(540, 1642),
	]
	var out: Array = []
	for p in points:
		if p.x < image.get_width() and p.y < image.get_height():
			var c := image.get_pixel(p.x, p.y)
			out.append("#%s" % c.to_html(false))
	var distinct := 0
	var seen := {}
	var x := 0
	while x < image.get_width():
		var y := 0
		while y < image.get_height():
			var key := image.get_pixel(x, y).to_rgba32()
			if not seen.has(key):
				seen[key] = true
			y += 17
		x += 19
	distinct = seen.size()
	return "colors=%d %s" % [distinct, " ".join(out)]


func _finish(code: int) -> void:
	print("[shot] exit=" + str(code))
	quit(code)
