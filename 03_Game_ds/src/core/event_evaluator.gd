extends RefCounted
## The single event evaluator shared by sim, view and audio.
##
## One resolved, sorted stream (EventModel) is walked exactly once; each event is
## handed to the sim only when channel == "sim", and to the view sink for every
## event. The view therefore never re-implements anchor resolution or ordering,
## which is what makes preview / single-step / offline render agree.
##
## steps and digests are comparable across runs: same seed + same timeline must
## produce the same digest sequence.

const EventModel = preload("res://src/core/event_model.gd")
const Sim = preload("res://src/core/sim.gd")

var model
var sim
var events: Array = []
var cursor: int = 0
var errors: Array = []
var end_time: float = 0.0
var seed_value: int = 0
var view_sink = null
var dispatched: int = 0
var load_ok: bool = true


func setup(model_in, seed_value_in: int, view_sink_in = null) -> void:
	model = model_in
	seed_value = seed_value_in
	view_sink = view_sink_in
	sim = Sim.new()
	sim.setup(model, seed_value_in)
	events = []
	cursor = 0
	errors = []
	dispatched = 0
	end_time = 0.0


func load_timeline(timeline: Array) -> Dictionary:
	var r: Dictionary = EventModel.resolve(timeline)
	if not bool(r.get("ok", false)):
		load_ok = false
		errors = (r.get("errors", []) as Array).duplicate(true)
		events = []
		cursor = 0
		end_time = 0.0
		return {"ok": false, "errors": errors, "count": 0, "end_time": 0.0}
	load_ok = true
	events = (r.get("events", []) as Array).duplicate(true)
	cursor = 0
	errors = []
	end_time = float(r.get("end_time", 0.0))
	return {
		"ok": true,
		"errors": [],
		"count": events.size(),
		"end_time": end_time,
		"start_time": float(r.get("start_time", 0.0)),
	}


## Walks one event: advance the shared clock, apply on sim channel, notify the
## view sink for every channel, bump the cursor. Returns a per-event report.
func step() -> Dictionary:
	if cursor >= events.size():
		var now := 0.0
		if sim != null:
			now = float(sim.time)
		return {
			"ok": false,
			"code": "EVAL_END",
			"id": "",
			"type": "",
			"channel": "",
			"at": now,
			"sim": {},
		}
	var ev: Dictionary = events[cursor]
	var at := float(ev.get("at", 0.0))
	var channel := String(ev.get("channel", ""))
	var type := String(ev.get("type", ""))
	var out := {
		"ok": true,
		"code": "",
		"id": String(ev.get("id", "")),
		"type": type,
		"channel": channel,
		"at": at,
		"sim": {},
	}
	# §3.3: a type only exists once it is registered. An unregistered type or an
	# unknown channel must fail loudly here, not pass silently in preview/step.
	if not EventModel.CHANNEL_PRIORITY.has(channel):
		out["ok"] = false
		out["code"] = "EV_CHANNEL"
		out["note"] = "unknown channel \"" + channel + "\""
	elif not EventModel.type_registered(channel, type):
		out["ok"] = false
		out["code"] = "EV_UNKNOWN_TYPE"
		out["note"] = "type \"" + type + "\" is not registered for channel \"" + channel + "\""
	elif channel == "sim" and sim != null:
		# only sim events advance the game clock; view/audio are presentation
		sim.set_time(at)
		var applied: Dictionary = sim.apply(ev)
		out["ok"] = bool(applied.get("ok", false))
		out["code"] = String(applied.get("code", ""))
		out["note"] = String(applied.get("note", ""))
		out["sim"] = applied
	_notify(ev)
	cursor += 1
	dispatched += 1
	return out


func _notify(ev: Dictionary) -> void:
	if view_sink == null:
		return
	if typeof(view_sink) == TYPE_CALLABLE:
		(view_sink as Callable).call(ev)
		return
	if view_sink.has_method("on_event"):
		view_sink.on_event(ev)


func run_all() -> Dictionary:
	var rejected: Array = []
	var digests: Array = []
	while cursor < events.size():
		var r: Dictionary = step()
		if not bool(r.get("ok", false)):
			rejected.append({
				"id": String(r.get("id", "")),
				"channel": String(r.get("channel", "")),
				"code": String(r.get("code", "")),
			})
		if String(r.get("channel", "")) == "sim" and sim != null:
			digests.append(sim.digest())
	return {
		"ok": load_ok and errors.is_empty() and rejected.is_empty(),
		"load_ok": load_ok,
		"dispatched": dispatched,
		"rejected": rejected,
		"end_time": end_time,
		"digests": digests,
	}


## Replay from a fresh sim with the same seed; the loaded timeline is kept so a
## second run_all can be compared digest-for-digest.
func reset() -> void:
	sim = Sim.new()
	sim.setup(model, seed_value)
	cursor = 0
	dispatched = 0
	# deliberately keeps `errors`/`load_ok`: resetting the replay position must not
	# turn a timeline that failed to parse into a "successful" empty run
