extends RefCounted
## Read-only view of project.json for the runtime (sim / view).
##
## The validator owns the error catalogue; this model only guarantees that the
## data is structurally usable for simulation. `load_data` exists so tests can
## build fixtures in memory without touching disk.

const DEFAULT_HUD := {
	"level": 1,
	"energy": 0,
	"energyTickSeconds": 120,
	"energyTickMode": "decrement",
	"coin": 0,
	"gem": 0,
	"exp": 0,
}

var project: Dictionary = {}
var load_error: String = ""
var source_path: String = ""


func load_file(path: String) -> bool:
	project = {}
	load_error = ""
	source_path = path
	if path.is_empty():
		load_error = "IO_NOT_FOUND empty path"
		return false
	if not FileAccess.file_exists(path):
		load_error = "IO_NOT_FOUND " + path
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		load_error = "IO_EMPTY " + path
		return false
	var j := JSON.new()
	if j.parse(text) != OK:
		load_error = "JSON_PARSE %s (line %d)" % [j.get_error_message(), j.get_error_line()]
		return false
	if typeof(j.data) != TYPE_DICTIONARY:
		load_error = "JSON_ROOT root must be an object"
		return false
	return load_data(j.data)


func load_data(data: Dictionary) -> bool:
	project = {}
	load_error = ""
	var levels = data.get("levels", null)
	if typeof(levels) != TYPE_ARRAY or (levels as Array).is_empty():
		load_error = "NO_LEVELS project needs a non-empty levels array"
		return false
	var entities = data.get("entities", null)
	if typeof(entities) != TYPE_DICTIONARY:
		load_error = "NO_ENTITIES project needs an entities table"
		return false
	project = data
	return true


func level_count() -> int:
	var levels = project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return 0
	return (levels as Array).size()


func level(index: int) -> Dictionary:
	var levels = project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return {}
	var arr: Array = levels
	if index < 0 or index >= arr.size():
		return {}
	var lvl = arr[index]
	if typeof(lvl) != TYPE_DICTIONARY:
		return {}
	return lvl


func entity(id: String) -> Dictionary:
	var table = project.get("entities", {})
	if typeof(table) != TYPE_DICTIONARY:
		return {}
	var e = (table as Dictionary).get(id, {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	return e


func generator(id: String) -> Dictionary:
	var table = project.get("generators", {})
	if typeof(table) != TYPE_DICTIONARY:
		return {}
	var g = (table as Dictionary).get(id, {})
	if typeof(g) != TYPE_DICTIONARY:
		return {}
	return g


func character(id: String) -> Dictionary:
	var table = project.get("characters", {})
	if typeof(table) != TYPE_DICTIONARY:
		return {}
	var c = (table as Dictionary).get(id, {})
	if typeof(c) != TYPE_DICTIONARY:
		return {}
	return c


## Fresh dictionary every call: the sim owns and mutates its own HUD copy.
func hud_initial() -> Dictionary:
	var out := DEFAULT_HUD.duplicate(true)
	var table = project.get("hud", {})
	if typeof(table) == TYPE_DICTIONARY:
		for k in (table as Dictionary).keys():
			out[String(k)] = (table as Dictionary)[k]
	return out


func entity_ids() -> Array:
	var table = project.get("entities", {})
	if typeof(table) != TYPE_DICTIONARY:
		return []
	var ids: Array = (table as Dictionary).keys()
	ids.sort()
	return ids
