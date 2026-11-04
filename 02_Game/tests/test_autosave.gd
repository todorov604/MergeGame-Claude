extends RefCounted

## 第 8 步验收：AutosaveStore（自动保存草稿：写入 / 读取 / 清除 / 损坏容错）。
## 契约：setup(path)、save(project_data, source) -> bool、load_draft() -> Dictionary、
##      has_draft() -> bool、clear() -> bool、draft_path() -> String、last_error。
## load_draft() 返回 {source: String, saved_at: int(>0), project: Dictionary}。

const AutosaveStore = preload("res://editor/autosave.gd")

# 测试专用路径：避免与编辑器真实草稿（user://timeline_autosave.json）冲突。
const DRAFT_PATH := "user://test_autosave.json"
const SOURCE_PATH := "res://data/projects/sample_30s.json"


func run(r) -> void:
	var store = AutosaveStore.new()
	_test_save_and_load(r, store)
	_test_clear(r, store)
	_test_corrupt_draft(r, store)
	_remove_test_file()


# ---------------------------------------------------------------- save / load

func _test_save_and_load(r, store) -> void:
	store.setup(DRAFT_PATH)
	store.clear()  # 清掉上次中断运行可能残留的同名文件
	r.eq(store.draft_path(), DRAFT_PATH, "draft_path() 应返回 setup 的路径")

	var draft_project := {"version": 2, "meta": {"title": "draft"}}
	r.check(store.save(draft_project, SOURCE_PATH), "save 应成功: " + str(store.last_error))
	r.check(store.has_draft(), "save 后 has_draft() 应为 true")

	var draft: Dictionary = store.load_draft()
	r.eq(str(draft.get("source", "")), SOURCE_PATH, "load_draft 的 source 应等于保存时的来源")
	r.eq(typeof(draft.get("saved_at")), TYPE_INT, "saved_at 应为 int")
	r.check(int(draft.get("saved_at", 0)) > 0, "saved_at 应大于 0")
	var project: Dictionary = draft.get("project", {})
	r.eq(int(project.get("version", -1)), 2, "草稿 project.version 应为 2")
	var meta: Dictionary = project.get("meta", {})
	r.eq(str(meta.get("title", "")), "draft", "草稿 project.meta.title 应为 draft")


# ---------------------------------------------------------------- clear

func _test_clear(r, store) -> void:
	r.check(store.clear(), "已有草稿时 clear() 应返回 true: " + str(store.last_error))
	r.check(not store.has_draft(), "clear 后 has_draft() 应为 false")
	var draft: Dictionary = store.load_draft()
	r.check(draft.is_empty(), "clear 后 load_draft() 应返回空字典")


# ---------------------------------------------------------------- 损坏容错

func _test_corrupt_draft(r, store) -> void:
	var file := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	r.check(file != null, "应能创建损坏草稿测试文件")
	if file != null:
		file.store_string("not json")
		file.close()

	var draft: Dictionary = store.load_draft()
	r.check(draft.is_empty(), "非法 JSON 时 load_draft() 应返回空字典")
	r.check(
		not store.has_draft() or not str(store.last_error).is_empty(),
		"非法 JSON 时 has_draft() 应为 false 或 last_error 应非空"
	)

	r.check(store.clear(), "损坏草稿也应能 clear(): " + str(store.last_error))
	r.check(not FileAccess.file_exists(DRAFT_PATH), "clear 后草稿文件应被删除")


# ---------------------------------------------------------------- 清理

func _remove_test_file() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_autosave.json"):
		dir.remove("test_autosave.json")
