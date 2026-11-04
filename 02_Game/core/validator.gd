extends RefCounted

## 数据校验器：resource manifest / project.json / assets.json。
## 规则来源：00_design/M0-冻结规格.md §2（数据模型 v2）、§3（事件模型 v2）、§4（资源治理）。
## 所有要求整数的字段使用 int-like 判断（JSON 数字一律解析为 float）。

const ManifestDoc := preload("res://core/manifest_doc.gd")
const ProjectDoc := preload("res://core/project_doc.gd")
const ResourceGuard := preload("res://core/resource_guard.gd")
const EventEvaluator := preload("res://core/event_evaluator.gd")

const MANIFEST_FIELDS := [
	"id", "category", "use", "priority", "status", "usage", "license",
	"file", "target_size", "actual_size", "fit", "nine_slice", "animation", "notes",
]
const USAGE_VALUES := ["REFERENCE_ONLY", "PLACEHOLDER", "PRODUCTION", "TODO"]
const STATUS_TO_USAGE := {
	"参考图（禁止打包）": "REFERENCE_ONLY",
	"占位（可用）": "PLACEHOLDER",
	"可用": "PRODUCTION",
	"未补": "TODO",
}
const PRIORITY_VALUES := ["P0", "P1", "P2"]
const ENTITY_KINDS := ["chip", "generator", "special", "character"]
const SLOT_KINDS := ["chip", "generator", "special"]
const OBSTACLE_TYPES := ["lock", "web", "bubble", "ice"]
const TIMELINE_CHANNELS := ["sim", "view", "audio"]
const ORDER_EVENT_TYPES := ["deliver", "order_claim"]

var errors: Array = []
var warnings: Array = []


func add_error(path: String, message: String) -> void:
	errors.append({"path": path, "message": message})


func add_warning(path: String, message: String) -> void:
	warnings.append({"path": path, "message": message})


func summary() -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"errors": errors,
		"warnings": warnings,
	}


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

