extends RefCounted
## Usage rules (资源守卫) — every resource id a project touches goes through AssetGuard:
##   theme icons, entity visual.icon, character idle/done, audio payloads.
##
## REFERENCE_ONLY -> error. PLACEHOLDER -> error unless allow_placeholders. TODO -> error.
## Unknown id or a declared-but-missing file -> error.
##
## Type guards: a JSON value is only converted when it IS a String. `String(5)` is a
## runtime SCRIPT ERROR that aborts just this function, which would leave the report
## green while these refs were never checked; non-string leaves are skipped here and
## owned by the schema rules.

const Ctx = preload("res://src/validate/validate_ctx.gd")


static func check(ctx) -> void:
	var guard = ctx.guard
	if guard == null:
		ctx.warn("ASSET_INDEX_MISSING", "data/manifest_index.json", "asset index not loaded; usage rules skipped")
		ctx.rule_done()
		return
	var refs: Array = []

	_check_theme(ctx, refs)
	_collect_entity_icons(ctx, refs)
	_collect_character_icons(ctx, refs)
	_collect_audio_refs(ctx, refs)

	for r in refs:
		var id := str((r as Dictionary).get("id", ""))
		var path := str((r as Dictionary).get("path", ""))
		var code := str(guard.check_ref(id))
		if code.is_empty():
			guard.note(id, path)
			continue
		ctx.err(code, path, str(guard.ref_message(code, id)), {
			"id": id,
			"usage": str(guard.usage(id)),
			"license": str(guard.license_of(id)),
		})
	ctx.stats["asset_refs"] = refs.size()
	ctx.rule_done()


static func _theme_path(theme_name: String) -> String:
	return "res://data/%s/theme.json" % theme_name


static func _check_theme(ctx, refs: Array) -> void:
	var theme_name := Ctx.as_str(ctx.project.get("theme", ""))
	if theme_name.is_empty():
		ctx.err("THEME_MISSING", "theme", "theme is required (path like \"themes/default\")")
		return
	var path := _theme_path(theme_name)
	if not FileAccess.file_exists(path):
		ctx.err("THEME_MISSING", "theme", "theme.json not found at %s" % path)
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		ctx.err("THEME_PARSE", "theme", "%s is not valid JSON: %s" % [path, j.get_error_message()])
		return
	if typeof(j.data) != TYPE_DICTIONARY:
		ctx.err("THEME_PARSE", "theme", "%s root must be an object" % path)
		return
	var root: Dictionary = j.data
	var icons = root.get("icons", {})
	if typeof(icons) != TYPE_DICTIONARY:
		ctx.err("THEME_PARSE", "theme.icons", "theme icons must be an object")
		return
	_collect_icon_leaves(icons, "theme.icons", refs)


static func _collect_icon_leaves(node, path: String, refs: Array) -> void:
	match typeof(node):
		TYPE_DICTIONARY:
			for k in (node as Dictionary).keys():
				_collect_icon_leaves(node[k], "%s.%s" % [path, str(k)], refs)
		TYPE_STRING:
			refs.append({"id": String(node), "path": path})
		TYPE_NIL:
			pass
		_:
			pass


static func _collect_entity_icons(ctx, refs: Array) -> void:
	var entities = ctx.project.get("entities", {})
	if typeof(entities) != TYPE_DICTIONARY:
		return
	for eid in (entities as Dictionary).keys():
		var e = entities[eid]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var vis = (e as Dictionary).get("visual", {})
		if typeof(vis) != TYPE_DICTIONARY:
			continue
		var icon = (vis as Dictionary).get("icon", null)
		if typeof(icon) == TYPE_STRING:
			refs.append({"id": String(icon), "path": "entities.%s.visual.icon" % str(eid)})


static func _collect_character_icons(ctx, refs: Array) -> void:
	var chars = ctx.project.get("characters", {})
	if typeof(chars) != TYPE_DICTIONARY:
		return
	for cid in (chars as Dictionary).keys():
		var c = chars[cid]
		if typeof(c) != TYPE_DICTIONARY:
			continue
		for key in ["idle", "done"]:
			var v = (c as Dictionary).get(key, null)
			if typeof(v) == TYPE_STRING:
				refs.append({"id": String(v), "path": "characters.%s.%s" % [str(cid), key]})


static func _collect_audio_refs(ctx, refs: Array) -> void:
	var timeline = ctx.project.get("timeline", [])
	if typeof(timeline) != TYPE_ARRAY:
		return
	for i in timeline.size():
		var ev = timeline[i]
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		if Ctx.as_str((ev as Dictionary).get("channel", "")) != "audio":
			continue
		var p = (ev as Dictionary).get("payload", {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		for key in ["resource_id", "resource"]:
			var v = (p as Dictionary).get(key, null)
			if typeof(v) == TYPE_STRING:
				refs.append({"id": String(v), "path": "timeline[%d].payload.%s" % [i, key]})
