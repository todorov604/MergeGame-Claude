extends SceneTree
## Real-window screenshot for the M0 step 4 screen (never run with --headless:
## the renderer must exist for get_image()).
##
##   godot --path . --script res://tools/shot_game_screen.gd -- --t=6.2
##   godot --path . --script res://tools/shot_game_screen.gd -- --t=6.2 --theme=themes/pet_shop --out=output/game_theme_pet_shop.png
##
## Writes the full 1080x1920 frame plus an order-panel close-up (the panel is
## reparented into its own SubViewport, so the crop is a real render, not a crop
## of a scaled texture). Prints ASCII sizes and the panels' debug summaries.

const SCENE_PATH := "res://src/view/game_screen.tscn"
const OUT_DIR := "res://output"
const FULL_PATH := "res://output/game_1080x1920.png"
const ORDERS_PATH := "res://output/orders_panel.png"
const PAGE := Vector2i(1080, 1920)
const ORDERS_SIZE := Vector2i(1080, 250)
const WARMUP_FRAMES := 6
const SETTLE_FRAMES := 4

var _screen = null
var _viewport: SubViewport = null
var _order_viewport: SubViewport = null
var _out_full: String = FULL_PATH
var _skip_orders: bool = false
var _stage: int = 0
var _frames: int = 0
var _done: bool = false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--out="):
			_out_full = OUT_DIR + "/" + text.substr(6).get_file()
		elif text == "--skip-orders":
			_skip_orders = true

	var packed = load(SCENE_PATH)
	if packed == null:
		print("[shot] FAIL cannot load " + SCENE_PATH)
		_finish(1)
		return

	_viewport = SubViewport.new()
	_viewport.size = PAGE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_screen = packed.instantiate()
	_viewport.add_child(_screen)
	print("[shot] scene loaded window=%dx%d viewport=%dx%d out=%s" % [
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		PAGE.x, PAGE.y, _out_full,
	])


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	match _stage:
		0:
			if _frames >= WARMUP_FRAMES:
				_stage = 1
				_frames = 0
				if not _capture(_viewport, _out_full, PAGE, "frame"):
					_finish(1)
				elif _skip_orders:
					_finish(0)
		1:
			_stage = 2
			_frames = 0
			if not _prepare_orders():
				_finish(0)
		2:
			if _frames >= SETTLE_FRAMES:
				var ok := _capture(_order_viewport, ORDERS_PATH, ORDERS_SIZE, "orders")
				_finish(0 if ok else 1)
	return _done


func _prepare_orders() -> bool:
	if _screen == null or _screen.get("orders") == null:
		return false
	var panel = _screen.get("orders")
	_screen.remove_child(panel)
	_order_viewport = SubViewport.new()
	_order_viewport.size = ORDERS_SIZE
	_order_viewport.disable_3d = true
	_order_viewport.transparent_bg = false
	_order_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_order_viewport)
	_order_viewport.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = Vector2(ORDERS_SIZE)
	panel.queue_redraw()
	return true


func _capture(viewport: SubViewport, path: String, expected: Vector2i, label: String) -> bool:
	var texture := viewport.get_texture()
	var image: Image = null
	if texture != null:
		image = texture.get_image()
	if image == null or image.is_empty():
		print("[shot] FAIL empty render target for " + label)
		return false
	if image.get_size() != expected:
		var scaled := Image.new()
		scaled.copy_from(image)
		scaled.resize(expected.x, expected.y, Image.INTERPOLATE_BILINEAR)
		image = scaled
		print("[shot] WARN %s resized to %dx%d" % [label, expected.x, expected.y])
	var status := image.save_png(path)
	if status != OK:
		print("[shot] FAIL save_png %s code=%d" % [path, status])
		return false
	print("[shot] saved %s %dx%d bytes=%d" % [label, image.get_width(), image.get_height(),
			FileAccess.get_file_as_bytes(path).size()])
	if label == "orders" and _screen != null:
		var panel = _order_viewport.get_child(0) if _order_viewport.get_child_count() > 0 else null
		if panel != null and panel.has_method("debug_summary"):
			print("[shot] panel " + String(panel.call("debug_summary")))
	if _screen != null and _screen.has_method("debug_summary"):
		print("[shot] " + String(_screen.call("debug_summary")))
	return true


func _finish(code: int) -> void:
	_done = true
	print("[shot] exit=" + str(code))
	quit(code)
