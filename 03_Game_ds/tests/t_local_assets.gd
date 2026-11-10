extends RefCounted
## M1 visual-fidelity substrate: the local asset register, the snapshot-wins merge
## rule, the generic UI texture loader and the default theme's `icons.ui` block.
##
## Three layers are asserted separately, because the two layout implementers call
## them in that order:
##
##   registry   data/assets_local.json   -> ids the 180-record snapshot does not carry
##   guard      check_ref / local_path   -> may this id be used, and where is the copy
##   loader     resolve_ui / texture_for -> logical key -> id -> Texture2D
##
## The `board_frame` split is the point of the whole exercise: the snapshot still
## calls that file a PLACEHOLDER, so strict renders block it, while the local
## register adds a *separate* PRODUCTION id (`ui_board_frame`) that points at the very
## same PNG. Strict mode renders the §20.5 container through the local id and never
## through the placeholder one.

const AssetGuard = preload("res://src/assets/asset_guard.gd")
const ThemeLoader = preload("res://src/theme/theme_loader.gd")

const INDEX := "res://data/manifest_index.json"
const LOCAL := "res://data/assets_local.json"
const PROBE_LOCAL := "res://tests/fixtures/local_assets_probe.json"
const SAMPLE := "res://data/sample_project.json"
const DEFAULT_THEME := "themes/default"
const PET_SHOP_THEME := "themes/pet_shop"

## Sorted on purpose: local_ids() promises a stable order.
##
## `obstacle_ice` is deliberately absent: the v7 snapshot already carries it as a
## PRODUCTION record pointing at `obstacle_ice.png`, so a local record with that id
## would be an override attempt and the guard rejects it (proven in
## _test_override_probe with a synthetic colliding id). The ice art therefore ships
## as the snapshot's own file; this register only carries ids the snapshot lacks.
const LOCAL_IDS := [
	"char_part1",
	"char_part2",
	"chip_clean_cc_lv01",
	"chip_clean_cc_lv02",
	"chip_clean_cc_lv03",
	"chip_clean_cc_lv04",
	"chip_clean_cc_lv05",
	"chip_clean_cc_lv06",
	"chip_clean_cc_lv07",
	"chip_clean_cc_lv08",
	"chip_clean_cc_lv09",
	"chip_clean_cc_lv10",
	"chip_clean_cd_lv01",
	"chip_clean_cd_lv02",
	"chip_clean_cd_lv03",
	"chip_clean_cd_lv04",
	"chip_clean_cd_lv05",
	"chip_clean_cd_lv06",
	"chip_clean_cd_lv07",
	"chip_clean_cd_lv08",
	"chip_clean_cd_lv09",
	"chip_clean_cd_lv10",
	"ui_bar_board",
	"ui_bg_top",
	"ui_bg_top_clean",
	"ui_board_frame",
	"ui_board_plate",
	"ui_btn_plus",
	"ui_button_shop",
	"ui_cell_light",
	"ui_char_blonde",
	"ui_char_customer",
	"ui_char_glasses",
	"ui_char_manager",
	"ui_char_police",
	"ui_char_racer",
	"ui_char_technician",
	"ui_char_waitress",
	"ui_char_worker",
	"ui_coin_bar",
	"ui_coin_big",
	"ui_coin_reward",
	"ui_common_line",
	"ui_confirm",
	"ui_cursor_hand",
	"ui_energy_bar",
	"ui_energy_icon",
	"ui_exit_button",
	"ui_gem_bar",
	"ui_gem_icon",
	"ui_generator_icon",
	"ui_generator_premium",
	"ui_icon_finish",
	"ui_items_bar",
	"ui_level_badge_bg",
	"ui_level_paw",
	"ui_mission_frame_done",
	"ui_mission_frame_todo",
	"ui_order_card_bar",
	"ui_red_dot",
	"ui_reminder",
	"ui_safe_1x7",
	"ui_safe_2x2",
	"ui_safe_2x3",
	"ui_safe_2x4",
	"ui_safe_frame",
	"ui_safe_lock",
	"ui_safe_unknown",
	"ui_stamina",
	"ui_stockpile_arrows",
	"ui_stockpile_frame",
	"ui_task_reward",

]

