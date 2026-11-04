extends Control
## M0 step 5: timeline editor page (channels, tracks, anchors, single step, play,
## validation with jump-to-error, undo/redo, save/save-as).
##
## Two layers, on purpose:
##   * a UI-free data layer (`add_event`, `apply_props`, `validate_now`,
##     `locate_error`, `step_once`, ...) that headless tests drive directly;
##   * a Control UI built entirely from code in `_ready()`, so nothing in this
##     file ever loads a REFERENCE_ONLY texture. The only asset it touches is the
##     PRODUCTION font.
##
## Playback and single step run through src/core/event_evaluator.gd, the same
## evaluator the sim uses, so the editor cannot invent its own ordering.

const Store = preload("res://src/editor/project_store.gd")
const EventModel = preload("res://src/core/event_model.gd")
const Evaluator = preload("res://src/core/event_evaluator.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const Validator = preload("res://src/validate/validator.gd")
const AssetGuard = preload("res://src/assets/asset_guard.gd")

const SAMPLE := "res://data/sample_project.json"
const INDEX := "res://data/manifest_index.json"
const FONT_PATH := "res://assets/fonts/font_zh.otf"

const TIMELINE_SECONDS := 30.0
const CHANNELS := ["sim", "view", "audio"]
const EDITABLE_KEYS := ["channel", "type", "at", "duration", "track", "order", "payload"]

const COLOR_PAGE := Color("#151A21")
const COLOR_PANEL := Color("#1E2631")
const COLOR_PANEL_2 := Color("#26303D")
const COLOR_INK := Color("#E6EDF6")
const COLOR_DIM := Color("#93A6BC")
const COLOR_OK := Color("#7FD35F")
const COLOR_WARN := Color("#E9C46A")
const COLOR_ERR := Color("#E76F51")
const LANE_COLORS := {
	"sim": Color("#5B8DEF"),
	"view": Color("#59C3A5"),
	"audio": Color("#C08BE0"),
}

var store = null
var report = null
var error_rows: Array = []
var rows: Array = []
var groups: Array = []
var resolved: Dictionary = {}
var selected_id: String = ""
var focused_slot := Vector2i(-1, -1)
var playhead: float = 0.0
var playing: bool = false
var evaluator = null
var last_step: Dictionary = {}
var allow_placeholders: bool = false
var strict: bool = false
var recovery: Dictionary = {}
var status_text: String = ""
var clock: float = 0.0

var _ui: Dictionary = {}
var _font: Font = null
var _open_groups: Dictionary = {}


# =========================================================== data layer (no UI)

func setup(store_in, opts: Dictionary = {}) -> Dictionary:
	store = store_in
	allow_placeholders = bool(opts.get("allow_placeholders", false))
	strict = bool(opts.get("strict", false))
	if store == null:
		store = Store.new()
		store.load_file(SAMPLE, 0.0)
	selected_id = ""
	error_rows = []
	report = null
	var r: Dictionary = refresh()
	if _ui.has("canvas"):
		_sync_ui()
	return r


func load_project(path: String) -> Dictionary:
	var r: Dictionary = store.load_file(path, clock)
	selected_id = ""
	refresh()
	_sync_ui()
	return r


func timeline() -> Array:
	var t = store.project.get("timeline", [])
	return t if typeof(t) == TYPE_ARRAY else []


func level_count() -> int:
	var l = store.project.get("levels", [])
	return (l as Array).size() if typeof(l) == TYPE_ARRAY else 0


func find_index(id: String) -> int:
	var t := timeline()
	for i in t.size():
		if typeof(t[i]) == TYPE_DICTIONARY and String((t[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func event_by_id(id: String) -> Dictionary:
	var i := find_index(id)
	if i < 0:
		return {}
	return (timeline()[i] as Dictionary).duplicate(true)


func _anchor_of(ev: Dictionary) -> String:
	var at = ev.get("at", null)
	if typeof(at) == TYPE_DICTIONARY:
		return String((at as Dictionary).get("after", ""))
	return ""


func anchor_ids() -> Array:
	var out: Array = []
	for ev in timeline():
		if typeof(ev) == TYPE_DICTIONARY:
			out.append(String((ev as Dictionary).get("id", "")))
	out.sort()
	return out


## Re-resolves the timeline and rebuilds list rows, groups and lane blocks.
func refresh() -> Dictionary:
	var t := timeline()
	var r: Dictionary = EventModel.resolve(t)
	resolved = r
	var by_id := {}
	for ev in r.get("events", []):
		by_id[String((ev as Dictionary).get("id", ""))] = ev
	rows = []
	for i in t.size():
		if typeof(t[i]) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = t[i]
		var id := String(ev.get("id", ""))
		var res = by_id.get(id, null)
		var at_abs := -1.0
		var valid := res != null
		if res != null:
			at_abs = float((res as Dictionary).get("at", -1.0))
		var anchor := _anchor_of(ev)
		var offset := 0.0
		if typeof(ev.get("at")) == TYPE_DICTIONARY:
			offset = float((ev.get("at") as Dictionary).get("offset", 0.0))
		var dur := 0.0
		var raw_dur = ev.get("duration", 0)
		if typeof(raw_dur) == TYPE_INT or typeof(raw_dur) == TYPE_FLOAT:
			dur = float(raw_dur)
		var ord_v = ev.get("order", 0)
		var ordv := int(ord_v) if typeof(ord_v) == TYPE_INT or typeof(ord_v) == TYPE_FLOAT else 0
		rows.append({
			"index": i,
			"id": id,
			"channel": String(ev.get("channel", "")),
			"type": String(ev.get("type", "")),
			"track": String(ev.get("track", "")),
			"at": at_abs,
			"duration": dur,
			"order": ordv,
			"anchor": anchor,
			"offset": offset,
			"valid": valid,
		})
	_rebuild_groups()
	if find_index(selected_id) < 0:
		selected_id = "" if rows.is_empty() else String((rows[0] as Dictionary)["id"])
	return {
		"ok": bool(r.get("ok", false)),
		"rows": rows.size(),
		"groups": groups.size(),
		"events": (r.get("events", []) as Array).size(),
		"end_time": float(r.get("end_time", 0.0)),
		"errors": (r.get("errors", []) as Array).size(),
		"resolved_errors": (r.get("errors", []) as Array).duplicate(true),
	}


func _rebuild_groups() -> void:
	var order: Array = []
	var bucket := {}
	for row in rows:
		var key := "%s|%s" % [String(row["channel"]), String(row["track"])]
		if not bucket.has(key):
			bucket[key] = {"key": key, "channel": String(row["channel"]), "track": String(row["track"]), "count": 0, "ids": []}
			order.append(key)
		bucket[key]["count"] = int(bucket[key]["count"]) + 1
		(bucket[key]["ids"] as Array).append(String(row["id"]))
	order.sort_custom(func(a, b):
		var pa: int = int(EventModel.CHANNEL_PRIORITY.get(bucket[a]["channel"], 9))
		var pb: int = int(EventModel.CHANNEL_PRIORITY.get(bucket[b]["channel"], 9))
		if pa != pb:
			return pa < pb
		return String(bucket[a]["track"]) < String(bucket[b]["track"])
	)
	groups = []
	for key in order:
		var g: Dictionary = bucket[key]
		g["open"] = bool(_open_groups.get(String(g["key"]), true))
		groups.append(g)


## Flat list the left panel renders: group header rows followed by member rows.
func display_rows() -> Array:
	var out: Array = []
	for g in groups:
		out.append({"kind": "group", "key": String(g["key"]), "channel": String(g["channel"]),
			"track": String(g["track"]), "count": int(g["count"]), "open": bool(g["open"])})
		if not bool(g["open"]):
			continue
		for id in (g["ids"] as Array):
			var row := row_for(String(id))
			if not row.is_empty():
				out.append({"kind": "event", "id": String(id), "row": row})
	return out


func row_for(id: String) -> Dictionary:
	for r in rows:
		if String((r as Dictionary)["id"]) == id:
			return r
	return {}


func toggle_group(key: String) -> void:
	_open_groups[key] = not bool(_open_groups.get(key, true))
	_rebuild_groups()
	_sync_ui()


## Lane geometry: x = 0..1 of the lane rect for the 0..TIMELINE_SECONDS window.
func lane_blocks() -> Array:
	var out: Array = []
	for row in rows:
		var r: Dictionary = row
		var t := float(r["at"])
		if t < 0.0:
			continue
		var frac := clampf(t / TIMELINE_SECONDS, 0.0, 1.0)
		var dur_frac := clampf(float(r["duration"]) / TIMELINE_SECONDS, 0.0, 1.0)
		out.append({
			"id": String(r["id"]),
			"channel": String(r["channel"]),
			"type": String(r["type"]),
			"at": t,
			"anchor": String(r["anchor"]),
			"offset": float(r["offset"]),
			"x": frac,
			"w": maxf(dur_frac, 0.004),
			"selected": String(r["id"]) == selected_id,
		})
	return out


# ------------------------------------------------------------------- mutations

func _next_event_id() -> String:
	var used := {}
	for id in anchor_ids():
		used[id] = true
	var n := 1
	while n < 10000:
		var cand := "e%02d" % n
		if not used.has(cand):
			return cand
		n += 1
	return "e_%d" % Time.get_ticks_usec()


func _is_at_form(value) -> bool:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value) >= 0.0
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		return not String(d.get("after", "")).is_empty()
	return false


func add_event(channel: String, type_id: String, at_value, payload: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	if not store.is_loaded():
		return {"ok": false, "code": "STORE_EMPTY"}
	if not CHANNELS.has(channel):
		return {"ok": false, "code": "EV_CHANNEL"}
	var allow_unregistered := bool(opts.get("allow_unregistered", false))
	if not allow_unregistered and not EventModel.type_registered(channel, type_id):
		return {"ok": false, "code": "EV_TYPE_UNKNOWN"}
	if not _is_at_form(at_value):
		return {"ok": false, "code": "EV_AT_INVALID"}
	var new_id := String(opts.get("id", "")) if not String(opts.get("id", "")).is_empty() else _next_event_id()
	if find_index(new_id) >= 0:
		return {"ok": false, "code": "EV_DUP_ID"}
	var ev := {
		"id": new_id,
		"channel": channel,
		"type": type_id,
		"at": at_value,
		"payload": payload.duplicate(true),
	}
	var dur = opts.get("duration", null)
	if dur != null:
		ev["duration"] = dur
	var track := String(opts.get("track", ""))
	if not track.is_empty():
		ev["track"] = track
	var pushed: Dictionary = store.apply_edit("add " + new_id, func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) == TYPE_ARRAY:
			(arr as Array).append(ev.duplicate(true))
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	selected_id = new_id
	refresh()
	_sync_ui()
	return {"ok": true, "code": "", "id": new_id, "index": find_index(new_id)}


func delete_event(id: String) -> Dictionary:
	var idx := find_index(id)
	if idx < 0:
		return {"ok": false, "code": "EV_NOT_FOUND"}
	var dependents: Array = []
	for ev in timeline():
		if typeof(ev) == TYPE_DICTIONARY and _anchor_of((ev as Dictionary)) == id:
			dependents.append(String((ev as Dictionary).get("id", "")))
	var pushed: Dictionary = store.apply_edit("delete " + id, func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) == TYPE_ARRAY:
			(arr as Array).remove_at(idx)
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	if selected_id == id:
		selected_id = ""
	refresh()
	_sync_ui()
	return {"ok": true, "code": "", "removed": id, "index": idx, "dependents": dependents}


func duplicate_event(id: String) -> Dictionary:
	var src := event_by_id(id)
	if src.is_empty():
		return {"ok": false, "code": "EV_NOT_FOUND"}
	var new_id := _next_event_id()
	var copy := src.duplicate(true)
	copy["id"] = new_id
	copy["at"] = {"after": id, "offset": 0.5}
	var pushed: Dictionary = store.apply_edit("duplicate " + id, func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) == TYPE_ARRAY:
			(arr as Array).append(copy.duplicate(true))
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	selected_id = new_id
	refresh()
	_sync_ui()
	return {"ok": true, "code": "", "id": new_id, "from": id}


func rename_event(old_id: String, new_id: String) -> Dictionary:
	if new_id.is_empty() or old_id == new_id:
		return {"ok": false, "code": "EV_ID_INVALID"}
	if find_index(old_id) < 0:
		return {"ok": false, "code": "EV_NOT_FOUND"}
	if find_index(new_id) >= 0:
		return {"ok": false, "code": "EV_DUP_ID"}
	var rewritten: Array = []
	var pushed: Dictionary = store.apply_edit("rename %s->%s" % [old_id, new_id], func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) != TYPE_ARRAY:
			return
		for ev in arr:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = ev
			if String(d.get("id", "")) == old_id:
				d["id"] = new_id
			var at = d.get("at", null)
			if typeof(at) == TYPE_DICTIONARY and String((at as Dictionary).get("after", "")) == old_id:
				(at as Dictionary)["after"] = new_id
				rewritten.append(d.get("id", ""))
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	if selected_id == old_id:
		selected_id = new_id
	refresh()
	_sync_ui()
	return {"ok": true, "code": "", "from": old_id, "to": new_id, "rewritten": rewritten}


func set_field(id: String, key: String, value) -> Dictionary:
	if key == "id":
		return rename_event(id, String(value))
	if not EDITABLE_KEYS.has(key):
		return {"ok": false, "code": "EV_FIELD_UNKNOWN"}
	var idx := find_index(id)
	if idx < 0:
		return {"ok": false, "code": "EV_NOT_FOUND"}
	if key == "channel" and not CHANNELS.has(String(value)):
		return {"ok": false, "code": "EV_CHANNEL"}
	if key == "at" and not _is_at_form(value):
		return {"ok": false, "code": "EV_AT_INVALID"}
	var pushed: Dictionary = store.apply_edit("set %s.%s" % [id, key], func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) == TYPE_ARRAY:
			((arr as Array)[idx] as Dictionary)[key] = value
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	refresh()
	_sync_ui()
	return {"ok": true, "code": ""}


func set_at_absolute(id: String, seconds: float) -> Dictionary:
	return set_field(id, "at", seconds)


func set_at_anchor(id: String, after_id: String, offset: float) -> Dictionary:
	if after_id == id:
		return {"ok": false, "code": "EV_ANCHOR_SELF"}
	if find_index(after_id) < 0:
		return {"ok": false, "code": "EV_ANCHOR_MISSING"}
	return set_field(id, "at", {"after": after_id, "offset": offset})


## One undo entry for the whole property panel.
func apply_props(id: String, fields: Dictionary) -> Dictionary:
	var idx := find_index(id)
	if idx < 0:
		return {"ok": false, "code": "EV_NOT_FOUND"}
	var new_id := String(fields.get("id", id))
	if new_id != id:
		if new_id.is_empty():
			return {"ok": false, "code": "EV_ID_INVALID"}
		if find_index(new_id) >= 0:
			return {"ok": false, "code": "EV_DUP_ID"}
	var at_value = fields.get("at", null)
	if at_value != null and not _is_at_form(at_value):
		return {"ok": false, "code": "EV_AT_INVALID"}
	var ch := String(fields.get("channel", ""))
	if not ch.is_empty() and not CHANNELS.has(ch):
		return {"ok": false, "code": "EV_CHANNEL"}
	var pushed: Dictionary = store.apply_edit("edit " + id, func(p):
		var arr = p.get("timeline", [])
		if typeof(arr) != TYPE_ARRAY:
			return
		var d: Dictionary = (arr as Array)[idx]
		if new_id != id:
			d["id"] = new_id
			for other in arr:
				if typeof(other) != TYPE_DICTIONARY:
					continue
				var oat = (other as Dictionary).get("at", null)
				if typeof(oat) == TYPE_DICTIONARY and String((oat as Dictionary).get("after", "")) == id:
					(oat as Dictionary)["after"] = new_id
		if not ch.is_empty():
			d["channel"] = ch
		if fields.has("type"):
			d["type"] = String(fields["type"])
		if at_value != null:
			d["at"] = at_value
		if fields.has("duration"):
			d["duration"] = float(fields["duration"])
		if fields.has("track"):
			var tr := String(fields["track"])
			if tr.is_empty():
				d.erase("track")
			else:
				d["track"] = tr
		if fields.has("order"):
			d["order"] = int(fields["order"])
		if fields.has("payload") and typeof(fields["payload"]) == TYPE_DICTIONARY:
			d["payload"] = (fields["payload"] as Dictionary).duplicate(true)
	)
	if not bool(pushed.get("ok", false)):
		return {"ok": false, "code": String(pushed.get("code", ""))}
	selected_id = new_id
	refresh()
	_sync_ui()
	return {"ok": true, "code": "", "id": new_id}


# -------------------------------------------------------------- validate/jump

func validate_now(strict_flag: bool = false) -> Dictionary:
	strict = strict_flag
	var guard = AssetGuard.new()
	guard.load_from(INDEX, allow_placeholders)
	var path: String = store.source_path
	if path.is_empty():
		path = "res://data/unsaved_project.json"
	report = Validator.validate_dictionary(store.project, path, guard, strict)
	_rebuild_error_rows()
	_sync_ui()
	return {
		"ok": report.ok,
		"errors": report.errors.size(),
		"warnings": report.warnings.size(),
		"stats": report.stats.duplicate(true),
		"codes": report.codes(),
	}


func _rebuild_error_rows() -> void:
	error_rows = []
	if report == null:
		return
	var ev_re := RegEx.create_from_string("timeline\\[(\\d+)\\]")
	var lvl_re := RegEx.create_from_string("levels\\[(\\d+)\\]")
	var slot_re := RegEx.create_from_string("board\\.slots\\[(\\d+)\\]")
	for e in report.errors:
		var m: Dictionary = e
		var path := String(m.get("path", ""))
		var row := {
			"code": String(m.get("code", "")),
			"path": path,
			"msg": String(m.get("msg", "")),
			"kind": "other",
			"index": -1,
			"event_id": "",
			"level": -1,
			"slot": Vector2i(-1, -1),
		}
		var lm := lvl_re.search(path)
		if lm != null:
			row["level"] = int(lm.get_string(1))
		var em := ev_re.search(path)
		if em != null:
			var idx := int(em.get_string(1))
			row["index"] = idx
			row["kind"] = "event"
			var t := timeline()
			if idx >= 0 and idx < t.size() and typeof(t[idx]) == TYPE_DICTIONARY:
				row["event_id"] = String((t[idx] as Dictionary).get("id", ""))
		else:
			var sm := slot_re.search(path)
			if sm != null and int(row["level"]) >= 0:
				row["kind"] = "slot"
				row["slot"] = _slot_coords(int(row["level"]), int(sm.get_string(1)))
		error_rows.append(row)


func _slot_coords(level_index: int, slot_index: int) -> Vector2i:
	var levels = store.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY or level_index >= (levels as Array).size():
		return Vector2i(-1, -1)
	var lvl = (levels as Array)[level_index]
	if typeof(lvl) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var board = (lvl as Dictionary).get("board", {})
	if typeof(board) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var slots = (board as Dictionary).get("slots", [])
	if typeof(slots) != TYPE_ARRAY or slot_index >= (slots as Array).size():
		return Vector2i(-1, -1)
	var s = (slots as Array)[slot_index]
	if typeof(s) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	return Vector2i(int((s as Dictionary).get("x", -1)), int((s as Dictionary).get("y", -1)))


## Clicking one row in the error list: select the event, or remember the cell.
func locate_error(row_index: int) -> Dictionary:
	if row_index < 0 or row_index >= error_rows.size():
		return {"ok": false, "code": "ERR_ROW"}
	var row: Dictionary = error_rows[row_index]
	match String(row["kind"]):
		"event":
			select(String(row["event_id"]))
			return {"ok": true, "kind": "event", "selected": selected_id, "path": String(row["path"])}
		"slot":
			focused_slot = row["slot"]
			select_event_at_slot(focused_slot)
			return {"ok": true, "kind": "slot", "slot": focused_slot, "path": String(row["path"])}
	return {"ok": false, "kind": String(row["kind"]), "path": String(row["path"]), "code": "ERR_NO_TARGET"}


## Best-effort: an event whose payload points at this slot gets selected too.
func select_event_at_slot(slot: Vector2i) -> String:
	for ev in timeline():
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var p = (ev as Dictionary).get("payload", {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		for key in ["slot", "target", "from", "to"]:
			if not (p as Dictionary).has(key):
				continue
			var v = (p as Dictionary)[key]
			if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("slot"):
				v = (v as Dictionary)["slot"]
			if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
				if int((v as Array)[0]) == slot.x and int((v as Array)[1]) == slot.y:
					select(String((ev as Dictionary).get("id", "")))
					return selected_id
	return ""


func select(id: String) -> void:
	if find_index(id) < 0:
		return
	selected_id = id
	_sync_ui()


func selected_event() -> Dictionary:
	return event_by_id(selected_id)


func selected_index() -> int:
	return find_index(selected_id)


# ------------------------------------------------------------------- playback

func _ensure_evaluator(reset: bool = false) -> void:
	if evaluator != null and not reset:
		return
	var pm = ProjectModel.new()
	pm.load_data(store.project)
	evaluator = Evaluator.new()
	evaluator.setup(pm, 0, null)
	evaluator.load_timeline(timeline())
	playhead = 0.0
	last_step = {}


## One event forward through the shared evaluator. Rebuilds at the end so the
## button is never a dead end.
func step_once() -> Dictionary:
	if evaluator == null or int(evaluator.cursor) >= (evaluator.events as Array).size():
		_ensure_evaluator(true)
	var r: Dictionary = evaluator.step()
	last_step = r
	playhead = float(r.get("at", playhead))
	if _ui.has("canvas"):
		(_ui["canvas"] as Control).queue_redraw()
	_update_play_label()
	return r


func play() -> void:
	_ensure_evaluator(evaluator == null or int(evaluator.cursor) >= (evaluator.events as Array).size())
	playing = true
	set_process(true)
	_update_play_label()


func pause() -> void:
	playing = false
	_update_play_label()


func toggle_play() -> void:
	if playing:
		pause()
	else:
		play()


func advance(dt: float) -> Dictionary:
	var stepped := 0
	if evaluator == null:
		return {"steps": 0, "playhead": playhead, "done": true}
	playhead += maxf(dt, 0.0)
	while int(evaluator.cursor) < (evaluator.events as Array).size():
		var ev: Dictionary = (evaluator.events as Array)[int(evaluator.cursor)]
		if float(ev.get("at", 0.0)) > playhead:
			break
		var r: Dictionary = evaluator.step()
		last_step = r
		stepped += 1
	var done := int(evaluator.cursor) >= (evaluator.events as Array).size()
	if done:
		playing = false
	if _ui.has("canvas"):
		(_ui["canvas"] as Control).queue_redraw()
	_update_play_label()
	return {"steps": stepped, "playhead": playhead, "done": done}


func reset_playback() -> void:
	_ensure_evaluator(true)
	playing = false
	if _ui.has("canvas"):
		(_ui["canvas"] as Control).queue_redraw()
	_update_play_label()


# --------------------------------------------------------------------- saving

func save() -> Dictionary:
	var r: Dictionary = store.save()
	status_text = "saved: %s" % String(r.get("path", "")) if bool(r.get("ok", false)) else "save failed: %s" % String(r.get("code", ""))
	_sync_ui()
	return r


func save_as(path: String) -> Dictionary:
	var r: Dictionary = store.save_as(path)
	_sync_ui()
	return r


func autosave_tick(now_seconds: float) -> Dictionary:
	var r: Dictionary = store.maybe_autosave(now_seconds)
	status_text = ("autosaved: %s" % String(r.get("path", ""))) if bool(r.get("written", false)) else status_text
	if bool(r.get("written", false)):
		_sync_ui()
	return r


func on_page_exit(now_seconds: float) -> Dictionary:
	return store.force_autosave(now_seconds)


func check_recovery() -> Dictionary:
	recovery = store.find_recovery(store.source_path)
	_sync_ui()
	return recovery


func apply_recovery() -> Dictionary:
	var r: Dictionary = store.restore_from_recovery()
	if bool(r.get("ok", false)):
		selected_id = ""
		refresh()
		_sync_ui()
	return r


func discard_recovery() -> Dictionary:
	var r: Dictionary = store.discard_recovery(store.source_path)
	recovery = {"found": false, "reason": ""}
	_sync_ui()
	return r


func status() -> Dictionary:
	return {
		"source": store.source_path,
		"dirty": store.dirty,
		"events": timeline().size(),
		"groups": groups.size(),
		"selected": selected_id,
		"errors": error_rows.size(),
		"playing": playing,
		"playhead": playhead,
		"undo": store.history.size(),
		"cursor": store.history.depth(),
		"can_undo": store.can_undo(),
		"can_redo": store.can_redo(),
	}


# ========================================================================== UI
# Everything below runs only when this Control is inside the tree. Headless tests
# exercise the data layer above and never touch a node.

class LaneCanvas extends Control:
	var host = null

	func _draw() -> void:
		if host != null:
			host.draw_lanes(self)

	func _gui_input(event: InputEvent) -> void:
		if host != null:
			host.on_canvas_input(self, event)


func _ready() -> void:
	if store == null:
		store = Store.new()
		store.load_file(SAMPLE, 0.0)
	_font = _load_font()
	_build_ui()
	refresh()
	_validate_and_show()
	check_recovery()
	set_process(false)
	print("[editor] ready %s" % str(status()))


func _process(delta: float) -> void:
	clock += delta
	if playing:
		advance(delta)
	autosave_tick(clock)


func _load_font() -> Font:
	if not FileAccess.file_exists(FONT_PATH):
		return null
	if ResourceLoader.exists(FONT_PATH):
		var res = load(FONT_PATH)
		if res is Font:
			return res
	# A project that was never opened in the editor has no import cache yet, so
	# fall back to reading the font file directly instead of failing.
	var ff := FontFile.new()
	if ff.load_dynamic_font(FONT_PATH) == OK:
		return ff
	return null


func draw_lanes(c: Control) -> void:
	var rect := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(rect, COLOR_PANEL_2)
	var label_w := 74.0
	var right := rect.size.x - 12.0
	var left := label_w + 8.0
	var lane_h := (rect.size.y - 34.0) / 3.0
	# time grid
	for i in range(0, int(TIMELINE_SECONDS) + 1, 5):
		var f := float(i) / TIMELINE_SECONDS
		var x := left + f * (right - left)
		c.draw_line(Vector2(x, 22.0), Vector2(x, rect.size.y - 6.0), Color(1, 1, 1, 0.07), 1.0)
		if _font != null:
			c.draw_string(_font, Vector2(x - 8.0, 18.0), "%ds" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_DIM)
	var lane_index := {}
	for i in CHANNELS.size():
		var ch: String = CHANNELS[i]
		lane_index[ch] = i
		var y := 26.0 + lane_h * i
		c.draw_rect(Rect2(0.0, y, rect.size.x, lane_h - 4.0), Color(1, 1, 1, 0.03))
		if _font != null:
			c.draw_string(_font, Vector2(8.0, y + lane_h * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LANE_COLORS[ch])
	# anchor connectors first
	var by_id := {}
	for b in lane_blocks():
		by_id[String((b as Dictionary)["id"])] = b
	for b in lane_blocks():
		var blk: Dictionary = b
		if String(blk["anchor"]).is_empty():
			continue
		var src = by_id.get(String(blk["anchor"]), null)
		if src == null:
			continue
		var li: int = int(lane_index.get(String(blk["channel"]), 0))
		var y0 := 26.0 + lane_h * li + lane_h * 0.5 - 2.0
		var x0 := left + float((src as Dictionary)["x"]) * (right - left)
		var x1 := left + float(blk["x"]) * (right - left)
		c.draw_line(Vector2(x0, y0), Vector2(x1, y0), Color(1, 1, 1, 0.18), 1.0)
	# blocks
	for b in lane_blocks():
		var blk: Dictionary = b
		var li: int = int(lane_index.get(String(blk["channel"]), 0))
		var y := 26.0 + lane_h * li
		var x := left + float(blk["x"]) * (right - left)
		var w := maxf(float(blk["w"]) * (right - left), 8.0)
		w = minf(w, right - x)
		var r := Rect2(x, y + 6.0, w, lane_h - 16.0)
		var base: Color = LANE_COLORS.get(String(blk["channel"]), COLOR_DIM)
		c.draw_rect(r, Color(base.r, base.g, base.b, 0.55))
		if not String(blk["anchor"]).is_empty():
			# anchor events are drawn hollow and flagged with a small notch
			c.draw_rect(r, base, false, 1.0)
			c.draw_rect(Rect2(r.position, Vector2(minf(4.0, r.size.x), r.size.y)), COLOR_WARN)
		if bool(blk["selected"]):
			c.draw_rect(r.grow(2.0), COLOR_INK, false, 2.0)
		if _font != null and r.size.x > 26.0:
			var label := String(blk["id"])
			if not String(blk.get("anchor", "")).is_empty() and float(blk["offset"]) != 0.0:
				label = "%s%+.1f" % [label, float(blk["offset"])]
			c.draw_string(_font, Vector2(r.position.x + 3.0, r.position.y + r.size.y * 0.72),
				label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4.0, 11, COLOR_INK)
	# playhead
	var px := left + clampf(playhead / TIMELINE_SECONDS, 0.0, 1.0) * (right - left)
	c.draw_line(Vector2(px, 20.0), Vector2(px, rect.size.y - 4.0), COLOR_ERR, 2.0)


func on_canvas_input(c: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var label_w := 74.0 + 8.0
		var right := c.size.x - 12.0
		var frac := clampf((event.position.x - label_w) / maxf(right - label_w, 1.0), 0.0, 1.0)
		playhead = frac * TIMELINE_SECONDS
		if evaluator != null:
			# seeking rewinds and replays to the target so sim state stays honest
			_ensure_evaluator(true)
			while int(evaluator.cursor) < (evaluator.events as Array).size():
				var ev: Dictionary = (evaluator.events as Array)[int(evaluator.cursor)]
				if float(ev.get("at", 0.0)) > playhead:
					break
				last_step = evaluator.step()
		c.queue_redraw()
		_update_play_label()


# ------------------------------------------------------------------ ui builder

func _mk_theme() -> Theme:
	var th := Theme.new()
	if _font != null:
		th.default_font = _font
	th.default_font_size = 15
	return th


func _panel(parent: Node, rect: Rect2, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = rect.position
	box.size = rect.size
	box.add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", COLOR_DIM)
	box.add_child(head)
	parent.add_child(box)
	return box


func _build_ui() -> void:
	theme = _mk_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = COLOR_PAGE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ---- toolbar
	var bar := HBoxContainer.new()
	bar.position = Vector2(14, 8)
	bar.size = Vector2(1052, 42)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	bar.add_child(_btn("Validate", func(): _validate_and_show()))
	bar.add_child(_btn("Step", func(): step_once()))
	bar.add_child(_btn("Play/Pause", func(): toggle_play()))
	bar.add_child(_btn("Undo", func(): _on_undo()))
	bar.add_child(_btn("Redo", func(): _on_redo()))
	bar.add_child(_btn("Save", func(): save()))
	bar.add_child(_btn("Save As", func(): _on_save_as()))
	bar.add_child(_btn("Recover", func(): _on_recover()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", COLOR_DIM)
	status.name = "StatusLabel"
	bar.add_child(status)
	_ui["status"] = status

	# ---- left: groups + list
	var left := _panel(self, Rect2(14, 58, 340, 1212), "events (channel / track)")
	var adder := HBoxContainer.new()
	adder.add_theme_constant_override("separation", 4)
	left.add_child(adder)
	var ch_opt := OptionButton.new()
	for ch in CHANNELS:
		ch_opt.add_item(ch)
	ch_opt.item_selected.connect(func(_i): _refresh_type_options())
	ch_opt.custom_minimum_size = Vector2(74, 0)
	adder.add_child(ch_opt)
	var ty_opt := OptionButton.new()
	ty_opt.custom_minimum_size = Vector2(120, 0)
	adder.add_child(ty_opt)
	adder.add_child(_btn("Add", func(): _on_add()))
	_ui["add_channel"] = ch_opt
	_ui["add_type"] = ty_opt

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	_ui["list_box"] = list_box

	# ---- center: lanes + error list
	var mid := _panel(self, Rect2(364, 58, 702, 306), "timeline 0-30s")
	var canvas := LaneCanvas.new()
	canvas.host = self
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(690, 260)
	mid.add_child(canvas)
	_ui["canvas"] = canvas

	var err := _panel(self, Rect2(364, 372, 702, 300), "validation errors (click to jump)")
	var err_list := ItemList.new()
	err_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	err_list.item_selected.connect(func(i): _on_error_selected(i))
	err.add_child(err_list)
	_ui["errors"] = err_list

	# ---- right column: properties
	var props := _panel(self, Rect2(364, 680, 702, 1224), "event properties")
	var ps := ScrollContainer.new()
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props.add_child(ps)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 3)
	ps.add_child(form)

	_ui["f_id"] = _field_line(form, "id")
	_ui["f_channel"] = _field_option(form, "channel", CHANNELS)
	_ui["f_type"] = _field_option(form, "type", [])
	_ui["f_at_mode"] = _field_option(form, "at mode", ["absolute", "anchor"])
	_ui["f_at"] = _field_num(form, "at (seconds)", 0.0, 30.0, 0.1)
	_ui["f_anchor"] = _field_option(form, "after (event id)", [])
	_ui["f_offset"] = _field_num(form, "offset (seconds)", -30.0, 30.0, 0.1)
	_ui["f_duration"] = _field_num(form, "duration", 0.0, 30.0, 0.1)
	_ui["f_track"] = _field_line(form, "track")
	_ui["f_order"] = _field_num(form, "order", -100, 100, 1)
	_ui["f_payload"] = _field_text(form, "payload (JSON)")

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	form.add_child(actions)
	actions.add_child(_btn("Apply", func(): _on_apply()))
	actions.add_child(_btn("Delete", func(): _on_delete()))
	actions.add_child(_btn("Duplicate", func(): _on_duplicate()))

	(_ui["f_at_mode"] as OptionButton).item_selected.connect(func(_i): _sync_at_mode())
	(_ui["f_channel"] as OptionButton).item_selected.connect(func(_i): _refresh_field_types())
	(_ui["f_type"] as OptionButton).item_selected.connect(func(_i): pass)

	_refresh_type_options()


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _field_line(parent: Node, label: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_color_override("font_color", COLOR_DIM)
	row.add_child(l)
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	parent.add_child(row)
	return e


func _field_num(parent: Node, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_color_override("font_color", COLOR_DIM)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	parent.add_child(row)
	return s


func _field_option(parent: Node, label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_color_override("font_color", COLOR_DIM)
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	parent.add_child(row)
	return o


func _field_text(parent: Node, label: String) -> TextEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_color_override("font_color", COLOR_DIM)
	row.add_child(l)
	var t := TextEdit.new()
	t.custom_minimum_size = Vector2(0, 96)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	parent.add_child(row)
	return t


# ---------------------------------------------------------------- ui plumbing

func _refresh_type_options() -> void:
	if not _ui.has("add_type"):
		return
	var ch: String = String(CHANNELS[(_ui["add_channel"] as OptionButton).selected])
	var o: OptionButton = _ui["add_type"]
	o.clear()
	for t in EventModel.known_types(ch):
		o.add_item(String(t))
	o.add_item("wait")


func _refresh_field_types() -> void:
	if not _ui.has("f_type"):
		return
	var ch: String = String(CHANNELS[(_ui["f_channel"] as OptionButton).selected])
	var o: OptionButton = _ui["f_type"]
	var keep := _opt_text(o)
	o.clear()
	var types: Array = EventModel.known_types(ch).duplicate()
	if not keep.is_empty() and not types.has(keep):
		types.append(keep)
	for t in types:
		o.add_item(String(t))
	for i in o.item_count:
		if o.get_item_text(i) == keep:
			o.select(i)
			break


static func _opt_text(o: OptionButton) -> String:
	if o == null or o.item_count == 0:
		return ""
	var idx := o.selected
	if idx < 0 or idx >= o.item_count:
		idx = 0
	return o.get_item_text(idx)


func _sync_at_mode() -> void:
	var anchor_mode := (_ui["f_at_mode"] as OptionButton).selected == 1
	(_ui["f_at"] as SpinBox).editable = not anchor_mode
	(_ui["f_anchor"] as OptionButton).disabled = not anchor_mode
	(_ui["f_offset"] as SpinBox).editable = anchor_mode


func _sync_ui() -> void:
	if not _ui.has("list_box"):
		return
	_rebuild_list()
	_sync_props()
	_sync_errors()
	_update_status_label()
	_update_play_label()
	if _ui.has("canvas"):
		(_ui["canvas"] as Control).queue_redraw()
	(_ui["f_anchor"] as OptionButton).clear()
	for id in anchor_ids():
		(_ui["f_anchor"] as OptionButton).add_item(String(id))


func _rebuild_list() -> void:
	var box: VBoxContainer = _ui["list_box"]
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for item in display_rows():
		var d: Dictionary = item
		if String(d["kind"]) == "group":
			var h := Button.new()
			var mark := "v" if bool(d["open"]) else ">"
			h.text = "%s %s / %s  (%d)" % [mark, String(d["channel"]), String(d["track"]) if not String(d["track"]).is_empty() else "-", int(d["count"])]
			h.alignment = HORIZONTAL_ALIGNMENT_LEFT
			h.add_theme_font_size_override("font_size", 13)
			var key := String(d["key"])
			h.pressed.connect(func(): toggle_group(key))
			box.add_child(h)
			continue
		var row: Dictionary = d["row"]
		var b := Button.new()
		var at_txt := "%.2fs" % float(row["at"]) if float(row["at"]) >= 0.0 else "?s"
		var anchor_txt := ""
		if not String(row["anchor"]).is_empty():
			anchor_txt = " <-%s" % String(row["anchor"])
		var mark := "*" if String(row["id"]) == selected_id else " "
		b.text = "%s %s  %-6s %-10s %s%s" % [mark, String(row["id"]), String(row["channel"]), String(row["type"]), at_txt, anchor_txt]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		if String(row["id"]) == selected_id:
			b.add_theme_color_override("font_color", COLOR_WARN)
		var id := String(row["id"])
		b.pressed.connect(func(): select(id))
		box.add_child(b)


func _sync_props() -> void:
	var ev := selected_event()
	var disabled := ev.is_empty()
	for key in ["f_id", "f_at", "f_offset", "f_duration", "f_track", "f_order", "f_payload"]:
		if not _ui.has(key):
			continue
		var w = _ui[key]
		if w is LineEdit or w is SpinBox or w is TextEdit:
			w.editable = not disabled
	if disabled:
		if _ui.has("f_id"):
			(_ui["f_id"] as LineEdit).text = ""
		if _ui.has("f_payload"):
			(_ui["f_payload"] as TextEdit).text = ""
		return
	(_ui["f_id"] as LineEdit).text = String(ev.get("id", ""))
	var ch := String(ev.get("channel", "sim"))
	var ci: int = CHANNELS.find(ch)
	(_ui["f_channel"] as OptionButton).select(maxi(ci, 0))
	_refresh_field_types()
	var to: OptionButton = _ui["f_type"]
	for i in to.item_count:
		if to.get_item_text(i) == String(ev.get("type", "")):
			to.select(i)
			break
	var at = ev.get("at", 0.0)
	var anchor_mode := typeof(at) == TYPE_DICTIONARY
	(_ui["f_at_mode"] as OptionButton).select(1 if anchor_mode else 0)
	if anchor_mode:
		var after := String((at as Dictionary).get("after", ""))
		var off := float((at as Dictionary).get("offset", 0.0))
		var ao: OptionButton = _ui["f_anchor"]
		for i in ao.item_count:
			if ao.get_item_text(i) == after:
				ao.select(i)
				break
		(_ui["f_offset"] as SpinBox).value = off
	else:
		(_ui["f_at"] as SpinBox).value = float(at) if typeof(at) == TYPE_INT or typeof(at) == TYPE_FLOAT else 0.0
	var raw_dur = ev.get("duration", 0)
	(_ui["f_duration"] as SpinBox).value = float(raw_dur) if typeof(raw_dur) == TYPE_INT or typeof(raw_dur) == TYPE_FLOAT else 0.0
	(_ui["f_track"] as LineEdit).text = String(ev.get("track", ""))
	var raw_ord = ev.get("order", 0)
	(_ui["f_order"] as SpinBox).value = float(raw_ord) if typeof(raw_ord) == TYPE_INT or typeof(raw_ord) == TYPE_FLOAT else 0.0
	(_ui["f_payload"] as TextEdit).text = JSON.stringify(ev.get("payload", {}), "  ", false)
	_sync_at_mode()


func _sync_errors() -> void:
	if not _ui.has("errors"):
		return
	var list: ItemList = _ui["errors"]
	list.clear()
	if error_rows.is_empty():
		list.add_item("ok - 0 errors, 0 warnings")
	for row in error_rows:
		var d: Dictionary = row
		var tag := "[%s]" % String(d["kind"])
		var where := String(d["event_id"]) if not String(d["event_id"]).is_empty() else String(d["path"])
		list.add_item("%s %-24s %-14s %s" % [tag, String(d["code"]), where, String(d["msg"])])


func _update_status_label() -> void:
	if not _ui.has("status"):
		return
	var s := status()
	var head := "dirty" if bool(s["dirty"]) else "clean"
	var label: Label = _ui["status"]
	label.text = "%s | %s | events=%d | err=%d | undo=%d/%d" % [
		head, String(s["source"]).get_file(), int(s["events"]), int(s["errors"]), int(s["cursor"]), int(s["undo"]),
	]


func _update_play_label() -> void:
	if not _ui.has("status"):
		return
	_update_status_label()


# ----------------------------------------------------------------- ui actions

func _validate_and_show() -> void:
	var r := validate_now()
	status_text = "validate ok=%s errors=%d warnings=%d" % [str(r["ok"]), int(r["errors"]), int(r["warnings"])]
	if _ui.has("status"):
		_update_status_label()


func _on_add() -> void:
	var ch: String = CHANNELS[(_ui["add_channel"] as OptionButton).selected]
	var to: OptionButton = _ui["add_type"]
	var type_id := _opt_text(to)
	var at_abs := float(int(playhead * 10.0)) / 10.0
	var r: Dictionary = add_event(ch, type_id, at_abs, {}, {"allow_unregistered": true})
	if not bool(r.get("ok", false)):
		status_text = "add failed: %s" % String(r.get("code", ""))


func _on_delete() -> void:
	if selected_id.is_empty():
		return
	var r: Dictionary = delete_event(selected_id)
	if not bool(r.get("ok", false)):
		status_text = "delete failed: %s" % String(r.get("code", ""))


func _on_duplicate() -> void:
	if selected_id.is_empty():
		return
	duplicate_event(selected_id)


func _on_apply() -> void:
	if selected_id.is_empty():
		return
	var fields := {"id": (_ui["f_id"] as LineEdit).text}
	fields["channel"] = CHANNELS[(_ui["f_channel"] as OptionButton).selected]
	fields["type"] = _opt_text(_ui["f_type"])
	if (_ui["f_at_mode"] as OptionButton).selected == 1:
		var ao: OptionButton = _ui["f_anchor"]
		if ao.item_count == 0:
			status_text = "apply failed: no anchor id available"
			return
		fields["at"] = {"after": ao.get_item_text(ao.selected), "offset": float((_ui["f_offset"] as SpinBox).value)}
	else:
		fields["at"] = float((_ui["f_at"] as SpinBox).value)
	fields["duration"] = float((_ui["f_duration"] as SpinBox).value)
	fields["track"] = (_ui["f_track"] as LineEdit).text
	fields["order"] = int((_ui["f_order"] as SpinBox).value)
	var payload_text := (_ui["f_payload"] as TextEdit).text
	var parsed = JSON.parse_string(payload_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		status_text = "apply failed: payload is not a JSON object"
		return
	fields["payload"] = parsed
	var r: Dictionary = apply_props(selected_id, fields)
	if not bool(r.get("ok", false)):
		status_text = "apply failed: %s" % String(r.get("code", ""))


func _on_undo() -> void:
	var r: Dictionary = store.undo()
	if bool(r.get("ok", false)):
		selected_id = ""
		refresh()
		_sync_ui()
	else:
		status_text = "undo: %s" % String(r.get("code", ""))


func _on_redo() -> void:
	var r: Dictionary = store.redo()
	if bool(r.get("ok", false)):
		selected_id = ""
		refresh()
		_sync_ui()
	else:
		status_text = "redo: %s" % String(r.get("code", ""))


func _on_save_as() -> void:
	var target := "user://project_variant.json"
	var r: Dictionary = save_as(target)
	status_text = "save as %s -> %s" % [target, str(r.get("ok", false))]


func _on_recover() -> void:
	var found := check_recovery()
	if not bool(found.get("found", false)):
		status_text = "recovery: %s" % String(found.get("reason", ""))
		return
	var r: Dictionary = apply_recovery()
	status_text = "recovered saved_at=%d" % int(r.get("saved_at", 0)) if bool(r.get("ok", false)) else "recover failed"


func _on_error_selected(i: int) -> void:
	var r: Dictionary = locate_error(i)
	status_text = "jump %s %s" % [String(r.get("kind", "")), String(r.get("path", ""))]
	if _ui.has("status"):
		_update_status_label()
	if _ui.has("list_box"):
		_rebuild_list()
