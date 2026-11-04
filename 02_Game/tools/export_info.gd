extends SceneTree

## 出片信息（M0 第 6 步）：校验项目并输出分辨率/帧率/时长/帧数，供 render.sh 使用。
## 用法：godot --headless --path 02_Game -s res://tools/export_info.gd -- [--project <path>] [--manifest <path>] [--allow-placeholders]

const ProjectDoc := preload("res://core/project_doc.gd")
const ManifestDoc := preload("res://core/manifest_doc.gd")
const EventEvaluator := preload("res://core/event_evaluator.gd")
const Validator := preload("res://core/validator.gd")

const DEFAULT_PROJECT := "res://data/projects/sample_30s.json"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var project_path := DEFAULT_PROJECT
	var manifest_path := "res://data/manifest_index.json"
	var allow_placeholders := false
	var i := 0
	while i < args.size():
		var arg := String(args[i])
		if arg == "--project" and i + 1 < args.size():
			i += 1
			project_path = String(args[i])
		elif arg == "--manifest" and i + 1 < args.size():
			i += 1
			manifest_path = String(args[i])
		elif arg == "--allow-placeholders":
			allow_placeholders = true
		i += 1

	var resolved := _resolve_path(project_path)
	var doc := ProjectDoc.new()
	if not doc.load_file(resolved):
		_fail("项目加载失败: %s" % doc.parse_error)
		return

	var manifest := ManifestDoc.new()
	if not manifest.load_file(_resolve_path(manifest_path)):
		_fail("manifest 加载失败: %s" % manifest.parse_error)
		return

	var validator := Validator.new()
	validator.validate_project(doc, manifest, allow_placeholders)
	if not validator.errors.is_empty():
		for error_v in validator.errors:
			var error: Dictionary = error_v
			print("ERROR %s: %s" % [str(error.get("path", "")), str(error.get("message", ""))])
		_fail("项目校验失败")
		return

	var evaluator := EventEvaluator.new()
	var timeline_v: Variant = doc.data.get("timeline", [])
	var timeline: Array = []
	if typeof(timeline_v) == TYPE_ARRAY:
		timeline = timeline_v
	if not evaluator.evaluate(timeline):
		for error_v in evaluator.errors:
			var error: Dictionary = error_v
			print("ERROR timeline[%d]: %s" % [int(error.get("index", -1)), str(error.get("message", ""))])
		_fail("时间轴求值失败")
		return

	var meta_v: Variant = doc.data.get("meta", {})
	var meta: Dictionary = {}
	if typeof(meta_v) == TYPE_DICTIONARY:
		meta = meta_v
	var resolution_v: Variant = meta.get("resolution")
	var width := 0
	var height := 0
	if typeof(resolution_v) == TYPE_ARRAY and (resolution_v as Array).size() == 2:
		width = _int_value((resolution_v as Array)[0])
		height = _int_value((resolution_v as Array)[1])
	var fps := _int_value(meta.get("fps"))
	if width <= 0 or height <= 0 or fps <= 0:
		_fail("meta.resolution/fps 非法")
		return

	var duration := evaluator.end_time()
	if duration <= 0.0:
		_fail("时间轴时长为 0")
		return
	var frames := int(round(duration * float(fps)))

	print("ok=true")
	print("project=%s" % resolved)
	print("width=%d" % width)
	print("height=%d" % height)
	print("fps=%d" % fps)
	print("duration=%.3f" % duration)
	print("frames=%d" % frames)
	quit(0)


func _fail(message: String) -> void:
	print("ok=false")
	print("error=%s" % message)
	quit(1)


func _resolve_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


static func _int_value(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return 0
