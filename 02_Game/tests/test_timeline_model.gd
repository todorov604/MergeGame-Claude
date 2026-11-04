extends RefCounted

## 第 5 步验收：TimelineModel（加载 / 编辑 / 校验 / 撤销重做 / 草稿保存）。

const TimelineModel = preload("res://editor/timeline_model.gd")
const ProjectDoc = preload("res://core/project_doc.gd")

const SAMPLE_PATH := "res://data/projects/sample_30s.json"
const DRAFT_PATH := "user://test_timeline_draft.json"


func run(r) -> void:
	var model = TimelineModel.new()
	_test_load(r, model)
	_test_update_undo_redo(r, model)
	_test_invalid_event(r, model)
	_test_add_delete(r, model)
	_test_history_limit(r, model)
	_test_move_event(r, model)
	_test_save_draft(r, model)
	_test_next_event_id(r)
	_test_load_from_dict(r)
	_test_load_from_dict_edit_undo(r)


# ---------------------------------------------------------------- load / validate

func _test_load(r, model) -> void:
	r.check(model.load_file(SAMPLE_PATH), "样例项目应能加载: " + _errors_text(model.last_errors))
	r.eq(model.event_count(), 11, "样例时间轴事件数应为 11")
	r.eq(model.timeline().size(), 11, "timeline() 长度应为 11")
	r.eq(str(model.get_event(0).get("id", "")), "e1", "0 号事件应为 e1")
	r.check(not model.can_undo(), "加载后不应可撤销")
	r.check(not model.can_redo(), "加载后不应可重做")

	var report: Dictionary = model.validate()
	r.check(bool(report.get("ok", false)), "样例时间轴应通过校验: " + _errors_text(report.get("errors", [])))
	r.eq(_array_size(report.get("errors", [])), 0, "样例时间轴校验错误数应为 0")


# ---------------------------------------------------------------- update / undo / redo

func _test_update_undo_redo(r, model) -> void:
	var edited: Dictionary = model.get_event(0).duplicate(true)
	edited["duration"] = 9.0
	r.check(model.update_event(0, edited), "update_event 应成功")
	r.check(is_equal_approx(float(model.get_event(0).get("duration", 0.0)), 9.0), "更新后 duration 应为 9.0")
	r.check(model.can_undo(), "更新后应可撤销")

	r.check(model.undo(), "undo 应成功")
	var undone: Dictionary = model.get_event(0)
	# 样例 e1 原本没有 duration 字段（3.0 是 at），撤销应恢复原始事件。
	r.eq(str(undone.get("id", "")), "e1", "undo 后 0 号事件仍应为 e1")
	r.check(is_equal_approx(float(undone.get("at", -1.0)), 3.0), "undo 后 at 应回到 3.0")
	r.check(not is_equal_approx(float(undone.get("duration", 0.0)), 9.0), "undo 后 duration 不应再是 9.0")

	r.check(model.can_redo(), "undo 后应可重做")
	r.check(model.redo(), "redo 应成功")
	r.check(is_equal_approx(float(model.get_event(0).get("duration", 0.0)), 9.0), "redo 后 duration 应恢复为 9.0")


# ---------------------------------------------------------------- invalid event

func _test_invalid_event(r, model) -> void:
	var before: int = model.event_count()
	var bad := {"id": "bad", "channel": "sim", "type": "wait", "at": 1.0, "payload": {}}
	r.check(not model.add_event(bad), "wait 事件应被拒绝")
	r.check(_array_size(model.last_errors) > 0, "非法事件的 last_errors 应非空")
	r.eq(model.event_count(), before, "非法事件不应改变事件数")


# ---------------------------------------------------------------- add / delete

func _test_add_delete(r, model) -> void:
	var event := {"id": "e_test", "channel": "sim", "type": "tap", "at": 31.0, "payload": {}}
	r.check(model.add_event(event), "合法事件应可新增: " + _errors_text(model.last_errors))
	r.eq(model.event_count(), 12, "新增后事件数应为 12")
	var last_index: int = model.event_count() - 1
	r.eq(str(model.get_event(last_index).get("id", "")), "e_test", "新增事件应位于末尾")
	r.check(model.delete_event(last_index), "删除末尾事件应成功")
	r.eq(model.event_count(), 11, "删除后事件数应回到 11")


# ---------------------------------------------------------------- history limit

func _test_history_limit(r, model) -> void:
	# 先撤销所有现存历史，回到加载初始状态。
	var drained := 0
	while model.can_undo() and drained < 500:
		if not model.undo():
			break
		drained += 1
	r.check(not model.can_undo(), "循环 undo 后应回到初始状态")
	r.eq(model.event_count(), 11, "回到初始后事件数应为 11")

	# 对 0 号事件连续做 60 次 duration 修改，每次不同值。
	var all_updated := true
	for i in range(60):
		var event: Dictionary = model.get_event(0).duplicate(true)
		event["duration"] = float(i + 1)
		if not model.update_event(0, event):
			all_updated = false
	r.check(all_updated, "60 次 duration 修改应全部成功")

	var undo_count := 0
	while model.can_undo() and undo_count < 500:
		if not model.undo():
			break
		undo_count += 1
	r.check(undo_count >= 50, "历史应至少保留 50 步（实际 undo %d 次）" % undo_count)

	var redo_count := 0
	while model.can_redo() and redo_count < undo_count:
		if not model.redo():
			break
		redo_count += 1
	r.eq(redo_count, undo_count, "redo 次数应等于 undo 次数")
	r.check(is_equal_approx(float(model.get_event(0).get("duration", 0.0)), 60.0), "redo 后应恢复最新值 duration=60.0")


