extends RefCounted
## Schema v2 invariants and deterministic event ordering. Validators are only called, never changed.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")
const EventModel = preload("res://src/core/event_model.gd")

const INDEX := "res://data/manifest_index.json"
const SAMPLE := "res://data/sample_project.json"
const OK_MIN := "res://tests/fixtures/ok_min.json"

const HUD_FIELDS := [
	"level",
	"energy",
	"energyTickSeconds",
	"energyTickMode",
	"coin",
	"star",
	"gem",
	"exp",
]
const VALID_KINDS := ["chip", "generator", "special", "character"]
const GENERATOR_BEHAVIOR_FIELDS := ["charges", "cooldown", "outputs", "rareOutputs", "levelFromItem", "missionPool"]
const CHANNEL_PRIORITY := {"sim": 0, "view": 1, "audio": 2}


func run(t) -> void:
	var guard = AssetGuard.new()
	t.ok(guard.load_from(INDEX, false), "asset guard loads with placeholders disabled", guard.load_error)

	for path in [SAMPLE, OK_MIN]:
		_test_project(t, String(path), guard)


func _test_project(t, path: String, guard) -> void:
	var project := _load_json(path)
	t.ok(not project.is_empty(), path.get_file() + " parses as an object")
	if project.is_empty():
		return

	var report = ProjectValidator.validate_file(path, guard, true)
	t.ok(bool(report.ok), path.get_file() + " validates in strict mode", _error_codes(report.errors))
	t.ok(report.errors.size() == 0, path.get_file() + " has zero errors", _error_codes(report.errors))
	t.ok(report.warnings.size() == 0, path.get_file() + " has zero warnings", _warning_codes(report.warnings))

	_test_schema_terms(t, path, project)
	_test_events(t, path, project)


