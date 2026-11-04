extends RefCounted
## Event model v2 tests: anchor resolution, forbidden forms, deterministic ordering.
## These guard the piece that the validator and (from S2) the sim/view dispatcher share.

const EventModel = preload("res://src/core/event_model.gd")


func _ev(id: String, channel: String, type: String, at, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "channel": channel, "type": type, "at": at, "payload": {}}
	for k in extra.keys():
		e[k] = extra[k]
	return e


func _ids(resolved: Array) -> Array:
	var out: Array = []
	for r in resolved:
		out.append(String(r["id"]))
	return out


func _codes(errors: Array) -> Array:
	var out: Array = []
	for e in errors:
		out.append(String(e["code"]))
	return out


func run(t) -> void:
	_test_absolute_and_relative(t)
	_test_forbidden_forms(t)
	_test_cycles(t)
	_test_sorting(t)
	_test_end_time(t)
	_test_determinism(t)


func _test_absolute_and_relative(t) -> void:
	var events := [
		_ev("e1", "sim", "tap", 2.0),
		_ev("e2", "sim", "merge", {"after": "e1", "offset": 1.2}, {"duration": 0.3}),
		_ev("e3", "view", "text", {"after": "e2", "offset": 0.8}, {"duration": 1.0}),
	]
	var r: Dictionary = EventModel.resolve(events)
	t.ok(bool(r["ok"]), "absolute + relative anchors resolve", str(_codes(r["errors"])))
	var times := {}
	for ev in r["events"]:
		times[String(ev["id"])] = float(ev["at"])
	t.ok(is_equal_approx(float(times.get("e1", -1.0)), 2.0), "e1 at 2.0", str(times.get("e1")))
	t.ok(is_equal_approx(float(times.get("e2", -1.0)), 3.2), "e2 = e1 + 1.2", str(times.get("e2")))
	t.ok(is_equal_approx(float(times.get("e3", -1.0)), 4.0), "chained anchor e3 = e2 + 0.8", str(times.get("e3")))


func _test_forbidden_forms(t) -> void:
	var r1: Dictionary = EventModel.resolve([_ev("e1", "view", "text", {"after": "nope", "offset": 0.1})])
	t.ok(_codes(r1["errors"]).has("EV_ANCHOR_MISSING"), "missing anchor is reported", str(_codes(r1["errors"])))

	var r2: Dictionary = EventModel.resolve([_ev("e1", "view", "text", {"after": "e1", "offset": 0.1})])
	t.ok(_codes(r2["errors"]).has("EV_ANCHOR_SELF"), "self anchor is reported", str(_codes(r2["errors"])))

	var r3: Dictionary = EventModel.resolve([_ev("e1", "sim", "tap", -1.0)])
	t.ok(_codes(r3["errors"]).has("EV_AT_NEGATIVE"), "negative absolute time is reported", str(_codes(r3["errors"])))

	var r4: Dictionary = EventModel.resolve([_ev("e1", "sim", "tap", null)])
	t.ok(_codes(r4["errors"]).has("EV_AT_MISSING"), "missing at is reported", str(_codes(r4["errors"])))

	var r5: Dictionary = EventModel.resolve([
		_ev("e1", "sim", "tap", 1.0),
		_ev("e1", "view", "cta", 2.0),
	])
	t.ok(_codes(r5["errors"]).has("EV_DUP_ID"), "duplicate event id is reported", str(_codes(r5["errors"])))

	t.ok(not EventModel.type_registered("sim", "wait"), "wait is not a registered sim type")
	t.ok(EventModel.type_registered("sim", "order_claim"), "order_claim is registered on sim")
	t.ok(EventModel.type_registered("view", "star_fly"), "star_fly is registered on view")
	t.ok(not EventModel.type_registered("view", "merge"), "merge is not a view type")


func _test_cycles(t) -> void:
	var events := [
		_ev("a", "view", "text", {"after": "b", "offset": 0.1}),
		_ev("b", "view", "text", {"after": "a", "offset": 0.1}),
		_ev("c", "sim", "tap", 1.0),
	]
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = EventModel.resolve(events)
	var elapsed := Time.get_ticks_msec() - t0
	t.ok(_codes(r["errors"]).has("EV_ANCHOR_CYCLE"), "anchor cycle is reported", str(_codes(r["errors"])))
	t.ok(elapsed < 500, "cycle detection terminates quickly", str(elapsed) + "ms")
	t.ok(_ids(r["events"]) == ["c"], "only the resolvable event survives", str(_ids(r["events"])))


func _test_sorting(t) -> void:
	# same `at` for every event: order must be channel -> track -> order -> id
	var events := [
		_ev("a1", "audio", "sfx", 5.0),
		_ev("v2", "view", "text", 5.0, {"track": "cam"}),
		_ev("s1", "sim", "tap", 5.0),
		_ev("v1", "view", "cta", 5.0),
		_ev("s2", "sim", "tap", 5.0, {"order": 2}),
		_ev("s0", "sim", "tap", 5.0, {"order": 1}),
		_ev("v3", "view", "text", 5.0, {"track": "aaa"}),
	]
	var r: Dictionary = EventModel.resolve(events)
	var expected := ["s1", "s0", "s2", "v1", "v3", "v2", "a1"]
	t.ok(_ids(r["events"]) == expected, "sort key at->channel->track->order->id", str(_ids(r["events"])))

	# earlier `at` always wins over channel priority
	var r2: Dictionary = EventModel.resolve([
		_ev("view_first", "view", "cta", 1.0),
		_ev("sim_later", "sim", "tap", 2.0),
	])
	t.ok(_ids(r2["events"]) == ["view_first", "sim_later"], "time dominates channel priority", str(_ids(r2["events"])))


func _test_end_time(t) -> void:
	var r: Dictionary = EventModel.resolve([
		_ev("e1", "view", "text", 1.0, {"duration": 2.0}),
		_ev("e2", "view", "cta", 28.0, {"duration": 2.0}),
	])
	t.ok(is_equal_approx(float(r["end_time"]), 30.0), "end_time = last at + duration", str(r["end_time"]))
	t.ok(is_equal_approx(float(r["start_time"]), 1.0), "start_time = first at", str(r["start_time"]))


func _test_determinism(t) -> void:
	var events := [
		_ev("e3", "view", "text", 4.0),
		_ev("e1", "sim", "tap", 2.0),
		_ev("e2", "view", "camera", 2.0),
	]
	var a: Dictionary = EventModel.resolve(events)
	var b: Dictionary = EventModel.resolve(events)
	t.ok(_ids(a["events"]) == _ids(b["events"]), "same input -> same order", str(_ids(a["events"])))
	t.ok(is_equal_approx(float(a["end_time"]), float(b["end_time"])), "same input -> same end_time")
	# input order must not matter
	var shuffled := [events[1], events[2], events[0]]
	var c: Dictionary = EventModel.resolve(shuffled)
	t.ok(_ids(a["events"]) == _ids(c["events"]), "input order does not change output order", str(_ids(c["events"])))
