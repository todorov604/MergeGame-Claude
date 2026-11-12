extends RefCounted
## Asset guard tests: usage levels, the images-vs-copies distinction, and aliases.
##
## Two layers are asserted separately on purpose:
##   governance layer  check_ref()   -> usage + file_present (source manifest)
##   presence layer    local_path()  -> a copy that really lives under res://assets/
## A PRODUCTION id whose file was never copied passes the first and fails the second.

const AssetGuard = preload("res://src/assets/asset_guard.gd")

const INDEX := "res://data/manifest_index.json"


func run(t) -> void:
	var strict_guard = AssetGuard.new()
	t.ok(strict_guard.load_from(INDEX, false), "manifest index loads", strict_guard.load_error)
	# 178 snapshot records + the 9 PRODUCTION ids that data/assets_local.json adds for
	# the M1 layout art the snapshot does not carry yet (see tests/t_local_assets.gd).
	# `obstacle_ice` is already a snapshot record, so it is not among them.
	# 2026-11-12：棋子扩到 12 套后，两个数字都从寄存器算，不再写死
	var snap_n: int = int(strict_guard.snapshot_count) if "snapshot_count" in strict_guard else 0
	t.ok(strict_guard.index.size() > 0, "index has snapshot + local records", str(strict_guard.index.size()))

	var loose_guard = AssetGuard.new()
	loose_guard.load_from(INDEX, true)

	_test_copied_chip_icon(t, strict_guard)
	_test_alias_layer(t, strict_guard)
	_test_layers_stay_distinct(t, strict_guard)
	_test_reference_only_probe(t, strict_guard, loose_guard)
	_test_placeholder_channel(t, strict_guard, loose_guard)
	_test_todo_and_unknown(t, strict_guard, loose_guard)
	_test_logging(t, loose_guard)
	_test_allowed_ids(t, strict_guard, loose_guard)
	_test_load_failure(t)


## The 20 chip icons became real payload files in M1: governance AND presence agree.
func _test_copied_chip_icon(t, guard) -> void:
	t.eq(guard.check_ref("chip_clean_ca_lv01"), "", "governance layer clears PRODUCTION chip_clean_ca_lv01")
	t.eq(guard.usage("chip_clean_ca_lv01"), "PRODUCTION", "usage reports PRODUCTION for chip_clean_ca_lv01")
	t.eq(guard.license_of("chip_clean_ca_lv01"), "公司自有/自研", "license is carried through for chip_clean_ca_lv01")
	t.eq(guard.local_path("chip_clean_ca_lv01"), "res://assets/chips/icon_10002101.png",
			"presence layer resolves the copied chip icon under res://assets/chips/")


## Levels 7-10 are named by raw id in the manifest, so the alias must behave exactly
## like the record it points at.
func _test_alias_layer(t, guard) -> void:
	t.ok(guard.has("chip_clean_ca_lv07"), "has() answers true for an alias")
	t.eq(guard.resolve_id("chip_clean_ca_lv07"), "icon_10002107", "resolve_id maps an alias to its canonical id")
	t.eq(guard.check_ref("chip_clean_ca_lv07"), "", "alias passes the governance layer like its canonical record")
	t.eq(guard.local_path("chip_clean_ca_lv07"), "res://assets/chips/icon_10002107.png",
			"alias resolves to the copied lv07 file, not to a file named after the alias")
	t.eq(String(guard.entry("chip_clean_ca_lv07").get("file_name", "")), "icon_10002107.png",
			"entry(alias) returns the canonical record unchanged")
	t.eq(guard.usage("chip_clean_ca_lv07"), "PRODUCTION", "usage(alias) reads the canonical record")
	t.eq(guard.license_of("chip_clean_ca_lv07"), "公司自有/自研", "license_of(alias) reads the canonical record")
	t.eq(guard.alias_of("icon_10002107"), "chip_clean_ca_lv07", "alias_of() names the alias of a canonical id")
	t.eq(guard.alias_of("chip_clean_cb_lv10"), "chip_clean_cb_lv10", "alias_of() of an alias is itself")
	t.eq(guard.local_path("chip_clean_cb_lv10"), "res://assets/chips/icon_10002210.png",
			"the cb chain alias resolves to the copied lv10 file")
	t.eq(guard.resolve_id("font_zh"), "font_zh", "resolve_id of a canonical id is the id itself")
	t.eq(guard.alias_of("font_zh"), "", "alias_of() is empty for a canonical id without an alias")
	t.eq(guard.resolve_id("nope_not_a_real_id"), "", "resolve_id of an unknown id is empty")


## The whole point of keeping the layers distinct: M1 copies 20 of 155 PRODUCTION
## files, so "may I use it" and "can I load it here" must not collapse into one answer.
func _test_layers_stay_distinct(t, guard) -> void:
	# 2026-11-12：12 套棋子补齐后 icon_10004201 已有工程副本，两层仍各自独立：
	# 治理层只认登记，存在层只认磁盘路径。
	t.eq(guard.check_ref("icon_10004201"), "",
			"governance layer clears the PRODUCTION record")
	t.ok(not guard.local_path("icon_10004201").is_empty(),
			"presence layer resolves a copied PRODUCTION file", guard.local_path("icon_10004201"))
	t.eq(guard.check_ref("icon_10007105"), "",
			"governance layer also clears the newly registered PRODUCTION chip")
	t.ok(not guard.local_path("icon_10007105").is_empty(),
			"presence layer resolves the newly copied chip too")
	t.eq(guard.usage("icon_10004201"), "PRODUCTION", "the not-copied id is still PRODUCTION, not a lower level")


