extends RefCounted
## F1 order reachability (P0): a mission item counts only when THIS level's board
## can supply it — chips already placed there, generators actually placed there,
## their charges, and the merge closure inside one chain. The project-level
## `generators` table is behaviour config, not a source on every level.
##
## Every case deep-duplicates data/sample_project.json in memory and runs the real
## validator, so no fixture file has to be written.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")

const SAMPLE := "res://data/sample_project.json"
const INDEX := "res://data/manifest_index.json"


func run(t) -> void:
	_test_sample_is_green(t)
	_test_case_a_generator_off_this_board(t)
	_test_case_b_zero_charges(t)
	_test_case_c_no_cross_level_borrowing(t)
	_test_case_d1_one_charge_cannot_reach_lv3(t)
	_test_case_d2_empty_board(t)
	_test_case_e_four_charges_reach_lv3(t)
	_test_case_n5_board_merge_only(t)
	_test_case_n5b_same_generator_counts_once(t)
	_test_case_r1_rare_default_true_not_needed(t)
	_test_case_r2_rare_direct_order_false(t)
	_test_case_r3_rare_default_true_needed(t)
	_test_type_guards(t)


# ------------------------------------------------------------------ helpers

func _guard():
	var g = AssetGuard.new()
	g.load_from(INDEX, false)
	return g


func _project() -> Dictionary:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(SAMPLE)) != OK:
		return {}
	var root = j.data
	if typeof(root) != TYPE_DICTIONARY:
		return {}
	return (root as Dictionary).duplicate(true)


func _validate(project: Dictionary):
	return ProjectValidator.validate_dictionary(project, "case_x", _guard(), true)


func _level(project: Dictionary, li: int) -> Dictionary:
	var levels: Array = project["levels"]
	return levels[li] as Dictionary


func _slots(project: Dictionary, li: int) -> Array:
	var board: Dictionary = _level(project, li)["board"]
	return board["slots"]


func _set_slots(project: Dictionary, li: int, slots: Array) -> void:
	var board: Dictionary = _level(project, li)["board"]
	board["slots"] = slots


func _slot(x: int, y: int, entity: String, level: int) -> Dictionary:
	return {"x": x, "y": y, "entity": entity, "level": level}


func _set_mission(project: Dictionary, li: int, oi: int, mission: Array) -> void:
	var orders: Array = _level(project, li)["orders"]
	var order: Dictionary = orders[oi]
	order["mission"] = mission


func _generator(project: Dictionary, gid: String) -> Dictionary:
	var generators: Dictionary = project["generators"]
	return generators[gid] as Dictionary


func _errors_of(errors: Array, code: String) -> Array:
	var out: Array = []
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("code", "")) == code:
			out.append(e)
	return out


func _error_at(errors: Array, code: String, path: String) -> Dictionary:
	for e in _errors_of(errors, code):
		if String((e as Dictionary).get("path", "")) == path:
			return e
	return {}


func _paths_of(errors: Array, code: String) -> Array:
	var out: Array = []
	for e in _errors_of(errors, code):
		out.append(String((e as Dictionary).get("path", "")))
	return out


func _detail(e: Dictionary, key: String):
	if not e.has("detail"):
		return null
	var d = e["detail"]
	if typeof(d) != TYPE_DICTIONARY:
		return null
	return (d as Dictionary).get(key, null)


func _assert_clean(t, r, label: String) -> void:
	t.ok(bool(r.ok), label + ": project validates", str(r.codes()))
	t.eq(r.errors.size(), 0, label + ": zero errors")
	t.ok(not r.has_code("INTERNAL_SCRIPT_ERROR"), label + ": no INTERNAL_SCRIPT_ERROR", str(r.codes()))


func _assert_unreachable(t, r, path: String, entity: String, level: int, label: String) -> void:
	t.ok(not bool(r.ok), label + ": project is rejected", str(r.codes()))
	var e := _error_at(r.errors, "ORDER_UNREACHABLE", path)
	t.ok(not e.is_empty(), label + ": ORDER_UNREACHABLE at " + path, str(_paths_of(r.errors, "ORDER_UNREACHABLE")))
	t.eq(_detail(e, "entity"), entity, label + ": detail.entity is " + entity)
	t.eq(_detail(e, "level"), level, label + ": detail.level is " + str(level))
	t.ok(not r.has_code("INTERNAL_SCRIPT_ERROR"), label + ": no INTERNAL_SCRIPT_ERROR", str(r.codes()))


func _assert_no_blame_below(t, r, li: int, label: String) -> void:
	var prefix := "levels[%d]" % li
	var blamed: Array = []
	for path in _paths_of(r.errors, "ORDER_UNREACHABLE"):
		if String(path).begins_with(prefix):
			blamed.append(path)
	t.eq(blamed.size(), 0, label + " (blamed=" + str(blamed) + ")")


func _has_error_at(t, r, code: String, path: String, label: String) -> void:
	var e := _error_at(r.errors, code, path)
	t.ok(not e.is_empty(), label, str(_paths_of(r.errors, code)))
	t.ok(not r.has_code("INTERNAL_SCRIPT_ERROR"), label + ": no INTERNAL_SCRIPT_ERROR", str(r.codes()))


