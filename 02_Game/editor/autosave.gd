extends RefCounted
## 时间轴项目自动保存与异常恢复（M0 第 8 步）。
## 职责：把当前项目数据连同来源路径写入用户目录下的自动保存草稿，
## 并在启动时检测/读取草稿用于恢复。仅编辑器侧使用，不参与 sim/出片路径。

const DEFAULT_PATH := "user://timeline_autosave.json"

var path := DEFAULT_PATH
var last_error := ""


func setup(path_arg := DEFAULT_PATH) -> void:
	path = path_arg
	last_error = ""


func save(project_data: Dictionary, source_path: String) -> bool:
	last_error = ""
	var payload := {
		"version": 1,
		"source": source_path,
		"saved_at": int(Time.get_unix_time_from_system()),
		"project": project_data,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入自动保存草稿(%s): %s" % [error_string(FileAccess.get_open_error()), path]
		return false
	file.store_string(JSON.stringify(payload, "\t", false))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "写入自动保存草稿失败(%s): %s" % [error_string(write_error), path]
		return false
	return true


func load_draft() -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		return {}

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		last_error = "读取自动保存草稿失败(%s): %s" % [error_string(FileAccess.get_open_error()), path]
		return {}

	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = "自动保存草稿 JSON 非法: %s（%s）" % [path, json.get_error_message()]
		return {}
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		last_error = "自动保存草稿根节点不是 Dictionary: %s" % path
		return {}
	var root_dict: Dictionary = root

	var project_v: Variant = root_dict.get("project")
	if typeof(project_v) != TYPE_DICTIONARY:
		last_error = "自动保存草稿缺少 project 或类型不是 Dictionary: %s" % path
		return {}
	var project: Dictionary = project_v

	var source := ""
	var source_v: Variant = root_dict.get("source")
	if typeof(source_v) == TYPE_STRING:
		source = source_v

	var saved_at := 0
	var saved_at_v: Variant = root_dict.get("saved_at")
	if typeof(saved_at_v) == TYPE_INT or typeof(saved_at_v) == TYPE_FLOAT:
		saved_at = int(saved_at_v)

	return {"source": source, "saved_at": saved_at, "project": project}


func has_draft() -> bool:
	return not load_draft().is_empty()


func clear() -> bool:
	last_error = ""
	if not FileAccess.file_exists(path):
		return true
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		last_error = "删除自动保存草稿失败(%s): %s" % [error_string(err), path]
		return false
	return true


func draft_path() -> String:
	return path
