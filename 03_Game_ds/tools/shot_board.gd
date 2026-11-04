extends SceneTree
## Renders the static board to a real PNG with a real (non-headless) renderer.
##
##   godot --path . --script res://tools/shot_board.gd
##
## The capture goes through a fixed-size SubViewport instead of the window texture,
## so the PNG is always exactly 1080x1920 no matter how the OS resized the window.
## Writes res://output/board_1080x1920.png and prints an ASCII summary.

const SCENE_PATH := "res://src/view/board_view.tscn"
const OUT_DIR := "res://output"
const OUT_PNG := "res://output/board_1080x1920.png"
const TARGET := Vector2i(1080, 1920)
const WARMUP_FRAMES := 6

var _frames: int = 0
var _viewport: SubViewport = null
var _board: Control = null
var _done: bool = false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
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
	_viewport.add_child(_board)
	print("[shot] scene loaded, window=%dx%d viewport=%dx%d" % [
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		TARGET.x, TARGET.y,
	])


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
	print("[shot] sample pixels " + _sample(image))
	_finish(0)


func _sample(image: Image) -> String:
	var points := [
		Vector2i(4, 4), Vector2i(540, 400), Vector2i(120, 520), Vector2i(890, 1570),
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
