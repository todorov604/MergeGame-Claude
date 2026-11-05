extends SceneTree
## 资源同步工具（M0/M1）：按 resource_manifest.json 的 usage 把允许打包的资源复制进 02_Game，
## 生成 <out>/assets.json 复制记录，并生成内嵌 manifest 快照 <index>（默认 res://data/manifest_index.json），
## 供运行时资源守卫 / 校验 / 测试在无 00_design 的干净副本中使用。
##
## 用法：
##   godot --headless -s res://tools/sync_assets.gd -- --manifest <path> [--set <json>] [--out <dir>] [--index <path>]
##   --manifest  必填：源 manifest（开发期指向 ../00_design/resource_manifest.json）
##   --set       可选：资产集合 JSON（{"ids": [...]}）；给出时只复制集合内的 PLACEHOLDER/PRODUCTION，
##               其余资源仍写入快照（file 保留仓库相对溯源路径），实现「配置一套资产 → 出一条片」。
##   --local     可选：本地登记素材 JSON（未进 00_design manifest 的 PSD 切片等）；
##               只复制并写入 assets.json（local=true），不写入 manifest 快照。
##   --out       默认 res://assets
##   --index     默认 res://data/manifest_index.json
##
## 只有 PLACEHOLDER / PRODUCTION 会被复制；REFERENCE_ONLY / TODO 不打包。
## 快照中已复制资源的 file 指向工程内 res://assets/<id>.<ext>；
## 未复制资源（含 REFERENCE_ONLY/TODO）的 file 保留仓库相对溯源路径（正斜杠、无盘符）。


const ManifestDoc = preload("res://core/manifest_doc.gd")
const Validator = preload("res://core/validator.gd")

const DEFAULT_OUT := "res://assets"
const DEFAULT_INDEX := "res://data/manifest_index.json"

var _manifest_arg := ""
var _set_arg := ""
var _local_arg := ""
var _out_arg := ""
var _index_arg := ""
var _manifest_abs := ""
var _set_provided := false
var _set_ids: Dictionary = {}
var _set_order: Array = []
var _set_seen: Dictionary = {}
var _local_entries: Array = []
var _copied := 0
var _local_copied := 0
var _skipped := 0
var _errors := 0


func _initialize() -> void:
	_out_arg = DEFAULT_OUT
	_index_arg = DEFAULT_INDEX
	if not _parse_args():
		quit(1)
		return
	if _manifest_arg.is_empty():
		_record_error("缺少必填参数 --manifest（开发期指向源 manifest，如 ../00_design/resource_manifest.json）")
		quit(1)
		return

	_manifest_abs = _resolve_project_path(_manifest_arg)
	var manifest = ManifestDoc.new()
	if not manifest.load_file(_manifest_abs):
		_record_error("加载 manifest 失败: %s" % manifest.parse_error)
		quit(1)
		return

	if not _set_arg.is_empty():
		_set_provided = true
		if not _load_asset_set(_set_arg):
			quit(1)
			return

	if not _local_arg.is_empty():
		if not _load_local_assets(_local_arg, manifest):
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
	var index_resources: Array = []
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
		var in_set := _set_ids.has(resource_id)
		var packaged := (usage == "PLACEHOLDER" or usage == "PRODUCTION") and (not _set_provided or in_set)
		if in_set:
			_set_seen[resource_id] = true
			if usage != "PLACEHOLDER" and usage != "PRODUCTION":
				_record_error("资产集合包含不允许打包的 usage=%s: %s" % [usage, resource_id])
		index_resources.append(_index_entry(resource, resource_id, usage, out_json_dir, packaged))
		match usage:
			"REFERENCE_ONLY", "TODO":
				_skipped += 1
			"PLACEHOLDER", "PRODUCTION":
				if packaged:
					var asset := _copy_asset(resource, resource_id, usage, out_abs, out_json_dir)
					if not asset.is_empty():
						assets.append(asset)
				else:
					_skipped += 1
			_:
				_record_error("未知 usage: %s (id=%s)" % [usage, resource_id])

	if _set_provided:
		for set_id_v in _set_order:
			var set_id := String(set_id_v)
			if not _set_seen.has(set_id):
				_record_error("资产集合资源未在 manifest 中定义: %s" % set_id)

	for local_entry_v in _local_entries:
		var local_entry: Dictionary = local_entry_v
		var local_asset := _copy_local_asset(local_entry, out_abs, out_json_dir)
		if not local_asset.is_empty():
			assets.append(local_asset)

	assets.sort_custom(_asset_id_less)

	var record := {
		"version": 1,
		"manifest_version": int(manifest.version),
		"manifest_path": _index_arg,
		"assets": assets,
	}
	_write_assets_json(out_abs, record)

	var index_record := {
		"version": int(manifest.version),
		"resources": index_resources,
	}
	_write_index_json(index_record)

	_print_summary()
	quit(1 if _errors > 0 else 0)


