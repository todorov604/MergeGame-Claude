extends RefCounted
## Manifest snapshot audit. Frozen expectations only: no network and no 00_design reads.
##
## The snapshot keeps two layers apart on purpose:
##   governance layer  `usage` + `file_present`  -> does the *source* file exist?
##   presence layer    `in_project`              -> is a copy of it under res://assets/?
## A PRODUCTION record can pass the governance layer and still have in_project=false,
## because M1 only copies the 20 chip icons, the 2 fonts and the 5 placeholders.

const INDEX := "res://data/manifest_index.json"
const EXPECTED_RESOURCE_COUNT := 180
const EXPECTED_COUNTS := {
	"REFERENCE_ONLY": 0,
	"PLACEHOLDER": 20,
	"PRODUCTION": 155,
	"TODO": 5,
}
const EXPECTED_MISSING := [
	"audio_bgm",
	"audio_merge",
	"audio_click",
	"audio_star",
	"audio_levelup",
]
const REQUIRED_FIELDS := [
	"usage",
	"status",
	"priority",
	"category",
	"use",
	"license",
	"file_name",
	"file_present",
	"target_size",
	"actual_size",
	"fit",
	"animation",
	"in_project",
]
const VALID_USAGES := ["REFERENCE_ONLY", "PLACEHOLDER", "PRODUCTION", "TODO"]
const ABS_DRIVE_PATTERN := "(?<![A-Za-z0-9_])[A-Za-z]:[\\\\/]"
const DATE_PATTERN := "^\\d{4}-\\d{2}-\\d{2}$"

## The v7 manifest names chain levels 7-10 by raw file id; the alias map restores the
## chip_clean_*_lvNN naming that levels 1-6 already use.
const EXPECTED_ALIASES := {
	"chip_clean_ca_lv07": "icon_10002107",
	"chip_clean_ca_lv08": "icon_10002108",
	"chip_clean_ca_lv09": "icon_10002109",
	"chip_clean_ca_lv10": "icon_10002110",
	"chip_clean_cb_lv07": "icon_10002207",
	"chip_clean_cb_lv08": "icon_10002208",
	"chip_clean_cb_lv09": "icon_10002209",
	"chip_clean_cb_lv10": "icon_10002210",
}

## Where AssetGuard looks for a copied payload file.
const PROJECT_ASSET_DIRS := ["res://assets/ui", "res://assets/fonts", "res://assets/chips"]

## The 20 copied chip icons (canonical record ids, not the lv07-10 aliases).
const EXPECTED_CHIP_IDS := [
	"chip_clean_ca_lv01",
	"chip_clean_ca_lv02",
	"chip_clean_ca_lv03",
	"chip_clean_ca_lv04",
	"chip_clean_ca_lv05",
	"chip_clean_ca_lv06",
	"icon_10002107",
	"icon_10002108",
	"icon_10002109",
	"icon_10002110",
	"chip_clean_cb_lv01",
	"chip_clean_cb_lv02",
	"chip_clean_cb_lv03",
	"chip_clean_cb_lv04",
	"chip_clean_cb_lv05",
	"chip_clean_cb_lv06",
	"icon_10002207",
	"icon_10002208",
	"icon_10002209",
	"icon_10002210",
]

## M1 visual fidelity added 15 more copied records (the layout art that used to be
## registered but absent: background layers, board cells/frame, top bar, order card,
## buttons, obstacles), so the presence layer now covers 42 records = 20 chip icons +
## 2 fonts + 5 placeholder files + those 15.
const EXPECTED_IN_PROJECT := [
	"board_bg",
	"board_frame",
	"box_energe_w",
	"box_safe_x",
	"box_treasure_y",
	"chip_clean_ca_lv01",
	"chip_clean_ca_lv02",
	"chip_clean_ca_lv03",
	"chip_clean_ca_lv04",
	"chip_clean_ca_lv05",
	"chip_clean_ca_lv06",
	"chip_clean_cb_lv01",
	"chip_clean_cb_lv02",
	"chip_clean_cb_lv03",
	"chip_clean_cb_lv04",
	"chip_clean_cb_lv05",
	"chip_clean_cb_lv06",
	"font_en",
	"font_zh",
	"icon_10001101",
	"icon_10001102",
	"icon_10001103",
	"icon_10001104",
	"icon_10001105",
	"icon_10001106",
	"icon_10001107",
	"icon_10001108",
	"icon_10001109",
	"icon_10001110",
	"icon_10002107",
	"icon_10002108",
	"icon_10002109",
	"icon_10002110",
	"icon_10002207",
	"icon_10002208",
	"icon_10002209",
	"icon_10002210",
	"icon_10005101",
	"icon_10005102",
	"icon_10005103",
	"icon_10005104",
	"icon_10005105",
	"icon_10005106",
	"icon_10005107",
	"icon_10005108",
	"icon_10005109",
	"icon_10005110",
	"obstacle_bubble",
	"obstacle_ice",
	"obstacle_lock",
	"obstacle_web",
	"slot_empty",
	"slot_locked",
	"ui_button_primary",
	"ui_button_secondary",
	"ui_energy_timer",
	"ui_exclamation",
	"ui_icon_star",
	"ui_level_badge",
	"ui_order_card",
	"ui_order_card_done",
	"ui_select_frame",
	"ui_topbar",

]


