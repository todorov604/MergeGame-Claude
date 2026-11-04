extends RefCounted
## Theme mapping (M0 step 7). Resolution order is theme > project > default:
##
##   theme    data/themes/<name>/theme.json -> icons.<kind>.<key>
##   project  entities[].visual.icon / characters[].idle / board frame
##   default  "" -> the view draws that element procedurally (no asset at all)
##
## Every id that ends up in a render must pass AssetGuard first, so a theme file
## can never smuggle a REFERENCE_ONLY file into a build, and a PLACEHOLDER id
## needs allow_placeholders=true. Palette and metrics are plain data: changing
## them is enough to re-skin the screen, no code edit.
##
## No class_name on purpose (several agents share this project); preload it.

const DEFAULT_PALETTE := {
	"page": "#E6EDF6",
	"panel": "#A8BDD5",
	"panel_edge": "#93AAC6",
	"cell": "#C9DAEB",
	"card": "#FFFFFF",
	"card_edge": "#BACCE0",
	"ink": "#22303F",
	"ink_dim": "#5C6B7D",
	"accent": "#5B8DEF",
	"done": "#8FD46B",
	"coin": "#F6C445",
	"star": "#F2B233",
	"gem": "#B27BEA",
	"board_tint": "#FFFFFF",
	"banner": "#FFFFFF",
	"band": "#A8BDD5",
}

const DEFAULT_METRICS := {
	"card_radius": 22.0,
	"card_gap": 14.0,
	"hud_radius": 26.0,
	"board_radius": 28.0,
	"band_height": 200.0,
	"tint_alpha": 0.0,
}

const THEME_DIR := "res://data"

var guard = null
var allow_placeholders: bool = false
var ok: bool = false
var theme_name: String = ""
var theme_path: String = ""
var palette: Dictionary = {}
var metrics: Dictionary = {}
var icons: Dictionary = {}
var errors: Array = []


func setup(guard_in, allow_placeholders_in: bool = false) -> void:
	guard = guard_in
	allow_placeholders = allow_placeholders_in
	_reset()


func _reset() -> void:
	ok = false
	theme_name = ""
	theme_path = ""
	palette = DEFAULT_PALETTE.duplicate(true)
	metrics = DEFAULT_METRICS.duplicate(true)
	icons = {}
	errors = []


func result() -> Dictionary:
	return {
		"ok": ok,
		"name": theme_name,
		"path": theme_path,
		"palette": palette.duplicate(true),
		"metrics": metrics.duplicate(true),
		"icons": icons.duplicate(true),
		"errors": errors.duplicate(true),
	}


## Loads data/themes/<name>/theme.json. `name` is the project field as-is,
## e.g. "themes/default" or "themes/pet_shop".
func load_theme(name: String, project: Dictionary) -> Dictionary:
	_reset()
	theme_name = name
	theme_path = "%s/%s/theme.json" % [THEME_DIR, name]
	if not FileAccess.file_exists(theme_path):
		errors.append(_err("THEME_MISSING", theme_path, "", "theme.json not found"))
		return result()
	var text := FileAccess.get_file_as_string(theme_path)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		errors.append(_err("THEME_PARSE", theme_path, "",
				"invalid JSON: " + parser.get_error_message()))
		return result()
	if typeof(parser.data) != TYPE_DICTIONARY:
		errors.append(_err("THEME_PARSE", theme_path, "", "root must be an object"))
		return result()
	return ingest(parser.data, project, theme_path)


## Same pipeline without disk IO, so tests can feed a theme dictionary.
func ingest(data: Dictionary, project: Dictionary, path: String = "") -> Dictionary:
	# Fresh state per ingest: a rejected probe must not leak errors into the next.
	var keep_name := theme_name
	_reset()
	theme_name = keep_name
	if not path.is_empty():
		theme_path = path
	if data.has("name"):
		theme_name = String(data.get("name", theme_name))
	var raw_palette = data.get("palette", null)
	if typeof(raw_palette) == TYPE_DICTIONARY:
		for key in (raw_palette as Dictionary).keys():
			palette[String(key)] = String((raw_palette as Dictionary)[key])
	elif raw_palette != null:
		errors.append(_err("THEME_PARSE", "palette", "", "palette must be an object"))
	var raw_metrics = data.get("metrics", null)
	if typeof(raw_metrics) == TYPE_DICTIONARY:
		for key in (raw_metrics as Dictionary).keys():
			metrics[String(key)] = _num((raw_metrics as Dictionary)[key],
					float(metrics.get(String(key), 0.0)))
	elif raw_metrics != null:
		errors.append(_err("THEME_PARSE", "metrics", "", "metrics must be an object"))
	var raw_icons = data.get("icons", null)
	if typeof(raw_icons) == TYPE_DICTIONARY:
		icons = (raw_icons as Dictionary).duplicate(true)
	elif raw_icons != null:
		errors.append(_err("THEME_PARSE", "icons", "", "icons must be an object"))
	_check_icons(project, errors)
	ok = errors.is_empty()
	return result()


