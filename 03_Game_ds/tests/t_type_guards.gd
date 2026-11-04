extends RefCounted
## N1 — type guards on identifier fields.
##
## Before this fix, `e03.track = 5` raised a GDScript runtime error inside
## EventModel.resolve. A runtime error aborts only the innermost function, so the
## validator carried on and still printed `ok=true errors=0` / exit 0 (false green).
##
## These cases pin the contract: a wrong type in a String()-converted identifier is
## a validation ERROR, it must never be a runtime abort, and the validator must have
## an engine-level backstop (INTERNAL_SCRIPT_ERROR) for rule functions that abort.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")
const ValidateCtx = preload("res://src/validate/validate_ctx.gd")

const INDEX := "res://data/manifest_index.json"
const SAMPLE := "res://data/sample_project.json"

## e03 is `{"id": "e03", "channel": "view", "type": "text", "track": "text", ...}`
const EVENT_INDEX := 2
const EVENT_FIELDS := [
	{"field": "track", "value": 5},
	{"field": "channel", "value": 9},
	{"field": "type", "value": 9},
]

## Guards for these live in rules_levels.gd (another agent's file); the cases are
## still pinned here so integration is measurable. Two of them (order.character,
## mission.entity) are also guarded by rules_refs.gd.
const IDENTITY_CASES := [
	{"path": ["levels", 0, "id"], "value": 5, "label": "level id"},
	{"path": ["levels", 0, "orders", 0, "id"], "value": 5, "label": "order id"},
	{"path": ["levels", 0, "orders", 0, "character"], "value": 5, "label": "order character"},
	{"path": ["levels", 0, "orders", 0, "mission", 0, "entity"], "value": 5, "label": "mission entity"},
	{"path": ["meta", "locale"], "value": 5, "label": "meta.locale"},
]


func run(t) -> void:
	_test_run_rule_gate(t)
	_test_event_field_types(t)
	_test_identity_field_types(t)
	_test_board_field_types(t)
	_test_non_array_levels(t)
	_test_valid_strings_stay_green(t)


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


func _has_internal(errors: Array) -> bool:
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("code", "")) == "INTERNAL_SCRIPT_ERROR":
			return true
	return false


func _has_path(errors: Array, code: String, path: String) -> bool:
	for e in errors:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("code", "")) != code:
			continue
		if String(e.get("path", "")) == path:
			return true
	return false


func _set_path(root, path: Array, value) -> void:
	var cur = root
	for i in path.size():
		var key = path[i]
		var last := i == path.size() - 1
		if typeof(cur) == TYPE_DICTIONARY:
			var k := String(key)
			if last:
				cur[k] = value
				return
			cur = cur[k]
		elif typeof(cur) == TYPE_ARRAY:
			var idx := int(key)
			if last:
				cur[idx] = value
				return
			cur = cur[idx]
		else:
			return


# ------------------------------------------------ engine-level abort gate (N1.4)

func _test_run_rule_gate(t) -> void:
	var ctx = ValidateCtx.new()
	# A real runtime error, not a compile-time one: the value has to come from a
	# variable, otherwise the parser rejects the constant conversion up front.
	var boom := func() -> void:
		var v = 5
		var s := String(v)
		print("unreachable ", s)

	# The abort itself is the point of the case; keep the expected engine error out
	# of the suite log so a green run stays pristine.
	var echo := Engine.print_error_messages
	Engine.print_error_messages = false
	var crashed: bool = ProjectValidator.run_rule(ctx, "boom_rule", boom)
	Engine.print_error_messages = echo
	t.ok(not crashed, "run_rule reports false when the rule aborts on a runtime error")
	t.has_code(ctx.errors, "INTERNAL_SCRIPT_ERROR", "an aborted rule records INTERNAL_SCRIPT_ERROR")
	var internal: Dictionary = {}
	for e in ctx.errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("code", "")) == "INTERNAL_SCRIPT_ERROR":
			internal = e
	var where := String(internal.get("path", "")) + "|" + String(internal.get("msg", ""))
	t.ok(where.contains("boom_rule"), "the INTERNAL_SCRIPT_ERROR names the rule", where)
	t.eq(String(internal.get("level", "")), "error", "INTERNAL_SCRIPT_ERROR is an error, not a warning")

	var before: int = ctx.errors.size()
	var clean := func() -> void:
		ctx.rule_done()
	var finished: bool = ProjectValidator.run_rule(ctx, "clean_rule", clean)
	t.ok(finished, "run_rule reports true for a rule that completes")
	t.eq(ctx.errors.size(), before, "a completed rule adds no error")
	t.eq(String(ctx.rule), "", "run_rule leaves no rule name behind")

	var after: bool = ProjectValidator.run_rule(ctx, "boom_then_clean", func() -> void: ctx.rule_done())
	t.ok(after, "the gate keeps working after an aborted rule")


