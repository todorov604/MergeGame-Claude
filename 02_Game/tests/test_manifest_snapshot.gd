extends RefCounted

## M1 验收：内嵌 manifest 快照 74→180；资产集合与本地登记素材一致。
## 快照条目必须与 00_design/resource_manifest.json 的 MANIFEST_FIELDS 一致；
## 只有被复制的资源把 file 指向 res://assets/，其余 PRODUCTION 保留仓库相对溯源路径。
## 本地登记（未进 00_design manifest）的素材写在 data/local_assets.json，只进 assets.json。

const ManifestDoc = preload("res://core/manifest_doc.gd")
const Validator = preload("res://core/validator.gd")

const INDEX_PATH := "res://data/manifest_index.json"
const ASSETS_PATH := "res://assets/assets.json"
const ASSET_SET_PATH := "res://data/asset_set.json"
const LOCAL_ASSETS_PATH := "res://data/local_assets.json"

## chip_clean_ca = icon_10002101..10002110（lv01–10）；chip_clean_cb = icon_10002201..10002210。
## lv01–06 在 manifest 中登记为 chip_clean_<chain>_lvNN，lv07–10 登记为 icon_<family><chain><level>。
const CHIP_ICON_IDS := [
	"chip_clean_ca_lv01", "chip_clean_ca_lv02", "chip_clean_ca_lv03",
	"chip_clean_ca_lv04", "chip_clean_ca_lv05", "chip_clean_ca_lv06",
	"icon_10002107", "icon_10002108", "icon_10002109", "icon_10002110",
	"chip_clean_cb_lv01", "chip_clean_cb_lv02", "chip_clean_cb_lv03",
	"chip_clean_cb_lv04", "chip_clean_cb_lv05", "chip_clean_cb_lv06",
	"icon_10002207", "icon_10002208", "icon_10002209", "icon_10002210",
]