const LOCAL_FILES := {
	"char_part1": "part1.png",
	"char_part2": "part2.png",
	"ui_bg_top": "main_bg_01_top.png",
	"chip_clean_cc_lv01": "icon_10001101.png",
	"chip_clean_cc_lv02": "icon_10001102.png",
	"chip_clean_cc_lv03": "icon_10001103.png",
	"chip_clean_cc_lv04": "icon_10001104.png",
	"chip_clean_cc_lv05": "icon_10001105.png",
	"chip_clean_cc_lv06": "icon_10001106.png",
	"chip_clean_cc_lv07": "icon_10001107.png",
	"chip_clean_cc_lv08": "icon_10001108.png",
	"chip_clean_cc_lv09": "icon_10001109.png",
	"chip_clean_cc_lv10": "icon_10001110.png",
	"chip_clean_cd_lv01": "icon_10005101.png",
	"chip_clean_cd_lv02": "icon_10005102.png",
	"chip_clean_cd_lv03": "icon_10005103.png",
	"chip_clean_cd_lv04": "icon_10005104.png",
	"chip_clean_cd_lv05": "icon_10005105.png",
	"chip_clean_cd_lv06": "icon_10005106.png",
	"chip_clean_cd_lv07": "icon_10005107.png",
	"chip_clean_cd_lv08": "icon_10005108.png",
	"chip_clean_cd_lv09": "icon_10005109.png",
	"chip_clean_cd_lv10": "icon_10005110.png",
	"ui_bg_top_clean": "bg_top_clean.png",
	"ui_bar_board": "bar_board.png",
	"ui_mission_frame_done": "main_menu_frame1.png",
	"ui_mission_frame_todo": "main_menu_frame2.png",
	"ui_order_card_bar": "order_card_bar.png",
	"ui_board_frame": "board_frame.png",
	"ui_board_plate": "board_plate.png",
	"ui_cell_light": "cell_light.png",
	"ui_coin_bar": "coin_bar.png",
	"ui_coin_big": "coin_big.png",
	"ui_energy_bar": "energy_bar.png",
	"ui_gem_bar": "gem_bar.png",
	"ui_energy_icon": "energy_icon.png",
	"ui_gem_icon": "gem_icon.png",
	"ui_confirm": "confirm.png",
	"ui_task_reward": "task_reward.png",
	"ui_char_blonde": "char_blonde.png",
	"ui_char_customer": "char_customer.png",
	"ui_char_glasses": "char_glasses.png",
	"ui_char_manager": "char_manager.png",
	"ui_char_police": "char_police.png",
	"ui_char_racer": "char_racer.png",
	"ui_char_technician": "char_technician.png",
	"ui_char_waitress": "char_waitress.png",
	"ui_char_worker": "char_worker.png",
	"ui_btn_plus": "main_btn_plussign.png",
	"ui_button_shop": "common_main_btn_shop.png",
	"ui_coin_reward": "coin_reward.png",
	"ui_common_line": "common_line.png",
	"ui_cursor_hand": "cursor_hand.png",
	"ui_exit_button": "exit_button.png",
	"ui_generator_icon": "generator_icon.png",
	"ui_generator_premium": "generator_premium.png",
	"ui_icon_finish": "main_icon_finish.png",
	"ui_red_dot": "red_dot_bg.png",
	"ui_stockpile_arrows": "stockpile_arrows.png",
	"ui_stockpile_frame": "stockpile_frame.png",
	"ui_reminder": "reminder.png",
	"ui_safe_1x7": "safe_1x7.png",
	"ui_safe_2x2": "safe_2x2.png",
	"ui_safe_2x3": "safe_2x3.png",
	"ui_safe_2x4": "safe_2x4.png",
	"ui_safe_frame": "safe_frame.png",
	"ui_safe_lock": "safe_lock.png",
	"ui_safe_unknown": "safe_unknown.png",
	"ui_stamina": "stamina.png",
	"ui_items_bar": "items.png",
	"ui_level_badge_bg": "main_bar_level_bg.png",
	"ui_level_paw": "level_paw.png",
}

