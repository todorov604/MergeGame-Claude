extends RefCounted
## Timeline rules (event model v2): channel / registered type / anchor form /
## `wait` ban / duration / field types / sim payload contract / locale keys /
## total length.
##
## Anchor resolution and sorting are delegated to src/core/event_model.gd — the same
## resolver the S2 sim/view dispatcher will use, so the validator cannot drift from
## playback behaviour.
##
## Type guards: `String(5)` is a runtime SCRIPT ERROR in GDScript and a runtime error
## only aborts the innermost function, so an unguarded conversion would silently
## truncate this rule and still leave the report green. Every identifier is read with
## Ctx.as_str / Ctx.is_string and a wrong type is reported as EV_FIELD_TYPE.

const Ctx = preload("res://src/validate/validate_ctx.gd")
const EventModel = preload("res://src/core/event_model.gd")

const KNOWN_CHANNELS := ["sim", "view", "audio"]

## Sim payload contract. Every entry mirrors what src/core/sim.gd actually reads:
##   _do_tap          -> target.slot
##   _do_merge        -> from / to
##   _do_deliver      -> order + from
##   _do_order_claim  -> order
##   _do_energy_tick  -> delta
##   _do_level_next / _do_board_full / _do_level_complete take the payload as-is,
##   but the dispatcher still requires an object.
const SIM_PAYLOAD_TYPES := [
	"tap", "drag", "merge", "deliver", "order_claim",
	"board_full", "energy_tick", "level_complete", "level_next",
]


static func check(ctx) -> void:
	var timeline = ctx.project.get("timeline", [])
	if typeof(timeline) != TYPE_ARRAY:
		ctx.err("SCHEMA_TYPE", "timeline", "timeline must be an array")
		ctx.rule_done()
		return
	ctx.stats["events"] = timeline.size()

	var meta = ctx.project.get("meta", {})
	var locale := ""
	var locale_type_ok := true
	var locale_table := {}
	if typeof(meta) == TYPE_DICTIONARY:
		var raw_locale = (meta as Dictionary).get("locale", null)
		locale_type_ok = Ctx.is_string(raw_locale)
		locale = Ctx.as_str(raw_locale)
	var locales = ctx.project.get("locales", {})
	if typeof(locales) == TYPE_DICTIONARY and (locales as Dictionary).has(locale):
		var t = (locales as Dictionary)[locale]
		if typeof(t) == TYPE_DICTIONARY:
			locale_table = t

	for i in timeline.size():
		_check_raw_event(ctx, timeline[i], i)

	var r: Dictionary = EventModel.resolve(timeline)
	for e in r["errors"]:
		ctx.err(Ctx.as_str(e.get("code", "")), Ctx.as_str(e.get("path", "")), Ctx.as_str(e.get("msg", "")))

	ctx.stats["end_time"] = r["end_time"]
	ctx.stats["events_resolved"] = (r["events"] as Array).size()
	if float(r["end_time"]) > EventModel.M0_MAX_TIMELINE_SECONDS + 0.0001:
		ctx.warn("TIMELINE_END_OVER", "timeline", "timeline ends at %.2fs, above the M0 30s template" % float(r["end_time"]))

	_check_resolved(ctx, r["events"], locale, locale_table, locale_type_ok)
	ctx.rule_done()


# ------------------------------------------------------------ raw event shape

