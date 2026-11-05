extends RefCounted
## User-supplied display fonts (2026-11-05). The TTFs live under res://font/源字体
## and are loaded straight from disk — they are intentionally NOT copied into
## assets/ (each weight is ~15 MB) and therefore stay out of the payload count.

const DISPLAY_BOLD := "res://font/源字体/中文-江城圆体600W/江城圆体 700W.ttf"
const DISPLAY_REGULAR := "res://font/源字体/中文-江城圆体600W/江城圆体 400W.ttf"


static func load_font(path: String) -> Font:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		return null
	return file
