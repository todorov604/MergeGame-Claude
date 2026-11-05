extends RefCounted

## 主题映射（M0 第 1 周第 7 步）：默认值 -> project.icons -> themes/<name>/theme.json。
## 主题中的素材 ID 一律经 AssetLoader 资源守卫加载；PLACEHOLDER 需 allow_placeholders=true。

const AssetLoader := preload("res://game/asset_loader.gd")

const DEFAULT_THEME_DIR := "themes/pet_shop"
const DEFAULT_FRAME_ID := "board_frame"
const DEFAULT_FONT_ID := "font_zh"
const DEFAULT_STAR_ID := "ui_icon_star"
const DEFAULT_BG_TOP := Color("#35455f")
const DEFAULT_BG_BOTTOM := Color("#101a2b")
const DEFAULT_PALETTE := [
	Color("#ff8a5c"),
	Color("#5cc8ff"),
	Color("#a07cff"),
	Color("#6be585"),
	Color("#ffd83d"),
	Color("#ff6fa5"),
	Color("#4fd1c5"),
	Color("#c0d3e8"),
]

var ok := false
var error := ""
var theme_dir := DEFAULT_THEME_DIR
var theme_name := ""
var background_top := DEFAULT_BG_TOP
var background_bottom := DEFAULT_BG_BOTTOM
var palette: Array[Color] = []
var board_frame_id := DEFAULT_FRAME_ID
var font_ui_id := DEFAULT_FONT_ID
var star_id := DEFAULT_STAR_ID
## chip 图标映射：entity -> {"1": resource_id, ...}。优先级 project_data.chips.<entity>.icons < theme.chip_icons。
var chip_icons: Dictionary = {}
var warnings: Array = []
var loader: AssetLoader = null

var _board_frame_texture: Texture2D = null
var _star_texture: Texture2D = null
var _ui_font: Font = null
var _chip_textures: Dictionary = {}