func validate_manifest(manifest) -> void:
	# M1 解析失败
	if not manifest.ok:
		add_error("<manifest>", String(manifest.parse_error))
		return

	# M2 resources 必须是非空数组
	var resources_v: Variant = manifest.resources
	if typeof(resources_v) != TYPE_ARRAY or (resources_v as Array).is_empty():
		add_error("<manifest>", "resources 必须是非空数组")
		return

	# M3 版本
	if manifest.version != 7:
		add_warning("<manifest>", "manifest 版本不是 7（当前 M0 期望 v7）")

	var resources: Array = resources_v
	var seen_ids: Dictionary = {}
	for i in range(resources.size()):
		var path := "resources[%d]" % i
		var entry_v: Variant = resources[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			add_error(path, "资源项必须是对象")
			continue
		var entry: Dictionary = entry_v

		# M4 字段齐全（缺哪个报哪个）
		for field in MANIFEST_FIELDS:
			if not entry.has(field):
				add_error(path + "." + String(field), "缺少字段: %s" % field)

		# M5 id 非空且唯一
		var id_v: Variant = entry.get("id")
		if not _is_non_empty_string(id_v):
			add_error(path + ".id", "id 必须是非空字符串")
		elif seen_ids.has(id_v):
			add_error(path + ".id", "资源 ID 重复: %s" % id_v)
		else:
			seen_ids[id_v] = true

		# M6 usage 合法
		var usage_v: Variant = entry.get("usage")
		var usage_valid: bool = typeof(usage_v) == TYPE_STRING and (usage_v in USAGE_VALUES)
		if not usage_valid:
			add_error(path + ".usage", "usage 必须是 REFERENCE_ONLY/PLACEHOLDER/PRODUCTION/TODO")

		# M7 priority（仅警告）
		var priority_v: Variant = entry.get("priority")
		if typeof(priority_v) != TYPE_STRING or not (priority_v in PRIORITY_VALUES):
			add_warning(path + ".priority", "priority 不是 P0/P1/P2: %s" % str(priority_v))

		# M8 status <-> usage 一致性（严格映射）
		var status_v: Variant = entry.get("status")
		if typeof(status_v) == TYPE_STRING and STATUS_TO_USAGE.has(status_v):
			if usage_v != STATUS_TO_USAGE[status_v]:
				add_error(path + ".status", "status 与 usage 不一致: %s / %s" % [status_v, str(usage_v)])

		# M9 仅对会打包的 PLACEHOLDER/PRODUCTION 校验文件存在性；
		# REFERENCE_ONLY/TODO 不进入工程（内嵌快照只保留溯源路径，干净副本中不存在）。
		if typeof(usage_v) == TYPE_STRING and (usage_v == "PLACEHOLDER" or usage_v == "PRODUCTION"):
			var file_v: Variant = entry.get("file")
			if not _is_non_empty_string(file_v):
				add_error(path + ".file", "file 为空")
			elif not FileAccess.file_exists(file_v):
				add_error(path + ".file", "缺图: %s" % file_v)

		# M10 license 非空
		var license_v: Variant = entry.get("license")
		if not _is_non_empty_string(license_v):
			add_error(path + ".license", "license 不能为空")


# ---------------------------------------------------------------------------
# Project
# ---------------------------------------------------------------------------

func validate_project(project, manifest, allow_placeholders: bool) -> void:
	if not project.ok:
		add_error("<project>", String(project.parse_error))
		return
	var data: Dictionary = project.data

	# P1 版本
	var version_v: Variant = data.get("version")
	if not _is_int_like(version_v) or int(version_v) != 2:
		add_error("version", "项目版本必须是 2")

	# P2 顶层必填
	for key in ["meta", "locales", "hud", "entities", "generators", "characters", "levels", "timeline"]:
		if not data.has(key):
			add_error(String(key), "缺少字段: %s" % key)

	var locales_v: Variant = data.get("locales")

	# P3 meta
	var meta_locale := ""
	var meta_v: Variant = data.get("meta")
	if typeof(meta_v) != TYPE_DICTIONARY:
		add_error("meta", "meta 必须是对象")
	else:
		var meta: Dictionary = meta_v
		if not _is_non_empty_string(meta.get("title")):
			add_error("meta.title", "title 必须是非空字符串")
		if not _is_resolution(meta.get("resolution")):
			add_error("meta.resolution", "resolution 必须是 [1080,1920]")
		var fps_v: Variant = meta.get("fps")
		if not _is_int_like(fps_v) or int(fps_v) != 60:
			add_error("meta.fps", "fps 必须是 60")
		var locale_v: Variant = meta.get("locale")
		if _is_non_empty_string(locale_v):
			meta_locale = String(locale_v)
		else:
			add_error("meta.locale", "locale 必须是非空字符串")
		if meta.has("duration"):
			add_warning("meta.duration", "meta.duration 已废弃，不作为时长来源")
		if not meta_locale.is_empty() and typeof(locales_v) == TYPE_DICTIONARY:
			if not (locales_v as Dictionary).has(meta_locale):
				add_error("meta.locale", "语言未定义: %s" % meta_locale)

	# P4 locales
	if typeof(locales_v) != TYPE_DICTIONARY:
		add_error("locales", "locales 必须是对象")
	elif (locales_v as Dictionary).is_empty():
		add_error("locales", "locales 不能为空")
	else:
		var locales: Dictionary = locales_v
		for lang_key in locales.keys():
			var lang := String(lang_key)
			var pack_v: Variant = locales[lang_key]
			if typeof(pack_v) != TYPE_DICTIONARY:
				add_error("locales.%s" % lang, "语言包必须是对象")
				continue
			var pack: Dictionary = pack_v
			for text_key in pack.keys():
				if typeof(text_key) != TYPE_STRING or typeof(pack[text_key]) != TYPE_STRING:
					add_error("locales.%s.%s" % [lang, text_key], "文案键和值必须是字符串")
			if meta_locale == lang and pack.is_empty():
				add_error("locales.%s" % lang, "语言包不能为空")

	# P5 hud（全部显式）
	var hud_v: Variant = data.get("hud")
	if typeof(hud_v) != TYPE_DICTIONARY:
		add_error("hud", "hud 必须是对象")
	else:
		var hud: Dictionary = hud_v
		_check_int_min(hud, "level", "hud.level", 1)
		_check_int_min(hud, "energy", "hud.energy", 0)
		_check_int_min(hud, "energyTickSeconds", "hud.energyTickSeconds", 1)
		_check_int_min(hud, "coin", "hud.coin", 0)
		_check_int_min(hud, "star", "hud.star", 0)
		_check_int_min(hud, "gem", "hud.gem", 0)
		_check_int_min(hud, "exp", "hud.exp", 0)
		if not hud.has("energyTickMode"):
			add_error("hud.energyTickMode", "缺少字段: energyTickMode")
		else:
			var mode_v: Variant = hud["energyTickMode"]
			if typeof(mode_v) != TYPE_STRING or not (mode_v in ["decrement", "increment"]):
				add_error("hud.energyTickMode", "energyTickMode 必须是 decrement 或 increment")

	# P6 entities
	var entities: Dictionary = {}
	var entities_ok := false
	var entities_v: Variant = data.get("entities")
	if typeof(entities_v) != TYPE_DICTIONARY:
		add_error("entities", "entities 必须是对象")
	elif (entities_v as Dictionary).is_empty():
		add_error("entities", "entities 不能为空")
	else:
		entities = entities_v
		entities_ok = true
		for entity_key in entities.keys():
			var epath := "entities.%s" % entity_key
			var entity_v: Variant = entities[entity_key]
			if typeof(entity_v) != TYPE_DICTIONARY:
				add_error(epath, "实体必须是对象")
				continue
			var entity: Dictionary = entity_v
			var kind_v: Variant = entity.get("kind")
			if typeof(kind_v) != TYPE_STRING or not (kind_v in ENTITY_KINDS):
				add_error(epath + ".kind", "kind 必须是 chip/generator/special/character")
				continue
			if kind_v == "chip":
				if not _is_non_empty_string(entity.get("family")):
					add_error(epath + ".family", "family 必须是非空字符串")
				if not _is_non_empty_string(entity.get("chain")):
					add_error(epath + ".chain", "chain 必须是非空字符串")
				_check_max_level(entity, epath, true)
			elif kind_v == "generator":
				if entity.has("maxLevel"):
					_check_max_level(entity, epath, false)

	# P7 generators（只存行为）
	var generators: Dictionary = {}
	var generators_v: Variant = data.get("generators")
	if typeof(generators_v) != TYPE_DICTIONARY:
		add_error("generators", "generators 必须是对象")
	else:
		generators = generators_v
		for generator_key in generators.keys():
			var gpath := "generators.%s" % generator_key
			if entities_ok:
				if not entities.has(generator_key):
					add_error(gpath, "生成器实体未定义: %s" % generator_key)
				elif _entity_kind(entities, String(generator_key)) != "generator":
					add_error(gpath, "实体不是 generator: %s" % generator_key)
			var behavior_v: Variant = generators[generator_key]
			if typeof(behavior_v) != TYPE_DICTIONARY:
				add_error(gpath, "生成器行为必须是对象")
				continue
			var behavior: Dictionary = behavior_v
			_check_int_min(behavior, "charges", gpath + ".charges", 0)
			_check_number_min(behavior, "cooldown", gpath + ".cooldown", 0.0)
			_check_outputs(behavior, gpath, entities, entities_ok, "outputs", true)
			if behavior.has("rareOutputs"):
				_check_outputs(behavior, gpath, entities, entities_ok, "rareOutputs", false)

	# P8 characters（只查结构）
	var characters_v: Variant = data.get("characters")
	if typeof(characters_v) != TYPE_DICTIONARY:
		add_error("characters", "characters 必须是对象")
	else:
		var characters: Dictionary = characters_v
		for character_key in characters.keys():
			var cpath := "characters.%s" % character_key
			if entities_ok:
				if not entities.has(character_key):
					add_error(cpath, "角色实体未定义: %s" % character_key)
				elif _entity_kind(entities, String(character_key)) != "character":
					add_error(cpath, "实体不是 character: %s" % character_key)
			var character_v: Variant = characters[character_key]
			if typeof(character_v) != TYPE_DICTIONARY:
				add_error(cpath, "必须是对象")
				continue
			var character: Dictionary = character_v
			if not _is_non_empty_string(character.get("idle")):
				add_error(cpath + ".idle", "idle 必须是非空字符串")
			if not _is_non_empty_string(character.get("done")):
				add_error(cpath + ".done", "done 必须是非空字符串")

	# P9 levels
	var order_ids: Dictionary = {}
	var levels_v: Variant = data.get("levels")
	if typeof(levels_v) != TYPE_ARRAY:
		add_error("levels", "levels 必须是数组")
	elif (levels_v as Array).is_empty():
		add_error("levels", "levels 不能为空")
	else:
		var levels: Array = levels_v
		var level_ids: Dictionary = {}
		for li in range(levels.size()):
			var lpath := "levels[%d]" % li
			var level_v: Variant = levels[li]
			if typeof(level_v) != TYPE_DICTIONARY:
				add_error(lpath, "关卡必须是对象")
				continue
			var level: Dictionary = level_v
			if level.has("next"):
				add_error(lpath + ".next", "M0 已删除 next 指针")
			var level_id_v: Variant = level.get("id")
			if not _is_non_empty_string(level_id_v):
				add_error(lpath + ".id", "关卡 id 必须是非空字符串")
			elif level_ids.has(level_id_v):
				add_error(lpath + ".id", "关卡 ID 重复: %s" % level_id_v)
			else:
				level_ids[level_id_v] = true
			var width := -1
			var height := -1
			var board_v: Variant = level.get("board")
			if typeof(board_v) != TYPE_DICTIONARY:
				add_error(lpath + ".board", "board 必须是对象")
			else:
				var board: Dictionary = board_v
				var width_v: Variant = board.get("width")
				var height_v: Variant = board.get("height")
				if _is_int_like(width_v) and int(width_v) >= 1:
					width = int(width_v)
				else:
					add_error(lpath + ".board.width", "width 必须是 >= 1 的整数")
				if _is_int_like(height_v) and int(height_v) >= 1:
					height = int(height_v)
				else:
					add_error(lpath + ".board.height", "height 必须是 >= 1 的整数")
				_check_board_slots(board, lpath + ".board", width, height, entities, entities_ok)
			_check_obstacles(level, lpath, width, height)
			_check_orders(level, lpath, entities, entities_ok, order_ids)
			_check_order_reachability(level, lpath, entities, entities_ok, generators)

	# P10 timeline
	var timeline_v: Variant = data.get("timeline")
	if typeof(timeline_v) != TYPE_ARRAY:
		add_error("timeline", "timeline 必须是数组")
	else:
		_validate_timeline(timeline_v, data)

	# P11 事件引用：订单必须存在
	if typeof(timeline_v) == TYPE_ARRAY:
		var timeline: Array = timeline_v
		for i in range(timeline.size()):
			var entry_v: Variant = timeline[i]
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			if entry.get("channel") != "sim":
				continue
			var type_v: Variant = entry.get("type")
			if typeof(type_v) != TYPE_STRING or not (type_v in ORDER_EVENT_TYPES):
				continue
			var payload_v: Variant = entry.get("payload")
			var order_v: Variant = null
			if typeof(payload_v) == TYPE_DICTIONARY:
				order_v = (payload_v as Dictionary).get("order")
			if not _is_non_empty_string(order_v):
				add_error("timeline[%d].payload.order" % i, "订单未定义: %s" % str(order_v))
			elif not order_ids.has(order_v):
				add_error("timeline[%d].payload.order" % i, "订单未定义: %s" % order_v)

	# P12 theme / icons（静态结构 + 资源引用守卫，不加载纹理）
	var theme_ok := true
	var theme_dir := ""
	if data.has("theme"):
		var theme_v: Variant = data.get("theme")
		if not _is_non_empty_string(theme_v):
			add_error("theme", "theme 必须是非空字符串")
			theme_ok = false
		else:
			theme_dir = String(theme_v)
	if theme_ok:
		var theme_refs: Array = []
		if data.has("theme"):
			var theme_data_v: Variant = _load_theme(theme_dir)
			if typeof(theme_data_v) == TYPE_DICTIONARY:
				_collect_theme_refs(theme_data_v, theme_refs)
		theme_refs.append_array(_validate_icons(data))
		if manifest != null and manifest.ok:
			_check_theme_refs(theme_refs, manifest, allow_placeholders)


# ---------------------------------------------------------------------------
# P12 细节：主题文件与图标
# ---------------------------------------------------------------------------

## 读取并校验 res://<theme>/theme.json；返回主题 Dictionary，失败返回 null。
func _load_theme(theme_dir: String) -> Variant:
	var theme_path := theme_dir
	if not theme_path.begins_with("res://"):
		theme_path = "res://" + theme_path
	var path := theme_path.path_join("theme.json")
	if not FileAccess.file_exists(path):
		add_error("theme", "主题文件不存在: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		add_error("theme", "主题 JSON 非法: %s" % path)
		return null
	var theme: Dictionary = parsed
	_validate_theme_fields(theme)
	return theme


func _validate_theme_fields(theme: Dictionary) -> void:
	if theme.has("name") and typeof(theme["name"]) != TYPE_STRING:
		add_error("theme.name", "name 必须是字符串")

	if theme.has("background"):
		var background_v: Variant = theme["background"]
		if typeof(background_v) != TYPE_DICTIONARY:
			add_error("theme.background", "background 必须是对象")
		else:
			var background: Dictionary = background_v
			for key in ["top", "bottom"]:
				if not background.has(key):
					continue
				var color_v: Variant = background[key]
				if typeof(color_v) != TYPE_STRING or not String(color_v).is_valid_html_color():
					add_error("theme.background." + String(key), "%s 必须是合法 HTML 颜色" % key)

	if theme.has("board_frame") and not _is_non_empty_string(theme["board_frame"]):
		add_error("theme.board_frame", "board_frame 必须是非空字符串")
	if theme.has("star") and not _is_non_empty_string(theme["star"]):
		add_error("theme.star", "star 必须是非空字符串")

	if theme.has("fonts"):
		var fonts_v: Variant = theme["fonts"]
		if typeof(fonts_v) != TYPE_DICTIONARY:
			add_error("theme.fonts", "fonts 必须是对象")
		elif (fonts_v as Dictionary).has("ui") and not _is_non_empty_string((fonts_v as Dictionary)["ui"]):
			add_error("theme.fonts.ui", "ui 必须是非空字符串")

	if theme.has("chip_palette"):
		var palette_v: Variant = theme["chip_palette"]
		if typeof(palette_v) != TYPE_ARRAY:
			add_error("theme.chip_palette", "chip_palette 必须是数组")
		elif (palette_v as Array).is_empty():
			add_error("theme.chip_palette", "chip_palette 必须是非空数组")
		else:
			var palette: Array = palette_v
			for i in range(palette.size()):
				var color_v: Variant = palette[i]
				if typeof(color_v) != TYPE_STRING or not String(color_v).is_valid_html_color():
					add_error("theme.chip_palette[%d]" % i, "颜色必须是合法 HTML 颜色")


## 校验可选 icons 字段；返回其中合法的资源引用 [{id, path}]。
func _validate_icons(data: Dictionary) -> Array:
	var refs: Array = []
	if not data.has("icons"):
		return refs
	var icons_v: Variant = data["icons"]
	if typeof(icons_v) != TYPE_DICTIONARY:
		add_error("icons", "icons 必须是对象")
		return refs
	var icons: Dictionary = icons_v
	for key in icons.keys():
		var icon_path := "icons.%s" % String(key)
		var icon_v: Variant = icons[key]
		if not _is_non_empty_string(icon_v):
			add_error(icon_path, "值必须是非空字符串")
		else:
			refs.append({"id": String(icon_v), "path": icon_path})
	return refs


func _collect_theme_refs(theme: Dictionary, refs: Array) -> void:
	var board_frame_v: Variant = theme.get("board_frame")
	if _is_non_empty_string(board_frame_v):
		refs.append({"id": String(board_frame_v), "path": "theme.board_frame"})
	var star_v: Variant = theme.get("star")
	if _is_non_empty_string(star_v):
		refs.append({"id": String(star_v), "path": "theme.star"})
	var fonts_v: Variant = theme.get("fonts")
	if typeof(fonts_v) == TYPE_DICTIONARY:
		var ui_v: Variant = (fonts_v as Dictionary).get("ui")
		if _is_non_empty_string(ui_v):
			refs.append({"id": String(ui_v), "path": "theme.fonts.ui"})


func _check_theme_refs(refs: Array, manifest, allow_placeholders: bool) -> void:
	var seen: Dictionary = {}
	for ref_v in refs:
		var ref: Dictionary = ref_v
		var id := String(ref["id"])
		if seen.has(id):
			continue
		seen[id] = true
		var ref_path := String(ref["path"])
		if not manifest.has_resource(id):
			add_error(ref_path, "主题引用资源未定义: %s" % id)
			continue
		var resource: Dictionary = manifest.get_resource(id)
		var usage_v: Variant = resource.get("usage")
		var usage := ""
		if typeof(usage_v) == TYPE_STRING:
			usage = String(usage_v)
		if usage == "REFERENCE_ONLY":
			add_error(ref_path, "REFERENCE_ONLY 资源禁止主题引用: %s" % id)
		elif usage == "TODO":
			add_error(ref_path, "TODO 资源未补齐: %s" % id)
		elif usage == "PLACEHOLDER" and not allow_placeholders:
			add_error(ref_path, "PLACEHOLDER 资源需 allow_placeholders=true: %s" % id)


# ---------------------------------------------------------------------------
# assets.json（sync_assets.gd 的产物）
# ---------------------------------------------------------------------------

func validate_assets_record(record_path: String, manifest) -> void:
	if not FileAccess.file_exists(record_path):
		add_warning(record_path, "未找到 assets.json（先运行 sync_assets.gd）")
		return
	var file := FileAccess.open(record_path, FileAccess.READ)
	if file == null:
		add_error(record_path, "无法读取 assets.json")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		add_error(record_path, "assets.json 解析失败")
		return
	var root: Dictionary = parsed
	var assets_v: Variant = root.get("assets")
	if typeof(assets_v) != TYPE_ARRAY:
		add_error(record_path, "assets.json 缺少 assets 数组")
		return
	var assets: Array = assets_v
	var seen_ids: Dictionary = {}
	for i in range(assets.size()):
		var path := "assets[%d]" % i
		var item_v: Variant = assets[i]
		if typeof(item_v) != TYPE_DICTIONARY:
			add_error(path, "资源记录必须是对象")
			continue
		var item: Dictionary = item_v
		var id_v: Variant = item.get("id")
		var usage_v: Variant = item.get("usage")
		if not _is_non_empty_string(id_v):
			add_error(path + ".id", "id 必须是非空字符串")
		else:
			var asset_id := String(id_v)
			if seen_ids.has(asset_id):
				add_error(path + ".id", "资源 ID 重复: %s" % asset_id)
			else:
				seen_ids[asset_id] = true
			if not manifest.has_resource(asset_id):
				add_error(path + ".id", "资源未定义: %s" % asset_id)
			else:
				var manifest_entry: Dictionary = manifest.get_resource(asset_id)
				if usage_v != manifest_entry.get("usage"):
					add_error(path + ".usage", "usage 与 manifest 记录不一致")
		if usage_v == "REFERENCE_ONLY" or usage_v == "TODO":
			add_error(path + ".usage", "usage 不允许 %s" % usage_v)
		var file_v: Variant = item.get("file")
		if not _is_non_empty_string(file_v):
			add_error(path + ".file", "缺图")
		elif not FileAccess.file_exists(file_v):
			add_error(path + ".file", "缺图")
		if not _is_non_empty_string(item.get("license")):
			add_error(path + ".license", "license 不能为空")


# ---------------------------------------------------------------------------
# P10 细节
# ---------------------------------------------------------------------------

func _validate_timeline(timeline: Array, data: Dictionary) -> void:
	if timeline.is_empty():
		add_warning("timeline", "时间轴为空")

	# 锚点表：id -> 首次出现的 index
	var ids: Dictionary = {}
	for i in range(timeline.size()):
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry_id: Variant = (entry_v as Dictionary).get("id")
		if _is_non_empty_string(entry_id) and not ids.has(entry_id):
			ids[entry_id] = i

	var seen_ids: Dictionary = {}
	var negative_literal: Dictionary = {}
	var locale := _project_locale(data)
	for i in range(timeline.size()):
		var epath := "timeline[%d]" % i
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			add_error(epath, "事件必须是对象")
			continue
		var entry: Dictionary = entry_v

		var entry_id: Variant = entry.get("id")
		if not _is_non_empty_string(entry_id):
			add_error(epath + ".id", "id 必须是非空字符串")
		elif seen_ids.has(entry_id):
			add_error(epath + ".id", "事件 ID 重复: %s" % entry_id)
		else:
			seen_ids[entry_id] = true

		var channel_v: Variant = entry.get("channel")
		var channel := ""
		var channel_ok := false
		if typeof(channel_v) == TYPE_STRING and (channel_v in TIMELINE_CHANNELS):
			channel = String(channel_v)
			channel_ok = true
		else:
			add_error(epath + ".channel", "channel 必须是 sim/view/audio")

		var type_v: Variant = entry.get("type")
		var type_ok := _is_non_empty_string(type_v)
		var type_str := ""
		if type_ok:
			type_str = String(type_v)
		if not type_ok:
			add_error(epath + ".type", "type 必须是非空字符串")
		elif type_str == "wait":
			add_error(epath + ".type", "禁止 wait 事件")
		elif channel_ok:
			var registered := false
			if channel == "sim":
				registered = type_str in EventEvaluator.SIM_TYPES
			elif channel == "view":
				registered = type_str in EventEvaluator.VIEW_TYPES
			else:
				registered = type_str in EventEvaluator.AUDIO_TYPES
			if not registered:
				add_error(epath + ".type", "未注册的事件类型")

		if _check_event_at(entry, epath, ids):
			negative_literal[i] = true

		if entry.has("duration"):
			var duration_v: Variant = entry["duration"]
			if not _is_number(duration_v) or float(duration_v) < 0.0:
				add_error(epath + ".duration", "duration 必须是非负数字")
		if entry.has("order") and not _is_int_like(entry["order"]):
			add_error(epath + ".order", "order 必须是整数")
		if entry.has("track") and not _is_int_like(entry["track"]):
			add_error(epath + ".track", "track 必须是整数")

		var payload_v: Variant = entry.get("payload")
		if typeof(payload_v) != TYPE_DICTIONARY:
			add_error(epath + ".payload", "payload 必须是对象")
		elif channel_ok and channel == "view" and (type_str == "text" or type_str == "cta"):
			var text_key_v: Variant = (payload_v as Dictionary).get("text_key")
			if not _is_non_empty_string(text_key_v):
				add_error(epath + ".payload.text_key", "text_key 必须是非空字符串")
			elif not locale.is_empty() and not _locale_has_key(data, locale, String(text_key_v)):
				add_warning(epath + ".payload.text_key", "文案键未定义: %s" % text_key_v)

	# 统一交给事件求值器：锚点循环/缺失、排序结果。
	var evaluator = EventEvaluator.new()
	evaluator.evaluate(timeline)
	for err_v in evaluator.errors:
		var err: Dictionary = err_v
		add_error("timeline[%d]" % int(err["index"]), String(err["message"]))

	# 解析后的绝对时间不能为负（字面量负数已在上面报过，避免重复）。
	var index_by_id: Dictionary = {}
	for i in range(timeline.size()):
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry_id: Variant = (entry_v as Dictionary).get("id")
		if _is_non_empty_string(entry_id) and not index_by_id.has(entry_id):
			index_by_id[entry_id] = i
	for computed_v in evaluator.events:
		var computed: Dictionary = computed_v
		var at_resolved := float(computed.get("at_resolved", 0.0))
		if at_resolved >= 0.0:
			continue
		var computed_id: Variant = computed.get("id")
		if not _is_non_empty_string(computed_id) or not index_by_id.has(computed_id):
			continue
		var idx := int(index_by_id[computed_id])
		if negative_literal.has(idx):
			continue
		add_error("timeline[%d].at" % idx, "at_resolved 不能小于 0")


## 检查 at 结构；返回是否属于“字面量负数”（已报错，供 at_resolved 去重）。
func _check_event_at(entry: Dictionary, epath: String, ids: Dictionary) -> bool:
	var at_v: Variant = entry.get("at")
	if typeof(at_v) == TYPE_INT or typeof(at_v) == TYPE_FLOAT:
		if float(at_v) < 0.0:
			add_error(epath + ".at", "at 不能小于 0")
			return true
		return false
	if typeof(at_v) == TYPE_DICTIONARY:
		var anchor: Dictionary = at_v
		var after_v: Variant = anchor.get("after")
		if not _is_non_empty_string(after_v):
			add_error(epath + ".at.after", "after 必须是非空字符串")
		elif not ids.has(after_v):
			add_error(epath + ".at.after", "锚点不存在: %s" % after_v)
		if anchor.has("offset"):
			var offset_v: Variant = anchor["offset"]
			if typeof(offset_v) != TYPE_INT and typeof(offset_v) != TYPE_FLOAT:
				add_error(epath + ".at.offset", "offset 必须是数字")
		return false
	add_error(epath + ".at", "at 必须是数字或锚点对象")
	return false


func _project_locale(data: Dictionary) -> String:
	var meta_v: Variant = data.get("meta")
	if typeof(meta_v) != TYPE_DICTIONARY:
		return ""
	var locale_v: Variant = (meta_v as Dictionary).get("locale")
	if typeof(locale_v) == TYPE_STRING:
		return String(locale_v)
	return ""


func _locale_has_key(data: Dictionary, locale: String, key: String) -> bool:
	var locales_v: Variant = data.get("locales")
	if typeof(locales_v) != TYPE_DICTIONARY:
		return true
	var locales: Dictionary = locales_v
	if not locales.has(locale):
		return true
	var pack_v: Variant = locales[locale]
	if typeof(pack_v) != TYPE_DICTIONARY:
		return true
	return (pack_v as Dictionary).has(key)


# ---------------------------------------------------------------------------
# P9 细节
# ---------------------------------------------------------------------------

func _check_board_slots(board: Dictionary, board_path: String, width: int, height: int, entities: Dictionary, entities_ok: bool) -> void:
	var path := board_path + ".slots"
	if not board.has("slots"):
		add_error(path, "缺少字段: slots")
		return
	var slots_v: Variant = board["slots"]
	if typeof(slots_v) != TYPE_ARRAY:
		add_error(path, "slots 必须是数组")
		return
	var slots: Array = slots_v
	var seen_slots: Dictionary = {}
	for i in range(slots.size()):
		var spath := "%s[%d]" % [path, i]
		var slot_v: Variant = slots[i]
		if typeof(slot_v) != TYPE_DICTIONARY:
			add_error(spath, "格子必须是对象")
			continue
		var slot: Dictionary = slot_v

		var x_v: Variant = slot.get("x")
		var y_v: Variant = slot.get("y")
		var x_ok := _is_int_like(x_v)
		var y_ok := _is_int_like(y_v)
		if not x_ok:
			add_error(spath + ".x", "x 必须是整数")
		if not y_ok:
			add_error(spath + ".y", "y 必须是整数")
		if x_ok and y_ok:
			var x := int(x_v)
			var y := int(y_v)
			if width > 0 and (x < 0 or x >= width):
				add_error(spath + ".x", "x 超出棋盘范围")
			if height > 0 and (y < 0 or y >= height):
				add_error(spath + ".y", "y 超出棋盘范围")
			var slot_key := "%d,%d" % [x, y]
			if seen_slots.has(slot_key):
				add_error(spath, "格子重复: (%d,%d)" % [x, y])
			else:
				seen_slots[slot_key] = true

		var entity_v: Variant = slot.get("entity")
		var entity_ok := false
		var entity_max_level := 0
		if not _is_non_empty_string(entity_v):
			add_error(spath + ".entity", "entity 必须是非空字符串")
		elif entities_ok:
			var entity_id := String(entity_v)
			if not entities.has(entity_id):
				add_error(spath + ".entity", "实体未定义: %s" % entity_id)
			else:
				var slot_kind := _entity_kind(entities, entity_id)
				if not (slot_kind in SLOT_KINDS):
					add_error(spath + ".entity", "格子实体 kind 非法: %s" % slot_kind)
				else:
					entity_ok = true
					entity_max_level = _entity_max_level(entities, entity_id)

		var level_v: Variant = slot.get("level")
		if not _is_int_like(level_v):
			add_error(spath + ".level", "level 必须是整数")
		else:
			var level := int(level_v)
			if level < 1:
				add_error(spath + ".level", "level 必须 >= 1")
			if entity_ok and entity_max_level > 0 and level > entity_max_level:
				add_error(spath + ".level", "level 超过实体 maxLevel")
			if level > 10:
				add_error(spath + ".level", "M0 等级上限 10")


func _check_obstacles(level: Dictionary, lpath: String, width: int, height: int) -> void:
	var path := lpath + ".obstacles"
	if not level.has("obstacles"):
		add_error(path, "缺少字段: obstacles")
		return
	var obstacles_v: Variant = level["obstacles"]
	if typeof(obstacles_v) != TYPE_ARRAY:
		add_error(path, "obstacles 必须是数组")
		return
	var obstacles: Array = obstacles_v
	var seen_slots: Dictionary = {}
	for i in range(obstacles.size()):
		var opath := "%s[%d]" % [path, i]
		var obstacle_v: Variant = obstacles[i]
		if typeof(obstacle_v) != TYPE_DICTIONARY:
			add_error(opath, "障碍必须是对象")
			continue
		var obstacle: Dictionary = obstacle_v
		var slot_v: Variant = obstacle.get("slot")
		var slot_valid := typeof(slot_v) == TYPE_ARRAY and (slot_v as Array).size() == 2
		if slot_valid:
			slot_valid = _is_int_like((slot_v as Array)[0]) and _is_int_like((slot_v as Array)[1])
		if not slot_valid:
			add_error(opath + ".slot", "slot 必须是 [x, y] 两个整数")
		else:
			var slot_arr: Array = slot_v
			var x := int(slot_arr[0])
			var y := int(slot_arr[1])
			if width > 0 and (x < 0 or x >= width):
				add_error(opath + ".slot", "slot x 超出棋盘范围")
			if height > 0 and (y < 0 or y >= height):
				add_error(opath + ".slot", "slot y 超出棋盘范围")
			var slot_key := "%d,%d" % [x, y]
			if seen_slots.has(slot_key):
				add_error(opath + ".slot", "重复障碍: (%d,%d)" % [x, y])
			else:
				seen_slots[slot_key] = true
		var type_v: Variant = obstacle.get("type")
		if typeof(type_v) != TYPE_STRING or not (type_v in OBSTACLE_TYPES):
			add_error(opath + ".type", "type 必须是 lock/web/bubble/ice")


func _check_orders(level: Dictionary, lpath: String, entities: Dictionary, entities_ok: bool, order_ids: Dictionary) -> void:
	var path := lpath + ".orders"
	if not level.has("orders"):
		add_error(path, "缺少字段: orders")
		return
	var orders_v: Variant = level["orders"]
	if typeof(orders_v) != TYPE_ARRAY:
		add_error(path, "orders 必须是数组")
		return
	var orders: Array = orders_v
	for i in range(orders.size()):
		var opath := "%s[%d]" % [path, i]
		var order_v: Variant = orders[i]
		if typeof(order_v) != TYPE_DICTIONARY:
			add_error(opath, "订单必须是对象")
			continue
		var order: Dictionary = order_v

		var order_id_v: Variant = order.get("id")
		if not _is_non_empty_string(order_id_v):
			add_error(opath + ".id", "订单 id 必须是非空字符串")
		elif order_ids.has(order_id_v):
			add_error(opath + ".id", "订单 ID 重复: %s" % order_id_v)
		else:
			order_ids[order_id_v] = true

		var character_v: Variant = order.get("character")
		if not _is_non_empty_string(character_v):
			add_error(opath + ".character", "character 必须是非空字符串")
		elif entities_ok:
			var character_id := String(character_v)
			if not entities.has(character_id):
				add_error(opath + ".character", "角色实体未定义: %s" % character_id)
			elif _entity_kind(entities, character_id) != "character":
				add_error(opath + ".character", "实体不是 character: %s" % character_id)

		var mission_v: Variant = order.get("mission")
		if typeof(mission_v) != TYPE_ARRAY:
			add_error(opath + ".mission", "mission 必须是数组")
		else:
			var mission: Array = mission_v
			if mission.size() < 1 or mission.size() > 2:
				add_error(opath + ".mission", "mission 长度必须是 1..2")
			for mi in range(mission.size()):
				var mpath := "%s.mission[%d]" % [opath, mi]
				var item_v: Variant = mission[mi]
				if typeof(item_v) != TYPE_DICTIONARY:
					add_error(mpath, "订单物品必须是对象")
					continue
				var item: Dictionary = item_v
				var entity_v: Variant = item.get("entity")
				var entity_ok := false
				var entity_max_level := 0
				if not _is_non_empty_string(entity_v):
					add_error(mpath + ".entity", "entity 必须是非空字符串")
				elif entities_ok:
					var entity_id := String(entity_v)
					if not entities.has(entity_id):
						add_error(mpath + ".entity", "实体未定义: %s" % entity_id)
					elif _entity_kind(entities, entity_id) != "chip":
						add_error(mpath + ".entity", "订单实体必须是 chip: %s" % entity_id)
					else:
						entity_ok = true
						entity_max_level = _entity_max_level(entities, entity_id)
				var level_v: Variant = item.get("level")
				if not _is_int_like(level_v):
					add_error(mpath + ".level", "level 必须是整数")
				else:
					var item_level := int(level_v)
					if item_level < 1:
						add_error(mpath + ".level", "level 必须 >= 1")
					if item_level > 10:
						add_error(mpath + ".level", "M0 等级上限 10")
					if entity_ok and entity_max_level > 0 and item_level > entity_max_level:
						add_error(mpath + ".level", "level 超过实体 maxLevel")

		_check_int_min(order, "star", opath + ".star", 0)
		_check_int_min(order, "coin", opath + ".coin", 0)


## M0 §7 订单不可达：按当前关卡棋盘与生成器产出估算 chip 可得数量上界
## （Dictionary entity -> Dictionary level -> int），再用“两枚同级合成一枚高一级”
## 判断每件订单物品是否可达。上界只用于可达性，不代表概率。
func _check_order_reachability(level: Dictionary, lpath: String, entities: Dictionary, entities_ok: bool, generators: Dictionary) -> void:
	if not entities_ok:
		return
	var board_v: Variant = level.get("board")
	if typeof(board_v) != TYPE_DICTIONARY:
		return
	var slots_v: Variant = (board_v as Dictionary).get("slots")
	if typeof(slots_v) != TYPE_ARRAY:
		return

	# 1) 统计当前关卡每类 chip 的可得数量。
	var counts: Dictionary = {}
	var seen_generators: Dictionary = {}
	var slots: Array = slots_v
	for slot_v in slots:
		if typeof(slot_v) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_v
		var entity_v: Variant = slot.get("entity")
		if not _is_non_empty_string(entity_v):
			continue
		var entity_id := String(entity_v)
		var kind := _entity_kind(entities, entity_id)
		if kind == "chip":
			var level_v: Variant = slot.get("level")
			if _is_int_like(level_v) and int(level_v) >= 1:
				_add_chip_count(counts, entity_id, int(level_v), 1)
		elif kind == "generator":
			# 同一生成器实体只计一次（棋盘上出现多个同实体生成器时不重复计产出）。
			if seen_generators.has(entity_id):
				continue
			seen_generators[entity_id] = true
			var behavior_v: Variant = generators.get(entity_id)
			if typeof(behavior_v) != TYPE_DICTIONARY:
				continue
			var behavior: Dictionary = behavior_v
			var charges := 0
			var charges_v: Variant = behavior.get("charges")
			if _is_int_like(charges_v) and int(charges_v) > 0:
				charges = int(charges_v)
			if charges == 0:
				continue
			_add_output_counts(counts, behavior, "outputs", charges, entities)
			_add_output_counts(counts, behavior, "rareOutputs", charges, entities)

	# 2) 对每个订单的 mission 每件做合并可达判断。
	var orders_v: Variant = level.get("orders")
	if typeof(orders_v) != TYPE_ARRAY:
		return
	var orders: Array = orders_v
	var reported: Dictionary = {}
	for oi in range(orders.size()):
		var order_v: Variant = orders[oi]
		if typeof(order_v) != TYPE_DICTIONARY:
			continue
		var mission_v: Variant = (order_v as Dictionary).get("mission")
		if typeof(mission_v) != TYPE_ARRAY:
			continue
		var mission: Array = mission_v
		for mi in range(mission.size()):
			var item_v: Variant = mission[mi]
			if typeof(item_v) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = item_v
			var mission_entity_v: Variant = item.get("entity")
			if not _is_non_empty_string(mission_entity_v):
				continue
			var mission_entity := String(mission_entity_v)
			if _entity_kind(entities, mission_entity) != "chip":
				continue
			var mission_level_v: Variant = item.get("level")
			if not _is_int_like(mission_level_v):
				continue
			var target_level := int(mission_level_v)
			if target_level < 1 or target_level > 10:
				# 非法等级（已有错误）不参与可达性分析，也避免超大等级导致长循环。
				continue
			# 同一 entity/level 的不可达只报一次。
			var key := "%s|%d" % [mission_entity, target_level]
			if reported.has(key):
				continue
			if _chip_reachable(counts, mission_entity, target_level):
				continue
			reported[key] = true
			add_error(
				"%s.orders[%d].mission[%d]" % [lpath, oi, mi],
				"订单物品不可达: %s Lv%d" % [mission_entity, target_level]
			)


func _add_chip_count(counts: Dictionary, entity_id: String, level: int, amount: int) -> void:
	if amount <= 0:
		return
	var by_level_v: Variant = counts.get(entity_id)
	if typeof(by_level_v) != TYPE_DICTIONARY:
		by_level_v = {}
		counts[entity_id] = by_level_v
	var by_level: Dictionary = by_level_v
	by_level[level] = int(by_level.get(level, 0)) + amount


## 生成器产出计入可达上界：同一 charge 可全部产出某一种，故每种产出各加 charges。
func _add_output_counts(counts: Dictionary, behavior: Dictionary, key: String, charges: int, entities: Dictionary) -> void:
	var outputs_v: Variant = behavior.get(key)
	if typeof(outputs_v) != TYPE_ARRAY:
		return
	var outputs: Array = outputs_v
	for item_v in outputs:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var entity_v: Variant = item.get("entity")
		if not _is_non_empty_string(entity_v):
			continue
		var entity_id := String(entity_v)
		if _entity_kind(entities, entity_id) != "chip":
			continue
		var level := 1
		if item.has("level"):
			var level_v: Variant = item["level"]
			if not _is_int_like(level_v) or int(level_v) < 1:
				continue
			level = int(level_v)
		_add_chip_count(counts, entity_id, level, charges)


## 合并可达：avail[l] 初始为可得数量；低一级两枚可合成高一级一枚。
func _chip_reachable(counts: Dictionary, entity_id: String, target_level: int) -> bool:
	var by_level_v: Variant = counts.get(entity_id)
	if typeof(by_level_v) != TYPE_DICTIONARY:
		return false
	var by_level: Dictionary = by_level_v
	var avail: Dictionary = {}
	for l in range(1, target_level + 1):
		avail[l] = int(by_level.get(l, 0))
	for l in range(1, target_level):
		var current := int(avail.get(l, 0))
		avail[l + 1] = int(avail.get(l + 1, 0)) + int(current / 2.0)
	return int(avail.get(target_level, 0)) >= 1


# ---------------------------------------------------------------------------
# P6/P7 细节与通用工具
# ---------------------------------------------------------------------------

func _check_max_level(entity: Dictionary, epath: String, required: bool) -> void:
	var path := epath + ".maxLevel"
	if not entity.has("maxLevel"):
		if required:
			add_error(path, "缺少字段: maxLevel")
		return
	var max_level_v: Variant = entity["maxLevel"]
	if not _is_int_like(max_level_v):
		add_error(path, "maxLevel 必须是整数")
		return
	var max_level := int(max_level_v)
	if max_level < 1:
		add_error(path, "maxLevel 必须在 1..10")
	elif max_level > 10:
		add_error(path, "M0 等级上限 10")


func _check_outputs(behavior: Dictionary, gpath: String, entities: Dictionary, entities_ok: bool, key: String, require_non_empty: bool) -> void:
	var path := gpath + "." + key
	if not behavior.has(key):
		add_error(path, "缺少字段: %s" % key)
		return
	var outputs_v: Variant = behavior[key]
	if typeof(outputs_v) != TYPE_ARRAY:
		add_error(path, "必须是数组")
		return
	var outputs: Array = outputs_v
	if require_non_empty and outputs.is_empty():
		add_error(path, "不能为空")
		return
	for i in range(outputs.size()):
		var opath := "%s[%d]" % [path, i]
		var item_v: Variant = outputs[i]
		if typeof(item_v) != TYPE_DICTIONARY:
			add_error(opath, "产出项必须是对象")
			continue
		var item: Dictionary = item_v

		var entity_v: Variant = item.get("entity")
		var entity_ok := false
		var entity_max_level := 0
		if not _is_non_empty_string(entity_v):
			add_error(opath + ".entity", "entity 必须是非空字符串")
		elif entities_ok:
			var entity_id := String(entity_v)
			if not entities.has(entity_id):
				add_error(opath + ".entity", "实体未定义: %s" % entity_id)
			elif _entity_kind(entities, entity_id) != "chip":
				add_error(opath + ".entity", "产出实体必须是 chip: %s" % entity_id)
			else:
				entity_ok = true
				entity_max_level = _entity_max_level(entities, entity_id)

		var weight_v: Variant = item.get("weight")
		if not _is_number(weight_v):
			add_error(opath + ".weight", "weight 必须是数字")
		elif float(weight_v) <= 0.0:
			add_error(opath + ".weight", "weight 必须大于 0")

		if item.has("level"):
			var level_v: Variant = item["level"]
			if not _is_int_like(level_v):
				add_error(opath + ".level", "level 必须是整数")
			else:
				var level := int(level_v)
				if level < 1:
					add_error(opath + ".level", "level 必须 >= 1")
				elif entity_ok and entity_max_level > 0 and level > entity_max_level:
					add_error(opath + ".level", "level 超过实体 maxLevel")

		if key == "rareOutputs" and item.has("directOrder"):
			if typeof(item["directOrder"]) != TYPE_BOOL:
				add_error(opath + ".directOrder", "directOrder 必须是布尔值")


func _check_int_min(dictionary: Dictionary, key: String, path: String, minimum: int) -> void:
	if not dictionary.has(key):
		add_error(path, "缺少字段: %s" % key)
		return
	var value_v: Variant = dictionary[key]
	if not _is_int_like(value_v):
		add_error(path, "%s 必须是整数" % key)
		return
	if int(value_v) < minimum:
		add_error(path, "%s 必须 >= %d" % [key, minimum])


func _check_number_min(dictionary: Dictionary, key: String, path: String, minimum: float) -> void:
	if not dictionary.has(key):
		add_error(path, "缺少字段: %s" % key)
		return
	var value_v: Variant = dictionary[key]
	if not _is_number(value_v):
		add_error(path, "%s 必须是数字" % key)
		return
	if float(value_v) < minimum:
		add_error(path, "%s 必须 >= %s" % [key, str(minimum)])


func _entity_kind(entities: Dictionary, entity_id: String) -> String:
	var entity_v: Variant = entities.get(entity_id)
	if typeof(entity_v) != TYPE_DICTIONARY:
		return ""
	var kind_v: Variant = (entity_v as Dictionary).get("kind")
	if typeof(kind_v) == TYPE_STRING:
		return String(kind_v)
	return ""


func _entity_max_level(entities: Dictionary, entity_id: String) -> int:
	var entity_v: Variant = entities.get(entity_id)
	if typeof(entity_v) != TYPE_DICTIONARY:
		return 0
	var max_level_v: Variant = (entity_v as Dictionary).get("maxLevel")
	if _is_int_like(max_level_v) and int(max_level_v) > 0:
		return int(max_level_v)
	return 0


func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).is_empty()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Godot JSON 把数字都解析成 float：TYPE_INT，或有限且等于 floor 的 float。
func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var f := float(value)
	return is_finite(f) and f == floor(f)


func _is_resolution(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var resolution: Array = value
	if resolution.size() != 2:
		return false
	if not _is_number(resolution[0]) or not _is_number(resolution[1]):
		return false
	return float(resolution[0]) == 1080.0 and float(resolution[1]) == 1920.0
