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
var warnings: Array = []
var loader: AssetLoader = null

var _board_frame_texture: Texture2D = null
var _star_texture: Texture2D = null
var _ui_font: Font = null


func load_theme(theme_dir_arg: String, project_data: Dictionary, allow_placeholders := true) -> bool:
	_reset_defaults()

	theme_dir = theme_dir_arg if not theme_dir_arg.is_empty() else DEFAULT_THEME_DIR

	loader = AssetLoader.new()
	if not loader.setup("res://assets/assets.json", bool(allow_placeholders)):
		return _fail(loader.setup_error)

	_apply_project_icons(project_data)

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
	warnings = []
	loader = null
	_board_frame_texture = null
	_star_texture = null
	_ui_font = null


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