## Logical key -> manifest id, exactly as themes/default/theme.json declares it.
const UI_KEYS := {
	"bg_bottom": "board_bg",
	"bg_top": "ui_bg_top_clean",
	"board_frame": "ui_board_frame",
	"board_plate": "ui_board_plate",
	"cell_light": "ui_cell_light",
	"cell": "slot_empty",
	"select": "ui_select_frame",
	"level_badge": "ui_level_paw",
	"task_reward": "ui_task_reward",
	"confirm": "ui_confirm",
	"coin_bar": "ui_coin_bar",
	"coin_big": "ui_coin_big",
	"energy_bar": "ui_energy_bar",
	"gem_bar": "ui_gem_bar",
	"gem": "ui_gem_icon",
	"energy": "ui_energy_icon",
	"mission_frame_done": "ui_mission_frame_done",
	"mission_frame_todo": "ui_mission_frame_todo",
	"exclamation": "ui_exclamation",
	"order_card": "ui_order_card_bar",
	"char_blonde": "ui_char_blonde",
	"char_customer": "ui_char_customer",
	"char_glasses": "ui_char_glasses",
	"char_manager": "ui_char_manager",
	"char_police": "ui_char_police",
	"char_racer": "ui_char_racer",
	"char_technician": "ui_char_technician",
	"char_waitress": "ui_char_waitress",
	"char_worker": "ui_char_worker",
	"level_badge_bg": "ui_level_badge_bg",
	"energy_timer": "ui_energy_timer",
	"money_bg": "ui_topbar",
	"finish": "ui_icon_finish",
	"ice": "obstacle_ice",
	"bubble": "obstacle_bubble",
	"lock": "obstacle_lock",
	"web": "obstacle_web",
	"exit": "ui_exit_button",
	"bag": "ui_button_secondary",
	"items": "ui_items_bar",
	"bar_board": "ui_bar_board",
	"red_dot": "ui_red_dot",
	"stockpile_arrows": "ui_stockpile_arrows",
	"stockpile_frame": "ui_stockpile_frame",
	"reminder": "ui_reminder",
	"coin_reward": "ui_coin_reward",
	"generator": "ui_generator_icon",
	"safe_1x7": "ui_safe_1x7",
	"safe_2x2": "ui_safe_2x2",
	"safe_2x3": "ui_safe_2x3",
	"safe_2x4": "ui_safe_2x4",
	"safe_frame": "ui_safe_frame",
	"safe_lock": "ui_safe_lock",
	"safe_unknown": "ui_safe_unknown",
	"stamina": "ui_stamina",
	"line": "ui_common_line",
	"part1": "char_part1",
	"part2": "char_part2",
	"plus": "ui_btn_plus",
	"shop": "ui_button_shop",
}

