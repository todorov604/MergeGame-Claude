extends RefCounted
## Manifest snapshot audit. Frozen expectations only: no network and no 00_design reads.

const INDEX := "res://data/manifest_index.json"
const EXPECTED_RESOURCE_COUNT := 74
const EXPECTED_COUNTS := {
	"REFERENCE_ONLY": 47,
	"PLACEHOLDER": 20,
	"PRODUCTION": 2,
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
]
const VALID_USAGES := ["REFERENCE_ONLY", "PLACEHOLDER", "PRODUCTION", "TODO"]
const ABS_DRIVE_PATTERN := "(?<![A-Za-z0-9_])[A-Za-z]:[\\\\/]"


func run(t) -> void:
	var root := _load_json(INDEX)
	t.ok(not root.is_empty(), "manifest_index.json parses as an object")
	if root.is_empty():
		return

	t.eq(int(root.get("count", -1)), EXPECTED_RESOURCE_COUNT, "snapshot count metadata is 74")
	var resources = root.get("resources", null)
	if typeof(resources) != TYPE_DICTIONARY:
		t.ok(false, "resources is a dictionary", str(typeof(resources)))
		return
	t.eq(resources.size(), EXPECTED_RESOURCE_COUNT, "snapshot has 74 resources")

	_test_usage_counts(t, root, resources)
	_test_missing_files(t, root, resources)
	_test_record_contract(t, resources)
	_test_no_absolute_paths(t, root)
	_test_known_ids(t, resources)


func _test_usage_counts(t, root: Dictionary, resources: Dictionary) -> void:
	var declared = root.get("usage_counts", null)
	t.ok(typeof(declared) == TYPE_DICTIONARY, "usage_counts is a dictionary")
	if typeof(declared) != TYPE_DICTIONARY:
		declared = {}

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


func _test_record_contract(t, resources: Dictionary) -> void:
	var missing_fields: Array = []
	var invalid_usage_type: Array = []
	var invalid_present_type: Array = []
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
		var file_name := String(record.get("file_name", ""))
		if file_name.find("/") >= 0 or file_name.find("\\") >= 0:
			non_basename_paths.append(String(id) + "=" + file_name)

	t.ok(missing_fields.size() == 0, "every record has all required fields", _detail_values(missing_fields))
	t.ok(invalid_usage_type.size() == 0, "every usage field is a string", _detail_values(invalid_usage_type))
	t.ok(invalid_present_type.size() == 0, "every file_present field is a bool", _detail_values(invalid_present_type))
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
	_expect_usage(t, resources, "chip_clean_ca_lv01", "REFERENCE_ONLY")
	_expect_usage(t, resources, "obstacle_web", "REFERENCE_ONLY")
	_expect_usage(t, resources, "char_order_01_idle", "REFERENCE_ONLY")
	_expect_usage(t, resources, "board_bg", "REFERENCE_ONLY")
	_expect_usage(t, resources, "font_zh", "PRODUCTION")
	_expect_usage(t, resources, "font_en", "PRODUCTION")

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