static func _check_raw_event(ctx, ev, i: int) -> void:
	var base := "timeline[%d]" % i
	if typeof(ev) != TYPE_DICTIONARY:
		ctx.err("EV_NOT_OBJECT", base, "event must be an object")
		return
	var evd: Dictionary = ev

	# ---- id: absent is EV_ID_MISSING from the resolver; a wrong type is reported here
	if evd.has("id") and not Ctx.is_string(evd["id"]):
		ctx.err("EV_FIELD_TYPE", base + ".id", "event id must be a string (got %s)" % Ctx.type_name_of(evd["id"]))

	# ---- channel
	var ch := Ctx.as_str(evd.get("channel", null))
	if not evd.has("channel") or typeof(evd["channel"]) == TYPE_NIL:
		ctx.err("EV_CHANNEL", base + ".channel", "channel must be one of %s (got \"\")" % str(KNOWN_CHANNELS))
	elif not Ctx.is_string(evd["channel"]):
		ctx.err("EV_FIELD_TYPE", base + ".channel", "channel must be a string (got %s)" % Ctx.type_name_of(evd["channel"]))
	elif not KNOWN_CHANNELS.has(ch):
		ctx.err("EV_CHANNEL", base + ".channel", "channel must be one of %s (got \"%s\")" % [str(KNOWN_CHANNELS), ch])

	# ---- type
	var tp := Ctx.as_str(evd.get("type", null))
	if evd.has("type") and not Ctx.is_string(evd["type"]):
		ctx.err("EV_FIELD_TYPE", base + ".type", "type must be a string (got %s)" % Ctx.type_name_of(evd["type"]))
	elif KNOWN_CHANNELS.has(ch) and not EventModel.type_registered(ch, tp):
		ctx.err("EV_TYPE_UNKNOWN", base + ".type", "type \"%s\" is not registered for channel \"%s\"" % [tp, ch])
	if tp == "wait":
		ctx.err("EV_WAIT_FORBIDDEN", base + ".type", "`wait` events are forbidden; express gaps with time or {after, offset}")

	# ---- optional scalar fields: typed when present
	if evd.has("track") and not Ctx.is_string(evd["track"]):
		ctx.err("EV_FIELD_TYPE", base + ".track", "track must be a string (got %s)" % Ctx.type_name_of(evd["track"]))
	if evd.has("order") and not Ctx.is_num(evd["order"]):
		ctx.err("EV_FIELD_TYPE", base + ".order", "order must be a number (got %s)" % Ctx.type_name_of(evd["order"]))

	# ---- at: absolute seconds or {after: <event id>, offset: <seconds>}
	if evd.has("at"):
		var at = evd["at"]
		if typeof(at) == TYPE_DICTIONARY:
			var atd: Dictionary = at
			if atd.has("after") and not Ctx.is_string(atd["after"]):
				ctx.err("EV_FIELD_TYPE", base + ".at.after", "at.after must be an event id string (got %s)" % Ctx.type_name_of(atd["after"]))
			if atd.has("offset") and not Ctx.is_num(atd["offset"]):
				ctx.err("EV_FIELD_TYPE", base + ".at.offset", "at.offset must be a number (got %s)" % Ctx.type_name_of(atd["offset"]))
		elif not Ctx.is_num(at):
			ctx.err("EV_FIELD_TYPE", base + ".at", "at must be a number or {after: <id>, offset: <seconds>} (got %s)" % Ctx.type_name_of(at))

	# ---- duration
	if evd.has("duration"):
		var d = evd["duration"]
		if not Ctx.is_num(d):
			ctx.err("EV_FIELD_TYPE", base + ".duration", "duration must be a number (got %s)" % Ctx.type_name_of(d))
		elif float(d) < 0.0:
			ctx.err("EV_DURATION_NEG", base + ".duration", "duration must be a number >= 0")

	# ---- payload container
	if not evd.has("payload"):
		ctx.err("EV_PAYLOAD_MISSING", base + ".payload", "payload is required")
	elif typeof(evd["payload"]) != TYPE_DICTIONARY:
		ctx.err("SCHEMA_TYPE", base + ".payload", "payload must be an object")


# --------------------------------------------------------- resolved event rules