func _check_icons(project: Dictionary, out: Array) -> void:
	var leaves: Array = []
	_collect_leaves(icons, "theme.icons", leaves)
	for ref in leaves:
		_check_one(String(ref["id"]), String(ref["path"]), out)
	# project-level icon overrides take part in the same gate
	var entities := _dict(project.get("entities", {}))
	for eid in entities.keys():
		var vis := _dict(_dict(entities[eid]).get("visual", {}))
		var icon := String(vis.get("icon", ""))
		if not icon.is_empty():
			_check_one(icon, "project.entities.%s.visual.icon" % String(eid), out)
	var chars := _dict(project.get("characters", {}))
	for cid in chars.keys():
		var c := _dict(chars[cid])
		for key in ["idle", "done"]:
			var ref := String(c.get(key, ""))
			if not ref.is_empty():
				_check_one(ref, "project.characters.%s.%s" % [String(cid), key], out)


func _check_one(id: String, path: String, out: Array) -> void:
	if id.is_empty():
		return
	var code := ""
	if guard == null:
		code = "ASSET_INDEX_MISSING"
	else:
		code = String(guard.check_ref(id))
	if code.is_empty():
		guard.note(id, path)
		return
	var msg := code
	if guard != null:
		msg = String(guard.ref_message(code, id))
	out.append(_err(code, path, id, msg))


func _collect_leaves(node, path: String, out: Array) -> void:
	match typeof(node):
		TYPE_DICTIONARY:
			for key in (node as Dictionary).keys():
				_collect_leaves((node as Dictionary)[key], "%s.%s" % [path, String(key)], out)
		TYPE_STRING:
			out.append({"id": String(node), "path": path})
		_:
			pass


## theme > project > default for one logical slot, e.g. ("chip", "CleanSet_Ca")
## or ("hud", "star") or ("board", "frame").
func resolve_icon(kind: String, key: String, project: Dictionary) -> Dictionary:
	var themed := _dig(icons, kind, key)
	if not themed.is_empty():
		return {"id": themed, "source": "theme"}
	var from_project := ""
	match kind:
		"chip", "special", "generator":
			var ent := _dict(_dict(project.get("entities", {})).get(key, {}))
			from_project = String(_dict(ent.get("visual", {})).get("icon", ""))
		"character":
			var ch := _dict(_dict(project.get("characters", {})).get(key, {}))
			from_project = String(ch.get("idle", ""))
		"board":
			var icons_block := _dict(project.get("icons", {}))
			from_project = String(_dig(icons_block, "board", key))
		_:
			from_project = ""
	if not from_project.is_empty():
		return {"id": from_project, "source": "project"}
	return {"id": "", "source": "default"}


func colors() -> Dictionary:
	var out := {}
	for key in palette.keys():
		out[String(key)] = Color.from_string(String(palette[key]), Color.MAGENTA)
	return out


## Pushes the palette to every view under `root` that accepts one.
func apply_palette(root: Node) -> int:
	var palette_colors := colors()
	var applied := 0
	if root == null:
		return applied
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == null:
			continue
		if node.has_method("set_palette"):
			node.call("set_palette", palette_colors)
			applied += 1
		if node is Node:
			for child in (node as Node).get_children():
				stack.append(child)
	return applied


func summary() -> String:
	return "theme=%s ok=%s palette=%d metrics=%d icons=%d errors=%d" % [
		theme_name, str(ok), palette.size(), metrics.size(), _leaf_count(icons), errors.size(),
	]


func _leaf_count(node) -> int:
	var out: Array = []
	_collect_leaves(node, "i", out)
	return out.size()


func _dig(node: Dictionary, a: String, b: String) -> String:
	var first = node.get(a, null)
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	var second = (first as Dictionary).get(b, null)
	if typeof(second) == TYPE_STRING:
		return String(second)
	return ""


func _dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _num(value, fallback: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


func _err(code: String, path: String, id: String, msg: String) -> Dictionary:
	return {"code": code, "path": path, "id": id, "msg": msg}