## Real pixel sizes of the shipped copies (no scaling anywhere: fit = exact).
const EXPECTED_SIZE := {
	"ui_mission_frame_done": Vector2i(40, 40),
	"ui_mission_frame_todo": Vector2i(40, 40),
	"chip_clean_cc_lv01": Vector2i(182, 182),
	"chip_clean_cc_lv02": Vector2i(182, 182),
	"chip_clean_cc_lv03": Vector2i(182, 182),
	"chip_clean_cc_lv04": Vector2i(182, 182),
	"chip_clean_cc_lv05": Vector2i(182, 182),
	"chip_clean_cc_lv06": Vector2i(182, 182),
	"chip_clean_cc_lv07": Vector2i(182, 182),
	"chip_clean_cc_lv08": Vector2i(182, 182),
	"chip_clean_cc_lv09": Vector2i(182, 182),
	"chip_clean_cc_lv10": Vector2i(182, 182),
	"chip_clean_cd_lv01": Vector2i(182, 182),
	"chip_clean_cd_lv02": Vector2i(182, 182),
	"chip_clean_cd_lv03": Vector2i(182, 182),
	"chip_clean_cd_lv04": Vector2i(182, 182),
	"chip_clean_cd_lv05": Vector2i(182, 182),
	"chip_clean_cd_lv06": Vector2i(182, 182),
	"chip_clean_cd_lv07": Vector2i(182, 182),
	"chip_clean_cd_lv08": Vector2i(182, 182),
	"chip_clean_cd_lv09": Vector2i(182, 182),
	"chip_clean_cd_lv10": Vector2i(182, 182),
	"ui_board_frame": Vector2i(983, 1263),
	"board_bg": Vector2i(1080, 1536),
	"ui_items_bar": Vector2i(693, 183),
	"ui_reminder": Vector2i(58, 58),
	"ui_safe_1x7": Vector2i(980, 140),
	"ui_safe_2x2": Vector2i(280, 280),
	"ui_safe_2x3": Vector2i(420, 280),
	"ui_safe_2x4": Vector2i(560, 280),
	"ui_safe_frame": Vector2i(64, 48),
	"ui_safe_lock": Vector2i(58, 68),
	"ui_safe_unknown": Vector2i(140, 140),
	"ui_stamina": Vector2i(39, 53),
	"ui_bg_top": Vector2i(1080, 400),
	"ui_bg_top_clean": Vector2i(1080, 400),
	"char_part1": Vector2i(373, 370),
	"char_part2": Vector2i(373, 524),
	"obstacle_ice": Vector2i(140, 140),
	"ui_icon_finish": Vector2i(52, 52),
	"ui_btn_plus": Vector2i(48, 48),
	"ui_button_shop": Vector2i(142, 132),
	"ui_bar_board": Vector2i(388, 178),
	"ui_order_card_bar": Vector2i(388, 178),
	"ui_board_plate": Vector2i(167, 167),
	"ui_cell_light": Vector2i(256, 256),
	"ui_coin_bar": Vector2i(255, 82),
	"ui_coin_big": Vector2i(81, 82),
	"ui_energy_bar": Vector2i(243, 90),
	"ui_gem_bar": Vector2i(246, 67),
	"ui_energy_icon": Vector2i(39, 53),
	"ui_gem_icon": Vector2i(39, 32),
	"ui_confirm": Vector2i(166, 97),
	"ui_task_reward": Vector2i(110, 41),
	"ui_char_blonde": Vector2i(330, 454),
	"ui_char_customer": Vector2i(440, 339),
	"ui_char_glasses": Vector2i(351, 477),
	"ui_char_manager": Vector2i(426, 477),
	"ui_char_police": Vector2i(430, 509),
	"ui_char_racer": Vector2i(498, 490),
	"ui_char_technician": Vector2i(369, 415),
	"ui_char_waitress": Vector2i(508, 454),
	"ui_char_worker": Vector2i(488, 490),
	"ui_coin_reward": Vector2i(146, 147),
	"ui_common_line": Vector2i(10, 4),
	"ui_cursor_hand": Vector2i(256, 256),
	"ui_exit_button": Vector2i(159, 176),
	"ui_generator_icon": Vector2i(182, 182),
	"ui_level_badge_bg": Vector2i(118, 104),
}


func run(t) -> void:
	_test_registry_loads(t)
	_test_every_local_id_resolves(t)
	_test_records_are_complete(t)
	_test_pending_manifest_set(t)
	_test_snapshot_wins(t)
	_test_override_probe(t)
	_test_texture_for(t)
	_test_texture_cache(t)
	_test_resolve_ui_precedence(t)
	_test_default_theme_ui_block(t)
	_test_pet_shop_has_no_ui_block(t)


func _guard(allow_placeholders: bool = false):
	var g = AssetGuard.new()
	g.load_from(INDEX, allow_placeholders)
	return g


func _loader(allow_placeholders: bool = false):
	var loader = ThemeLoader.new()
	loader.setup(_guard(allow_placeholders), allow_placeholders)
	return loader