func _test_schema_terms(t, path: String, project: Dictionary) -> void:
	var prefix := path.get_file() + ": "
	t.eq(int(project.get("version", -1)), 2, prefix + "version is 2")

	var levels = project.get("levels", null)
	if typeof(levels) != TYPE_ARRAY:
		t.ok(false, prefix + "levels is an array", str(typeof(levels)))
		return
	t.ok(levels.size() <= 10, prefix + "levels.size() <= 10", str(levels.size()))

	var level_ids: Array = []
	var duplicate_levels: Array = []
	var seen_levels := {}
	for i in levels.size():
		var level = levels[i]
		if typeof(level) != TYPE_DICTIONARY:
			duplicate_levels.append("levels[" + str(i) + "]")
			continue
		var lid := String(level.get("id", ""))
		if lid.is_empty() or seen_levels.has(lid):
			duplicate_levels.append("levels[" + str(i) + "]=" + lid)
		else:
			seen_levels[lid] = i
			level_ids.append(lid)
	t.ok(duplicate_levels.size() == 0, prefix + "level ids are present and unique in array order", _detail_values(duplicate_levels))

	var next_paths: Array = []
	_find_key_paths(project, "next", "root", next_paths)
	t.ok(next_paths.size() == 0, prefix + "no recursive next key exists", _detail_values(next_paths))

	var entities = project.get("entities", null)
	if typeof(entities) != TYPE_DICTIONARY:
		t.ok(false, prefix + "entities is a dictionary", str(typeof(entities)))
		entities = {}
	var bad_kinds: Array = []
	for id in entities:
		var entity = entities[id]
		if typeof(entity) != TYPE_DICTIONARY:
			bad_kinds.append(String(id) + ".<record>")
			continue
		var kind := String(entity.get("kind", ""))
		if not VALID_KINDS.has(kind):
			bad_kinds.append(String(id) + "=" + kind)
	t.ok(bad_kinds.size() == 0, prefix + "every entity has a legal kind", _detail_values(bad_kinds))

	var slot_key_errors: Array = []
	for li in levels.size():
		var level = levels[li]
		if typeof(level) != TYPE_DICTIONARY:
			continue
		var board = level.get("board", null)
		if typeof(board) != TYPE_DICTIONARY:
			slot_key_errors.append("levels[" + str(li) + "].board")
			continue
		var slots = board.get("slots", null)
		if typeof(slots) != TYPE_ARRAY:
			slot_key_errors.append("levels[" + str(li) + "].board.slots")
			continue
		for si in slots.size():
			var slot = slots[si]
			if typeof(slot) != TYPE_DICTIONARY:
				slot_key_errors.append("levels[" + str(li) + "].board.slots[" + str(si) + "]")
				continue
			if not slot.has("entity") or String(slot.get("entity", "")).is_empty():
				slot_key_errors.append("levels[" + str(li) + "].board.slots[" + str(si) + "].entity")
			if slot.has("chip"):
				slot_key_errors.append("levels[" + str(li) + "].board.slots[" + str(si) + "].chip")
	t.ok(slot_key_errors.size() == 0, prefix + "board slots use entity and never chip", _detail_values(slot_key_errors))

	var generators = project.get("generators", null)
	if typeof(generators) != TYPE_DICTIONARY:
		t.ok(false, prefix + "generators is a dictionary", str(typeof(generators)))
		generators = {}
	var generator_field_errors: Array = []
	for gid in generators:
		var generator = generators[gid]
		if typeof(generator) != TYPE_DICTIONARY:
			generator_field_errors.append("generators." + String(gid))
			continue
		for field in generator:
			if not GENERATOR_BEHAVIOR_FIELDS.has(String(field)):
				generator_field_errors.append("generators." + String(gid) + "." + String(field))
	t.ok(generator_field_errors.size() == 0, prefix + "generators contain behaviour fields only", _detail_values(generator_field_errors))

	var hud = project.get("hud", null)
	if typeof(hud) != TYPE_DICTIONARY:
		t.ok(false, prefix + "hud is a dictionary", str(typeof(hud)))
		hud = {}
	var hud_missing: Array = []
	for field in HUD_FIELDS:
		if not hud.has(field):
			hud_missing.append(String(field))
	t.ok(hud_missing.size() == 0, prefix + "HUD has all eight required fields", _detail_values(hud_missing))

	var meta = project.get("meta", null)
	if typeof(meta) != TYPE_DICTIONARY:
		t.ok(false, prefix + "meta is a dictionary", str(typeof(meta)))
	else:
		t.ok(not meta.has("duration"), prefix + "meta has no duration")

	var chip_cap_errors: Array = []
	for id in entities:
		var entity = entities[id]
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		if String(entity.get("kind", "")) != "chip":
			continue
		var max_level = entity.get("maxLevel", null)
		if not _is_number(max_level) or float(max_level) > 10.0:
			chip_cap_errors.append(String(id) + "=" + str(max_level))
	t.ok(chip_cap_errors.size() == 0, prefix + "every chip maxLevel is <= 10", _detail_values(chip_cap_errors))

	var timeline = project.get("timeline", null)
	if typeof(timeline) != TYPE_ARRAY:
		t.ok(false, prefix + "timeline is an array", str(typeof(timeline)))
		return
	var wait_events: Array = []
	var bad_at: Array = []
	for i in timeline.size():
		var event = timeline[i]
		if typeof(event) != TYPE_DICTIONARY:
			bad_at.append("timeline[" + str(i) + "]")
			continue
		if String(event.get("type", "")) == "wait":
			wait_events.append("timeline[" + str(i) + "]")
		if not _valid_at(event.get("at", null)):
			bad_at.append("timeline[" + str(i) + "].at")
	t.ok(wait_events.size() == 0, prefix + "timeline has no wait event", _detail_values(wait_events))
	t.ok(bad_at.size() == 0, prefix + "every at is numeric or a valid after/offset object", _detail_values(bad_at))


