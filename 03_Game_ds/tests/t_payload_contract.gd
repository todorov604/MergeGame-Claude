extends RefCounted
## N2 (validator side) — sim event payload contract.
##
## src/core/sim.gd reads a fixed shape out of every sim payload: tap reads
## target.slot, merge/drag read from/to, deliver reads order + from, order_claim
## reads order, energy_tick reads delta. A payload that does not match the shape
## can only fail at playback time with a generic SIM_* code, which is exactly the
## kind of late failure the validator exists to prevent.
##
## The contract is checked on RESOLVED events, so the reported path is the raw
## timeline index (`timeline[i].payload...`), matching EventModel's `index`.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")

const INDEX := "res://data/manifest_index.json"
const SAMPLE := "res://data/sample_project.json"
const SHAPE := "EV_PAYLOAD_SHAPE"


func run(t) -> void:
	_test_sample_is_clean(t)
	_test_tap(t)
	_test_merge(t)
	_test_drag(t)
	_test_deliver(t)
	_test_order_claim(t)
	_test_energy_tick(t)
	_test_marker_events(t)
	_test_good_shapes(t)


# ------------------------------------------------------------------ helpers

func _guard(allow_placeholders: bool = false):
	var g = AssetGuard.new()
	g.load_from(INDEX, allow_placeholders)
	return g


func _sample() -> Dictionary:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(SAMPLE)) != OK:
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		return {}
	return (j.data as Dictionary).duplicate(true)


func _validate(project: Dictionary, label: String):
	return ProjectValidator.validate_dictionary(project, label, _guard(), true)


func _event_index(project: Dictionary, id: String) -> int:
	var timeline: Array = project.get("timeline", [])
	for i in timeline.size():
		if typeof(timeline[i]) == TYPE_DICTIONARY and String(timeline[i].get("id", "")) == id:
			return i
	return -1


func _set_payload(project: Dictionary, id: String, payload) -> void:
	var timeline: Array = project["timeline"]
	for i in timeline.size():
		if typeof(timeline[i]) == TYPE_DICTIONARY and String(timeline[i].get("id", "")) == id:
			timeline[i]["payload"] = payload
			return


## Appends a sim event. `at` stays well inside the 30s M0 window so no
## TIMELINE_END_OVER warning can muddy the assertion.
func _append(project: Dictionary, id: String, type: String, at: float, payload) -> void:
	(project["timeline"] as Array).append({
		"id": id,
		"channel": "sim",
		"type": type,
		"at": at,
		"payload": payload,
	})


func _find_shape(errors: Array, path: String) -> Dictionary:
	for e in errors:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("code", "")) != SHAPE:
			continue
		if String(e.get("path", "")) == path:
			return e
	return {}


func _has_shape(errors: Array) -> bool:
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("code", "")) == SHAPE:
			return true
	return false


func _assert_shape(t, r, path: String, what: String) -> void:
	t.ok(not bool(r.ok), what + ": the project is rejected", str(r.codes()))
	t.ok(not _find_shape(r.errors, path).is_empty(), "%s: %s reported at %s" % [what, SHAPE, path], str(r.codes()))
	var e := _find_shape(r.errors, path)
	if not e.is_empty():
		t.ok(String(e.get("msg", "")).length() > 0, what + ": the message explains the expected shape")


# ----------------------------------------------------------- the sample itself

func _test_sample_is_clean(t) -> void:
	var r = _validate(_sample(), "case_payload_sample")
	t.ok(bool(r.ok), "sample payloads satisfy every sim contract", str(r.codes()))
	t.ok(not _has_shape(r.errors), "sample produces no EV_PAYLOAD_SHAPE")


# --------------------------------------------------------------- per-type cases

func _test_tap(t) -> void:
	var p := _sample()
	_set_payload(p, "e01", {})
	var idx := _event_index(p, "e01")
	var r = _validate(p, "case_payload_tap_empty")
	_assert_shape(t, r, "timeline[%d].payload.target" % idx, "tap with an empty payload")

	var p2 := _sample()
	_set_payload(p2, "e01", {"target": {"slot": ["a", 0]}})
	var r2 = _validate(p2, "case_payload_tap_slot")
	t.ok(not bool(r2.ok), "tap with a non-numeric slot is rejected", str(r2.codes()))
	t.ok(not _find_shape(r2.errors, "timeline[%d].payload.target.slot" % idx).is_empty(),
		"tap reports EV_PAYLOAD_SHAPE at target.slot", str(r2.codes()))