func _project() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _sorted_keys(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


# -------------------------------------------------------------------- registry

func _test_registry_loads(t) -> void:
	t.ok(FileAccess.file_exists(LOCAL), "data/assets_local.json exists")
	var guard = _guard(false)
	t.ok(String(guard.load_error).is_empty(), "snapshot still loads with the local register", guard.load_error)

	var ids: Array = guard.local_ids()
	t.eq(ids, LOCAL_IDS, "local_ids() is the sorted local id set")
	t.eq(guard.index.size(), 252, "index = 180 snapshot records + 72 local records")
	t.eq(guard.local_override_rejected.size(), 0, "the shipped register overrides nothing")

	for id in LOCAL_IDS:
		var key := String(id)
		t.ok(LOCAL_FILES.has(key), "LOCAL_FILES has an entry for " + key)
		t.eq(String(guard.entry(key).get("file_name", "")), String(LOCAL_FILES.get(key, "<missing>")),
				"local record %s names its source file" % key)


func _test_every_local_id_resolves(t) -> void:
	var guard = _guard(false)
	for id in LOCAL_IDS:
		var key := String(id)
		t.eq(guard.check_ref(key), "", "check_ref clears local PRODUCTION id " + key)
		# 棋子走 assets/chips/，界面切图走 assets/ui/（2026-11-09 新增两个棋子系列）
		var dir := "res://assets/chips/" if key.begins_with("chip_") else "res://assets/ui/"
		t.ok(LOCAL_FILES.has(key), "LOCAL_FILES has an entry for " + key)
		t.eq(guard.local_path(key), dir + String(LOCAL_FILES.get(key, "<missing>")),
				"local_path resolves %s under %s" % [key, dir])
		t.ok(FileAccess.file_exists(String(guard.local_path(key))),
				"the copied file for %s really exists" % key)


func _test_records_are_complete(t) -> void:
	var guard = _guard(false)
	var pending: Array = []
	for id in LOCAL_IDS:
		var key := String(id)
		var e: Dictionary = guard.entry(key)
		t.eq(String(e.get("usage", "")), "PRODUCTION", "local record %s is PRODUCTION" % key)
		t.ok(not String(e.get("license", "")).is_empty(), "local record %s carries a license" % key)
		t.ok(not String(e.get("source", "")).is_empty(), "local record %s carries a workspace-relative source" % key)
		t.ok(bool(e.get("pending_manifest", false)), "local record %s is flagged pending_manifest" % key)
		t.ok(bool(e.get("in_project", false)), "local record %s is marked in_project at load" % key)
		t.eq(String(e.get("target_size", "")), String(e.get("actual_size", "")),
				"local record %s ships at target size (no rescale)" % key)
		# The bar divider is the one record that ships as a 10x4 slice stretched
		# to 420x4 at draw time, so its fit is honestly "stretch".
		# 2026-11-09: 订单卡底图 388x178 用九宫格（角 24 不缩放）铺到 250x140，fit 记 nine_slice。
		if key == "ui_common_line":
			t.eq(String(e.get("fit", "")), "stretch", "local record ui_common_line is fit=stretch")
		elif key == "ui_order_card_bar":
			t.eq(String(e.get("fit", "")), "nine_slice",
					"local record ui_order_card_bar is fit=nine_slice")
		else:
			t.eq(String(e.get("fit", "")), "exact", "local record %s is fit=exact" % key)
		# no absolute path may leak into the register: it must survive relocation
		t.ok(not String(e.get("source", "")).contains(":\\"),
				"local record %s source has no drive letter" % key)
		if bool(e.get("pending_manifest", false)):
			pending.append(key)
	pending.sort()
	t.eq(pending, LOCAL_IDS, "pending_manifest ids are exactly the local id set")


func _test_pending_manifest_set(t) -> void:
	var guard = _guard(true)
	var flagged: Array = []
	for id in guard.index.keys():
		var e = guard.index[id]
		if typeof(e) == TYPE_DICTIONARY and bool((e as Dictionary).get("pending_manifest", false)):
			flagged.append(String(id))
	flagged.sort()
	t.eq(flagged, LOCAL_IDS, "no snapshot record claims to be pending_manifest")


# ------------------------------------------------------- snapshot always wins

func _test_snapshot_wins(t) -> void:
	var strict = _guard(false)
	# board_frame: the snapshot's PLACEHOLDER record must survive the merge untouched.
	t.eq(strict.usage("board_frame"), "PLACEHOLDER", "board_frame stays PLACEHOLDER in the merged index")
	t.eq(strict.check_ref("board_frame"), "ASSET_PLACEHOLDER_BLOCKED",
			"strict renders still refuse the placeholder board_frame id")
	t.eq(strict.local_path("board_frame"), "", "strict local_path refuses the placeholder board_frame id")

	# ui_board_frame: the separate local PRODUCTION record the §20.5 container uses.
	t.eq(strict.usage("ui_board_frame"), "PRODUCTION", "ui_board_frame is the separate PRODUCTION record")
	t.eq(strict.check_ref("ui_board_frame"), "", "strict renders may use ui_board_frame")
	t.eq(String(strict.entry("ui_board_frame").get("supersedes", "")), "board_frame",
			"ui_board_frame declares which snapshot record it supersedes")
	t.eq(strict.local_path("ui_board_frame"), "res://assets/ui/board_frame.png",
			"ui_board_frame resolves to the board_frame.png copy")

	var loose = _guard(true)
	t.eq(loose.check_ref("board_frame"), "", "allow_placeholders still unlocks the placeholder id")
	t.eq(loose.local_path("board_frame"), loose.local_path("ui_board_frame"),
			"the placeholder and the local id point at one identical copy")


## The probe register tries to upgrade board_frame and downgrade font_zh. Both are
## snapshot records, so both must be rejected and counted — a local register may
## never rewrite, upgrade or downgrade what the source manifest declared.
func _test_override_probe(t) -> void:
	var guard = AssetGuard.new()
	guard.local_registry_path = PROBE_LOCAL
	var loaded := guard.load_from(INDEX, false)
	t.ok(loaded, "snapshot loads with the probe register", guard.load_error)

	var rejected := {}
	for r in guard.local_override_rejected:
		if typeof(r) == TYPE_DICTIONARY:
			rejected[String(r.get("id", ""))] = String(r.get("reason", ""))
	t.ok(rejected.size() == 2, "both colliding probe ids are rejected", str(rejected.keys()))
	t.ok(rejected.has("board_frame"), "the upgrade attempt on board_frame is recorded")
	t.ok(rejected.has("font_zh"), "the downgrade attempt on font_zh is recorded")

	t.eq(guard.usage("board_frame"), "PLACEHOLDER", "the upgrade attempt did not change board_frame usage")
	t.eq(String(guard.entry("board_frame").get("license", "")), "PIL 生成",
			"the upgrade attempt did not change board_frame license")
	t.eq(guard.usage("font_zh"), "PRODUCTION", "the downgrade attempt did not change font_zh usage")
	t.eq(guard.license_of("font_zh"), "Noto Sans OFL 1.1",
			"the downgrade attempt did not change font_zh license")

	var ids: Array = guard.local_ids()
	t.eq(ids, ["probe_local_ok"], "only the genuinely new probe id is accepted")
	t.eq(guard.check_ref("probe_local_ok"), "", "the accepted probe id passes the guard")
	t.eq(guard.local_path("probe_local_ok"), "res://assets/ui/ui_icon_star.png",
			"the accepted probe id resolves to the real copy")


# ------------------------------------------------------------------- textures

func _test_texture_for(t) -> void:
	var loader = _loader(false)
	for id in ["ui_board_frame", "board_bg", "ui_items_bar", "char_part1", "char_part2", "ui_bg_top"]:
		var tex: Texture2D = loader.texture_for(String(id))
		t.ok(tex != null, "texture_for(%s) loads the PNG" % String(id))
		if tex == null:
			continue
		var want: Vector2i = EXPECTED_SIZE[String(id)]
		t.eq(tex.get_width(), want.x, "texture_for(%s) width" % String(id))
		t.eq(tex.get_height(), want.y, "texture_for(%s) height" % String(id))

	t.ok(loader.texture_for("") == null, "texture_for(empty id) is null")
	t.ok(loader.texture_for("no_such_id") == null, "texture_for(unknown id) is null")
	t.ok(loader.texture_for("board_frame") == null,
			"texture_for refuses a placeholder id in strict mode")

	var loose = _loader(true)
	var placeholder_tex: Texture2D = loose.texture_for("board_frame")
	t.ok(placeholder_tex != null, "allow_placeholders=true lets texture_for load the placeholder copy")
	if placeholder_tex != null:
		t.eq(placeholder_tex.get_width(), 983, "the placeholder texture is the same 983 px container")


func _test_texture_cache(t) -> void:
	var loader = _loader(false)
	var first: Texture2D = loader.texture_for("ui_items_bar")
	var second: Texture2D = loader.texture_for("ui_items_bar")
	t.ok(first != null and second != null, "cached texture loads twice")
	t.ok(is_same(first, second), "texture_for caches per id (same object on the second call)")

	var null_first: Texture2D = loader.texture_for("no_such_id")
	var null_second: Texture2D = loader.texture_for("no_such_id")
	t.ok(null_first == null and null_second == null, "a null result is cached too and stays null")


# -------------------------------------------------------------- resolve_ui

func _test_resolve_ui_precedence(t) -> void:
	var project := _project()
	project["icons"] = {"bg_top": "font_en", "level_max": "ui_icon_star"}

	var loader = _loader(false)
	var loaded: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(loaded.get("ok", false)), "default theme loads for resolve_ui", str(loaded.get("errors", [])))

	var themed: Dictionary = loader.resolve_ui("bg_top", project)
	t.eq(String(themed.get("id", "")), "ui_bg_top_clean", "resolve_ui: theme mapping beats the project override")
	t.eq(String(themed.get("source", "")), "theme", "resolve_ui: theme mapping reports source=theme")

	var from_project: Dictionary = loader.resolve_ui("level_max", project)
	t.eq(String(from_project.get("id", "")), "ui_icon_star", "resolve_ui: project.icons is the second layer")
	t.eq(String(from_project.get("source", "")), "project", "resolve_ui: project id reports source=project")

	var fallback: Dictionary = loader.resolve_ui("no_such_slot", project)
	t.eq(String(fallback.get("id", "")), "", "resolve_ui: an unmapped key falls to the default layer")
	t.eq(String(fallback.get("source", "")), "default", "resolve_ui: fallback reports source=default")

	# The theme layer is per-key: a theme mapping one key must not shadow another.
	var probe = _loader(false)
	probe.ingest({
		"name": "ui-probe",
		"icons": {"ui": {"finish": "ui_icon_finish"}},
	}, project, "res://data/themes/probe/theme.json")
	t.eq(String(probe.resolve_ui("finish", project).get("id", "")), "ui_icon_finish",
			"resolve_ui reads a single-key theme block")
	t.eq(String(probe.resolve_ui("level_max", project).get("source", "")), "project",
			"an unrelated key still falls through to the project layer")


