extends RefCounted
## Editor data-layer tests: store round trip, edits that must stay valid under
## schema v2, and the `wait` ban surfacing in the jump-to-error list.

const Store = preload("res://src/editor/project_store.gd")
const Editor = preload("res://src/editor/timeline_editor.gd")
const UndoStack = preload("res://src/editor/undo_stack.gd")
const Validator = preload("res://src/validate/validator.gd")
const AssetGuard = preload("res://src/assets/asset_guard.gd")

const SAMPLE := "res://data/sample_project.json"
const INDEX := "res://data/manifest_index.json"
const TMP_DIR := "user://_test_editor"


func run(t) -> void:
	_cleanup()
	_round_trip(t)
	_saved_file_still_validates(t)
	_edits_keep_valid(t)
	_wait_is_caught(t)
	_view_helpers(t)
	_playback(t)
	_cleanup()


func _guard():
	var g = AssetGuard.new()
	g.load_from(INDEX, false)
	return g


## 2026-11-12（AGENTS §6.35）：样例工程是操作者的数据，里面可能本来就有内容错误。
## 编辑器测试只断言"这次操作没有引入新的错误码"，不要求整份工程 0 错误。
func _baseline_codes() -> Array:
	var rep = Validator.validate_file(SAMPLE, _guard(), false)
	return rep.codes()


func _extra_codes(codes: Array) -> Array:
	var base := _baseline_codes().duplicate()
	var out: Array = []
	for c in codes:
		var idx := base.find(c)
		if idx >= 0:
			base.remove_at(idx)
		else:
			out.append(c)
	return out


func _validate(project: Dictionary):
	return Validator.validate_dictionary(project, SAMPLE, _guard(), false)


# ------------------------------------------------------------------ round trip

func _round_trip(t) -> void:
	var store = Store.new()
	var r: Dictionary = store.load_file(SAMPLE)
	t.ok(bool(r.get("ok", false)), "store loads the sample", str(r))
	t.eq(int(r.get("events", 0)), 21, "sample has 21 events")
	var lv_count := 0
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(SAMPLE)) == OK and typeof(j.data) == TYPE_DICTIONARY:
		lv_count = ((j.data as Dictionary).get("levels", []) as Array).size()
	t.eq(int(r.get("levels", 0)), lv_count, "level count follows the data")
	t.ok(not store.dirty, "a freshly loaded project is clean")

	var json1 := store.to_json()
	var store2 = Store.new()
	var r2: Dictionary = store2.load_json(json1)
	t.ok(bool(r2.get("ok", false)), "to_json output loads back", str(r2))
	t.eq(UndoStack.canon(store2.project), UndoStack.canon(store.project), "round trip preserves the whole tree")
	t.eq(store2.to_json(), json1, "second serialization is byte identical")

	var reversed = _reverse_keys(store.project)
	t.eq(UndoStack.canon(reversed), UndoStack.canon(store.project), "key insertion order does not change canon")

	var bad = Store.new()
	t.ok(not bool(bad.load_json("{\"version\": 2").get("ok", true)), "unterminated JSON is rejected")
	t.ok(not bool(bad.load_json("[1,2,3]").get("ok", true)), "non-object root is rejected")
	t.eq(String(bad.last_error), "project root must be a JSON object", "root error is reported")