static func _check_resolved(ctx, events: Array, locale: String, locale_table: Dictionary, locale_type_ok: bool) -> void:
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var evd: Dictionary = ev
		var channel := Ctx.as_str(evd.get("channel", ""))
		var type := Ctx.as_str(evd.get("type", ""))
		var idx := int(evd.get("index", 0))
		if channel == "sim":
			_check_sim_payload(ctx, evd, type, idx)
		if channel != "view":
			continue
		# text keys must exist in the active locale (locales table is P0 in M0)
		var p = evd.get("payload", {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var tk = (p as Dictionary).get("text_key", null)
		if not Ctx.is_string(tk):
			continue
		if not locale_type_ok:
			continue  # meta.locale is mistyped; the schema rule owns that error
		var key := String(tk)
		if not locale_table.has(key):
			ctx.err("LOCALE_KEY_MISSING", "timeline[%d].payload.text_key" % idx, "text_key \"%s\" is missing from locales.%s" % [key, locale])


## Validated against the real handler in src/core/sim.gd, so playback cannot fail on
## a shape the validator accepted.
static func _check_sim_payload(ctx, ev: Dictionary, type: String, idx: int) -> void:
	if not SIM_PAYLOAD_TYPES.has(type):
		return
	var base := "timeline[%d].payload" % idx
	var p = ev.get("payload", null)
	if typeof(p) != TYPE_DICTIONARY:
		ctx.err("EV_PAYLOAD_SHAPE", base, "%s needs a payload object (got %s)" % [type, Ctx.type_name_of(p)])
		return
	var pd: Dictionary = p
	match type:
		"tap":
			var target = pd.get("target", null)
			if typeof(target) != TYPE_DICTIONARY:
				ctx.err("EV_PAYLOAD_SHAPE", base + ".target", "tap needs payload.target = {slot: [x, y]} (got %s)" % Ctx.type_name_of(target))
			elif not _is_xy((target as Dictionary).get("slot", null)):
				ctx.err("EV_PAYLOAD_SHAPE", base + ".target.slot", "tap needs target.slot = [x, y], two integers (got %s)" % _shape_of((target as Dictionary).get("slot", null)))
		"merge":
			_require_xy(ctx, pd, "from", base, type)
			_require_xy(ctx, pd, "to", base, type)
		"drag":
			_require_xy(ctx, pd, "from", base, type)
			_require_xy(ctx, pd, "to", base, type)
		"deliver":
			_require_order(ctx, pd, base, type)
			_require_xy(ctx, pd, "from", base, type)
		"order_claim":
			_require_order(ctx, pd, base, type)
		"energy_tick":
			if not Ctx.is_num(pd.get("delta", null)):
				ctx.err("EV_PAYLOAD_SHAPE", base + ".delta", "energy_tick needs payload.delta = <number> (got %s)" % Ctx.type_name_of(pd.get("delta", null)))
		"board_full", "level_complete", "level_next":
			pass  # no fields, but the container above must still be an object


static func _is_xy(v) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var a: Array = v
	if a.size() < 2:
		return false
	return Ctx.is_int_val(a[0]) and Ctx.is_int_val(a[1])


static func _shape_of(v) -> String:
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		var parts: Array = []
		for i in a.size():
			parts.append(Ctx.type_name_of(a[i]))
		return "[%s]" % ", ".join(parts)
	return Ctx.type_name_of(v)


static func _require_xy(ctx, payload: Dictionary, key: String, base: String, type: String) -> void:
	var v = payload.get(key, null)
	if _is_xy(v):
		return
	ctx.err("EV_PAYLOAD_SHAPE", "%s.%s" % [base, key], "%s needs payload.%s = [x, y], two integers (got %s)" % [type, key, _shape_of(v)])


static func _require_order(ctx, payload: Dictionary, base: String, type: String) -> void:
	var v = payload.get("order", null)
	if Ctx.is_string(v) and not String(v).is_empty():
		return
	ctx.err("EV_PAYLOAD_SHAPE", base + ".order", "%s needs payload.order = <non-empty string> (got %s)" % [type, Ctx.type_name_of(v)])