# ------------------------------------------------------------------ baseline

func _test_sample_is_green(t) -> void:
	_assert_clean(t, _validate(_project()), "base sample")


# ------------------------------------------------------------------ F1 cases

func _test_case_a_generator_off_this_board(t) -> void:
	var p := _project()
	var kept: Array = []
	for s in _slots(p, 0):
		if String((s as Dictionary).get("entity", "")) != "CleanBox_C":
			kept.append(s)
	_set_slots(p, 0, kept)
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Cb", "level": 2}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Cb", 2,
		"case A: generator not on this level's board -> Cb lv2 unreachable")
	t.eq(_paths_of(r.errors, "ORDER_UNREACHABLE").size(), 1,
		"case A: only level_1's order is blamed")


func _test_case_b_zero_charges(t) -> void:
	var p := _project()
	_generator(p, "CleanBox_C")["charges"] = 0
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Cb", "level": 2}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Cb", 2,
		"case B: zero charges -> Cb lv2 unreachable")
	t.eq(_paths_of(r.errors, "ORDER_UNREACHABLE").size(), 1,
		"case B: level_2 still reaches its own order with zero charges")


func _test_case_c_no_cross_level_borrowing(t) -> void:
	var p := _project()
	_set_slots(p, 0, [_slot(2, 3, "CleanSet_Ca", 1), _slot(3, 3, "CleanSet_Ca", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 3}])
	var l2: Array = _slots(p, 1)
	l2.append(_slot(6, 8, "CleanSet_Ca", 3))
	_set_slots(p, 1, l2)
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Ca", 3,
		"case C: level_2's Ca lv3 cannot be borrowed by level_1")
	_assert_no_blame_below(t, r, 1, "case C: level_2 keeps its own reachability")


func _test_case_d1_one_charge_cannot_reach_lv3(t) -> void:
	var p := _project()
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1)])
	_generator(p, "CleanBox_C")["charges"] = 1
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 3}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Ca", 3,
		"case D1: one charge cannot reach Ca lv3")
	_assert_no_blame_below(t, r, 1, "case D1: level_2 keeps its own reachability")


func _test_case_d2_empty_board(t) -> void:
	var p := _project()
	_set_slots(p, 0, [])
	_generator(p, "CleanBox_C")["charges"] = 1
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 3}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Ca", 3,
		"case D2: an empty board has no source at all -> Ca lv3 unreachable")
	_assert_no_blame_below(t, r, 1, "case D2: level_2 keeps its own reachability")


func _test_case_e_four_charges_reach_lv3(t) -> void:
	var p := _project()
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1)])
	_generator(p, "CleanBox_C")["charges"] = 4
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 3}])
	_assert_clean(t, _validate(p),
		"case E: 4 charges -> 4x Ca lv1 -> 2x lv2 -> 1x lv3")


func _test_case_n5_board_merge_only(t) -> void:
	var p := _project()
	p["generators"] = {}
	_set_slots(p, 0, [_slot(2, 3, "CleanSet_Ca", 1), _slot(3, 3, "CleanSet_Ca", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 2}])
	_assert_clean(t, _validate(p),
		"N5: generators={} and two Ca lv1 merge into Ca lv2; level_2 merges on its own board")


func _test_case_n5b_same_generator_counts_once(t) -> void:
	var p := _project()
	var g := _generator(p, "CleanBox_C")
	g["charges"] = 1
	g["rareOutputs"] = []
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1), _slot(1, 1, "CleanBox_C", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Ca", "level": 2}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Ca", 2,
		"N5b: two placements of one generator share one charge pool -> Ca lv2 unreachable")
	t.eq(_paths_of(r.errors, "ORDER_UNREACHABLE").size(), 1,
		"N5b: level_2 is not blamed")

	# control: the same double placement with charges=2 does reach Ca lv2, so
	# "counted once" must not degenerate into "only ever one chip".
	var p2 := _project()
	var g2 := _generator(p2, "CleanBox_C")
	g2["charges"] = 2
	g2["rareOutputs"] = []
	_set_slots(p2, 0, [_slot(0, 0, "CleanBox_C", 1), _slot(1, 1, "CleanBox_C", 1)])
	_set_mission(p2, 0, 0, [{"entity": "CleanSet_Ca", "level": 2}])
	_assert_clean(t, _validate(p2),
		"N5b control: charges=2 on the same double placement reaches Ca lv2")


func _test_case_r1_rare_default_true_not_needed(t) -> void:
	var p := _project()
	var g := _generator(p, "CleanBox_C")
	g["charges"] = 4
	g["outputs"] = [{"entity": "CleanSet_Ca", "weight": 60}]
	g["rareOutputs"] = [{"entity": "CleanSet_Cb", "level": 2, "weight": 5}]
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Cb", "level": 3}])
	var r = _validate(p)
	_assert_unreachable(t, r, "levels[0].orders[0].mission[0]", "CleanSet_Cb", 3,
		"R1: rare directOrder defaults true and this level has no order for Cb lv2 -> not counted")
	t.eq(_paths_of(r.errors, "ORDER_UNREACHABLE").size(), 1,
		"R1: level_2 still reaches its own order (Cb lv2 is required there)")