func run(r) -> void:
	var manifest = ManifestDoc.new()
	r.check(manifest.load_file(INDEX_PATH), "manifest 快照应能加载: " + str(manifest.parse_error))
	r.eq(manifest.resources.size(), 180, "manifest 快照应为 180 条")
	r.eq(manifest.version, 7, "manifest 快照版本应为 7")

	var counts := {"REFERENCE_ONLY": 0, "PLACEHOLDER": 0, "PRODUCTION": 0, "TODO": 0}
	for entry_v in manifest.resources:
		var entry: Dictionary = entry_v
		var usage := str(entry.get("usage", ""))
		counts[usage] = int(counts.get(usage, 0)) + 1
	r.eq(counts["PRODUCTION"], 155, "PRODUCTION 应为 155")
	r.eq(counts["PLACEHOLDER"], 20, "PLACEHOLDER 应为 20")
	r.eq(counts["TODO"], 5, "TODO 应为 5")
	r.eq(counts["REFERENCE_ONLY"], 0, "REFERENCE_ONLY 应为 0")

	for resource_id in CHIP_ICON_IDS:
		r.check(manifest.has_resource(resource_id), "快照应包含真实棋子图标: %s" % resource_id)

	# 字段完整性（聚合断言，避免 180×14 条噪声）。
	var missing_fields: Array = []
	for entry_v in manifest.resources:
		var entry: Dictionary = entry_v
		for field in Validator.MANIFEST_FIELDS:
			if not entry.has(field):
				missing_fields.append("%s.%s" % [str(entry.get("id", "?")), str(field)])
	r.check(missing_fields.is_empty(), "快照条目应包含全部 MANIFEST_FIELDS: %s" % ", ".join(missing_fields))

	# 打包集合：file 指向 res://assets/ 的条目必须存在；其余保留溯源路径。
	var packaged_ids: Array = []
	var packaged_missing_files: Array = []
	for entry_v in manifest.resources:
		var entry: Dictionary = entry_v
		var file := str(entry.get("file", ""))
		if file.begins_with("res://assets/"):
			packaged_ids.append(str(entry.get("id", "")))
			if not FileAccess.file_exists(file):
				packaged_missing_files.append(str(entry.get("id", "")))
	packaged_ids.sort()
	r.check(packaged_missing_files.is_empty(), "打包资源文件应存在: %s" % ", ".join(packaged_missing_files))

	var unpackaged_production_without_source: Array = []
	for entry_v in manifest.resources:
		var entry: Dictionary = entry_v
		if str(entry.get("usage", "")) != "PRODUCTION":
			continue
		var file := str(entry.get("file", ""))
		if not file.begins_with("res://assets/") and not file.begins_with("01_icon/"):
			unpackaged_production_without_source.append("%s=%s" % [str(entry.get("id", "")), file])
	r.check(unpackaged_production_without_source.is_empty(), "未打包 PRODUCTION 应保留 01_icon/ 溯源路径: %s" % ", ".join(unpackaged_production_without_source))

	# 资产集合：asset_set.json 内的 manifest 资源必须进入快照打包集合。
	var set_ids := _load_ids(ASSET_SET_PATH, "ids")
	r.check(set_ids.size() > 0, "asset_set.json 应包含非空 ids")
	var expected_packaged: Array = []
	for set_id_v in set_ids:
		var set_id := String(set_id_v)
		r.check(manifest.has_resource(set_id), "asset_set 资源应存在于快照: %s" % set_id)
		if manifest.has_resource(set_id):
			expected_packaged.append(set_id)
	expected_packaged.sort()
	r.eq(packaged_ids.size(), 61, "快照打包资源应为 61 项（20 占位 + 2 字体 + 20 棋子 + 19 UI）")
	r.eq(",".join(packaged_ids), ",".join(expected_packaged), "快照打包集合应等于 asset_set ∩ manifest")

	# assets.json：打包集合 + local_assets.json；本地条目必须标 local=true / PRODUCTION / 公司自有。
	var local_ids := _load_ids(LOCAL_ASSETS_PATH, "assets")
	var expected_assets: Array = expected_packaged.duplicate()
	for local_id_v in local_ids:
		expected_assets.append(String(local_id_v))
	expected_assets.sort()
	var assets_text := FileAccess.get_file_as_string(ASSETS_PATH)
	var assets_parsed: Variant = JSON.parse_string(assets_text)
	r.check(typeof(assets_parsed) == TYPE_DICTIONARY, "assets.json 应能解析")
	if typeof(assets_parsed) == TYPE_DICTIONARY:
		var assets_v: Variant = (assets_parsed as Dictionary).get("assets", [])
		r.check(typeof(assets_v) == TYPE_ARRAY, "assets.json.assets 应为数组")
		if typeof(assets_v) == TYPE_ARRAY:
			var assets: Array = assets_v
			var asset_ids: Array = []
			var usage_mismatch: Array = []
			var missing_files: Array = []
			for item_v in assets:
				var item: Dictionary = item_v
				var asset_id := str(item.get("id", ""))
				asset_ids.append(asset_id)
				var usage := str(item.get("usage", ""))
				if usage != "PLACEHOLDER" and usage != "PRODUCTION":
					usage_mismatch.append("%s=%s" % [asset_id, usage])
				var file := str(item.get("file", ""))
				if not FileAccess.file_exists(file):
					missing_files.append(asset_id)
				if bool(item.get("local", false)):
					if manifest.has_resource(asset_id):
						usage_mismatch.append("%s 本地标记但 manifest 已存在" % asset_id)
					if usage != "PRODUCTION":
						usage_mismatch.append("%s 本地条目 usage=%s" % [asset_id, usage])
					if str(item.get("license", "")) != "公司自有":
						usage_mismatch.append("%s 本地条目 license=%s" % [asset_id, str(item.get("license", ""))])
				else:
					var index_entry: Dictionary = manifest.get_resource(asset_id)
					if index_entry.is_empty() or str(index_entry.get("usage", "")) != usage:
						usage_mismatch.append("%s index=%s assets=%s" % [asset_id, str(index_entry.get("usage", "?")), usage])
			asset_ids.sort()
			r.eq(assets.size(), 66, "assets.json 应为 66 项（61 manifest + 5 local）")
			r.eq(assets.size(), expected_assets.size(), "assets.json 应为 %d 条" % expected_assets.size())
			r.eq(",".join(asset_ids), ",".join(expected_assets), "assets.json 集合应等于 asset_set ∩ manifest + local_assets")
			r.check(usage_mismatch.is_empty(), "assets.json usage/local 标记应合法: %s" % ", ".join(usage_mismatch))
			r.check(missing_files.is_empty(), "assets.json 文件应存在: %s" % ", ".join(missing_files))
			for resource_id in CHIP_ICON_IDS:
				r.check(asset_ids.has(resource_id), "assets.json 应登记真实棋子图标: %s" % resource_id)
			# 目录级断言：assets/ 里的 PNG 必须与 assets.json 完全一致（防止多复制 100 张或残留孤儿文件）。
			var expected_pngs: Array = []
			for item_v in assets:
				var item: Dictionary = item_v
				var file := str(item.get("file", ""))
				if file.ends_with(".png"):
					expected_pngs.append(file.get_file())
			expected_pngs.sort()
			var actual_pngs: Array = []
			var assets_dir := DirAccess.open("res://assets")
			if assets_dir != null:
				assets_dir.list_dir_begin()
				var entry_name := assets_dir.get_next()
				while not entry_name.is_empty():
					if not assets_dir.current_is_dir() and entry_name.ends_with(".png"):
						actual_pngs.append(entry_name)
					entry_name = assets_dir.get_next()
				assets_dir.list_dir_end()
			actual_pngs.sort()
			r.eq(",".join(actual_pngs), ",".join(expected_pngs), "assets/ 的 PNG 集合应等于 assets.json（无多余/缺失）")


## 读取 JSON 中指定数组字段的字符串 id（locals 支持 {id} 对象或裸字符串）。
func _load_ids(path: String, field: String) -> Array:
	var ids: Array = []
	if not FileAccess.file_exists(path):
		return ids
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ids
	var values_v: Variant = (parsed as Dictionary).get(field, [])
	if typeof(values_v) != TYPE_ARRAY:
		return ids
	for value_v in (values_v as Array):
		if typeof(value_v) == TYPE_STRING:
			ids.append(String(value_v))
		elif typeof(value_v) == TYPE_DICTIONARY:
			var id_v: Variant = (value_v as Dictionary).get("id", "")
			if typeof(id_v) == TYPE_STRING:
				ids.append(String(id_v))
	return ids
