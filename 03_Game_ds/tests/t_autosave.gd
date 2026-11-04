extends RefCounted
## Autosave + crash recovery tests, driven by a fake clock so nothing sleeps.
## Everything lands in its own `user://` sub-directory and is removed again.

const Store = preload("res://src/editor/project_store.gd")
const UndoStack = preload("res://src/editor/undo_stack.gd")

const SAMPLE := "res://data/sample_project.json"
const DIR := "user://_test_autosave"
const TMP := "user://_test_autosave_out"


func run(t) -> void:
	_cleanup()
	_interval(t)
	_payload(t)
	_force_on_page_change(t)
	_newer_draft_recovers(t)
	_older_draft_is_ignored(t)
	_source_mismatch_is_ignored(t)
	_save_drops_the_draft(t)
	_cleanup()


func _dirty_store(t):
	var s = Store.new()
	s.autosave_dir = DIR
	var r: Dictionary = s.load_file(SAMPLE, 0.0)
	t.ok(bool(r.get("ok", false)), "sample loads for autosave tests", str(r))
	var e: Dictionary = s.apply_edit("coin", func(p):
		p["hud"]["coin"] = 111
	)
	t.ok(bool(e.get("ok", false)), "store has one pending edit", str(e))
	return s


# ------------------------------------------------------------ 30 s interval

func _interval(t) -> void:
	var s = Store.new()
	s.autosave_dir = DIR
	s.load_file(SAMPLE, 0.0)
	var clean: Dictionary = s.maybe_autosave(100.0)
	t.ok(not bool(clean.get("written", true)), "a clean project is never autosaved")
	t.eq(String(clean.get("reason", "")), "clean", "reason is clean")

	s = _dirty_store(t)
	var path := s.autosave_path_for(SAMPLE)
	t.ok(not FileAccess.file_exists(path), "no draft before the first tick")

	var at0: Dictionary = s.maybe_autosave(0.0)
	t.ok(not bool(at0.get("written", true)), "t=0 writes nothing")
	var at29: Dictionary = s.maybe_autosave(29.0)
	t.ok(not bool(at29.get("written", true)), "t=29s writes nothing")
	t.eq(String(at29.get("reason", "")), "interval", "reason is interval")
	t.ok(absf(float(at29.get("next_in", 0.0)) - 1.0) < 0.0001, "next write is 1s away", str(at29.get("next_in")))
	t.ok(not FileAccess.file_exists(path), "still no draft at 29s")

	var at31: Dictionary = s.maybe_autosave(31.0)
	t.ok(bool(at31.get("written", false)), "t=31s writes a draft", str(at31))
	t.ok(FileAccess.file_exists(path), "draft file exists")
	t.eq(s.autosave_path_for(SAMPLE), DIR + "/sample_project.json", "draft path is <dir>/<basename>.json")

	var again: Dictionary = s.maybe_autosave(32.0)
	t.ok(not bool(again.get("written", true)), "the next 30s window starts over")
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- payload

func _payload(t) -> void:
	var s = _dirty_store(t)
	var w: Dictionary = s.maybe_autosave(40.0)
	t.ok(bool(w.get("written", false)), "draft written", str(w))
	var path := String(w.get("path", ""))
	var parser := JSON.new()
	t.ok(parser.parse(FileAccess.get_file_as_string(path)) == OK, "draft is valid JSON")
	var root: Dictionary = parser.data
	t.ok(root.has("saved_at"), "draft carries saved_at")
	t.ok(root.has("source_path"), "draft carries source_path")
	t.ok(root.has("project"), "draft carries the project")
	t.eq(String(root.get("source_path", "")), SAMPLE, "draft remembers which project it belongs to")
	t.ok(int(root.get("saved_at", 0)) > 0, "saved_at is a unix timestamp", str(root.get("saved_at")))
	var proj: Dictionary = root.get("project", {})
	var tl = proj.get("timeline", [])
	t.eq((tl as Array).size(), 21, "draft holds all 21 events")
	t.eq(int((proj.get("hud", {}) as Dictionary).get("coin", 0)), 111, "draft holds the pending edit")
	DirAccess.remove_absolute(path)


# ------------------------------------------------------------ page switch

func _force_on_page_change(t) -> void:
	var s = _dirty_store(t)
	s.maybe_autosave(10.0)
	var path := s.autosave_path_for(SAMPLE)
	t.ok(bool(s.maybe_autosave(10.5).get("written", true)) == false, "0.5s later the interval still blocks")
	t.ok(not FileAccess.file_exists(path), "nothing written yet")

	var forced: Dictionary = s.force_autosave(10.5)
	t.ok(bool(forced.get("written", false)), "page switch bypasses the interval", str(forced))
	t.ok(FileAccess.file_exists(path), "page switch wrote the draft")

	s.mark_clean()
	var clean_force: Dictionary = s.force_autosave(11.0)
	t.ok(not bool(clean_force.get("written", true)), "a clean project is not written on page switch")
	DirAccess.remove_absolute(path)