func _test_case_r2_rare_direct_order_false(t) -> void:
	var p := _project()
	var g := _generator(p, "CleanBox_C")
	g["charges"] = 4
	g["outputs"] = [{"entity": "CleanSet_Ca", "weight": 60}]
	g["rareOutputs"] = [{"entity": "CleanSet_Cb", "level": 2, "weight": 5, "directOrder": false}]
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Cb", "level": 3}])
	_assert_clean(t, _validate(p),
		"R2: rare directOrder=false counts unconditionally -> 4x Cb lv2 -> Cb lv3")


func _test_case_r3_rare_default_true_needed(t) -> void:
	var p := _project()
	var g := _generator(p, "CleanBox_C")
	g["charges"] = 4
	g["outputs"] = [{"entity": "CleanSet_Ca", "weight": 60}]
	g["rareOutputs"] = [{"entity": "CleanSet_Cb", "level": 2, "weight": 5}]
	_set_slots(p, 0, [_slot(0, 0, "CleanBox_C", 1)])
	_set_mission(p, 0, 0, [{"entity": "CleanSet_Cb", "level": 2}])
	_assert_clean(t, _validate(p),
		"R3: rare directOrder defaults true and this level's order needs Cb lv2 -> counted")


# ------------------------------------------------------------------ N1 guards

func _test_type_guards(t) -> void:
	var p1 := _project()
	(p1["entities"]["CleanSet_Ca"] as Dictionary)["kind"] = 5
	var r1 = _validate(p1)
	t.ok(not bool(r1.ok), "N1 entities.kind: numeric kind is rejected", str(r1.codes()))
	_has_error_at(t, r1, "ENTITY_KIND_TYPE", "entities.CleanSet_Ca.kind",
		"N1 entities.kind: ENTITY_KIND_TYPE points at the field")

	var p2 := _project()
	_level(p2, 0)["id"] = 12
	var r2 = _validate(p2)
	t.ok(not bool(r2.ok), "N1 level.id: numeric level id is rejected", str(r2.codes()))
	_has_error_at(t, r2, "LEVEL_ID_TYPE", "levels[0].id",
		"N1 level.id: LEVEL_ID_TYPE points at the field")

	var p3 := _project()
	var o3: Dictionary = (_level(p3, 0)["orders"] as Array)[0]
	o3["id"] = 42
	var r3 = _validate(p3)
	t.ok(not bool(r3.ok), "N1 order.id: numeric order id is rejected", str(r3.codes()))
	_has_error_at(t, r3, "ORDER_ID_TYPE", "levels[0].orders[0].id",
		"N1 order.id: ORDER_ID_TYPE points at the field")

	var p4 := _project()
	var o4: Dictionary = (_level(p4, 0)["orders"] as Array)[0]
	o4["character"] = 7
	var r4 = _validate(p4)
	t.ok(not bool(r4.ok), "N1 order.character: numeric character is rejected", str(r4.codes()))
	_has_error_at(t, r4, "ORDER_CHARACTER_TYPE", "levels[0].orders[0].character",
		"N1 order.character: ORDER_CHARACTER_TYPE points at the field")

	var p5 := _project()
	var o5: Dictionary = (_level(p5, 0)["orders"] as Array)[0]
	(o5["mission"] as Array)[0] = {"entity": 7, "level": 2}
	var r5 = _validate(p5)
	t.ok(not bool(r5.ok), "N1 mission.entity: numeric mission entity is rejected", str(r5.codes()))
	_has_error_at(t, r5, "MISSION_ENTITY_TYPE", "levels[0].orders[0].mission[0].entity",
		"N1 mission.entity: MISSION_ENTITY_TYPE points at the field")

	var p6 := _project()
	var g6 := _generator(p6, "CleanBox_C")
	(g6["outputs"] as Array)[0] = {"entity": 9, "weight": 60}
	var r6 = _validate(p6)
	t.ok(not bool(r6.ok), "N1 generator output: numeric output entity is rejected", str(r6.codes()))
	_has_error_at(t, r6, "GEN_OUTPUT_ENTITY_TYPE", "generators.CleanBox_C.outputs[0].entity",
		"N1 generator output: GEN_OUTPUT_ENTITY_TYPE points at the field")

	var p7 := _project()
	var g7 := _generator(p7, "CleanBox_C")
	(g7["rareOutputs"] as Array)[0] = {"entity": "CleanSet_Ca", "level": "2", "weight": 5}
	var r7 = _validate(p7)
	t.ok(not bool(r7.ok), "N1 rareOutputs.level: string level is rejected", str(r7.codes()))
	_has_error_at(t, r7, "GEN_RARE_LEVEL", "generators.CleanBox_C.rareOutputs[0].level",
		"N1 rareOutputs.level: GEN_RARE_LEVEL points at the field")
