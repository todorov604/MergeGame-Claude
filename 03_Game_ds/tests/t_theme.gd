extends RefCounted
## M0 step 7 headless checks: theme loading, theme > project > default, and the
## guard gate on every resolved icon id. Two themes must differ only in data.

const ThemeLoader = preload("res://src/theme/theme_loader.gd")
const AssetGuard = preload("res://src/assets/asset_guard.gd")

const SAMPLE := "res://data/sample_project.json"
const INDEX := "res://data/manifest_index.json"
const DEFAULT_THEME := "themes/default"
const WOOD_THEME := "themes/pet_shop"


func run(t) -> void:
	_load_both(t)
	_precedence(t)
	_guard_gate(t)
	_apply_palette(t)
	_chip_icons_ingest(t)
	_chip_icons_precedence(t)
	_chip_icons_texture_gate(t)
	_chip_icons_default_theme(t)
	_chip_icons_pet_shop(t)


func _guard(allow_placeholders: bool):
	var guard = AssetGuard.new()
	guard.load_from(INDEX, allow_placeholders)
	return guard


func _loader(allow_placeholders: bool):
	var loader = ThemeLoader.new()
	loader.setup(_guard(allow_placeholders), allow_placeholders)
	return loader


## Same as _loader, but the guard carries synthetic records. The 74 -> 180-entry
## snapshot has no REFERENCE_ONLY chips left, so the REFERENCE_ONLY gate is proven
## with an injected record instead of pretending the shipped table still has one.
func _loader_with(allow_placeholders: bool, records: Dictionary):
	var guard = _guard(allow_placeholders)
	for key in records.keys():
		guard.index[String(key)] = records[key]
	var loader = ThemeLoader.new()
	loader.setup(guard, allow_placeholders)
	return loader


## A legal chip record that points at a real file already under res://assets/ui,
## so the texture path can be exercised without depending on the chip snapshot.
func _record(usage: String, file_name: String, present: bool) -> Dictionary:
	return {
		"usage": usage,
		"license": "synthetic-test-record",
		"file_name": file_name,
		"file_present": present,
	}


func _error_path(errors: Array, code: String) -> String:
	for e in errors:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("code", "")) == code:
			return String(e.get("path", ""))
	return ""


func _load_both(t) -> void:
	var project := _project()
	var loader = _loader(false)
	var base: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(base.get("ok", false)), "default theme loads", str(base.get("errors", [])))
	var base_palette: Dictionary = base.get("palette", {})
	var base_metrics: Dictionary = base.get("metrics", {})
	t.ok(base_palette.size() >= 16, "default palette is complete", str(base_palette.size()))
	t.ok(base_metrics.size() >= 6, "default metrics are complete", str(base_metrics.size()))

	var wood: Dictionary = loader.load_theme(WOOD_THEME, project)
	t.ok(bool(wood.get("ok", false)), "pet_shop theme loads", str(wood.get("errors", [])))
	var wood_palette: Dictionary = wood.get("palette", {})
	var wood_metrics: Dictionary = wood.get("metrics", {})

	var base_keys: Array = base_palette.keys()
	var wood_keys: Array = wood_palette.keys()
	base_keys.sort()
	wood_keys.sort()
	t.eq(wood_keys, base_keys, "both themes expose the same palette keys")
	t.ne(String(wood_palette.get("page", "")), String(base_palette.get("page", "")),
			"the two themes have different page colors")
	t.ne(String(wood_palette.get("band", "")), String(base_palette.get("band", "")),
			"the two themes have different band colors")
	t.ne(String(wood_palette.get("ink", "")), String(base_palette.get("ink", "")),
			"the two themes have different ink colors")
	t.ne(float(wood_metrics.get("card_radius", 0.0)), float(base_metrics.get("card_radius", 0.0)),
			"the two themes have different card radii")
	t.ne(float(wood_metrics.get("band_height", 0.0)), float(base_metrics.get("band_height", 0.0)),
			"the two themes have different band heights")
	t.ok(float(wood_metrics.get("tint_alpha", 0.0)) > 0.0,
			"pet_shop tints the board instead of leaving it flat")

	var wood_keys_metrics: Array = wood_metrics.keys()
	var base_keys_metrics: Array = base_metrics.keys()
	wood_keys_metrics.sort()
	base_keys_metrics.sort()
	t.eq(wood_keys_metrics, base_keys_metrics, "both themes expose the same metric keys")

	var missing: Dictionary = loader.load_theme("themes/does_not_exist", project)
	t.ok(not bool(missing.get("ok", true)), "a missing theme is rejected")
	t.has_code(missing.get("errors", []), "THEME_MISSING", "missing theme reports THEME_MISSING")