# --------------------------------------------------------------- recovery

func _newer_draft_recovers(t) -> void:
	var s = Store.new()
	s.autosave_dir = DIR
	s.load_file(SAMPLE, 0.0)
	var draft_project: Dictionary = s.project.duplicate(true)
	draft_project["hud"]["coin"] = 4242
	var src_mtime := int(FileAccess.get_modified_time(SAMPLE))
	var path := _write_draft(s.autosave_path_for(SAMPLE), SAMPLE, src_mtime + 3600, draft_project)
	t.ok(FileAccess.file_exists(path), "hand written draft exists")

	var found: Dictionary = s.find_recovery(SAMPLE)
	t.ok(bool(found.get("found", false)), "a newer draft is offered", str(found))
	t.eq(int(found.get("saved_at", 0)), src_mtime + 3600, "draft timestamp is reported")
	t.eq(int(found.get("source_modified", 0)), src_mtime, "source timestamp is reported")
	t.eq(int(found.get("events", 0)), 21, "draft event count is reported")

	var restored: Dictionary = s.restore_from_recovery()
	t.ok(bool(restored.get("ok", false)), "restore succeeds", str(restored))
	t.eq(UndoStack.canon(s.project), UndoStack.canon(draft_project), "restored project matches the draft")
	t.ok(s.dirty, "a restored project is dirty until saved")

	var discarded: Dictionary = s.discard_recovery(SAMPLE)
	t.ok(bool(discarded.get("removed", false)), "discard removes the draft")
	t.ok(not bool(s.find_recovery(SAMPLE).get("found", true)), "discarded draft is no longer offered")
	t.eq(String(s.find_recovery(SAMPLE).get("reason", "")), "no_draft", "reason is no_draft")


func _older_draft_is_ignored(t) -> void:
	var s = Store.new()
	s.autosave_dir = DIR
	s.load_file(SAMPLE, 0.0)
	var src_mtime := int(FileAccess.get_modified_time(SAMPLE))
	var path := _write_draft(s.autosave_path_for(SAMPLE), SAMPLE, src_mtime - 3600, s.project)
	var found: Dictionary = s.find_recovery(SAMPLE)
	t.ok(not bool(found.get("found", true)), "a draft older than the source is not offered", str(found))
	t.eq(String(found.get("reason", "")), "older_than_source", "reason is older_than_source")
	DirAccess.remove_absolute(path)

	var restored: Dictionary = s.restore_from_recovery()
	t.eq(String(restored.get("code", "")), "RECOVERY_NONE", "restore without a draft reports RECOVERY_NONE")


func _source_mismatch_is_ignored(t) -> void:
	var s = Store.new()
	s.autosave_dir = DIR
	s.load_file(SAMPLE, 0.0)
	var other := "res://data/another_project.json"
	var path := _write_draft(s.autosave_path_for(SAMPLE), other, int(FileAccess.get_modified_time(SAMPLE)) + 500, s.project)
	var found: Dictionary = s.find_recovery(SAMPLE)
	t.ok(not bool(found.get("found", true)), "a draft for another project is not offered", str(found))
	t.eq(String(found.get("reason", "")), "source_mismatch", "reason is source_mismatch")
	DirAccess.remove_absolute(path)

	var empty = Store.new()
	empty.autosave_dir = DIR
	t.eq(String(empty.find_recovery("").get("reason", "")), "no_source", "no source path means no recovery")


func _save_drops_the_draft(t) -> void:
	var s = Store.new()
	s.autosave_dir = DIR
	s.load_file(SAMPLE, 0.0)
	DirAccess.make_dir_recursive_absolute(TMP)
	var target := TMP + "/work.json"
	t.ok(bool(s.save_as(target).get("ok", false)), "save_as creates the working file")
	s.apply_edit("coin", func(p):
		p["hud"]["coin"] = 7
	)
	var w: Dictionary = s.force_autosave(50.0)
	t.ok(bool(w.get("written", false)), "draft written for the working file", str(w))
	t.ok(FileAccess.file_exists(s.autosave_path_for(target)), "draft file exists before saving")

	t.ok(bool(s.save().get("ok", false)), "save the working file")
	t.ok(not FileAccess.file_exists(s.autosave_path_for(target)), "save deletes the draft file")
	var after: Dictionary = s.find_recovery(target)
	t.ok(not bool(after.get("found", true)), "a successful save drops its own draft", str(after))
	t.eq(String(after.get("reason", "")), "no_draft", "reason is no_draft after save")


# -------------------------------------------------------------------- helpers

func _write_draft(path: String, source: String, saved_at: int, project: Dictionary) -> String:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({
		"format": 1,
		"saved_at": saved_at,
		"source_path": source,
		"project": project,
	}, "  ", false) + "\n")
	f.close()
	return path


func _cleanup() -> void:
	for dir in [DIR, TMP]:
		_purge(String(dir))


func _purge(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir():
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)