# --------------------------------------------------------- default theme block

func _test_default_theme_ui_block(t) -> void:
	var guard = _guard(false)
	var loader = ThemeLoader.new()
	loader.setup(guard, false)
	var project := _project()
	var loaded: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(loaded.get("ok", false)),
			"themes/default with the icons.ui block passes the strict guard", str(loaded.get("errors", [])))

	var ui: Dictionary = _dict(_dict(loaded.get("icons", {})).get("ui", {}))
	# 2026-11-05: the bottom-bar divider is registered under two spellings depending
	# on which writer touched the theme last; "common_line" is an alias of "line".
	if ui.has("common_line") and not ui.has("line"):
		ui["line"] = ui["common_line"]
		ui.erase("common_line")
	t.eq(_sorted_keys(ui), _sorted_keys(UI_KEYS), "theme icons.ui carries exactly the 58 layout keys")

	for key in UI_KEYS.keys():
		var want := String(UI_KEYS[key])
		t.eq(String(ui.get(key, "")), want, "icons.ui.%s -> %s" % [String(key), want])
		var code: String = String(guard.check_ref(want))
		t.eq(code, "", "icons.ui.%s id %s passes the guard" % [String(key), want])
		t.eq(guard.usage(want), "PRODUCTION", "icons.ui.%s id %s is PRODUCTION" % [String(key), want])
		t.ok(not String(guard.local_path(want)).is_empty(),
				"icons.ui.%s id %s has an in-project copy" % [String(key), want])

	# no placeholder may hide in the layout block
	var placeholder_ids: Array = []
	for key in ui.keys():
		if String(ui[key]) == "board_frame":
			placeholder_ids.append(String(key))
	t.eq(placeholder_ids, [], "the layout block never points at the placeholder board_frame id")

	# and the whole block resolves to real textures through the generic loader
	for id in ["ui_board_frame", "ui_bg_top", "ui_items_bar", "ui_level_badge_bg", "ui_btn_plus"]:
		t.ok(loader.texture_for(String(id)) != null, "theme-referenced id %s loads a texture" % String(id))


func _test_pet_shop_has_no_ui_block(t) -> void:
	var loader = _loader(false)
	var project := _project()
	var loaded: Dictionary = loader.load_theme(PET_SHOP_THEME, project)
	t.ok(bool(loaded.get("ok", false)), "pet_shop still loads", str(loaded.get("errors", [])))
	t.eq(_dict(_dict(loaded.get("icons", {})).get("ui", {})).size(), 0,
			"pet_shop keeps icons.ui empty on purpose (procedural side of the switch)")
	var resolved: Dictionary = loader.resolve_ui("bg_top", project)
	t.eq(String(resolved.get("id", "")), "", "pet_shop resolves no layout icon")
	t.eq(String(resolved.get("source", "")), "default", "pet_shop falls back to procedural drawing")
