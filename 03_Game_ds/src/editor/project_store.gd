extends RefCounted
## Project store: load / save / dirty tracking / autosave / crash recovery.
##
## It is the only object the editor UI mutates, and every mutation goes through
## `apply_edit`, which is what ties the undo stack and the dirty flag together.
##
## Save format stays exactly schema v2: `to_json()` rebuilds the tree with sorted
## object keys (so diffs are stable and a no-op save is byte-identical) and does
## not add or drop fields. Whatever the validator accepted before a save it must
## accept after a load, because nothing is rewritten.
##
## Autosave goes to `user://autosave/<basename>.json` next to the project (never
## inside res://, so a relocated build cannot inherit stale drafts) and carries
## `{saved_at, source_path, project}`. Recovery only offers a draft when it is
## strictly newer than the project file on disk.

const UndoStack = preload("res://src/editor/undo_stack.gd")

const AUTOSAVE_DIR := "user://autosave"
const AUTOSAVE_INTERVAL_SECONDS := 30.0
const AUTOSAVE_FORMAT := 1

var project: Dictionary = {}
var source_path: String = ""
var dirty: bool = false
var autosave_dir: String = AUTOSAVE_DIR
var history
var last_error: String = ""

var _last_autosave_sec: float = 0.0
var _last_saved_unix: int = 0
var _load_count: int = 0


func _init(capacity: int = UndoStack.DEFAULT_CAPACITY) -> void:
	history = UndoStack.new(capacity)


# ------------------------------------------------------------------ load / save