func _test_events(t, path: String, project: Dictionary) -> void:
	var prefix := path.get_file() + ": "
	var timeline = project.get("timeline", [])
	if typeof(timeline) != TYPE_ARRAY:
		t.ok(false, prefix + "event resolution skipped because timeline is not an array")
		return

	var result: Dictionary = EventModel.resolve(timeline)
	t.ok(bool(result.get("ok", false)), prefix + "event resolver succeeds", _event_error_codes(result.get("errors", [])))
	var events: Array = result.get("events", [])
	t.ok(events.size() == timeline.size(), prefix + "every timeline event resolves", str(events.size()))
	t.ok(_event_order_errors(events).size() == 0, prefix + "resolved events obey the deterministic sort key", _detail_values(_event_order_errors(events)))

	var repeat: Dictionary = EventModel.resolve(timeline)
	t.eq(_event_ids(events), _event_ids(repeat.get("events", [])), prefix + "event order is stable across repeated resolve")

	var end_time := float(result.get("end_time", -1.0))
	if path == SAMPLE:
		t.ok(absf(end_time - 30.0) <= 0.001, prefix + "M0 template ends at 30.0s", str(end_time))
		t.ok(_same_time_pair_count(events) >= 2, prefix + "template includes at least two same-time ordering probes", str(_same_time_pair_count(events)))
		_assert_before(t, events, "e10", "e11", prefix + "8.0s level_next(sim) precedes transition(view)")
		_assert_before(t, events, "e19", "e18", prefix + "24.0s camera(track=cam) precedes text(track=text)")


func _assert_before(t, events: Array, first_id: String, second_id: String, what: String) -> void:
	var first := _event_index(events, first_id)
	var second := _event_index(events, second_id)
	t.ok(first >= 0 and second >= 0 and first < second, what, "first=" + str(first) + " second=" + str(second))


func _event_order_errors(events: Array) -> Array:
	var errors: Array = []
	for i in range(1, events.size()):
		var previous = events[i - 1]
		var current = events[i]
		if not _event_key_lte(previous, current):
			errors.append("events[" + str(i - 1) + "]->events[" + str(i) + "]")
	return errors


func _event_key_lte(a: Dictionary, b: Dictionary) -> bool:
	var at_a := float(a.get("at", 0.0))
	var at_b := float(b.get("at", 0.0))
	if at_a != at_b:
		return at_a < at_b
	var priority_a := int(CHANNEL_PRIORITY.get(String(a.get("channel", "")), 9))
	var priority_b := int(CHANNEL_PRIORITY.get(String(b.get("channel", "")), 9))
	if priority_a != priority_b:
		return priority_a < priority_b
	var track_a := String(a.get("track", ""))
	var track_b := String(b.get("track", ""))
	if track_a != track_b:
		return track_a < track_b
	var order_a := int(a.get("order", 0))
	var order_b := int(b.get("order", 0))
	if order_a != order_b:
		return order_a < order_b
	return String(a.get("id", "")) <= String(b.get("id", ""))


func _same_time_pair_count(events: Array) -> int:
	var count := 0
	for i in range(1, events.size()):
		if float(events[i - 1].get("at", -1.0)) == float(events[i].get("at", -2.0)):
			count += 1
	return count


func _event_index(events: Array, id: String) -> int:
	for i in events.size():
		if String(events[i].get("id", "")) == id:
			return i
	return -1


func _event_ids(events: Array) -> Array:
	var ids: Array = []
	for event in events:
		ids.append(String(event.get("id", "")))
	return ids


func _valid_at(value) -> bool:
	if _is_number(value):
		return float(value) >= 0.0
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if not value.has("after") or not value.has("offset"):
		return false
	return typeof(value.get("after", null)) == TYPE_STRING \
		and not String(value.get("after", "")).is_empty() \
		and _is_number(value.get("offset", null))


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _find_key_paths(value, key: String, path: String, out: Array) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for child_key in value:
				var child_path := path + "." + String(child_key)
				if String(child_key) == key:
					out.append(child_path)
				_find_key_paths(value[child_key], key, child_path, out)
		TYPE_ARRAY:
			for i in value.size():
				_find_key_paths(value[i], key, path + "[" + str(i) + "]", out)


func _load_json(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


func _error_codes(errors: Array) -> String:
	return _codes(errors, "code")


func _warning_codes(warnings: Array) -> String:
	return _codes(warnings, "code")


func _event_error_codes(errors: Array) -> String:
	return _codes(errors, "code")


func _codes(items: Array, field: String) -> String:
	var codes: Array = []
	for item in items:
		if typeof(item) == TYPE_DICTIONARY:
			codes.append(String(item.get(field, "")))
	return ", ".join(codes)


func _detail_values(values: Array) -> String:
	if values.is_empty():
		return "<none>"
	var limit := mini(values.size(), 12)
	var out: Array = []
	for i in limit:
		out.append(String(values[i]))
	var detail := ", ".join(out)
	if values.size() > limit:
		detail += ", ..."
	return detail