func _precedence(t) -> void:
	var project := _project()
	var themed := _with_project_icon(project, "CleanSet_Ca", "ui_icon_star")
	var loader = _loader(true)

	var theme_data := {
		"name": "precedence-probe",
		"icons": {"chip": {"CleanSet_Ca": "box_safe_x"}},
	}
	var loaded: Dictionary = loader.ingest(theme_data, themed, "res://data/themes/probe/theme.json")
	t.ok(bool(loaded.get("ok", false)), "probe theme ingests", str(loaded.get("errors", [])))

	var theme_wins: Dictionary = loader.resolve_icon("chip", "CleanSet_Ca", themed)
	t.eq(String(theme_wins.get("source", "")), "theme", "theme beats project for the same slot")
	t.eq(String(theme_wins.get("id", "")), "box_safe_x", "theme id wins")

	var project_only: Dictionary = loader.resolve_icon("chip", "CleanSet_Cb", themed)
	t.eq(String(project_only.get("id", "")), "", "project has no override for CleanSet_Cb")

	var project_with_more := project.duplicate(true)
	var entities := _dict(project_with_more.get("entities", {}))
	var ca := _dict(entities.get("CleanSet_Ca", {}))
	var visual := _dict(ca.get("visual", {}))
	visual["icon"] = "ui_icon_star"
	ca["visual"] = visual
	entities["CleanSet_Ca"] = ca
	project_with_more["entities"] = entities
	var plain_loader = _loader(true)
	plain_loader.ingest({"name": "no-icons", "icons": {}}, project_with_more, "res://data/themes/probe/theme.json")
	var project_wins: Dictionary = plain_loader.resolve_icon("chip", "CleanSet_Ca", project_with_more)
	t.eq(String(project_wins.get("source", "")), "project", "project is the second layer")
	t.eq(String(project_wins.get("id", "")), "ui_icon_star", "project id wins when no theme icon")

	var default_layer: Dictionary = plain_loader.resolve_icon("hud", "star", project_with_more)
	t.eq(String(default_layer.get("source", "")), "default", "missing everywhere falls to default")
	t.eq(String(default_layer.get("id", "")), "", "default layer renders procedurally")


