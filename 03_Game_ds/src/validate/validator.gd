extends RefCounted
## M0 project validator entry point.
##
##   const ProjectValidator = preload("res://src/validate/validator.gd")
##   var report = ProjectValidator.validate_file(path, guard, strict)
##
## Schema-level checks live here; the rule families live in rules_*.gd.

const ValidateCtx = preload("res://src/validate/validate_ctx.gd")
const ValidateReport = preload("res://src/validate/report.gd")
const RulesRefs = preload("res://src/validate/rules_refs.gd")
const RulesLevels = preload("res://src/validate/rules_levels.gd")
const RulesBoard = preload("res://src/validate/rules_board.gd")
const RulesTimeline = preload("res://src/validate/rules_timeline.gd")
const RulesUsage = preload("res://src/validate/rules_usage.gd")

const SCHEMA_VERSION := 2
const REQUIRED_TOP := ["version", "meta", "theme", "locales", "hud", "entities", "generators", "characters", "levels", "timeline"]
const HUD_FIELDS := ["level", "energy", "energyTickSeconds", "energyTickMode", "coin", "star", "gem", "exp"]
const KNOWN_TICK_MODES := ["decrement", "static"]
const M0_RESOLUTION := [1080, 1920]
const M0_FPS := 60


static func validate_file(path: String, guard, strict: bool = false):
	var report = ValidateReport.new()
	report.project_path = path
	if not FileAccess.file_exists(path):
		report.ok = false
		report.errors.append({"level": "error", "code": "IO_NOT_FOUND", "path": path, "msg": "project file not found"})
		return report
	var j := JSON.new()
	var e := j.parse(FileAccess.get_file_as_string(path))
	if e != OK:
		report.ok = false
		report.errors.append({"level": "error", "code": "JSON_PARSE", "path": path, "msg": "line %d: %s" % [j.get_error_line(), j.get_error_message()]})
		return report
	if typeof(j.data) != TYPE_DICTIONARY:
		report.ok = false
		report.errors.append({"level": "error", "code": "JSON_ROOT", "path": path, "msg": "project root must be a JSON object"})
		return report
	return validate_dictionary(j.data, path, guard, strict)


static func validate_dictionary(project: Dictionary, path: String, guard, strict: bool = false):
	var ctx = ValidateCtx.new()
	ctx.project = project
	ctx.project_path = path
	ctx.guard = guard
	ctx.strict = strict

	_run_rules(ctx)

	_finalize_stats(ctx)

	# --strict turns every warning into an error, so fixtures can assert on warnings too
	if strict and not ctx.warnings.is_empty():
		for w in ctx.warnings:
			var promoted: Dictionary = (w as Dictionary).duplicate(true)
			promoted["level"] = "error"
			promoted["code"] = str(w.get("code", ""))
			promoted["msg"] = "%s (promoted by --strict)" % str(w.get("msg", ""))
			promoted["promoted_from_warning"] = true
			ctx.errors.append(promoted)

	var report = ValidateReport.new()
	report.project_path = path
	report.errors = ctx.errors
	report.warnings = ctx.warnings
	report.stats = ctx.stats
	report.ok = ctx.errors.is_empty()
	return report


static func _run_rules(ctx) -> void:
	# A GDScript runtime error aborts only the innermost function, so a rule that
	# dies mid-way still lets validate_dictionary finish and print a green report.
	# Each rule therefore runs under an abort gate: the rule clears ctx.rule on its
	# last line, and a marker that is still set afterwards means it never got there.
	ctx.rule = "schema"
	_schema(ctx)
	_finish_rule(ctx, "schema")

	# rules_levels.gd / rules_board.gd clear the marker on their last line too, so
	# they are covered by the same abort gate as the modules below.
	ctx.rule = "levels"
	RulesLevels.check(ctx)
	_finish_rule(ctx, "levels")

	ctx.rule = "board"
	RulesBoard.check(ctx)
	_finish_rule(ctx, "board")

	ctx.rule = "refs"
	RulesRefs.check(ctx)
	_finish_rule(ctx, "refs")

	ctx.rule = "timeline"
	RulesTimeline.check(ctx)
	_finish_rule(ctx, "timeline")

	ctx.rule = "usage"
	RulesUsage.check(ctx)
	_finish_rule(ctx, "usage")


## Runs one rule family under the abort gate. The callable must call ctx.rule_done()
## as its last statement; without that marker the rule stopped early.
static func run_rule(ctx, name: String, fn: Callable) -> bool:
	ctx.rule = name
	fn.call()
	return _finish_rule(ctx, name)


static func _finish_rule(ctx, name: String) -> bool:
	var finished: bool = not ctx.rule_running()
	ctx.rule = ""
	if not finished:
		ctx.err_internal(name, "the rule stopped before its last line")
	return finished


