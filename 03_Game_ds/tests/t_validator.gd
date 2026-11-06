extends RefCounted
## Validator tests: the sample must pass, every broken fixture must fail with its
## own rule code, and --strict must promote warnings without hiding them.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ProjectValidator = preload("res://src/validate/validator.gd")

const INDEX := "res://data/manifest_index.json"
const SAMPLE := "res://data/sample_project.json"
const OK_MIN := "res://tests/fixtures/ok_min.json"
const OK_PLACEHOLDER := "res://tests/fixtures/ok_with_placeholders.json"
const CASES := "res://tests/fixtures/cases.json"


func _guard(allow_placeholders: bool):
	var g = AssetGuard.new()
	g.load_from(INDEX, allow_placeholders)
	return g


func run(t) -> void:
	_test_good_projects(t)
	_test_sample_stats(t)
	_test_broken_fixtures(t)
	_test_placeholder_channel(t)
	_test_strict_semantics(t)
	_test_io_errors(t)


func _test_good_projects(t) -> void:
	var r = ProjectValidator.validate_file(OK_MIN, _guard(true), true)
	t.ok(bool(r.ok), "ok_min.json validates in strict mode", str(r.codes()))
	if not r.ok:
		for line in r.lines():
			print("     ", line)

	var rs = ProjectValidator.validate_file(SAMPLE, _guard(false), true)
	t.ok(bool(rs.ok), "sample_project.json validates in strict mode without placeholders", str(rs.codes()))
	t.eq(rs.errors.size(), 0, "sample has zero errors")
	t.eq(rs.warnings.size(), 0, "sample has zero warnings with the default (chip-icon) theme")


func _test_sample_stats(t) -> void:
	var r = ProjectValidator.validate_file(SAMPLE, _guard(false), false)
	t.eq(int(r.stats.get("levels", -1)), 2, "sample declares 2 levels")
	t.eq(int(r.stats.get("events", -1)), 21, "sample declares 21 events")
	t.ok(is_equal_approx(float(r.stats.get("end_time", -1.0)), 30.0), "sample timeline ends at 30.0s", str(r.stats.get("end_time")))
	t.eq(int(r.stats.get("entities", -1)), 15, "sample declares 15 entities")
	# M1: data/themes/default ships chip_icons for CleanSet_Ca and CleanSet_Cb, ten
	# levels each (20 refs), plus the icons.ui layout block (21 refs) the visual
	# fidelity goal added, so the usage rule must see 41 theme asset refs.
	t.eq(int(r.stats.get("asset_refs", -1)), 71, "default theme references its 20 chip icons + 51 layout icons")


func _test_broken_fixtures(t) -> void:
	var j := JSON.new()
	var parsed := j.parse(FileAccess.get_file_as_string(CASES))
	t.ok(parsed == OK, "fixture case table parses")
	if parsed != OK:
		return
	var cases: Array = (j.data as Dictionary).get("cases", [])
	t.ok(cases.size() >= 20, "fixture case table is populated", str(cases.size()))
	for c in cases:
		var file := String(c.get("file", ""))
		var code := String(c.get("code", ""))
		var strict := bool(c.get("strict", false))
		var allow := bool(c.get("allow_placeholders", true))
		var r = ProjectValidator.validate_file(file, _guard(allow), strict)
		var name := file.get_file()
		t.ok(not bool(r.ok), "fixture rejected: " + name)
		t.has_code(r.errors, code, "%s -> %s" % [name, code])


func _test_placeholder_channel(t) -> void:
	var denied = ProjectValidator.validate_file(OK_PLACEHOLDER, _guard(false), false)
	t.ok(not bool(denied.ok), "placeholder theme is rejected without the flag")
	t.has_code(denied.errors, "ASSET_PLACEHOLDER_BLOCKED", "denial reports ASSET_PLACEHOLDER_BLOCKED")
	# The theme also carries a chip_icons leaf (box_safe_x for CleanSet_Ca Lv1); the
	# usage rule has to walk that block too, otherwise a chip icon would be the one
	# asset family the pre-render gate never looks at.
	var chip_paths := _paths_under(denied.errors, "theme.chip_icons")
	t.ok(chip_paths.size() >= 1, "PLACEHOLDER chip_icons leaf reaches the usage rule",
			"paths=" + str(_paths_of(denied.errors)))
	# A per-level project override (`entities.<id>.visual.icons.<level>`) is the third
	# precedence layer ThemeLoader reads; it must be walked too, otherwise a bad id
	# there passes `validate --strict` and the view silently falls back to procedural.
	var entity_paths := _paths_under(denied.errors, "entities.A.visual.icons")
	t.ok(entity_paths.size() >= 1, "project per-level chip icon reaches the usage rule",
			"paths=" + str(_paths_of(denied.errors)))

	var allowed = ProjectValidator.validate_file(OK_PLACEHOLDER, _guard(true), false)
	t.ok(bool(allowed.ok), "placeholder theme is accepted with --allow-placeholders", str(allowed.codes()))
	t.eq(allowed.warnings.size(), 0, "allow_placeholders does not create warnings by itself")


func _test_strict_semantics(t) -> void:
	var warn_only := "res://tests/fixtures/broken/bad_meta_duration.json"
	var lenient = ProjectValidator.validate_file(warn_only, _guard(true), false)
	t.ok(bool(lenient.ok), "a warning alone does not fail a non-strict run")
	t.ok(lenient.codes().is_empty(), "warning-only fixture has no errors")
	var found := false
	for w in lenient.warnings:
		if String(w.get("code", "")) == "META_DURATION_PRESENT":
			found = true
	t.ok(found, "warning META_DURATION_PRESENT is reported")

	var strict_run = ProjectValidator.validate_file(warn_only, _guard(true), true)
	t.ok(not bool(strict_run.ok), "--strict fails the same file")
	t.has_code(strict_run.errors, "META_DURATION_PRESENT", "--strict keeps the original code")


func _test_io_errors(t) -> void:
	var missing = ProjectValidator.validate_file("res://tests/fixtures/nope.json", _guard(true), false)
	t.ok(not bool(missing.ok), "missing project file fails")
	t.has_code(missing.errors, "IO_NOT_FOUND", "missing project reports IO_NOT_FOUND")

	var not_json = ProjectValidator.validate_file("res://tests/fixtures/not_json.json", _guard(true), false)
	t.ok(not bool(not_json.ok), "invalid JSON fails")
	t.has_code(not_json.errors, "JSON_PARSE", "invalid JSON reports JSON_PARSE")

	var arr = ProjectValidator.validate_file("res://tests/fixtures/array_root.json", _guard(true), false)
	t.ok(not bool(arr.ok), "non-object root fails")
	t.has_code(arr.errors, "JSON_ROOT", "non-object root reports JSON_ROOT")


func _paths_under(errors: Array, prefix: String) -> Array:
	var out: Array = []
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("path", "")).begins_with(prefix):
			out.append(String(e.get("path", "")))
	return out


func _paths_of(errors: Array) -> Array:
	var out: Array = []
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(String(e.get("path", "")))
	return out