## 复制单个 PLACEHOLDER / PRODUCTION 资源；失败时记录错误并返回空 Dictionary。
func _copy_asset(resource: Dictionary, resource_id: String, usage: String, out_abs: String, out_json_dir: String) -> Dictionary:
	var source := str(resource.get("file", ""))
	if source.is_empty():
		_record_error("[%s] 源文件为空" % resource_id)
		return {}

	var source_abs := _resolve_local_source(source)
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
		"source": _repo_relative(source),
		"file": file_for_json,
	}


## 内嵌快照的单条资源：保留 validator 要求的 MANIFEST_FIELDS，并把 file 改写成工程内路径或溯源路径。
func _index_entry(resource: Dictionary, resource_id: String, usage: String, out_json_dir: String, packaged: bool) -> Dictionary:
	var entry: Dictionary = {}
	for field_v in Validator.MANIFEST_FIELDS:
		var field := String(field_v)
		if resource.has(field):
			entry[field] = resource[field]
	entry["file"] = _index_file(resource, resource_id, usage, out_json_dir, packaged)
	return entry


func _index_file(resource: Dictionary, resource_id: String, usage: String, out_json_dir: String, packaged: bool) -> String:
	var source := str(resource.get("file", ""))
	if packaged:
		var ext := source.replace("\\", "/").get_extension()
		if ext.is_empty():
			return ""
		return _join_path(out_json_dir, "%s.%s" % [resource_id, ext])
	return _repo_relative(source)


## 把 manifest 中的绝对来源路径转换为仓库相对路径（正斜杠、无盘符、无 .claude/worktrees）。
## 仓库根通过 manifest 位置（<repo>/00_design/...）与来源文件祖先目录探测。
func _repo_relative(source: String) -> String:
	if source.is_empty():
		return ""
	var normalized := source.replace("\\", "/")
	if normalized.begins_with("res://") or not normalized.is_absolute_path():
		return _strip_worktree_segment(normalized)

	var roots: Array = []
	var manifest_abs := _to_absolute(_manifest_abs).replace("\\", "/")
	roots.append(manifest_abs.get_base_dir().get_base_dir())
	var probe := normalized.get_base_dir()
	while not probe.is_empty() and probe != "/" and not probe.ends_with(":"):
		if DirAccess.dir_exists_absolute(probe + "/00_design"):
			roots.append(probe)
			break
		var parent := probe.get_base_dir()
		if parent == probe:
			break
		probe = parent

	for root_v in roots:
		var root := String(root_v).trim_suffix("/")
		if root.is_empty():
			continue
		if normalized.to_lower().begins_with(root.to_lower() + "/"):
			return _strip_worktree_segment(normalized.substr(root.length() + 1))

	# 兜底：路径含 .claude/worktrees/<name>/ 时，从仓库内容起点截取。
	var marker := "/.claude/worktrees/"
	var marker_index := normalized.find(marker)
	if marker_index != -1:
		var rest := normalized.substr(marker_index + marker.length())
		var slash := rest.find("/")
		if slash != -1:
			return rest.substr(slash + 1)
	return normalized