static func _finalize_stats(ctx) -> void:
	var entities = ctx.project.get("entities", {})
	ctx.stats["entities"] = (entities as Dictionary).size() if typeof(entities) == TYPE_DICTIONARY else 0
	if not ctx.stats.has("levels"):
		var levels = ctx.project.get("levels", [])
		ctx.stats["levels"] = (levels as Array).size() if typeof(levels) == TYPE_ARRAY else 0
	if not ctx.stats.has("events"):
		var timeline = ctx.project.get("timeline", [])
		ctx.stats["events"] = (timeline as Array).size() if typeof(timeline) == TYPE_ARRAY else 0
	if not ctx.stats.has("end_time"):
		ctx.stats["end_time"] = 0.0
	ctx.stats["strict"] = ctx.strict


static func _schema(ctx) -> void:
	# ---- required top-level keys and their types ----
	for k in REQUIRED_TOP:
		if not ctx.project.has(k):
			ctx.err("SCHEMA_KEY_MISSING", k, "required top-level key \"%s\" is missing" % k)
			continue
		var v = ctx.project[k]
		var bad := false
		match k:
			"version":
				bad = not ValidateCtx.is_int_val(v)
			"meta", "locales", "hud", "entities", "generators", "characters":
				bad = not ValidateCtx.is_dict(v)
			"theme":
				bad = not ValidateCtx.is_str_val(v)
			"levels", "timeline":
				bad = not ValidateCtx.is_arr(v)
		if bad:
			ctx.err("SCHEMA_TYPE", k, "\"%s\" has the wrong type" % k)

	# ---- schema version ----
	var ver = ctx.project.get("version", null)
	if not ValidateCtx.is_int_val(ver):
		ctx.err("SCHEMA_VERSION", "version", "schema version must be the integer %d (got %s)" % [SCHEMA_VERSION, str(ver)])
	elif ValidateCtx.as_int(ver) != SCHEMA_VERSION:
		ctx.err("SCHEMA_VERSION", "version", "schema version must be %d (got %d)" % [SCHEMA_VERSION, ValidateCtx.as_int(ver)])

	# ---- meta ----
	var meta = ctx.project.get("meta", null)
	if ValidateCtx.is_dict(meta):
		var m: Dictionary = meta
		var res = m.get("resolution", null)
		var res_ok: bool = typeof(res) == TYPE_ARRAY and (res as Array).size() == 2 \
			and ValidateCtx.as_int((res as Array)[0], -1) == M0_RESOLUTION[0] \
			and ValidateCtx.as_int((res as Array)[1], -1) == M0_RESOLUTION[1]
		if not res_ok:
			ctx.err("META_RESOLUTION", "meta.resolution", "resolution must be [%d, %d] for M0 (got %s)" % [M0_RESOLUTION[0], M0_RESOLUTION[1], str(res)])
		var fps = m.get("fps", null)
		if not ValidateCtx.is_int_val(fps) or ValidateCtx.as_int(fps) != M0_FPS:
			ctx.err("META_FPS", "meta.fps", "fps must be %d for M0 (got %s)" % [M0_FPS, str(fps)])
		var loc := ""
		if not m.has("locale"):
			ctx.err("META_LOCALE", "meta.locale", "meta.locale is required")
		elif not ValidateCtx.is_string(m["locale"]):
			ctx.err("META_LOCALE_TYPE", "meta.locale", "meta.locale must be a string (got %s)" % ValidateCtx.type_name_of(m["locale"]))
		else:
			loc = String(m["locale"])
			if loc.is_empty():
				ctx.err("META_LOCALE", "meta.locale", "meta.locale is required")
			else:
				var locales = ctx.project.get("locales", {})
				if ValidateCtx.is_dict(locales) and not (locales as Dictionary).has(loc):
					ctx.err("META_LOCALE", "meta.locale", "locale \"%s\" has no table under locales" % loc)
		if m.has("duration"):
			ctx.warn("META_DURATION_PRESENT", "meta.duration", "meta.duration is not a length source; the timeline end is authoritative (found %s)" % str(m.get("duration")))

	# ---- hud: every field is explicit in M0 ----
	var hud = ctx.project.get("hud", null)
	if ValidateCtx.is_dict(hud):
		var h: Dictionary = hud
		for f in HUD_FIELDS:
			if not h.has(f):
				ctx.err("HUD_MISSING_FIELD", "hud." + str(f), "hud.%s is required in M0 (level/energy/energyTickSeconds/energyTickMode/coin/star/gem/exp)" % str(f))
				continue
			if f == "energyTickMode":
				if not ValidateCtx.is_string(h[f]):
					ctx.err("HUD_BAD_TYPE", "hud.energyTickMode", "energyTickMode must be a string (got %s)" % ValidateCtx.type_name_of(h[f]))
					continue
				var mode := String(h[f])
				if mode.is_empty():
					ctx.err("HUD_BAD_TYPE", "hud.energyTickMode", "energyTickMode must be a string")
				elif not KNOWN_TICK_MODES.has(mode):
					ctx.warn("HUD_TICK_MODE", "hud.energyTickMode", "unknown energyTickMode \"%s\" (known: %s)" % [mode, str(KNOWN_TICK_MODES)])
			elif not ValidateCtx.is_num(h.get(f)):
				ctx.err("HUD_BAD_TYPE", "hud." + str(f), "hud.%s must be a number" % str(f))
	ctx.rule_done()