func load_theme(theme_dir_arg: String, project_data: Dictionary, allow_placeholders := true) -> bool:
	_reset_defaults()

	theme_dir = theme_dir_arg if not theme_dir_arg.is_empty() else DEFAULT_THEME_DIR

	loader = AssetLoader.new()
	if not loader.setup("res://assets/assets.json", bool(allow_placeholders)):
		return _fail(loader.setup_error)

	_apply_project_icons(project_data)
	_apply_project_chips(project_data)

	var theme_path := theme_dir
	if not theme_path.begins_with("res://"):
		theme_path = "res://" + theme_path
	var path := theme_path.path_join("theme.json")
	if not FileAccess.file_exists(path):
		return _fail("theme.json 不存在: %s" % path)

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		return _fail("读取 theme.json 失败(%s): %s" % [error_string(FileAccess.get_open_error()), path])

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return _fail("theme.json 解析失败: %s" % path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("theme.json 根节点不是 Dictionary: %s" % path)

	var theme: Dictionary = parsed
	if not _apply_theme_doc(theme, path):
		return false

	return _load_guarded_resources()


func board_frame_texture() -> Texture2D:
	return _board_frame_texture


func star_texture() -> Texture2D:
	return _star_texture


func ui_font() -> Font:
	return _ui_font


## chip 图标资源 ID；未配置返回空字符串。
func chip_icon_id(entity: String, level: int) -> String:
	var entity_v: Variant = chip_icons.get(entity, null)
	if typeof(entity_v) != TYPE_DICTIONARY:
		return ""
	var levels: Dictionary = entity_v
	var id_v: Variant = levels.get(str(level), "")
	if typeof(id_v) == TYPE_STRING:
		return String(id_v)
	return ""


## chip 图标纹理；未配置或加载失败返回 null（调用方回退自绘 chip）。
func chip_texture(entity: String, level: int) -> Texture2D:
	var key := "%s:%d" % [entity, level]
	if _chip_textures.has(key):
		return _chip_textures[key] as Texture2D
	var id := chip_icon_id(entity, level)
	if id.is_empty() or loader == null:
		_chip_textures[key] = null
		return null
	var result: Dictionary = loader.load_texture(id)
	var texture_v: Variant = result.get("texture")
	if bool(result.get("ok", false)) and texture_v is Texture2D:
		_chip_textures[key] = texture_v
		return texture_v
	warnings.append("chip 图标加载失败（回退自绘）: %s -> %s" % [id, str(result.get("error", ""))])
	_chip_textures[key] = null
	return null


func _reset_defaults() -> void:
	ok = false
	error = ""
	theme_dir = DEFAULT_THEME_DIR
	theme_name = ""
	background_top = DEFAULT_BG_TOP
	background_bottom = DEFAULT_BG_BOTTOM
	palette.assign(DEFAULT_PALETTE)
	board_frame_id = DEFAULT_FRAME_ID
	font_ui_id = DEFAULT_FONT_ID
	star_id = DEFAULT_STAR_ID
	chip_icons = {}
	warnings = []
	loader = null
	_board_frame_texture = null
	_star_texture = null
	_ui_font = null
	_chip_textures = {}


func _apply_project_icons(project_data: Dictionary) -> void:
	var icons_v: Variant = project_data.get("icons", null)
	if icons_v == null:
		return
	if typeof(icons_v) != TYPE_DICTIONARY:
		warnings.append("project_data.icons 不是 Dictionary，已忽略")
		return

	var icons: Dictionary = icons_v
	if icons.has("board_frame"):
		var frame_v: Variant = icons["board_frame"]
		if typeof(frame_v) == TYPE_STRING:
			board_frame_id = String(frame_v)
		else:
			warnings.append("project_data.icons.board_frame 不是字符串，已忽略")
	if icons.has("star"):
		var star_v: Variant = icons["star"]
		if typeof(star_v) == TYPE_STRING:
			star_id = String(star_v)
		else:
			warnings.append("project_data.icons.star 不是字符串，已忽略")
	if icons.has("font_ui"):
		var font_v: Variant = icons["font_ui"]
		if typeof(font_v) == TYPE_STRING:
			font_ui_id = String(font_v)
		else:
			warnings.append("project_data.icons.font_ui 不是字符串，已忽略")


## project_data.chips.<entity>.icons.<level> -> 资源 ID（优先级最低，theme.chip_icons 覆盖）。
func _apply_project_chips(project_data: Dictionary) -> void:
	var chips_v: Variant = project_data.get("chips", null)
	if chips_v == null:
		return
	if typeof(chips_v) != TYPE_DICTIONARY:
		warnings.append("project_data.chips 不是 Dictionary，已忽略")
		return
	var chips: Dictionary = chips_v
	for entity_key in chips.keys():
		var entity := String(entity_key)
		var def_v: Variant = chips[entity_key]
		if typeof(def_v) != TYPE_DICTIONARY:
			warnings.append("project_data.chips.%s 不是 Dictionary，已忽略" % entity)
			continue
		var icons_v: Variant = (def_v as Dictionary).get("icons", null)
		if icons_v == null:
			continue
		if typeof(icons_v) != TYPE_DICTIONARY:
			warnings.append("project_data.chips.%s.icons 不是 Dictionary，已忽略" % entity)
			continue
		_merge_chip_map(entity, icons_v, "project_data.chips.%s.icons" % entity, false, "")


## 合并 entity 的 level -> id 映射。strict=true 时结构错误使主题加载失败；否则记 warning 并跳过。
func _merge_chip_map(entity: String, levels: Dictionary, context: String, strict: bool, path: String) -> bool:
	var entity_map: Dictionary = chip_icons.get(entity, {})
	for level_key in levels.keys():
		var level_text := str(level_key)
		var level := -1
		if level_text.is_valid_int():
			level = int(level_text)
		var id_v: Variant = levels[level_key]
		var problem := ""
		if level < 1 or level > 10:
			problem = "等级必须是 1-10 的整数: %s" % level_text
		elif typeof(id_v) != TYPE_STRING or String(id_v).is_empty():
			problem = "资源 ID 必须是非空字符串: %s" % str(id_v)
		if not problem.is_empty():
			if strict:
				return _fail("theme.json %s.%s: %s（%s）" % [context, level_text, problem, path])
			warnings.append("%s.%s: %s" % [context, level_text, problem])
			continue
		entity_map[str(level)] = String(id_v)
	chip_icons[entity] = entity_map
	return true


func _apply_theme_doc(theme: Dictionary, path: String) -> bool:
	if theme.has("name"):
		var name_v: Variant = theme["name"]
		if typeof(name_v) != TYPE_STRING:
			return _fail("theme.json name 必须是字符串: %s" % path)
		theme_name = String(name_v)

	if theme.has("background"):
		var bg_v: Variant = theme["background"]
		if typeof(bg_v) != TYPE_DICTIONARY:
			return _fail("theme.json background 必须是 Dictionary: %s" % path)
		var bg: Dictionary = bg_v
		if bg.has("top"):
			var top_result := _parse_color(bg["top"], "background.top")
			if not bool(top_result["ok"]):
				return _fail("theme.json %s: %s" % [top_result["error"], path])
			background_top = top_result["color"]
		if bg.has("bottom"):
			var bottom_result := _parse_color(bg["bottom"], "background.bottom")
			if not bool(bottom_result["ok"]):
				return _fail("theme.json %s: %s" % [bottom_result["error"], path])
			background_bottom = bottom_result["color"]

	if theme.has("board_frame"):
		var frame_v: Variant = theme["board_frame"]
		if typeof(frame_v) != TYPE_STRING:
			return _fail("theme.json board_frame 必须是字符串: %s" % path)
		board_frame_id = String(frame_v)

	if theme.has("star"):
		var star_v: Variant = theme["star"]
		if typeof(star_v) != TYPE_STRING:
			return _fail("theme.json star 必须是字符串: %s" % path)
		star_id = String(star_v)

	if theme.has("fonts"):
		var fonts_v: Variant = theme["fonts"]
		if typeof(fonts_v) != TYPE_DICTIONARY:
			return _fail("theme.json fonts 必须是 Dictionary: %s" % path)
		var fonts: Dictionary = fonts_v
		if fonts.has("ui"):
			var ui_v: Variant = fonts["ui"]
			if typeof(ui_v) != TYPE_STRING:
				return _fail("theme.json fonts.ui 必须是字符串: %s" % path)
			font_ui_id = String(ui_v)

	if theme.has("chip_palette"):
		var entries_v: Variant = theme["chip_palette"]
		if typeof(entries_v) != TYPE_ARRAY:
			return _fail("theme.json chip_palette 必须是数组: %s" % path)
		var entries: Array = entries_v
		if entries.is_empty():
			return _fail("theme.json chip_palette 至少需要 1 项: %s" % path)
		var next_palette: Array[Color] = []
		for i in entries.size():
			var entry_result := _parse_color(entries[i], "chip_palette[%d]" % i)
			if not bool(entry_result["ok"]):
				return _fail("theme.json %s: %s" % [entry_result["error"], path])
			next_palette.append(entry_result["color"])
		palette = next_palette

	if theme.has("chip_icons"):
		var chip_icons_v: Variant = theme["chip_icons"]
		if typeof(chip_icons_v) != TYPE_DICTIONARY:
			return _fail("theme.json chip_icons 必须是 Dictionary: %s" % path)
		var theme_chip_icons: Dictionary = chip_icons_v
		for entity_key in theme_chip_icons.keys():
			var entity := String(entity_key)
			if entity.is_empty():
				return _fail("theme.json chip_icons 实体不能为空: %s" % path)
			var levels_v: Variant = theme_chip_icons[entity_key]
			if typeof(levels_v) != TYPE_DICTIONARY:
				return _fail("theme.json chip_icons.%s 必须是 Dictionary: %s" % [entity, path])
			if not _merge_chip_map(entity, levels_v, "chip_icons.%s" % entity, true, path):
				return false

	return true


func _load_guarded_resources() -> bool:
	var frame_result: Dictionary = loader.load_texture(board_frame_id)
	if not bool(frame_result.get("ok", false)):
		return _fail(String(frame_result.get("error", "")))

	var star_result: Dictionary = loader.load_texture(star_id)
	if not bool(star_result.get("ok", false)):
		return _fail(String(star_result.get("error", "")))

	var font_result: Dictionary = loader.load_font(font_ui_id)
	if not bool(font_result.get("ok", false)):
		return _fail(String(font_result.get("error", "")))

	_board_frame_texture = frame_result.get("texture") as Texture2D
	_star_texture = star_result.get("texture") as Texture2D
	_ui_font = font_result.get("font") as Font
	ok = true
	error = ""
	return true


func _parse_color(value: Variant, context: String) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "color": Color.WHITE, "error": "%s 必须是颜色字符串" % context}
	var text := String(value)
	if not text.is_valid_html_color():
		return {"ok": false, "color": Color.WHITE, "error": "%s 不是合法颜色: %s" % [context, text]}
	return {"ok": true, "color": Color(text), "error": ""}


func _fail(message: String) -> bool:
	ok = false
	error = message
	return false