func run(t) -> void:
	var root := _load_json(INDEX)
	t.ok(not root.is_empty(), "manifest_index.json parses as an object")
	if root.is_empty():
		return

	t.eq(int(root.get("count", -1)), EXPECTED_RESOURCE_COUNT, "snapshot count metadata is 180")
	t.eq(int(root.get("manifest_version", -1)), 7, "manifest_version is copied from the source manifest")
	t.eq(String(root.get("manifest_generated", "")), "2026-11-04", "manifest_generated is copied from the source manifest")
	_test_snapshot_date(t, root)

	var resources = root.get("resources", null)
	if typeof(resources) != TYPE_DICTIONARY:
		t.ok(false, "resources is a dictionary", str(typeof(resources)))
		return
	t.eq(resources.size(), EXPECTED_RESOURCE_COUNT, "snapshot has 180 resources")

	_test_usage_counts(t, root, resources)
	_test_missing_files(t, root, resources)
	_test_aliases(t, root, resources)
	_test_in_project(t, resources)
	_test_record_contract(t, resources)
	_test_no_absolute_paths(t, root)
	_test_known_ids(t, resources)


func _test_snapshot_date(t, root: Dictionary) -> void:
	var stamp := String(root.get("snapshot_date", ""))
	var re := RegEx.create_from_string(DATE_PATTERN)
	t.ok(re != null and re.search(stamp) != null, "snapshot_date is an ISO date", stamp)
	# The snapshot is a committed artifact: nothing rebuilds it during a test run, so
	# comparing it to "today" would flip this gate red on the next calendar day (and
	# on accept.sh step 4's relocated copy). Assert a real, non-future date that is
	# not older than the source manifest it was generated from instead.
	var today := Time.get_date_string_from_system()
	var generated := String(root.get("manifest_generated", ""))
	t.ok(stamp <= today, "snapshot_date is not in the future", "%s > %s" % [stamp, today])
	t.ok(generated.is_empty() or stamp >= generated,
			"snapshot_date is not older than manifest_generated", "%s < %s" % [stamp, generated])


func _test_usage_counts(t, root: Dictionary, resources: Dictionary) -> void:
	var declared = root.get("usage_counts", null)
	t.ok(typeof(declared) == TYPE_DICTIONARY, "usage_counts is a dictionary")
	if typeof(declared) != TYPE_DICTIONARY:
		declared = {}

	var missing_keys: Array = []
	for usage in VALID_USAGES:
		if not declared.has(usage):
			missing_keys.append(String(usage))
	t.ok(missing_keys.size() == 0, "usage_counts emits all four keys even when zero", _detail_values(missing_keys))

	var actual := {
		"REFERENCE_ONLY": 0,
		"PLACEHOLDER": 0,
		"PRODUCTION": 0,
		"TODO": 0,
	}
	var invalid: Array = []
	for id in resources:
		var record = resources[id]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var usage := String(record.get("usage", ""))
		if actual.has(usage):
			actual[usage] = int(actual[usage]) + 1
		else:
			invalid.append(String(id))

	t.ok(invalid.size() == 0, "all usage values are in the four-level vocabulary", _detail_values(invalid))
	for usage in EXPECTED_COUNTS:
		t.eq(int(declared.get(usage, -1)), int(EXPECTED_COUNTS[usage]), "declared usage count: " + String(usage))
		t.eq(int(actual.get(usage, -1)), int(EXPECTED_COUNTS[usage]), "actual resource usage count: " + String(usage))