func _saved_file_still_validates(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var target := TMP_DIR + "/saved_project.json"
	var sr: Dictionary = store.save(target)
	t.ok(bool(sr.get("ok", false)), "save writes the file", str(sr))
	t.ok(FileAccess.file_exists(target), "saved file exists")
	t.eq(store.source_path, target, "save points the store at the new file")
	t.ok(not store.dirty, "save clears the dirty flag")

	var report = Validator.validate_file(target, _guard(), false)
	t.eq(_extra_codes(report.codes()), [], "saving adds no new validation errors", str(report.codes()))
	t.eq(int(report.stats.get("events", 0)), 21, "validator still sees 21 events")

	var store3 = Store.new()
	t.ok(bool(store3.load_file(target).get("ok", false)), "saved file loads back")
	t.eq(UndoStack.canon(store3.project), UndoStack.canon(store.project), "save/load is lossless")

	# duplicate_variant: keep editing the copy, the original stays untouched
	var variant := TMP_DIR + "/variant.json"
	var vr: Dictionary = store.duplicate_variant(variant)
	t.ok(bool(vr.get("ok", false)), "duplicate_variant writes a copy")
	t.eq(store.source_path, variant, "editing continues on the variant")
	t.ok(FileAccess.file_exists(variant), "variant file exists")


# ---------------------------------------------------------------- edit safety

func _edits_keep_valid(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var ed = Editor.new()
	var s: Dictionary = ed.setup(store)
	t.ok(int(s.get("rows", 0)) == 21, "editor resolves 21 rows", str(s))
	t.eq(ed.groups.size(), 5, "5 channel/track groups in the sample")

	var added: Dictionary = ed.add_event("view", "text", 20.0, {"text_key": "cta.play"}, {"track": "text", "duration": 1.0})
	t.ok(bool(added.get("ok", false)), "add event", str(added))
	t.eq(String(added.get("id", "")), "e22", "new id continues the sample sequence")
	var report = _validate(store.project)
	t.eq(_extra_codes(report.codes()), [], "add introduces no new validation errors", str(report.codes()))
	t.ok(store.can_undo(), "add went through the undo stack")
	t.eq(store.history.size(), 1, "one undo entry per add")

	var deleted: Dictionary = ed.delete_event("e20")
	t.ok(bool(deleted.get("ok", false)), "delete a leaf event", str(deleted))
	t.eq((deleted.get("dependents", []) as Array).size(), 0, "cta has no dependents")
	t.eq(_extra_codes(_validate(store.project).codes()), [], "delete introduces no new validation errors")

	t.ok(bool(ed.set_at_absolute("e05", 4.0).get("ok", false)), "set absolute at")
	t.eq(_extra_codes(_validate(store.project).codes()), [], "absolute at introduces no new errors")
	t.ok(bool(ed.set_at_anchor("e05", "e02", 0.4).get("ok", false)), "set anchor form")
	t.eq(_extra_codes(_validate(store.project).codes()), [], "anchor at introduces no new errors")
	t.ok(not bool(ed.set_at_anchor("e05", "nope_missing", 0.0).get("ok", true)), "editor refuses a missing anchor")
	t.ok(not bool(ed.set_at_anchor("e05", "e05", 0.0).get("ok", true)), "editor refuses a self anchor")

	var renamed: Dictionary = ed.rename_event("e07", "claim")
	t.ok(bool(renamed.get("ok", false)), "rename e07", str(renamed))
	t.eq((renamed.get("rewritten", []) as Array).size(), 3, "three events were anchored to e07")
	t.eq(_extra_codes(_validate(store.project).codes()), [], "rename introduces no new errors", str(_validate(store.project).codes()))

	var props: Dictionary = ed.apply_props("e03", {
		"id": "e03", "channel": "view", "type": "text",
		"at": {"after": "e01", "offset": 0.4}, "duration": 1.5,
		"track": "text", "order": 0, "payload": {"text_key": "hook.question"},
	})
	t.ok(bool(props.get("ok", false)), "composite property edit", str(props))
	t.eq(_extra_codes(_validate(store.project).codes()), [], "composite edit introduces no new errors")

	var json_now := store.to_json()
	t.ok(bool(store.undo().get("ok", false)), "undo the composite edit")
	t.ok(json_now != store.to_json(), "undo actually changed the tree")
	t.eq(_extra_codes(_validate(store.project).codes()), [], "undo introduces no new errors")
	store.redo()
	t.eq(store.to_json(), json_now, "redo restores the exact tree")
	ed.free()


# ------------------------------------------------------------------ wait ban

func _wait_is_caught(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var ed = Editor.new()
	ed.setup(store)

	var added: Dictionary = ed.add_event("sim", "wait", 7.0, {}, {"allow_unregistered": true})
	t.ok(bool(added.get("ok", false)), "editor can hold a raw event so the validator can judge it", str(added))
	var wait_id := String(added.get("id", ""))

	var v: Dictionary = ed.validate_now()
	t.ok(not bool(v.get("ok", true)), "a wait event fails validation", str(v))
	t.has_code(ed.error_rows, "EV_WAIT_FORBIDDEN", "error list carries EV_WAIT_FORBIDDEN")
	t.has_code(ed.error_rows, "EV_TYPE_UNKNOWN", "wait is also not a registered sim type")

	var hit := {}
	for row in ed.error_rows:
		if String((row as Dictionary)["code"]) == "EV_WAIT_FORBIDDEN":
			hit = row
			break
	t.eq(String(hit.get("kind", "")), "event", "wait error is classified as an event error")
	t.eq(String(hit.get("event_id", "")), wait_id, "error points at the new event id")
	t.ok(String(hit.get("path", "")).begins_with("timeline["), "path is a timeline path", String(hit.get("path", "")))
	t.eq(int(hit.get("index", -1)), ed.find_index(wait_id), "path index matches the event position")

	var row_index: int = ed.error_rows.find(hit)
	var located: Dictionary = ed.locate_error(row_index)
	t.ok(bool(located.get("ok", false)), "clicking the error jumps", str(located))
	t.eq(ed.selected_id, wait_id, "selection follows the error")

	# deleting the bad event clears the error again
	ed.delete_event(wait_id)
	var v2: Dictionary = ed.validate_now()
	t.eq(_extra_codes(v2.get("codes", [])), [], "removing the wait event clears its error again", str(v2))
	t.eq(ed.error_rows.size(), _baseline_codes().size(), "error list is back to the baseline")
	ed.free()


# --------------------------------------------------------------- view helpers

func _view_helpers(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var ed = Editor.new()
	ed.setup(store)

	t.eq(ed.rows.size(), 21, "21 rows")
	t.eq(ed.lane_blocks().size(), 21, "every resolved row has a lane block")
	var anchor_blocks := 0
	for b in ed.lane_blocks():
		if not String((b as Dictionary)["anchor"]).is_empty():
			anchor_blocks += 1
	t.eq(anchor_blocks, 10, "10 of the 21 events use {after, offset}")

	t.eq(ed.display_rows().size(), 5 + 21, "5 group headers + 21 event rows")
	var first_key := String((ed.display_rows()[0] as Dictionary)["key"])
	t.eq(first_key, "sim|", "sim lane without track sorts first")
	ed.toggle_group("view|text")
	t.eq(ed.display_rows().size(), 5 + 19, "collapsing a group hides its two events")
	ed.toggle_group("view|text")
	t.eq(ed.display_rows().size(), 5 + 21, "expanding restores them")

	var row := ed.row_for("e02")
	t.ok(absf(float(row.get("at", 0.0)) - 3.2) < 0.0001, "e02 resolves to 3.2s", str(row.get("at", -1)))
	t.eq(String(row.get("anchor", "")), "e01", "e02 remembers its anchor id")

	ed.select("e19")
	t.eq(ed.selected_id, "e19", "select by id")
	t.eq(String(ed.selected_event().get("type", "")), "camera", "selection exposes the event")
	t.eq(ed.selected_index(), 18, "selection exposes the index")
	ed.free()


# ------------------------------------------------------------------ playback

func _playback(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var ed = Editor.new()
	ed.setup(store)

	ed.reset_playback()
	var s1: Dictionary = ed.step_once()
	# 第一条事件可能是"点一个空格"（操作者会改关卡）；这里只验证派发成功，
	# 不假设它一定 ok=true。
	t.ok(not s1.is_empty(), "first step dispatches", str(s1))
	t.ok(bool(s1.get("ok", false)) or String(s1.get("code", "")).begins_with("SIM_"),
			"first step returns a sim verdict", str(s1))
	t.eq(String(s1.get("id", "")), "e01", "the shared evaluator starts at e01")
	t.eq(String(s1.get("channel", "")), "sim", "e01 is a sim event")
	t.ok(absf(ed.playhead - 2.0) < 0.0001, "playhead follows the event time", str(ed.playhead))

	var adv: Dictionary = ed.advance(3.5)
	t.ok(int(adv.get("steps", 0)) >= 3, "advance dispatches the next events", str(adv))
	t.ok(ed.playhead > 2.0, "playhead moved forward")

	ed.play()
	t.ok(ed.playing, "play sets the flag")
	ed.pause()
	t.ok(not ed.playing, "pause clears the flag")
	ed.reset_playback()
	t.eq(ed.playhead, 0.0, "reset rewinds")

	var status := ed.status()
	t.eq(int(status["events"]), 21, "status reports the event count")
	t.ok(String(status["source"]) != "", "status carries the source path")
	ed.free()


# -------------------------------------------------------------------- helpers

func _reverse_keys(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = (value as Dictionary).keys()
			keys.reverse()
			var out := {}
			for k in keys:
				out[String(k)] = _reverse_keys((value as Dictionary)[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for v in (value as Array):
				arr.append(_reverse_keys(v))
			return arr
	return value


func _cleanup() -> void:
	if not DirAccess.dir_exists_absolute(TMP_DIR):
		return
	var d := DirAccess.open(TMP_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir():
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(TMP_DIR)