func load_file(path: String, now_seconds: float = 0.0) -> Dictionary:
	last_error = ""
	if path.is_empty():
		return _fail("IO_NOT_FOUND", "empty path")
	if not FileAccess.file_exists(path):
		return _fail("IO_NOT_FOUND", "project file not found: " + path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail("IO_EMPTY", "project file is empty: " + path)
	return load_json(text, path, now_seconds)


func load_json(text: String, path: String = "", now_seconds: float = 0.0) -> Dictionary:
	last_error = ""
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return _fail("JSON_PARSE", "line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if typeof(parser.data) != TYPE_DICTIONARY:
		return _fail("JSON_ROOT", "project root must be a JSON object")
	project = (parser.data as Dictionary).duplicate(true)
	source_path = path
	dirty = false
	history.clear()
	_last_autosave_sec = now_seconds
	_last_saved_unix = int(FileAccess.get_modified_time(path)) if not path.is_empty() else 0
	_load_count += 1
	return {
		"ok": true,
		"code": "",
		"path": source_path,
		"levels": _levels().size(),
		"events": _timeline().size(),
	}


## Deterministic text: object keys sorted at every depth, two-space indent.
func to_json() -> String:
	return JSON.stringify(_sorted_copy(project), "  ", false) + "\n"


func to_dict() -> Dictionary:
	return project.duplicate(true)


func save(target: String = "") -> Dictionary:
	last_error = ""
	var path := target if not target.is_empty() else source_path
	if path.is_empty():
		return _fail("STORE_NO_TARGET", "no target path: pass one or load a project first")
	var text := to_json()
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return _fail("IO_WRITE", "cannot create directory %s (error %d)" % [dir, mk])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _fail("IO_WRITE", "cannot open %s for writing (%d)" % [path, FileAccess.get_open_error()])
	f.store_string(text)
	f.close()
	if not FileAccess.file_exists(path):
		return _fail("IO_WRITE", "write reported success but %s is missing" % path)
	source_path = path
	mark_clean()
	_last_saved_unix = int(Time.get_unix_time_from_system())
	# A successful save makes the draft redundant: drop it so recovery cannot
	# offer an older state right after the user saved.
	_remove_autosave(path)
	return {"ok": true, "code": "", "path": path, "bytes": text.length()}


func save_as(target: String) -> Dictionary:
	if target.is_empty():
		return _fail("STORE_NO_TARGET", "save_as needs a target path")
	var before := source_path
	var r := save(target)
	if not bool(r.get("ok", false)):
		source_path = before
	return r


## "复制变体": write the current project to a new path and continue editing there.
func duplicate_variant(target: String) -> Dictionary:
	if target.is_empty():
		return _fail("STORE_NO_TARGET", "duplicate_variant needs a target path")
	var r := save(target)
	if bool(r.get("ok", false)):
		r["variant_of"] = source_path
	return r


func mark_clean() -> void:
	dirty = false


func mark_dirty() -> void:
	dirty = true


func is_loaded() -> bool:
	return not project.is_empty()


func load_count() -> int:
	return _load_count


func last_saved_unix() -> int:
	return _last_saved_unix


# ------------------------------------------------------------- edits + history

## Applies `mutator` to a deep copy of the project. The mutator may edit in place
## and/or return a replacement dictionary. Nothing is recorded when the result is
## canonically identical to the current project.
func apply_edit(label: String, mutator: Callable) -> Dictionary:
	var before: Dictionary = project.duplicate(true)
	var draft: Dictionary = project.duplicate(true)
	var returned = mutator.call(draft)
	if typeof(returned) == TYPE_DICTIONARY:
		draft = returned
	if UndoStack.same(before, draft):
		return {"ok": false, "code": "NO_CHANGE", "label": label, "size": history.size()}
	var pushed: Dictionary = history.push(label, before, draft)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", "NO_CHANGE")), "label": label, "size": history.size()}
	project = draft
	dirty = true
	return {
		"ok": true,
		"code": "",
		"label": label,
		"size": history.size(),
		"cursor": history.depth(),
		"dropped": int(pushed.get("dropped", 0)),
	}


func can_undo() -> bool:
	return history.can_undo()


func can_redo() -> bool:
	return history.can_redo()


func undo() -> Dictionary:
	var r: Dictionary = history.undo()
	if not bool(r.get("ok", false)):
		return r
	project = (r["state"] as Dictionary).duplicate(true)
	dirty = true
	r["undo_size"] = history.size()
	return r


func redo() -> Dictionary:
	var r: Dictionary = history.redo()
	if not bool(r.get("ok", false)):
		return r
	project = (r["state"] as Dictionary).duplicate(true)
	dirty = true
	r["undo_size"] = history.size()
	r["last_label"] = history.last_label()
	return r


func undo_label() -> String:
	return history.last_label()


# ------------------------------------------------------------------- autosave

func autosave_path_for(source: String) -> String:
	var base := source.get_file().get_basename()
	if base.is_empty():
		base = "project"
	return autosave_dir.path_join(base + ".json")


## Writes at most one draft every 30 s, and only while the project is dirty.
func maybe_autosave(now_seconds: float) -> Dictionary:
	if not dirty:
		return {"written": false, "reason": "clean"}
	if source_path.is_empty():
		return {"written": false, "reason": "no_source"}
	var elapsed := now_seconds - _last_autosave_sec
	if elapsed < AUTOSAVE_INTERVAL_SECONDS:
		return {"written": false, "reason": "interval", "elapsed": elapsed, "next_in": AUTOSAVE_INTERVAL_SECONDS - elapsed}
	return _write_autosave(now_seconds)


## Page switch / explicit Ctrl+S-ish draft: interval does not apply.
func force_autosave(now_seconds: float) -> Dictionary:
	if not dirty:
		return {"written": false, "reason": "clean"}
	if source_path.is_empty():
		return {"written": false, "reason": "no_source"}
	return _write_autosave(now_seconds)


func _write_autosave(now_seconds: float) -> Dictionary:
	var path := autosave_path_for(source_path)
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return {"written": false, "reason": "io", "error": "mkdir %s (%d)" % [dir, mk]}
	var payload := {
		"format": AUTOSAVE_FORMAT,
		"saved_at": int(Time.get_unix_time_from_system()),
		"source_path": source_path,
		"project": project,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"written": false, "reason": "io", "error": "open %s (%d)" % [path, FileAccess.get_open_error()]}
	f.store_string(JSON.stringify(payload, "  ", false) + "\n")
	f.close()
	_last_autosave_sec = now_seconds
	return {"written": true, "reason": "", "path": path, "saved_at": int(payload["saved_at"])}


func autosave_age(now_seconds: float) -> float:
	return now_seconds - _last_autosave_sec


# ------------------------------------------------------------------- recovery

## Offers a draft only when it belongs to this project and is strictly newer than
## the project file on disk (a missing project file always counts as older).
func find_recovery(source: String = "") -> Dictionary:
	var src := source if not source.is_empty() else source_path
	if src.is_empty():
		return {"found": false, "reason": "no_source"}
	var path := autosave_path_for(src)
	if not FileAccess.file_exists(path):
		return {"found": false, "reason": "no_draft", "path": path}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"found": false, "reason": "draft_parse", "path": path}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"found": false, "reason": "draft_root", "path": path}
	var root: Dictionary = parser.data
	var payload_project = root.get("project", null)
	if typeof(payload_project) != TYPE_DICTIONARY:
		return {"found": false, "reason": "draft_payload", "path": path}
	var recorded_source := String(root.get("source_path", ""))
	if recorded_source != src:
		return {"found": false, "reason": "source_mismatch", "path": path, "draft_source": recorded_source}
	var saved_at := float(root.get("saved_at", 0))
	var source_modified := 0.0
	if FileAccess.file_exists(src):
		source_modified = float(FileAccess.get_modified_time(src))
	if saved_at <= source_modified:
		return {
			"found": false,
			"reason": "older_than_source",
			"path": path,
			"saved_at": int(saved_at),
			"source_modified": int(source_modified),
		}
	return {
		"found": true,
		"reason": "",
		"path": path,
		"saved_at": int(saved_at),
		"source_modified": int(source_modified),
		"events": _timeline_of(payload_project).size(),
		"levels": _levels_of(payload_project).size(),
	}