func _test_missing_files(t, root: Dictionary, resources: Dictionary) -> void:
	var missing = root.get("missing_files", null)
	if typeof(missing) != TYPE_ARRAY:
		t.ok(false, "missing_files is an array", str(typeof(missing)))
		return

	var declared := _sorted_string_array(missing)
	var expected := _sorted_string_array(EXPECTED_MISSING)
	t.ok(declared.size() == 5, "missing_files has exactly five ids", str(declared))
	t.ok(declared == expected, "missing_files is exactly the five audio ids", str(declared))

	var absent: Array = []
	for id in resources:
		var record = resources[id]
		if typeof(record) == TYPE_DICTIONARY and not bool(record.get("file_present", true)):
			absent.append(String(id))
	absent.sort()
	t.ok(absent == expected, "file_present=false ids match missing_files", str(absent))


func _test_aliases(t, root: Dictionary, resources: Dictionary) -> void:
	var aliases = root.get("aliases", null)
	if typeof(aliases) != TYPE_DICTIONARY:
		t.ok(false, "snapshot carries an aliases table", str(typeof(aliases)))
		return
	t.eq(aliases.size(), EXPECTED_ALIASES.size(), "aliases table has eight entries")

	var wrong: Array = []
	for alias in EXPECTED_ALIASES:
		var expected := String(EXPECTED_ALIASES[alias])
		if String(aliases.get(alias, "")) != expected:
			wrong.append("%s->%s" % [alias, String(aliases.get(alias, "<missing>"))])
	t.ok(wrong.size() == 0, "every alias points at the raw lv07-10 id", _detail_values(wrong))

	var dangling: Array = []
	for alias in aliases:
		var name := String(alias)
		if not EXPECTED_ALIASES.has(name):
			dangling.append("extra:" + name)
		elif not resources.has(String(aliases[alias])):
			dangling.append("dangling:" + name)
		elif resources.has(name):
			dangling.append("shadowed:" + name)
	t.ok(dangling.size() == 0, "aliases add no extras, dangle nowhere and shadow no record", _detail_values(dangling))


func _test_in_project(t, resources: Dictionary) -> void:
	var declared: Array = []
	for id in resources:
		var record = resources[id]
		if typeof(record) == TYPE_DICTIONARY and bool(record.get("in_project", false)):
			declared.append(String(id))
	declared.sort()

	var expected := _sorted_string_array(EXPECTED_IN_PROJECT)
	t.ok(declared.size() == 63, "exactly 63 records report in_project=true", str(declared.size()))
	t.ok(declared == expected, "in_project=true ids are the 40 chip icons + 2 fonts + 5 placeholders + 15 layout files", _detail_values(declared))

	# The flag must describe the disk, not a wish: recompute it from res://assets.
	var on_disk := _project_basenames()
	var mismatched: Array = []
	for id in resources:
		var record = resources[id]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var file_name := String(record.get("file_name", ""))
		var present := not file_name.is_empty() and on_disk.has(file_name)
		if present != bool(record.get("in_project", false)):
			mismatched.append(String(id))
	mismatched.sort()
	t.ok(mismatched.size() == 0, "in_project matches the files that really live under res://assets", _detail_values(mismatched))

	# Every copied chip icon carries a canonical PRODUCTION record.
	var chip_problems: Array = []
	for id in EXPECTED_CHIP_IDS:
		var record = resources.get(String(id), null)
		if typeof(record) != TYPE_DICTIONARY:
			chip_problems.append("missing:" + String(id))
			continue
		if String(record.get("usage", "")) != "PRODUCTION":
			chip_problems.append("usage:" + String(id))
		if not bool(record.get("in_project", false)):
			chip_problems.append("not-in-project:" + String(id))
	t.ok(chip_problems.size() == 0, "all 20 copied chip icons are PRODUCTION and in_project", _detail_values(chip_problems))


