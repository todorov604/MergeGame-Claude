extends RefCounted
## 时间轴编辑数据模型（M0 第 1 周第 5 步）：纯逻辑，不含 UI。
## 职责：加载项目数据、事件增删改移、整项目校验、撤销/重做、写出草稿。
## 规则来源：00_design/M0-冻结规格.md §2（数据模型 v2）、§3（事件模型 v2）、§5.2（撤销/重做至少 50 步）。
## 所有编辑都先改“候选副本”，跑完整项目校验通过后才提交并记入 history。

const ProjectDoc := preload("res://core/project_doc.gd")
const Validator := preload("res://core/validator.gd")
const HISTORY_LIMIT := 50          # 可撤销步数（history 保留 HISTORY_LIMIT+1 份快照）

var project_data: Dictionary = {}
var source_path := ""
var history: Array = []            # 每项是 project_data 的深拷贝
var history_index := -1
var last_errors: Array = []
var last_warnings: Array = []


# ---------------------------------------------------------------------------
# 加载与查询
# ---------------------------------------------------------------------------

func load_file(path: String) -> bool:
	var doc := ProjectDoc.new()
	if not doc.load_file(path):
		# 加载失败不改动现有文档，只刷新错误（Validator 原生 {path, message} 格式）。
		last_errors = [{"path": "<project>", "message": doc.parse_error}]
		last_warnings = []
		return false
	project_data = doc.data.duplicate(true)
	source_path = path
	# 初始快照也计入 history：不可 undo 到打开之前。
	history = [project_data.duplicate(true)]
	history_index = 0
	validate()
	return true


## 从内存字典恢复项目（自动保存草稿/异常恢复用）：替换文档并重置历史。
## 不做整项目校验门禁：草稿即使校验有错也保留，错误只刷新到 last_errors/last_warnings。
func load_from_dict(data: Dictionary, source_path_arg := "<recovered>") -> bool:
	project_data = data.duplicate(true)
	source_path = source_path_arg
	history = [project_data.duplicate(true)]
	history_index = 0
	validate()
	return true


func timeline() -> Array:
	var value: Variant = project_data.get("timeline")
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func event_count() -> int:
	var value: Variant = project_data.get("timeline")
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).size()
	return 0


func get_event(index: int) -> Dictionary:
	var entries := timeline()
	if index < 0 or index >= entries.size():
		return {}
	var value: Variant = entries[index]
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


## 生成当前 timeline 中第一个未占用的 `%s%d` 事件 id：
## 从 event_count()+1 起递增（删过中间事件时 count 变小，也不会与现有 id 冲突）。
func next_event_id(prefix := "e") -> String:
	var used: Dictionary = {}
	for entry_v in timeline():
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var id_v: Variant = (entry_v as Dictionary).get("id")
		if typeof(id_v) == TYPE_STRING:
			used[String(id_v)] = true
	var n := event_count() + 1
	var candidate := "%s%d" % [prefix, n]
	while used.has(candidate):
		n += 1
		candidate = "%s%d" % [prefix, n]
	return candidate


# ---------------------------------------------------------------------------
# 编辑（候选副本 -> 整项目校验 -> 提交并记录历史）
# ---------------------------------------------------------------------------

func add_event(event: Dictionary) -> bool:
	var candidate := project_data.duplicate(true)
	var entries: Array = []
	var entries_v: Variant = candidate.get("timeline")
	if typeof(entries_v) == TYPE_ARRAY:
		entries = entries_v
	else:
		# 缺 timeline / 类型不对时从空数组开始，提交仍由整项目校验把关。
		candidate["timeline"] = entries
	entries.append(event.duplicate(true))
	return _commit(candidate)


func update_event(index: int, event: Dictionary) -> bool:
	var candidate := project_data.duplicate(true)
	var entries_v: Variant = candidate.get("timeline")
	if typeof(entries_v) != TYPE_ARRAY:
		return false
	var entries: Array = entries_v
	if index < 0 or index >= entries.size():
		return false
	entries[index] = event.duplicate(true)
	return _commit(candidate)


func delete_event(index: int) -> bool:
	var candidate := project_data.duplicate(true)
	var entries_v: Variant = candidate.get("timeline")
	if typeof(entries_v) != TYPE_ARRAY:
		return false
	var entries: Array = entries_v
	if index < 0 or index >= entries.size():
		return false
	entries.remove_at(index)
	return _commit(candidate)


func move_event(index: int, delta: int) -> bool:
	# delta 仅允许 ±1：与相邻事件交换。
	if delta != 1 and delta != -1:
		return false
	var candidate := project_data.duplicate(true)
	var entries_v: Variant = candidate.get("timeline")
	if typeof(entries_v) != TYPE_ARRAY:
		return false
	var entries: Array = entries_v
	var target := index + delta
	if index < 0 or index >= entries.size() or target < 0 or target >= entries.size():
		return false
	var moved: Variant = entries[index]
	entries[index] = entries[target]
	entries[target] = moved
	return _commit(candidate)


# ---------------------------------------------------------------------------
# 撤销 / 重做
# ---------------------------------------------------------------------------

func undo() -> bool:
	if not can_undo():
		return false
	history_index -= 1
	var snapshot: Dictionary = history[history_index]
	project_data = snapshot.duplicate(true)
	validate()
	return true


func redo() -> bool:
	if not can_redo():
		return false
	history_index += 1
	var snapshot: Dictionary = history[history_index]
	project_data = snapshot.duplicate(true)
	validate()
	return true


func can_undo() -> bool:
	return history_index > 0


func can_redo() -> bool:
	return history_index >= 0 and history_index < history.size() - 1


# ---------------------------------------------------------------------------
# 校验 / 保存
# ---------------------------------------------------------------------------

func validate() -> Dictionary:
	var result := _check_project(project_data)
	last_errors = result["errors"]
	last_warnings = result["warnings"]
	return result


func save_draft(path := "user://timeline_draft.json") -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_errors = [{"path": path, "message": "无法写入草稿: %s" % error_string(FileAccess.get_open_error())}]
		last_warnings = []
		return false
	file.store_string(to_json_text())
	file.close()
	return true


func to_json_text() -> String:
	return JSON.stringify(project_data, "\t", false)


# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------

## 对候选完整项目跑 Validator；errors 为原生 {path, message} 格式。
func _check_project(data: Dictionary) -> Dictionary:
	var doc := ProjectDoc.new()
	doc.from_dict(data.duplicate(true), source_path)
	var validator := Validator.new()
	validator.validate_project(doc, null, true)
	return {
		"ok": validator.errors.is_empty(),
		"errors": validator.errors,
		"warnings": validator.warnings,
	}


## 校验通过才提交：替换文档、丢弃 redo 分支、追加快照。
func _commit(candidate: Dictionary) -> bool:
	var result := _check_project(candidate)
	if not bool(result["ok"]):
		last_errors = result["errors"]
		last_warnings = result["warnings"]
		return false
	project_data = candidate
	last_errors = []
	last_warnings = result["warnings"]
	_push_history()
	return true


func _push_history() -> void:
	# 丢弃 history_index 之后的 redo 分支。
	if history_index < history.size() - 1:
		history.resize(history_index + 1)
	history.append(project_data.duplicate(true))
	# 快照最多 HISTORY_LIMIT+1 份 => 可撤销 HISTORY_LIMIT 步。
	while history.size() > HISTORY_LIMIT + 1:
		history.pop_front()
		history_index -= 1
	history_index = history.size() - 1