# ------------------------------------------------- event field type guards (N1.1)

func _test_event_field_types(t) -> void:
	for c in EVENT_FIELDS:
		var field := String(c["field"])
		var p := _sample()
		(p["timeline"] as Array)[EVENT_INDEX][field] = c["value"]
		var r = _validate(p, "case_event_%s" % field)
		t.ok(not bool(r.ok), "timeline[%d].%s = %s fails validation" % [EVENT_INDEX, field, str(c["value"])])
		t.ok(not _has_internal(r.errors), "timeline[%d].%s is guarded before the abort" % [EVENT_INDEX, field], str(r.codes()))
		t.ok(_has_path(r.errors, "EV_FIELD_TYPE", "timeline[%d].%s" % [EVENT_INDEX, field]),
			"timeline[%d].%s reports EV_FIELD_TYPE at the exact path" % [EVENT_INDEX, field], str(r.codes()))


# --------------------------------------------- identity field type guards (N1.2)

func _test_identity_field_types(t) -> void:
	for c in IDENTITY_CASES:
		var label := String(c["label"])
		var p := _sample()
		_set_path(p, c["path"], c["value"])
		var r = _validate(p, "case_id_%s" % label.replace(" ", "_").replace(".", "_"))
		t.ok(not bool(r.ok), "%s = %s fails validation" % [label, str(c["value"])], str(r.codes()))


# --------------------------------------------- board field type guards (N1.2b)

## rules_board used to call String() on slot.entity and obstacle.type, so a numeric
## value aborted the rule function (findings after it were lost, one SCRIPT ERROR
## leaked to the console). Both fields are now typed before conversion.
func _test_board_field_types(t) -> void:
	var p := _sample()
	(p["levels"][0]["board"]["slots"] as Array)[0]["entity"] = 5
	var r = _validate(p, "case_id_slot_entity")
	t.ok(not bool(r.ok), "board slot entity = 5 fails validation", str(r.codes()))
	t.ok(not _has_internal(r.errors), "board slot entity is guarded before the abort", str(r.codes()))
	t.ok(_has_path(r.errors, "SLOT_ENTITY_TYPE", "levels[0].board.slots[0].entity"),
		"board slot entity reports SLOT_ENTITY_TYPE at the exact path", str(r.codes()))

	var p2 := _sample()
	(p2["levels"][0]["obstacles"] as Array)[0]["type"] = 5
	var r2 = _validate(p2, "case_id_obstacle_type")
	t.ok(not bool(r2.ok), "obstacle type = 5 fails validation", str(r2.codes()))
	t.ok(not _has_internal(r2.errors), "obstacle type is guarded before the abort", str(r2.codes()))
	t.ok(_has_path(r2.errors, "OBSTACLE_TYPE", "levels[0].obstacles[0].type"),
		"obstacle type reports OBSTACLE_TYPE at the exact path", str(r2.codes()))


# ------------------------------------------- early-return gate hygiene (N1.2c)

## A malformed `levels` value makes rules_board return before its last line. The
## abort gate must not turn that ordinary schema error into a fake
## INTERNAL_SCRIPT_ERROR: the schema rule owns the type error, nothing aborted.
func _test_non_array_levels(t) -> void:
	var p := _sample()
	p["levels"] = 5
	var r = _validate(p, "case_levels_not_array")
	t.ok(not bool(r.ok), "levels = 5 fails validation", str(r.codes()))
	t.ok(not _has_internal(r.errors), "a non-array levels is a schema error, not an aborted rule", str(r.codes()))
	t.ok(r.has_code("SCHEMA_TYPE"), "the schema rule reports SCHEMA_TYPE for levels", str(r.codes()))


# --------------------------------------------------- valid strings stay green (N1.3)

func _test_valid_strings_stay_green(t) -> void:
	var p := _sample()
	(p["timeline"] as Array)[EVENT_INDEX]["track"] = "custom_track"
	var r = _validate(p, "case_track_ok")
	t.ok(bool(r.ok), "a valid string track still validates", str(r.codes()))
	t.eq(r.errors.size(), 0, "a valid string track adds no error")

	var plain = ProjectValidator.validate_file(SAMPLE, _guard(), true)
	t.ok(bool(plain.ok), "the untouched sample still validates in strict mode", str(plain.codes()))
	t.eq(plain.errors.size(), 0, "the untouched sample has zero errors")