func restore_from_recovery() -> Dictionary:
	var src := source_path
	var found := find_recovery(src)
	if not bool(found.get("found", false)):
		return {"ok": false, "code": "RECOVERY_NONE", "reason": String(found.get("reason", ""))}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(String(found["path"]))) != OK:
		return {"ok": false, "code": "RECOVERY_PARSE"}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "code": "RECOVERY_PARSE"}
	var root: Dictionary = parser.data
	project = (root["project"] as Dictionary).duplicate(true)
	source_path = String(root.get("source_path", src))
	dirty = true
	history.clear()
	return {
		"ok": true,
		"code": "",
		"project": project.duplicate(true),
		"saved_at": int(found.get("saved_at", 0)),
		"path": String(found["path"]),
	}


func discard_recovery(source: String = "") -> Dictionary:
	var src := source if not source.is_empty() else source_path
	if src.is_empty():
		return {"ok": false, "code": "STORE_NO_TARGET", "removed": false}
	return _remove_autosave(src)


func _remove_autosave(source: String) -> Dictionary:
	var path := autosave_path_for(source)
	if not FileAccess.file_exists(path):
		return {"ok": true, "code": "", "removed": false, "path": path}
	var e := DirAccess.remove_absolute(path)
	return {"ok": e == OK, "code": "" if e == OK else "IO_REMOVE", "removed": e == OK, "path": path}


# -------------------------------------------------------------------- helpers

func _levels() -> Array:
	return _levels_of(project)


func _timeline() -> Array:
	return _timeline_of(project)


static func _levels_of(p: Dictionary) -> Array:
	var v = p.get("levels", [])
	return v if typeof(v) == TYPE_ARRAY else []


static func _timeline_of(p: Dictionary) -> Array:
	var v = p.get("timeline", [])
	return v if typeof(v) == TYPE_ARRAY else []


static func _sorted_copy(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			var keys: Array = (value as Dictionary).keys()
			keys.sort_custom(func(a, b): return String(a) < String(b))
			for k in keys:
				out[String(k)] = _sorted_copy((value as Dictionary)[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for v in (value as Array):
				arr.append(_sorted_copy(v))
			return arr
	return value


func _fail(code: String, msg: String) -> Dictionary:
	last_error = msg
	return {"ok": false, "code": code, "msg": msg}