## 去掉相对路径开头的 .claude/worktrees/<worktree-name>/ 片段。
func _strip_worktree_segment(rel: String) -> String:
	var prefix := ".claude/worktrees/"
	if rel.begins_with(prefix):
		var rest := rel.substr(prefix.length())
		var slash := rest.find("/")
		if slash != -1:
			return rest.substr(slash + 1)
	return rel


func _write_assets_json(out_abs: String, record: Dictionary) -> void:
	var json_path := _join_path(out_abs, "assets.json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		_record_error("写入 assets.json 失败(%s): %s" % [error_string(FileAccess.get_open_error()), json_path])
		return
	# sort_keys=false：保持上面固定好的键顺序（JSON.stringify 默认按字母排序）。
	file.store_string(JSON.stringify(record, "\t", false))
	file.close()


func _write_index_json(record: Dictionary) -> void:
	var json_path := _to_absolute(_resolve_project_path(_index_arg))
	var dir_error := DirAccess.make_dir_recursive_absolute(json_path.get_base_dir())
	if dir_error != OK:
		_record_error("创建快照目录失败(%s): %s" % [error_string(dir_error), json_path.get_base_dir()])
		return
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		_record_error("写入 manifest 快照失败(%s): %s" % [error_string(FileAccess.get_open_error()), json_path])
		return
	file.store_string(JSON.stringify(record, "\t", false))
	file.close()
	print("INDEX %s" % _index_arg)


## 读取本地登记素材 JSON：{"assets": [{id, usage, license, source, note}]}。
func _load_local_assets(path_arg: String, manifest) -> bool:
	var path := _resolve_project_path(path_arg)
	if not FileAccess.file_exists(path):
		_record_error("本地登记素材文件不存在: %s" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_record_error("读取本地登记素材失败(%s): %s" % [error_string(FileAccess.get_open_error()), path])
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_error("本地登记素材 JSON 根节点不是 Dictionary: %s" % path)
		return false
	var entries_v: Variant = (parsed as Dictionary).get("assets")
	if typeof(entries_v) != TYPE_ARRAY or (entries_v as Array).is_empty():
		_record_error("本地登记素材 assets 必须是非空数组: %s" % path)
		return false
	var seen: Dictionary = {}
	for entry_v in (entries_v as Array):
		if typeof(entry_v) != TYPE_DICTIONARY:
			_record_error("本地登记素材条目必须是对象: %s" % path)
			return false
		var entry: Dictionary = entry_v
		var id_v: Variant = entry.get("id")
		if typeof(id_v) != TYPE_STRING or String(id_v).is_empty():
			_record_error("本地登记素材 id 必须是非空字符串: %s" % path)
			return false
		var id := String(id_v)
		if seen.has(id):
			_record_error("本地登记素材 id 重复: %s" % id)
			return false
		seen[id] = true
		if manifest.has_resource(id):
			_record_error("本地登记素材 id 与 manifest 冲突: %s" % id)
			return false
		if str(entry.get("usage", "")) != "PRODUCTION":
			_record_error("本地登记素材只允许 PRODUCTION: %s" % id)
			return false
		if not (entry.get("license") is String) or String(entry.get("license", "")).is_empty():
			_record_error("本地登记素材 license 不能为空: %s" % id)
			return false
		var source_v: Variant = entry.get("source")
		if typeof(source_v) != TYPE_STRING or String(source_v).is_empty():
			_record_error("本地登记素材 source 不能为空: %s" % id)
			return false
		_local_entries.append(entry)
	return true


## 复制一条本地登记素材；source 优先按仓库根解析（01_icon/、00_design/），失败再按工程根解析。
func _copy_local_asset(entry: Dictionary, out_abs: String, out_json_dir: String) -> Dictionary:
	var local_id := str(entry.get("id", ""))
	var source := str(entry.get("source", ""))
	var source_abs := _resolve_local_source(source)
	if not FileAccess.file_exists(source_abs):
		_record_error("[%s] 本地素材源文件不存在: %s" % [local_id, source_abs])
		return {}
	var ext := source.replace("\\", "/").get_extension()
	if ext.is_empty():
		_record_error("[%s] 无法确定本地素材扩展名: %s" % [local_id, source])
		return {}
	var file_name := "%s.%s" % [local_id, ext]
	var dest_abs := _join_path(out_abs, file_name)
	var copy_error := DirAccess.copy_absolute(source_abs, dest_abs)
	if copy_error != OK:
		_record_error("[%s] 本地素材复制失败(%s): %s -> %s" % [local_id, error_string(copy_error), source_abs, dest_abs])
		return {}
	var file_for_json := _join_path(out_json_dir, file_name)
	_local_copied += 1
	print("COPY-LOCAL %s -> %s" % [local_id, file_for_json])
	var asset := {
		"id": local_id,
		"usage": "PRODUCTION",
		"license": str(entry.get("license", "")),
		"source": _repo_relative(source),
		"file": file_for_json,
		"local": true,
	}
	if entry.has("note"):
		asset["note"] = str(entry.get("note", ""))
	return asset


func _resolve_local_source(source: String) -> String:
	if source.begins_with("res://") or source.is_absolute_path():
		return _to_absolute(source)
	var repo_candidate := _repo_root().path_join(source).simplify_path()
	if FileAccess.file_exists(repo_candidate):
		return repo_candidate
	return _to_absolute(_resolve_project_path(source))


## 仓库根：manifest 位于 <repo>/00_design/...，取其上两级。
func _repo_root() -> String:
	if _manifest_abs.is_empty():
		return ProjectSettings.globalize_path("res://").simplify_path()
	var manifest_abs := _to_absolute(_manifest_abs).replace("\\", "/")
	return manifest_abs.get_base_dir().get_base_dir()


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
			"--set":
				if i + 1 >= args.size():
					_record_error("--set 缺少参数值")
					return false
				_set_arg = args[i + 1]
				i += 2
			"--local":
				if i + 1 >= args.size():
					_record_error("--local 缺少参数值")
					return false
				_local_arg = args[i + 1]
				i += 2
			"--out":
				if i + 1 >= args.size():
					_record_error("--out 缺少参数值")
					return false
				_out_arg = args[i + 1]
				i += 2
			"--index":
				if i + 1 >= args.size():
					_record_error("--index 缺少参数值")
					return false
				_index_arg = args[i + 1]
				i += 2
			_:
				_record_error("未知参数: %s" % arg)
				return false
	return true


## 读取资产集合 JSON：{"version": 1, "ids": ["..."]}。
func _load_asset_set(path_arg: String) -> bool:
	var path := _resolve_project_path(path_arg)
	if not FileAccess.file_exists(path):
		_record_error("资产集合文件不存在: %s" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_record_error("读取资产集合失败(%s): %s" % [error_string(FileAccess.get_open_error()), path])
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_error("资产集合 JSON 根节点不是 Dictionary: %s" % path)
		return false
	var ids_v: Variant = (parsed as Dictionary).get("ids")
	if typeof(ids_v) != TYPE_ARRAY or (ids_v as Array).is_empty():
		_record_error("资产集合 ids 必须是非空数组: %s" % path)
		return false
	for id_v in ids_v:
		if typeof(id_v) != TYPE_STRING or String(id_v).is_empty():
			_record_error("资产集合 ids 必须是非空字符串: %s" % path)
			return false
		var id := String(id_v)
		if _set_ids.has(id):
			_record_error("资产集合 ids 重复: %s" % id)
			return false
		_set_ids[id] = true
		_set_order.append(id)
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
	var set_note := ""
	if _set_provided:
		set_note += ", set=%d" % _set_ids.size()
	if not _local_arg.is_empty():
		set_note += ", local=%d" % _local_copied
	print("copied: %d, skipped: %d, errors: %d%s" % [_copied, _skipped, _errors, set_note])