# ---------------------------------------------------------------- move

func _test_move_event(r, model) -> void:
	var count_before: int = model.event_count()
	r.check(model.move_event(0, 1), "move_event(0, 1) 应成功")
	r.eq(str(model.get_event(0).get("id", "")), "e2", "下移后 0 号事件应为 e2")
	r.eq(str(model.get_event(1).get("id", "")), "e1", "下移后 1 号事件应为 e1")
	r.check(not model.move_event(0, -1), "越界上移应返回 false")
	r.eq(str(model.get_event(0).get("id", "")), "e2", "失败的移动不应改变顺序")
	r.eq(model.event_count(), count_before, "失败的移动不应改变事件数")


# ---------------------------------------------------------------- save draft

func _test_save_draft(r, model) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_timeline_draft.json"):
		dir.remove("test_timeline_draft.json")

	r.check(model.save_draft(DRAFT_PATH), "save_draft 应成功")
	r.check(FileAccess.file_exists(DRAFT_PATH), "草稿文件应存在")
	var text := FileAccess.get_file_as_string(DRAFT_PATH)
	r.check(not text.is_empty(), "草稿文件不应为空")
	r.check(JSON.parse_string(text) != null, "草稿应为合法 JSON")


# ---------------------------------------------------------------- next_event_id

## 删除中间事件后 count 变小，新 id 不得回退到已占用的编号（如 e11）。
func _test_next_event_id(r) -> void:
	var model = TimelineModel.new()
	r.check(model.load_file(SAMPLE_PATH), "next_event_id 测试应能加载样例: " + _errors_text(model.last_errors))
	r.eq(model.next_event_id(), "e12", "样例加载后 next_event_id 应为 e12")
	r.eq(str(model.get_event(4).get("id", "")), "e5", "索引 4 应为 e5")
	r.check(model.delete_event(4), "删除 e5 应成功")
	r.eq(model.event_count(), 10, "删除 e5 后事件数应为 10")
	r.eq(model.next_event_id(), "e12", "删除 e5 后 next_event_id 仍应为 e12")
	r.eq(str(model.get_event(9).get("id", "")), "e11", "删除后末尾事件应为 e11")


# ---------------------------------------------------------------- load_from_dict

## 第 8 步：从内存字典恢复（自动保存草稿恢复入口）。
func _test_load_from_dict(r) -> void:
	var doc := ProjectDoc.new()
	r.check(doc.load_file(SAMPLE_PATH), "load_from_dict 测试应能加载样例: " + doc.parse_error)
	var data: Dictionary = doc.data.duplicate(true)

	var model = TimelineModel.new()
	r.check(model.load_from_dict(data, "user://draft.json"), "load_from_dict 应成功")
	r.eq(model.event_count(), 11, "load_from_dict 后事件数应为 11")
	r.eq(model.source_path, "user://draft.json", "load_from_dict 后 source_path 应为传入路径")
	r.check(not model.can_undo(), "load_from_dict 后不应可撤销")
	r.check(not model.can_redo(), "load_from_dict 后不应可重做")

	var report: Dictionary = model.validate()
	r.eq(_array_size(report.get("errors", [])), 0, "load_from_dict 后校验错误数应为 0")


## load_from_dict 后的编辑应记入历史，undo 能回到草稿初始状态。
func _test_load_from_dict_edit_undo(r) -> void:
	var doc := ProjectDoc.new()
	r.check(doc.load_file(SAMPLE_PATH), "load_from_dict 撤销测试应能加载样例: " + doc.parse_error)
	var data: Dictionary = doc.data.duplicate(true)

	var model = TimelineModel.new()
	r.check(model.load_from_dict(data, "user://draft.json"), "草稿应有内存数据可恢复")
	var edited: Dictionary = model.get_event(0).duplicate(true)
	edited["duration"] = 9.0
	r.check(model.update_event(0, edited), "load_from_dict 后 update_event 应成功: " + _errors_text(model.last_errors))
	r.check(model.can_undo(), "load_from_dict 后的修改应可撤销")

	r.check(model.undo(), "undo 应成功")
	r.check(not model.can_undo(), "undo 回到草稿初始后不应再可撤销")
	var reverted: Dictionary = model.get_event(0)
	r.eq(str(reverted.get("id", "")), "e1", "undo 后 0 号事件仍应为 e1")
	r.check(not is_equal_approx(float(reverted.get("duration", 0.0)), 9.0), "undo 后 duration 应恢复草稿初始值")


# ---------------------------------------------------------------- helpers

func _errors_text(errors) -> String:
	var parts: Array = []
	if typeof(errors) == TYPE_ARRAY:
		for e in errors:
			if typeof(e) == TYPE_DICTIONARY:
				parts.append(str((e as Dictionary).get("message", str(e))))
			else:
				parts.append(str(e))
	else:
		parts.append(str(errors))
	return " | ".join(parts)


func _array_size(value) -> int:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).size()
	return -1