func _guard_gate(t) -> void:
	var project := _project()

	# The snapshot rebuilt for M1 has zero REFERENCE_ONLY records left (every 01_icon
	# material is PRODUCTION), so the REFERENCE_ONLY gate is proven with a synthetic
	# record injected into the guard — the code path is what matters, not the table.
	var strict = _loader_with(false, {"synth_ref_only": _record("REFERENCE_ONLY", "ui_icon_star.png", true)})
	var reference_only: Dictionary = strict.ingest({
		"name": "ref-only-probe",
		"icons": {"chip": {"CleanSet_Ca": "synth_ref_only"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(reference_only.get("ok", true)), "REFERENCE_ONLY icon makes the theme fail")
	t.has_code(reference_only.get("errors", []), "ASSET_REFERENCE_ONLY",
			"REFERENCE_ONLY is named in the error list")

	var placeholder: Dictionary = strict.ingest({
		"name": "placeholder-probe",
		"icons": {"hud": {"star": "ui_icon_star"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(placeholder.get("ok", true)), "PLACEHOLDER icon fails without the flag")
	t.has_code(placeholder.get("errors", []), "ASSET_PLACEHOLDER_BLOCKED",
			"PLACEHOLDER refusal is named")

	var permissive = _loader(true)
	var allowed: Dictionary = permissive.ingest({
		"name": "placeholder-probe",
		"icons": {"hud": {"star": "ui_icon_star"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(bool(allowed.get("ok", false)), "PLACEHOLDER icon passes with allow_placeholders=true",
			str(allowed.get("errors", [])))
	var resolved: Dictionary = permissive.resolve_icon("hud", "star", project)
	t.eq(String(resolved.get("id", "")), "ui_icon_star", "allowed placeholder id resolves")

	var unknown: Dictionary = strict.ingest({
		"name": "unknown-probe",
		"icons": {"chip": {"CleanSet_Ca": "no_such_resource"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(unknown.get("ok", true)), "an unknown id blocks the theme")
	t.has_code(unknown.get("errors", []), "ASSET_UNKNOWN", "unknown id is named")


func _apply_palette(t) -> void:
	var loader = _loader(false)
	loader.load_theme(WOOD_THEME, _project())
	var colors: Dictionary = loader.colors()
	t.ok(colors.size() >= 16, "colors() expands the whole palette", str(colors.size()))
	t.ok(colors.get("page", null) is Color, "palette values convert to Color")

	var root := Node.new()
	var child_ok = load("res://src/view/hud_view.gd").new()
	root.add_child(child_ok)
	var child_plain := Node.new()
	root.add_child(child_plain)
	var applied: int = loader.apply_palette(root)
	t.eq(applied, 1, "apply_palette touches only views that accept a palette")
	var received = child_ok.palette.get("ink", null)
	t.ok(received is Color and received == colors.get("ink", null),
			"the view really received the theme colors", str(received))
	root.free()


# ------------------------------------------------------------- chip_icons block
##
## chip_icons maps (entity, level) -> manifest id. It is a *second* icon table with
## its own guard walk, because a chip icon is addressed by level, not by entity:
## theme.chip_icons.<entity>.<level>. Every leaf must pass the same guard the rest
## of the theme goes through.

func _chip_icons_ingest(t) -> void:
	var project := _project()
	var ok_records := {"synth_chip_ok": _record("PRODUCTION", "ui_icon_star.png", true)}

	var plain = _loader_with(false, ok_records)
	var good: Dictionary = plain.ingest({
		"name": "chip-probe",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ok"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(bool(good.get("ok", false)), "chip_icons: a legal mapping ingests", str(good.get("errors", [])))
	t.eq(int(_dict(good.get("chip_icons", {})).size()), 1, "chip_icons: block is returned in result()")
	t.eq(_dict(_dict(good.get("chip_icons", {})).get("CleanSet_Ca", {})).size(), 1,
			"chip_icons: entity keeps its level table")

	var not_object = _loader_with(false, ok_records)
	var rejected: Dictionary = not_object.ingest({
		"name": "chip-probe",
		"chip_icons": ["CleanSet_Ca"],
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(rejected.get("ok", true)), "chip_icons: a non-object block is rejected")
	t.has_code(rejected.get("errors", []), "THEME_PARSE", "chip_icons: non-object reports THEME_PARSE")
	t.eq(_error_path(rejected.get("errors", []), "THEME_PARSE"), "chip_icons",
			"chip_icons: parse error names the chip_icons key")

	var unknown = _loader_with(false, ok_records)
	var unknown_res: Dictionary = unknown.ingest({
		"name": "chip-probe",
		"chip_icons": {"CleanSet_Ca": {"1": "no_such_chip_id"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(unknown_res.get("ok", true)), "chip_icons: an unknown id blocks the theme")
	t.has_code(unknown_res.get("errors", []), "ASSET_UNKNOWN", "chip_icons: unknown id reports ASSET_UNKNOWN")
	t.eq(_error_path(unknown_res.get("errors", []), "ASSET_UNKNOWN"),
			"theme.chip_icons.CleanSet_Ca.1", "chip_icons: error path is entity.level")

	var ref_records := {"synth_chip_ref": _record("REFERENCE_ONLY", "ui_icon_star.png", true)}
	var strict_ref = _loader_with(false, ref_records)
	var ref_res: Dictionary = strict_ref.ingest({
		"name": "chip-probe",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ref"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(ref_res.get("ok", true)), "chip_icons: REFERENCE_ONLY blocks the theme")
	t.has_code(ref_res.get("errors", []), "ASSET_REFERENCE_ONLY",
			"chip_icons: REFERENCE_ONLY is named in the error list")

	var ph_records := {"synth_chip_ph": _record("PLACEHOLDER", "ui_icon_star.png", true)}
	var strict_ph = _loader_with(false, ph_records)
	var ph_res: Dictionary = strict_ph.ingest({
		"name": "chip-probe",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ph"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(not bool(ph_res.get("ok", true)), "chip_icons: PLACEHOLDER fails without the flag")
	t.has_code(ph_res.get("errors", []), "ASSET_PLACEHOLDER_BLOCKED",
			"chip_icons: PLACEHOLDER refusal is named")

	var loose_ph = _loader_with(true, ph_records)
	var loose_res: Dictionary = loose_ph.ingest({
		"name": "chip-probe",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ph"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(bool(loose_res.get("ok", false)), "chip_icons: PLACEHOLDER passes with allow_placeholders=true",
			str(loose_res.get("errors", [])))


func _chip_icons_precedence(t) -> void:
	var records := {
		"synth_chip_theme": _record("PRODUCTION", "ui_icon_star.png", true),
		"synth_chip_level": _record("PRODUCTION", "ui_icon_star.png", true),
		"synth_chip_entity": _record("PRODUCTION", "ui_icon_star.png", true),
	}
	var project := _chip_project("CleanSet_Ca", "synth_chip_entity", {"2": "synth_chip_level"})

	var loader = _loader_with(false, records)
	var loaded: Dictionary = loader.ingest({
		"name": "chip-precedence",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_theme"}},
	}, project, "res://data/themes/probe/theme.json")
	t.ok(bool(loaded.get("ok", false)), "chip precedence probe ingests", str(loaded.get("errors", [])))

	var theme_wins: Dictionary = loader.resolve_chip_icon("CleanSet_Ca", 1, project)
	t.eq(String(theme_wins.get("id", "")), "synth_chip_theme", "chip: theme mapping wins for its level")
	t.eq(String(theme_wins.get("source", "")), "theme", "chip: theme mapping reports source=theme")

	var level_wins: Dictionary = loader.resolve_chip_icon("CleanSet_Ca", 2, project)
	t.eq(String(level_wins.get("id", "")), "synth_chip_level",
			"chip: project visual.icons[level] is the second layer")
	t.eq(String(level_wins.get("source", "")), "project", "chip: per-level project id reports source=project")

	var entity_wins: Dictionary = loader.resolve_chip_icon("CleanSet_Ca", 7, project)
	t.eq(String(entity_wins.get("id", "")), "synth_chip_entity",
			"chip: project visual.icon covers levels with no per-level entry")
	t.eq(String(entity_wins.get("source", "")), "project", "chip: entity-wide project id reports source=project")

	var default_layer: Dictionary = loader.resolve_chip_icon("CleanSet_Cb", 1, project)
	t.eq(String(default_layer.get("id", "")), "", "chip: nothing anywhere falls back to empty id")
	t.eq(String(default_layer.get("source", "")), "default", "chip: fallback reports source=default")

	var no_theme = _loader_with(false, records)
	no_theme.ingest({"name": "chip-precedence", "chip_icons": {}}, project,
			"res://data/themes/probe/theme.json")
	var project_only: Dictionary = no_theme.resolve_chip_icon("CleanSet_Ca", 2, project)
	t.eq(String(project_only.get("id", "")), "synth_chip_level",
			"chip: project per-level id survives without a theme mapping")
	t.eq(String(project_only.get("source", "")), "project",
			"chip: project per-level id reports source=project")

	var bare := _project()
	var bare_loader = _loader(false)
	bare_loader.ingest({"name": "chip-precedence", "chip_icons": {}}, bare,
			"res://data/themes/probe/theme.json")
	var bare_chip: Dictionary = bare_loader.resolve_chip_icon("CleanSet_Ca", 1, bare)
	t.eq(String(bare_chip.get("id", "")), "", "chip: sample project has no chip icon of its own")
	t.eq(String(bare_chip.get("source", "")), "default", "chip: sample project falls to default")


func _chip_icons_texture_gate(t) -> void:
	var project := _project()
	var ok_records := {"synth_chip_ok": _record("PRODUCTION", "ui_icon_star.png", true)}
	var theme_data := {
		"name": "chip-texture",
		"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ok"}},
	}

	var loader = _loader_with(false, ok_records)
	loader.ingest(theme_data, project, "res://data/themes/probe/theme.json")
	var tex: Texture2D = loader.chip_texture("CleanSet_Ca", 1, project)
	t.ok(tex != null, "chip_texture loads a legal id from res://assets/ui")
	if tex != null:
		t.eq(tex.get_width(), 128, "chip_texture keeps the source width")
		t.eq(tex.get_height(), 128, "chip_texture keeps the source height")
	var again: Texture2D = loader.chip_texture("CleanSet_Ca", 1, project)
	t.ok(is_same(tex, again), "chip_texture is cached per entity@level (same object)")
	t.ok(loader.chip_texture("CleanSet_Ca", 5, project) == null,
			"chip_texture is null for a level the theme does not map")

	var ref_loader = _loader_with(false, {"synth_chip_ref": _record("REFERENCE_ONLY", "ui_icon_star.png", true)})
	ref_loader.ingest({"name": "chip-texture",
			"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_ref"}}}, project,
			"res://data/themes/probe/theme.json")
	t.ok(ref_loader.chip_texture("CleanSet_Ca", 1, project) == null,
			"chip_texture returns null when the guard rejects the id")

	var missing_loader = _loader_with(false, {"synth_chip_gone": _record("PRODUCTION", "no_such_file.png", true)})
	missing_loader.ingest({"name": "chip-texture",
			"chip_icons": {"CleanSet_Ca": {"1": "synth_chip_gone"}}}, project,
			"res://data/themes/probe/theme.json")
	t.ok(missing_loader.chip_texture("CleanSet_Ca", 1, project) == null,
			"chip_texture returns null when the file is absent")

	var bare_loader = _loader(false)
	bare_loader.ingest({"name": "chip-texture", "chip_icons": {}}, project,
			"res://data/themes/probe/theme.json")
	t.ok(bare_loader.chip_texture("CleanSet_Ca", 1, project) == null,
			"chip_texture returns null when nothing resolves")
	t.eq(bare_loader.chip_refs().size(), 0, "chip_refs is empty for a theme without chip_icons")


func _chip_icons_default_theme(t) -> void:
	var project := _project()
	var loader = _loader(false)
	var loaded: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(loaded.get("ok", false)), "themes/default with chip icons passes the guard",
			str(loaded.get("errors", [])))

	var block: Dictionary = _dict(loaded.get("chip_icons", {}))
	t.eq(block.size(), 2, "themes/default maps both chip entities")
	t.ok(block.has("CleanSet_Ca"), "themes/default maps CleanSet_Ca")
	t.ok(block.has("CleanSet_Cb"), "themes/default maps CleanSet_Cb")

	var chains := {"CleanSet_Ca": "ca", "CleanSet_Cb": "cb"}
	var expected_ids: Array = []
	for entity_id in ["CleanSet_Ca", "CleanSet_Cb"]:
		var levels: Dictionary = _dict(block.get(entity_id, {}))
		t.eq(levels.size(), 10, "themes/default maps 10 levels for " + String(entity_id))
		for level in range(1, 11):
			var expected := "chip_clean_%s_lv%02d" % [String(chains[entity_id]), level]
			expected_ids.append(expected)
			var resolved: Dictionary = loader.resolve_chip_icon(String(entity_id), level, project)
			t.eq(String(resolved.get("id", "")), expected,
					"resolve_chip_icon(%s, %d)" % [String(entity_id), level])
			t.eq(String(resolved.get("source", "")), "theme",
					"resolve_chip_icon(%s, %d) comes from the theme" % [String(entity_id), level])
			var tex: Texture2D = loader.chip_texture(String(entity_id), level, project)
			t.ok(tex != null, "chip_texture(%s, %d) is a real texture" % [String(entity_id), level])
			if tex != null:
				t.eq(tex.get_width(), 182, "chip_texture(%s, %d) is 182 px wide" % [String(entity_id), level])
				t.eq(tex.get_height(), 182, "chip_texture(%s, %d) is 182 px tall" % [String(entity_id), level])

	expected_ids.sort()
	var refs: Array = loader.chip_refs()
	t.eq(refs.size(), 20, "chip_refs() lists exactly 20 chip ids")
	t.eq(refs, expected_ids, "chip_refs() is the sorted unique leaf id set")
	var unique := {}
	for id in refs:
		unique[String(id)] = true
	t.eq(unique.size(), refs.size(), "chip_refs() has no duplicates")


func _chip_icons_pet_shop(t) -> void:
	var project := _project()
	var loader = _loader(false)
	var base: Dictionary = loader.load_theme(DEFAULT_THEME, project)
	t.ok(bool(base.get("ok", false)), "default theme loads before the switch", str(base.get("errors", [])))
	t.eq(loader.chip_refs().size(), 20, "default theme exposes the chip icon set")
	# Prime the per-"entity@level" cache before the switch. Without this the post-switch
	# "no texture" assertion would also pass if load_theme() forgot to clear the cache,
	# because the cache was never filled.
	var primed = loader.chip_texture("CleanSet_Ca", 1, project)
	t.ok(primed != null, "default theme serves a real chip texture before the switch")

	var wood: Dictionary = loader.load_theme(WOOD_THEME, project)
	t.ok(bool(wood.get("ok", false)), "pet_shop theme loads after the switch", str(wood.get("errors", [])))
	t.ok(_dict(wood.get("chip_icons", {})).is_empty(), "pet_shop keeps chip_icons empty on purpose")
	t.eq(loader.chip_refs().size(), 0, "switching theme swaps the chip icon set (0 for pet_shop)")
	t.eq(String(loader.resolve_chip_icon("CleanSet_Ca", 1, project).get("source", "")), "default",
			"pet_shop resolves the chip through the default layer")
	t.ok(loader.chip_texture("CleanSet_Ca", 1, project) == null,
			"pet_shop draws chips procedurally (primed cache is cleared on theme switch)")


# --------------------------------------------------------------------- helpers

func _project() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _with_project_icon(project: Dictionary, entity_id: String, icon: String) -> Dictionary:
	var copy: Dictionary = project.duplicate(true)
	var entities := _dict(copy.get("entities", {}))
	var entity := _dict(entities.get(entity_id, {}))
	var visual := _dict(entity.get("visual", {}))
	visual["icon"] = icon
	entity["visual"] = visual
	entities[entity_id] = entity
	copy["entities"] = entities
	return copy


func _dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


## Project-side chip mapping: visual.icon is the entity-wide fallback and
## visual.icons is the per-level table the theme has to beat.
func _chip_project(entity_id: String, whole_icon: String, level_icons: Dictionary) -> Dictionary:
	var copy: Dictionary = _project().duplicate(true)
	if copy.is_empty():
		return copy
	var entities := _dict(copy.get("entities", {}))
	var entity := _dict(entities.get(entity_id, {}))
	var visual := _dict(entity.get("visual", {}))
	visual["icon"] = whole_icon
	visual["icons"] = level_icons
	entity["visual"] = visual
	entities[entity_id] = entity
	copy["entities"] = entities
	return copy
