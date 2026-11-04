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


func _guard(allow_placeholders: bool):
	var guard = AssetGuard.new()
	guard.load_from(INDEX, allow_placeholders)
	return guard


func _loader(allow_placeholders: bool):
	var loader = ThemeLoader.new()
	loader.setup(_guard(allow_placeholders), allow_placeholders)
	return loader


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

	var strict = _loader(false)
	var reference_only: Dictionary = strict.ingest({
		"name": "ref-only-probe",
		"icons": {"chip": {"CleanSet_Ca": "chip_clean_ca_lv01"}},
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
