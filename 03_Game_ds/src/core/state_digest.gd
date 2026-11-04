extends RefCounted
## Canonical serialisation + SHA-256 for state snapshots.
##
## JSON.stringify keeps dictionary insertion order, which is an accidental
## property of the caller. Digesting a canonical form instead means two runs
## that built the same state in a different order still hash the same, and a
## real difference is never masked by key order.


static func canonical(value) -> String:
	var t := typeof(value)
	match t:
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var f := float(value)
			if is_nan(f) or is_inf(f):
				return "\"" + str(f) + "\""
			return "%.6f" % f
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var parts: Array = []
			for v in (value as Array):
				parts.append(canonical(v))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = []
			for k in d.keys():
				keys.append(String(k))
			keys.sort()
			var parts: Array = []
			for k in keys:
				var raw_key = _find_key(d, String(k))
				parts.append(JSON.stringify(String(k)) + ":" + canonical(d[raw_key]))
			return "{" + ",".join(parts) + "}"
		TYPE_VECTOR2I:
			var v2: Vector2i = value
			return "[" + str(v2.x) + "," + str(v2.y) + "]"
		TYPE_VECTOR2:
			var vf: Vector2 = value
			return "[" + ("%.6f" % vf.x) + "," + ("%.6f" % vf.y) + "]"
	return JSON.stringify(str(value))


static func _find_key(d: Dictionary, as_string: String):
	if d.has(as_string):
		return as_string
	for k in d.keys():
		if String(k) == as_string:
			return k
	return as_string


static func hash_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func of(value) -> String:
	return hash_text(canonical(value))
