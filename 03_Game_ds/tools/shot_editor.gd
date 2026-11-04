extends SceneTree
## Small screenshot harness for the timeline editor page (real window, real
## renderer). Proves the code-built UI actually instantiates and draws.
##
##   godot --path . --script res://tools/shot_editor.gd
##
## Writes res://output/editor_1080x1920.png and prints an ASCII summary.

const SCENE_PATH := "res://src/editor/timeline_editor.tscn"
const OUT_DIR := "res://output"
const OUT_PNG := "res://output/editor_1080x1920.png"
const OUT_PNG_ERR := "res://output/editor_errors_1080x1920.png"
const TARGET := Vector2i(1080, 1920)
const WARMUP_FRAMES := 8

var _frames: int = 0
var _viewport: SubViewport = null
var _editor: Control = null
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

	_editor = packed.instantiate()
	_viewport.add_child(_editor)
	print("[shot] editor instantiated size=%s" % str(_editor.size))


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames == 2 and OS.get_cmdline_user_args().has("--demo-errors"):
		# inject a forbidden `wait` event and let the validator catch it
		var added: Dictionary = _editor.call("add_event", "sim", "wait", 7.0, {}, {"allow_unregistered": true})
		var v: Dictionary = _editor.call("validate_now")
		var jumped: Dictionary = _editor.call("locate_error", 0)
		print("[shot] demo-errors id=%s ok=%s errors=%d jump=%s" % [str(added.get("id", "")), str(v.get("ok", false)), int(v.get("errors", 0)), str(jumped.get("ok", false))])
	if _frames < WARMUP_FRAMES:
		return false
	_done = true
	_capture()
	return true


func _capture() -> void:
	var image: Image = null
	var texture := _viewport.get_texture()
	if texture != null:
		image = texture.get_image()
	if image == null or image.is_empty():
		print("[shot] FAIL empty render target")
		_finish(1)
		return
	if image.get_size() != TARGET:
		image.resize(TARGET.x, TARGET.y, Image.INTERPOLATE_BILINEAR)
	var out := OUT_PNG_ERR if OS.get_cmdline_user_args().has("--demo-errors") else OUT_PNG
	if image.save_png(out) != OK:
		print("[shot] FAIL save_png")
		_finish(1)
		return
	print("[shot] saved %dx%d bytes=%d" % [image.get_width(), image.get_height(),
			FileAccess.get_file_as_bytes(out).size()])
	if _editor != null and _editor.has_method("status"):
		print("[shot] editor status " + str(_editor.call("status")))
	_finish(0)


func _finish(code: int) -> void:
	print("[shot] exit=" + str(code))
	quit(code)