func _test_merge(t) -> void:
	var p := _sample()
	_set_payload(p, "e02", {"from": [2, 3]})
	var idx := _event_index(p, "e02")
	var r = _validate(p, "case_payload_merge")
	_assert_shape(t, r, "timeline[%d].payload.to" % idx, "merge without payload.to")


func _test_drag(t) -> void:
	var p := _sample()
	_append(p, "t_drag", "drag", 19.0, {"from": [0, 0], "to": "nope"})
	var r = _validate(p, "case_payload_drag")
	_assert_shape(t, r, "timeline[%d].payload.to" % _event_index(p, "t_drag"), "drag with a non-array to")


func _test_deliver(t) -> void:
	var p := _sample()
	_append(p, "t_deliver", "deliver", 19.5, {"order": "order_1"})
	var r = _validate(p, "case_payload_deliver")
	_assert_shape(t, r, "timeline[%d].payload.from" % _event_index(p, "t_deliver"), "deliver without payload.from")

	var p2 := _sample()
	_append(p2, "t_deliver2", "deliver", 19.5, {"order": "", "from": [0, 0]})
	var r2 = _validate(p2, "case_payload_deliver_order")
	t.ok(not bool(r2.ok), "deliver with an empty order id is rejected", str(r2.codes()))
	t.ok(not _find_shape(r2.errors, "timeline[%d].payload.order" % _event_index(p2, "t_deliver2")).is_empty(),
		"deliver reports EV_PAYLOAD_SHAPE at payload.order", str(r2.codes()))


func _test_order_claim(t) -> void:
	var p := _sample()
	_set_payload(p, "e07", {"order": 5})
	var idx := _event_index(p, "e07")
	var r = _validate(p, "case_payload_claim")
	_assert_shape(t, r, "timeline[%d].payload.order" % idx, "order_claim with a numeric order")


func _test_energy_tick(t) -> void:
	var p := _sample()
	_set_payload(p, "e06", {"delta": "1"})
	var idx := _event_index(p, "e06")
	var r = _validate(p, "case_payload_tick")
	_assert_shape(t, r, "timeline[%d].payload.delta" % idx, "energy_tick with a string delta")


func _test_marker_events(t) -> void:
	# level_next / board_full / level_complete take no fields, but their payload
	# still has to be an object: sim dispatches on a Dictionary.
	var p := _sample()
	_set_payload(p, "e10", 5)
	var idx := _event_index(p, "e10")
	var r = _validate(p, "case_payload_level_next")
	_assert_shape(t, r, "timeline[%d].payload" % idx, "level_next with a scalar payload")

	var p2 := _sample()
	_append(p2, "t_full", "board_full", 20.0, [])
	var r2 = _validate(p2, "case_payload_board_full")
	_assert_shape(t, r2, "timeline[%d].payload" % _event_index(p2, "t_full"), "board_full with an array payload")

	var p3 := _sample()
	_append(p3, "t_complete", "level_complete", 20.5, "done")
	var r3 = _validate(p3, "case_payload_level_complete")
	_assert_shape(t, r3, "timeline[%d].payload" % _event_index(p3, "t_complete"), "level_complete with a scalar payload")


# -------------------------------------------------------------- good shapes

func _test_good_shapes(t) -> void:
	var p := _sample()
	_append(p, "t_drag_ok", "drag", 18.5, {"from": [0, 0], "to": [1, 1]})
	_append(p, "t_deliver_ok", "deliver", 19.0, {"order": "order_1", "from": [0, 0]})
	_append(p, "t_full_ok", "board_full", 19.5, {})
	_append(p, "t_complete_ok", "level_complete", 20.0, {})
	_append(p, "t_next_ok", "level_next", 20.5, {})
	_append(p, "t_tap_ok", "tap", 21.0, {"target": {"slot": [1, 1]}})
	_append(p, "t_tick_ok", "energy_tick", 21.5, {"delta": -2})
	var r = _validate(p, "case_payload_good")
	t.ok(not _has_shape(r.errors), "every well-formed payload passes the contract", str(r.codes()))
	t.ok(bool(r.ok), "the extended project is otherwise valid", str(r.codes()))