func _test_record_contract(t, resources: Dictionary) -> void:
	var missing_fields: Array = []
	var invalid_usage_type: Array = []
	var invalid_present_type: Array = []
	var invalid_in_project_type: Array = []
	var non_basename_paths: Array = []
	for id in resources:
		var record = resources[id]
		if typeof(record) != TYPE_DICTIONARY:
			missing_fields.append(String(id) + ".<record>")
			continue
		for field in REQUIRED_FIELDS:
			if not record.has(field):
				missing_fields.append(String(id) + "." + String(field))
		if typeof(record.get("usage", null)) != TYPE_STRING:
			invalid_usage_type.append(String(id))
		if typeof(record.get("file_present", null)) != TYPE_BOOL:
			invalid_present_type.append(String(id))
		if typeof(record.get("in_project", null)) != TYPE_BOOL:
			invalid_in_project_type.append(String(id))
		var file_name := String(record.get("file_name", ""))
		if file_name.find("/") >= 0 or file_name.find("\\") >= 0:
			non_basename_paths.append(String(id) + "=" + file_name)

	t.ok(missing_fields.size() == 0, "every record has all required fields", _detail_values(missing_fields))
	t.ok(invalid_usage_type.size() == 0, "every usage field is a string", _detail_values(invalid_usage_type))
	t.ok(invalid_present_type.size() == 0, "every file_present field is a bool", _detail_values(invalid_present_type))
	t.ok(invalid_in_project_type.size() == 0, "every in_project field is a bool", _detail_values(invalid_in_project_type))
	t.ok(non_basename_paths.size() == 0, "snapshot file_name values are basenames only", _detail_values(non_basename_paths))


func _test_no_absolute_paths(t, root: Dictionary) -> void:
	var drive_re := RegEx.new()
	var compile_err := drive_re.compile(ABS_DRIVE_PATTERN)
	t.ok(compile_err == OK, "manifest absolute-path regex compiles", str(compile_err))
	if compile_err != OK:
		return

	var hits: Array = []
	_scan_strings(root, "root", drive_re, hits)
	t.ok(hits.size() == 0, "manifest snapshot has no Windows drive absolute paths", _detail_values(hits))


func _test_known_ids(t, resources: Dictionary) -> void:
	_expect_usage(t, resources, "chip_clean_ca_lv01", "PRODUCTION")
	_expect_usage(t, resources, "obstacle_web", "PRODUCTION")
	_expect_usage(t, resources, "char_order_01_idle", "PRODUCTION")
	_expect_usage(t, resources, "board_bg", "PRODUCTION")
	_expect_usage(t, resources, "font_zh", "PRODUCTION")
	_expect_usage(t, resources, "font_en", "PRODUCTION")
	_expect_usage(t, resources, "board_frame", "PLACEHOLDER")
	_expect_usage(t, resources, "audio_bgm", "TODO")

	_expect_in_project(t, resources, "chip_clean_ca_lv01", true)
	_expect_in_project(t, resources, "font_zh", true)
	_expect_in_project(t, resources, "board_frame", true)
	_expect_in_project(t, resources, "audio_bgm", false)

	var placeholders := [
		"board_frame",
		"ui_icon_star",
		"box_safe_x",
		"box_energe_w",
		"box_treasure_y",
	]
	for id in placeholders:
		_expect_usage(t, resources, String(id), "PLACEHOLDER")
		var record = resources.get(id, null)
		var present := typeof(record) == TYPE_DICTIONARY and bool(record.get("file_present", false))
		t.ok(present, "placeholder has file_present=true: " + String(id))


func _expect_usage(t, resources: Dictionary, id: String, expected: String) -> void:
	var record = resources.get(id, null)
	var actual := "<missing>"
	if typeof(record) == TYPE_DICTIONARY:
		actual = String(record.get("usage", "<missing>"))
	t.eq(actual, expected, "known id usage: " + id)


func _expect_in_project(t, resources: Dictionary, id: String, expected: bool) -> void:
	var record = resources.get(id, null)
	if typeof(record) != TYPE_DICTIONARY:
		t.ok(false, "known id in_project: " + id, "record is missing")
		return
	var value = record.get("in_project", null)
	if typeof(value) != TYPE_BOOL:
		t.ok(false, "known id in_project: " + id, "in_project type=" + str(typeof(value)))
		return
	t.eq(bool(value), expected, "known id in_project: " + id)


func _project_basenames() -> Dictionary:
	var out := {}
	for dir_path in PROJECT_ASSET_DIRS:
		var dir := DirAccess.open(String(dir_path))
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				out[entry] = true
			entry = dir.get_next()
		dir.list_dir_end()
	return out


func _scan_strings(value, path: String, drive_re: RegEx, hits: Array) -> void:
	match typeof(value):
		TYPE_STRING:
			if drive_re.search(String(value)) != null:
				hits.append(path)
		TYPE_DICTIONARY:
			for key in value:
				_scan_strings(value[key], path + "." + String(key), drive_re, hits)
		TYPE_ARRAY:
			for i in value.size():
				_scan_strings(value[i], path + "[" + str(i) + "]", drive_re, hits)


func _sorted_string_array(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	out.sort()
	return out


func _load_json(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


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
