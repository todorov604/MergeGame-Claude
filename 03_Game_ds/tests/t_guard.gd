extends RefCounted
## Asset guard tests: the three usage levels, the TODO block, and the fact that a
## REFERENCE_ONLY id cannot even be resolved to a file inside this project.

const AssetGuard = preload("res://src/assets/asset_guard.gd")

const INDEX := "res://data/manifest_index.json"


func run(t) -> void:
	var strict_guard = AssetGuard.new()
	t.ok(strict_guard.load_from(INDEX, false), "manifest index loads", strict_guard.load_error)
	t.ok(strict_guard.index.size() == 74, "index has 74 resources", str(strict_guard.index.size()))

	var loose_guard = AssetGuard.new()
	loose_guard.load_from(INDEX, true)

	# --- REFERENCE_ONLY: blocked in both modes ---
	t.eq(strict_guard.check_ref("chip_clean_ca_lv01"), "ASSET_REFERENCE_ONLY", "chip icon is REFERENCE_ONLY")
	t.eq(loose_guard.check_ref("chip_clean_ca_lv01"), "ASSET_REFERENCE_ONLY", "allow_placeholders does not unlock REFERENCE_ONLY")
	t.eq(strict_guard.check_ref("obstacle_web"), "ASSET_REFERENCE_ONLY", "obstacle_web is REFERENCE_ONLY")
	t.eq(strict_guard.local_path("chip_clean_ca_lv01"), "", "REFERENCE_ONLY id resolves to no in-project file")
	t.ok(strict_guard.usage("chip_clean_ca_lv01") == "REFERENCE_ONLY", "usage reports REFERENCE_ONLY")

	# --- PLACEHOLDER: blocked unless explicitly allowed ---
	t.eq(strict_guard.check_ref("board_frame"), "ASSET_PLACEHOLDER_BLOCKED", "placeholder blocked by default")
	t.eq(loose_guard.check_ref("board_frame"), "", "placeholder allowed with flag")
	t.eq(loose_guard.local_path("board_frame"), "res://assets/ui/board_frame.png", "placeholder resolves to the copied file")
	t.ok(loose_guard.check_ref("box_treasure_y").is_empty(), "second placeholder also allowed")

	# --- PRODUCTION: always allowed ---
	t.eq(strict_guard.check_ref("font_zh"), "", "PRODUCTION font allowed")
	t.eq(strict_guard.local_path("font_zh"), "res://assets/fonts/font_zh.otf", "PRODUCTION font resolves to the copied file")

	# --- TODO / unknown ---
	t.eq(strict_guard.check_ref("audio_bgm"), "ASSET_TODO", "TODO audio is blocked")
	t.eq(loose_guard.check_ref("audio_bgm"), "ASSET_TODO", "allow_placeholders does not unlock TODO")
	t.eq(strict_guard.check_ref("nope_not_a_real_id"), "ASSET_UNKNOWN", "unknown id is blocked")
	t.eq(strict_guard.check_ref(""), "ASSET_UNKNOWN", "empty id is blocked")

	# --- logging ---
	loose_guard.note("board_frame", "theme.icons.board.frame")
	t.ok(loose_guard.log_entries.size() == 1, "guard logs usage", str(loose_guard.log_entries.size()))
	if loose_guard.log_entries.size() == 1:
		var entry: Dictionary = loose_guard.log_entries[0]
		t.ok(bool(entry["allowed"]), "logged placeholder use is marked allowed")
		t.ok(String(entry["license"]) != "", "log carries the license string")

	# --- allowed id enumeration ---
	var allowed: Array = loose_guard.allowed_ids()
	t.ok(allowed.has("font_zh"), "allowed_ids contains PRODUCTION")
	t.ok(allowed.has("board_frame"), "allowed_ids contains placeholder when the flag is set")
	t.ok(not allowed.has("chip_clean_ca_lv01"), "allowed_ids never contains REFERENCE_ONLY")

	# --- load failure surface ---
	var broken = AssetGuard.new()
	t.ok(not broken.load_from("res://data/does_not_exist.json", true), "missing index fails to load")
	t.ok(not String(broken.load_error).is_empty(), "load_error explains the failure")
	t.eq(broken.check_ref("font_zh"), "ASSET_UNKNOWN", "no index means nothing is usable")
