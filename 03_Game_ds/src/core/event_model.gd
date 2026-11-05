extends RefCounted
## M0 event model v2 — the single anchor resolver + deterministic sorter.
##
## The validator uses it (S1) and the core sim/view dispatcher will use the very
## same object (S2), so "sim/view 共用一个求值器" is structural, not a promise.
##
## Rules implemented here:
##   * `at` is either absolute seconds, or {after: <event id>, offset: <seconds>}
##   * no `wait` events (rejected by the timeline rule module, listed here for clarity)
##   * sort key: at -> channel priority (sim=0, view=1, audio=2) -> track -> order -> id
##   * cycles / missing anchors / self anchors are reported, never looped on

const CHANNEL_PRIORITY := {"sim": 0, "view": 1, "audio": 2}

const SIM_TYPES := [
	"tap", "drag", "swap", "merge", "deliver", "order_claim",
	"board_full", "energy_tick", "level_complete", "level_next",
]
const VIEW_TYPES := [
	"camera", "text", "highlight", "select", "hint", "star_fly",
	"coin_popup", "character_leave", "character_next", "levelup", "cta", "transition",
]
const AUDIO_TYPES := ["bgm", "sfx", "stop"]

const M0_MAX_TIMELINE_SECONDS := 30.0


static func known_types(channel: String) -> Array:
	match channel:
		"sim":
			return SIM_TYPES
		"view":
			return VIEW_TYPES
		"audio":
			return AUDIO_TYPES
	return []


static func type_registered(channel: String, type: String) -> bool:
	return known_types(channel).has(type)


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## `String(v)` is a runtime SCRIPT ERROR for a number, a bool or an object, not a
## conversion — and a runtime error aborts the whole resolve() call, leaving the
## caller with null and the validation report falsely green. Every identifier is
## read through this guard instead; a wrong type simply resolves to "" and the
## rule modules report it as a field-type error.
static func _s(v) -> String:
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v)
	return ""


## Resolves anchors and returns:
##   { ok, errors:[{code,path,msg}], events:[resolved...], end_time:float, start_time:float }
## A resolved event keeps `raw` (the original dictionary) plus parsed fields.
static func resolve(events: Array) -> Dictionary:
	var errors: Array = []
	var by_id := {}

	# --- pass 1: ids ---
	for i in events.size():
		var ev = events[i]
		if typeof(ev) != TYPE_DICTIONARY:
			errors.append({"code": "EV_NOT_OBJECT", "path": "timeline[%d]" % i, "msg": "event must be an object"})
			continue
		var id := _s(ev.get("id", ""))
		if id.is_empty():
			errors.append({"code": "EV_ID_MISSING", "path": "timeline[%d].id" % i, "msg": "event id is required"})
			continue
		if by_id.has(id):
			errors.append({"code": "EV_DUP_ID", "path": "timeline[%d].id" % i, "msg": "duplicate event id \"%s\"" % id})
			continue
		by_id[id] = i

	# --- pass 2: absolute times / anchors ---
	var abs_times := {}
	var pending: Array = []
	for i in events.size():
		var ev = events[i]
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var id := _s(ev.get("id", ""))
		if id.is_empty() or int(by_id.get(id, -1)) != i:
			continue
		var at = ev.get("at", null)
		if _is_num(at):
			if float(at) < 0.0:
				errors.append({"code": "EV_AT_NEGATIVE", "path": "timeline[%d].at" % i, "msg": "at must be >= 0 (got %s)" % str(at)})
				continue
			abs_times[id] = float(at)
			continue
		if typeof(at) == TYPE_DICTIONARY:
			var after := _s(at.get("after", ""))
			var off = at.get("offset", 0.0)
			if after.is_empty():
				errors.append({"code": "EV_AT_INVALID", "path": "timeline[%d].at" % i, "msg": "anchor form is {after: <id>, offset: <seconds>}"})
				continue
			if after == id:
				errors.append({"code": "EV_ANCHOR_SELF", "path": "timeline[%d].at.after" % i, "msg": "event \"%s\" anchors to itself" % id})
				continue
			if not by_id.has(after):
				errors.append({"code": "EV_ANCHOR_MISSING", "path": "timeline[%d].at.after" % i, "msg": "anchor \"%s\" is not a defined event id" % after})
				continue
			if not _is_num(off):
				errors.append({"code": "EV_AT_INVALID", "path": "timeline[%d].at.offset" % i, "msg": "offset must be a number"})
				continue
			pending.append({"i": i, "id": id, "after": after, "offset": float(off)})
			continue
		errors.append({"code": "EV_AT_MISSING", "path": "timeline[%d].at" % i, "msg": "at is required (absolute seconds or {after, offset})"})

	# --- pass 3: iterative anchor resolution (no recursion, no infinite loop) ---
	var budget := pending.size() + 2
	while not pending.is_empty() and budget > 0:
		budget -= 1
		var still: Array = []
		var progressed := false
		for p in pending:
			if abs_times.has(p["after"]):
				var t: float = float(abs_times[p["after"]]) + float(p["offset"])
				progressed = true
				if t < 0.0:
					errors.append({"code": "EV_AT_NEGATIVE", "path": "timeline[%d].at" % int(p["i"]), "msg": "resolved time is negative (%.3f)" % t})
				else:
					abs_times[p["id"]] = t
			else:
				still.append(p)
		pending = still
		if not progressed:
			break
	if not pending.is_empty():
		for p in pending:
			errors.append({
				"code": "EV_ANCHOR_CYCLE",
				"path": "timeline[%d].at.after" % int(p["i"]),
				"msg": "anchor chain never resolves (cycle): \"%s\" after \"%s\"" % [p["id"], p["after"]],
			})

	# --- pass 4: build resolved list ---
	var resolved: Array = []
	for i in events.size():
		var ev = events[i]
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var id := _s(ev.get("id", ""))
		if not abs_times.has(id):
			continue
		var dur = ev.get("duration", 0.0)
		var durf := 0.0
		if _is_num(dur):
			durf = float(dur)
		var ordv = ev.get("order", 0)
		var ord := 0
		if _is_num(ordv):
			ord = int(ordv)
		resolved.append({
			"id": id,
			"channel": _s(ev.get("channel", "")),
			"type": _s(ev.get("type", "")),
			"at": float(abs_times[id]),
			"duration": durf,
			"track": _s(ev.get("track", "")),
			"order": ord,
			"payload": ev.get("payload", {}),
			"index": i,
			"raw": ev,
		})

	resolved.sort_custom(func(a, b):
		if a["at"] < b["at"]:
			return true
		if a["at"] > b["at"]:
			return false
		var pa: int = int(CHANNEL_PRIORITY.get(a["channel"], 9))
		var pb: int = int(CHANNEL_PRIORITY.get(b["channel"], 9))
		if pa != pb:
			return pa < pb
		if str(a["track"]) != str(b["track"]):
			return str(a["track"]) < str(b["track"])
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return str(a["id"]) < str(b["id"])
	)

	var end_time := 0.0
	var start_time := 0.0
	if not resolved.is_empty():
		start_time = float(resolved[0]["at"])
		for r in resolved:
			end_time = maxf(end_time, float(r["at"]) + float(r["duration"]))

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"events": resolved,
		"end_time": end_time,
		"start_time": start_time,
		"by_id": by_id,
	}
