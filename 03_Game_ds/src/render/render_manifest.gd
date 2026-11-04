extends RefCounted
## Builds output/render_manifest.json: which manifest resources a render touched,
## their usage level and licence, and every reference that had to be blocked.
##
## M0 spec 4.3: the export log must carry the resource id, usage and licence
## summary of everything that actually went into the film. `ok == false` means at
## least one reference was REFERENCE_ONLY / an un-opened PLACEHOLDER / a TODO, so
## the render pipeline must abort instead of shipping it.
##
## Pure data in, pure data out: the caller passes the asset guard (real or fake),
## which is what makes the blocking path unit-testable without a renderer.

const SCHEMA := 1


## ctx keys:
##   project, project_title, fps, frames, end_time, allow_placeholders, refs
## `refs` is the list of manifest ids the render actually asked the guard for.
static func build(ctx: Dictionary, guard = null) -> Dictionary:
	var assets: Array = []
	var blocked: Array = []
	var seen := {}
	var refs = ctx.get("refs", [])
	if typeof(refs) == TYPE_ARRAY:
		for raw in refs:
			var id := String(raw)
			if id.is_empty() or seen.has(id):
				continue
			seen[id] = true
			if guard == null:
				continue
			var code := String(guard.check_ref(id))
			var entry: Dictionary = guard.entry(id)
			assets.append({
				"id": id,
				"usage": String(entry.get("usage", "")),
				"license": String(entry.get("license", "")),
				"allowed": code.is_empty(),
			})
			if not code.is_empty():
				blocked.append({
					"id": id,
					"code": code,
					"message": String(guard.ref_message(code, id)),
				})

	return {
		"schema": SCHEMA,
		"ok": blocked.is_empty(),
		"project": String(ctx.get("project", "")),
		"project_title": String(ctx.get("project_title", "")),
		"fps": int(ctx.get("fps", 60)),
		"frames": int(ctx.get("frames", 0)),
		"end_time": float(ctx.get("end_time", 0.0)),
		"allow_placeholders": bool(ctx.get("allow_placeholders", false)),
		"assets": assets,
		"blocked": blocked,
	}


static func to_text(manifest: Dictionary) -> String:
	# sort_keys is on by default: the same render always produces the same file,
	# so a diff between two runs only ever shows a real change.
	return JSON.stringify(manifest, "  ") + "\n"


## One ASCII line for the render log.
static func summary(manifest: Dictionary) -> String:
	var ids: Array = []
	var assets = manifest.get("assets", [])
	if typeof(assets) == TYPE_ARRAY:
		for a in assets:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			ids.append("%s:%s" % [String(a.get("id", "")), String(a.get("usage", ""))])
	var blocked = manifest.get("blocked", [])
	var blocked_codes: Array = []
	if typeof(blocked) == TYPE_ARRAY:
		for b in blocked:
			if typeof(b) == TYPE_DICTIONARY:
				blocked_codes.append("%s=%s" % [String(b.get("id", "")), String(b.get("code", ""))])
	return "ok=%s frames=%d fps=%d end=%.3f allow_placeholders=%s assets=%d blocked=%d" % [
		"true" if bool(manifest.get("ok", false)) else "false",
		int(manifest.get("frames", 0)),
		int(manifest.get("fps", 0)),
		float(manifest.get("end_time", 0.0)),
		"true" if bool(manifest.get("allow_placeholders", false)) else "false",
		ids.size(),
		blocked_codes.size(),
	]


static func detail(manifest: Dictionary) -> String:
	var parts: Array = []
	var assets = manifest.get("assets", [])
	if typeof(assets) == TYPE_ARRAY:
		for a in assets:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			parts.append("%s(%s)" % [String(a.get("id", "")), String(a.get("usage", ""))])
	var blocked = manifest.get("blocked", [])
	if typeof(blocked) == TYPE_ARRAY:
		for b in blocked:
			if typeof(b) == TYPE_DICTIONARY:
				parts.append("BLOCKED:%s(%s)" % [String(b.get("id", "")), String(b.get("code", ""))])
	return ", ".join(PackedStringArray(parts))


static func write_file(path: String, manifest: Dictionary) -> int:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_text(manifest))
	f.close()
	return OK
