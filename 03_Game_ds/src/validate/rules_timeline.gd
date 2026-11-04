extends RefCounted
## Timeline rules (event model v2): channel / registered type / anchor form /
## `wait` ban / duration / payload / locale keys / total length.
##
## Anchor resolution and sorting are delegated to src/core/event_model.gd — the same
## resolver the S2 sim/view dispatcher will use, so the validator cannot drift from
## playback behaviour.

const Ctx = preload("res://src/validate/validate_ctx.gd")
const EventModel = preload("res://src/core/event_model.gd")

const KNOWN_CHANNELS := ["sim", "view", "audio"]


static func check(ctx) -> void:
	var timeline = ctx.project.get("timeline", [])
	if typeof(timeline) != TYPE_ARRAY:
		ctx.err("SCHEMA_TYPE", "timeline", "timeline must be an array")
		return
	ctx.stats["events"] = timeline.size()

	var meta = ctx.project.get("meta", {})
	var locale := ""
	var locale_table := {}
	if typeof(meta) == TYPE_DICTIONARY:
		locale = String(meta.get("locale", ""))
	var locales = ctx.project.get("locales", {})
	if typeof(locales) == TYPE_DICTIONARY and locales.has(locale):
		var t = locales[locale]
		if typeof(t) == TYPE_DICTIONARY:
			locale_table = t

	for i in timeline.size():
		var ev = timeline[i]
		var base := "timeline[%d]" % i
		if typeof(ev) != TYPE_DICTIONARY:
			ctx.err("EV_NOT_OBJECT", base, "event must be an object")
			continue
		var ch := String(ev.get("channel", ""))
		var tp := String(ev.get("type", ""))
		if not KNOWN_CHANNELS.has(ch):
			ctx.err("EV_CHANNEL", base + ".channel", "channel must be one of %s (got \"%s\")" % [str(KNOWN_CHANNELS), ch])
		elif not EventModel.type_registered(ch, tp):
			ctx.err("EV_TYPE_UNKNOWN", base + ".type", "type \"%s\" is not registered for channel \"%s\"" % [tp, ch])
		if tp == "wait":
			ctx.err("EV_WAIT_FORBIDDEN", base + ".type", "`wait` events are forbidden; express gaps with time or {after, offset}")
		if not ev.has("payload"):
			ctx.err("EV_PAYLOAD_MISSING", base + ".payload", "payload is required")
		elif typeof(ev.get("payload")) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", base + ".payload", "payload must be an object")
		if ev.has("duration"):
			var d = ev.get("duration")
			if not Ctx.is_num(d) or float(d) < 0.0:
				ctx.err("EV_DURATION_NEG", base + ".duration", "duration must be a number >= 0")

	var r: Dictionary = EventModel.resolve(timeline)
	for e in r["errors"]:
		ctx.err(String(e.get("code", "")), String(e.get("path", "")), String(e.get("msg", "")))

	ctx.stats["end_time"] = r["end_time"]
	ctx.stats["events_resolved"] = (r["events"] as Array).size()
	if float(r["end_time"]) > EventModel.M0_MAX_TIMELINE_SECONDS + 0.0001:
		ctx.warn("TIMELINE_END_OVER", "timeline", "timeline ends at %.2fs, above the M0 30s template" % float(r["end_time"]))

	# text keys must exist in the active locale (locales table is P0 in M0)
	for ev in r["events"]:
		if String(ev.get("channel", "")) != "view":
			continue
		var p = ev.get("payload", {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if typeof(p.get("text_key", null)) != TYPE_STRING:
			continue
		var tk := String(p["text_key"])
		if not locale_table.has(tk):
			ctx.err("LOCALE_KEY_MISSING", "timeline[%d].payload.text_key" % int(ev.get("index", 0)), "text_key \"%s\" is missing from locales.%s" % [tk, locale])