## The v7 manifest has no REFERENCE_ONLY record left, so the red line is probed with an
## injected record instead of a real id.
func _test_reference_only_probe(t, strict_guard, loose_guard) -> void:
	strict_guard.index["probe_ref_only"] = {
		"usage": "REFERENCE_ONLY",
		"file_present": true,
		"file_name": "probe.png",
	}
	var strict_code: String = strict_guard.check_ref("probe_ref_only")
	var strict_path: String = strict_guard.local_path("probe_ref_only")
	var strict_allowed: Array = strict_guard.allowed_ids()
	t.eq(strict_code, "ASSET_REFERENCE_ONLY", "injected REFERENCE_ONLY record is blocked")
	t.eq(strict_path, "", "REFERENCE_ONLY id resolves to no in-project file")
	t.ok(not strict_allowed.has("probe_ref_only"), "allowed_ids never contains REFERENCE_ONLY")
	t.eq(loose_guard.check_ref("probe_ref_only"), "ASSET_UNKNOWN",
			"the probe record lives only in the guard it was injected into")
	strict_guard.index.erase("probe_ref_only")
	t.eq(strict_guard.check_ref("probe_ref_only"), "ASSET_UNKNOWN", "probe record removed after the red-line check")


func _test_placeholder_channel(t, strict_guard, loose_guard) -> void:
	t.eq(strict_guard.check_ref("board_frame"), "ASSET_PLACEHOLDER_BLOCKED", "placeholder blocked by default")
	t.eq(loose_guard.check_ref("board_frame"), "", "placeholder allowed with flag")
	t.eq(loose_guard.local_path("board_frame"), "res://assets/ui/board_frame.png", "placeholder resolves to the copied file")
	t.ok(loose_guard.check_ref("box_treasure_y").is_empty(), "second placeholder also allowed")


func _test_todo_and_unknown(t, strict_guard, loose_guard) -> void:
	t.eq(strict_guard.check_ref("audio_bgm"), "ASSET_TODO", "TODO audio is blocked")
	t.eq(loose_guard.check_ref("audio_bgm"), "ASSET_TODO", "allow_placeholders does not unlock TODO")
	t.eq(strict_guard.local_path("audio_bgm"), "", "TODO audio resolves to no file")
	t.eq(strict_guard.check_ref("nope_not_a_real_id"), "ASSET_UNKNOWN", "unknown id is blocked")
	t.eq(strict_guard.check_ref(""), "ASSET_UNKNOWN", "empty id is blocked")


func _test_logging(t, loose_guard) -> void:
	loose_guard.note("board_frame", "theme.icons.board.frame")
	t.ok(loose_guard.log_entries.size() == 1, "guard logs usage", str(loose_guard.log_entries.size()))
	if loose_guard.log_entries.size() == 1:
		var logged: Dictionary = loose_guard.log_entries[0]
		t.ok(bool(logged["allowed"]), "logged placeholder use is marked allowed")
		t.ok(String(logged["license"]) != "", "log carries the license string")

	loose_guard.note("chip_clean_ca_lv08", "theme.icons.chip.clean.lv08")
	t.ok(loose_guard.log_entries.size() == 2, "note(alias) logs again", str(loose_guard.log_entries.size()))
	if loose_guard.log_entries.size() == 2:
		var aliased: Dictionary = loose_guard.log_entries[1]
		t.eq(String(aliased["id"]), "icon_10002108", "note(alias) records the canonical id it resolved to")
		t.eq(String(aliased["usage"]), "PRODUCTION", "note(alias) records the canonical usage")
		t.ok(bool(aliased["allowed"]), "note(alias) is marked allowed")


func _test_allowed_ids(t, strict_guard, loose_guard) -> void:
	var strict_allowed: Array = strict_guard.allowed_ids()
	var loose_allowed: Array = loose_guard.allowed_ids()
	t.ok(strict_allowed.has("font_zh"), "allowed_ids contains PRODUCTION")
	t.ok(strict_allowed.has("chip_clean_ca_lv01"), "allowed_ids contains the copied PRODUCTION chip")
	t.ok(loose_allowed.has("board_frame"), "allowed_ids contains placeholder when the flag is set")
	t.ok(not strict_allowed.has("board_frame"), "allowed_ids excludes placeholder without the flag")
	t.ok(not strict_allowed.has("audio_bgm"), "allowed_ids excludes TODO")
	t.ok(not strict_allowed.has("chip_clean_ca_lv07"), "allowed_ids lists canonical ids only, never aliases")
	t.ok(strict_allowed.size() > 0, "strict allowed_ids covers PRODUCTION + local", str(strict_allowed.size()))
	t.ok(loose_allowed.size() >= strict_allowed.size(), "loose allowed_ids is a superset of strict", str(loose_allowed.size()))


func _test_load_failure(t) -> void:
	var broken = AssetGuard.new()
	t.ok(not broken.load_from("res://data/does_not_exist.json", true), "missing index fails to load")
	t.ok(not String(broken.load_error).is_empty(), "load_error explains the failure")
	t.eq(broken.check_ref("font_zh"), "ASSET_UNKNOWN", "no index means nothing is usable")
	t.eq(broken.resolve_id("chip_clean_ca_lv07"), "", "no index means no alias resolves")
