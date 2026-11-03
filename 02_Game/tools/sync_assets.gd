extends SceneTree
## 资源同步工具（M0）：按 resource_manifest.json 的 usage 把允许打包的资源复制进 02_Game，
## 并生成 <out>/assets.json 复制记录，供运行时资源守卫使用。
##
## 用法：
##   godot --headless -s res://tools/sync_assets.gd -- [--manifest <path>] [--out <dir>]
##   --manifest  默认 <项目根>/../00_design/resource_manifest.json
##   --out       默认 res://assets
##
## 只有 PLACEHOLDER / PRODUCTION 会被复制；REFERENCE_ONLY / TODO 跳过。

const ManifestDoc = preload("res://core/manifest_doc.gd")

const DEFAULT_OUT := "res://assets"

var _manifest_arg := ""
var _out_arg := ""
var _copied := 0
var _skipped := 0
var _errors := 0


func _initialize() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	_manifest_arg = project_root.path_join("../00_design/resource_manifest.json").simplify_path()
	_out_arg = DEFAULT_OUT
	if not _parse_args():
		quit(1)
		return

	var manifest = ManifestDoc.new()
	if not manifest.load_file(_resolve_project_path(_manifest_arg)):
		_record_error("加载 manifest 失败: %s" % manifest.parse_error)
		quit(1)
		return

	var out_abs := _to_absolute(_resolve_project_path(_out_arg))
	var out_json_dir := _json_out_dir(_out_arg)
	var dir_error := DirAccess.make_dir_recursive_absolute(out_abs)
	if dir_error != OK:
		_record_error("创建输出目录失败(%s): %s" % [error_string(dir_error), out_abs])
		_print_summary()
		quit(1)
		return

	var assets: Array = []
	for resource in manifest.resources:
		if not (resource is Dictionary):
			continue
		var resource_id_value = resource.get("id", "")
		if not (resource_id_value is String):
			continue
		var resource_id: String = resource_id_value
		if resource_id.is_empty():
			continue

		var usage := str(resource.get("usage", ""))
		match usage:
			"REFERENCE_ONLY", "TODO":
				_skipped += 1
			"PLACEHOLDER", "PRODUCTION":
				var asset := _copy_asset(resource, resource_id, usage, out_abs, out_json_dir)
				if not asset.is_empty():
					assets.append(asset)
			_:
				_record_error("未知 usage: %s (id=%s)" % [usage, resource_id])

	assets.sort_custom(_asset_id_less)

	var record := {
		"version": 1,
		"manifest_version": int(manifest.version),
		"manifest_path": _manifest_arg,
		"assets": assets,
	}
	_write_assets_json(out_abs, record)

	_print_summary()
	quit(1 if _errors > 0 else 0)


## 复制单个 PLACEHOLDER / PRODUCTION 资源；失败时记录错误并返回空 Dictionary。
func _copy_asset(resource: Dictionary, resource_id: String, usage: String, out_abs: String, out_json_dir: String) -> Dictionary:
	var source := str(resource.get("file", ""))
	if source.is_empty():
		_record_error("[%s] 源文件为空" % resource_id)
		return {}

	var source_abs := _to_absolute(source)
	if not FileAccess.file_exists(source_abs):
		_record_error("[%s] 源文件不存在: %s" % [resource_id, source_abs])
		return {}

	var ext := source.replace("\\", "/").get_extension()
	if ext.is_empty():
		_record_error("[%s] 无法确定扩展名: %s" % [resource_id, source])
		return {}

	var file_name := "%s.%s" % [resource_id, ext]
	var dest_abs := _join_path(out_abs, file_name)
	var copy_error := DirAccess.copy_absolute(source_abs, dest_abs)
	if copy_error != OK:
		_record_error("[%s] 复制失败(%s): %s -> %s" % [resource_id, error_string(copy_error), source_abs, dest_abs])
		return {}

	var file_for_json := _join_path(out_json_dir, file_name)
	_copied += 1
	print("COPY %s -> %s" % [resource_id, file_for_json])
	return {
		"id": resource_id,
		"usage": usage,
		"license": str(resource.get("license", "")),
		"source": source,
		"file": file_for_json,
	}


func _write_assets_json(out_abs: String, record: Dictionary) -> void:
	var json_path := _join_path(out_abs, "assets.json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		_record_error("写入 assets.json 失败(%s): %s" % [error_string(FileAccess.get_open_error()), json_path])
		return
	# sort_keys=false：保持上面固定好的键顺序（JSON.stringify 默认按字母排序）。
	file.store_string(JSON.stringify(record, "\t", false))
	file.close()


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := args[i]
		match arg:
			"--manifest":
				if i + 1 >= args.size():
					_record_error("--manifest 缺少参数值")
					return false
				_manifest_arg = args[i + 1]
				i += 2
			"--out":
				if i + 1 >= args.size():
					_record_error("--out 缺少参数值")
					return false
				_out_arg = args[i + 1]
				i += 2
			_:
				_record_error("未知参数: %s" % arg)
				return false
	return true


func _asset_id_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a["id"]) < str(b["id"])


## res:// 原样；绝对路径原样；其它相对 02_Game 工程根解析。
func _resolve_project_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


## 转成可用于 FileAccess / DirAccess 的绝对路径（res:// 先 globalize）。
func _to_absolute(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


## assets.json 里 file 字段的目录写法：res:// 与绝对路径用原始写法，相对路径补成 res:// 形式。
func _json_out_dir(out_arg: String) -> String:
	if out_arg.begins_with("res://") or out_arg.is_absolute_path():
		return out_arg
	return "res://" + out_arg.replace("\\", "/").trim_prefix("/")


func _join_path(base: String, name: String) -> String:
	if base.ends_with("/") or base.ends_with("\\"):
		return base + name
	return base + "/" + name


func _record_error(message: String) -> void:
	_errors += 1
	print("ERROR: %s" % message)


func _print_summary() -> void:
	print("copied: %d, skipped: %d, errors: %d" % [_copied, _skipped, _errors])
