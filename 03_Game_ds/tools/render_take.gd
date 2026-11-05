extends SceneTree
## take -> MP4 in one shot, with no shell in the loop.
##
##   godot --headless --path . --script res://tools/render_take.gd -- \
##         --take=output/mov/take_20261105_153012.take.json \
##         --out=output/mov/take_20261105_153012.mp4
##
## The live screen spawns exactly this after R stops a recording, so "press R when
## you are done, the film appears in output/mov/" needs no terminal at all.
##
## Two child processes, both waited on from here (this process is headless and does
## nothing else, so blocking is free):
##   1. the engine itself with --write-movie (Movie Maker needs a real window)
##   2. ffmpeg: MJPEG AVI -> H.264 MP4, the same encode render.sh uses
##
## Every step writes to <out>.log next to the film, and a failure leaves the log
## behind instead of vanishing into a window that closed itself.

const TakeIo := preload("res://src/core/take_io.gd")
const FPS := 60
const WIDTH := 1080
const HEIGHT := 1920
const SCENE := "res://src/render/movie_scene.tscn"
const DEFAULT_PROJECT := "res://data/sample_project.json"

var _take_path := ""
var _out_path := ""


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--take="):
			_take_path = arg.substr(7)
		elif arg.begins_with("--out="):
			_out_path = arg.substr(6)
	if _take_path.is_empty() or _out_path.is_empty():
		print("[take] FAIL usage: --take=<file> --out=<mp4>")
		_finish(2)
		return

	var take: Dictionary = TakeIo.load_file(_abs(_take_path))
	if take.is_empty():
		print("[take] FAIL take not readable: " + _take_path)
		_finish(1)
		return
	var check: Dictionary = TakeIo.validate(take)
	if not bool(check.get("ok", false)):
		print("[take] FAIL invalid take: " + str(check.get("errors", [])))
		_finish(1)
		return

	var frames := _frame_count(take)
	if frames <= 0:
		print("[take] FAIL take has no duration and no events")
		_finish(1)
		return

	var out_abs := _abs(_out_path)
	var base := out_abs.get_basename()
	var avi := base + ".avi"
	var manifest_path := base + ".manifest.json"
	var log_path := base + ".log"
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())

	var project := String(take.get("project", DEFAULT_PROJECT))
	var lines: Array = []
	lines.append("[take] take=%s frames=%d fps=%d out=%s" % [_take_path, frames, FPS, _out_path])

	var movie_args := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		"--resolution", "%dx%d" % [WIDTH, HEIGHT],
		"--write-movie", avi,
		"--fixed-fps", str(FPS),
		"--quit-after", str(frames),
		SCENE,
		"--",
		"--frames=" + str(frames),
		"--take=" + _take_path,
		"--project=" + project,
		"--out-manifest=" + manifest_path,
	])
	var movie_out: Array = []
	var movie_code := OS.execute(OS.get_executable_path(), movie_args, movie_out, true)
	for raw in movie_out:
		lines.append(String(raw).strip_edges())
	lines.append("[take] movie exit=%d" % movie_code)
	if movie_code != 0:
		_write_log(log_path, lines)
		print("[take] FAIL movie exit=%d (see %s)" % [movie_code, log_path])
		_finish(1)
		return
	if not FileAccess.file_exists(avi):
		_write_log(log_path, lines)
		print("[take] FAIL movie wrote no avi: " + avi)
		_finish(1)
		return

	var ff_args := PackedStringArray([
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", avi,
		"-vf", "scale=%d:%d:flags=lanczos,fps=%d" % [WIDTH, HEIGHT, FPS],
		"-c:v", "libx264", "-preset", "medium", "-crf", "18",
		"-pix_fmt", "yuv420p", "-r", str(FPS), "-movflags", "+faststart", "-an",
		out_abs,
	])
	var ff_out: Array = []
	var ff_code := OS.execute("ffmpeg", ff_args, ff_out, true)
	for raw in ff_out:
		lines.append(String(raw).strip_edges())
	lines.append("[take] ffmpeg exit=%d" % ff_code)
	_write_log(log_path, lines)
	if ff_code != 0:
		print("[take] FAIL ffmpeg exit=%d (see %s)" % [ff_code, log_path])
		_finish(1)
		return
	DirAccess.remove_absolute(avi)
	print("[take] ok %s %s" % [_out_path, TakeIo.summary(take)])
	_finish(0)


## The film runs to max(recorded duration, last event), exactly like movie_scene.
func _frame_count(take: Dictionary) -> int:
	var end := float(take.get("duration", 0.0))
	for raw in take.get("timeline", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw
		var at = event.get("at", null)
		if typeof(at) == TYPE_INT or typeof(at) == TYPE_FLOAT:
			end = maxf(end, float(at) + float(event.get("duration", 0.0)))
	if end <= 0.0:
		return 0
	return int(ceil(end * float(FPS) - 1.0e-6))


## `res://` and `user://` resolve through the engine; a bare relative path is
## resolved against the project directory, never against the caller's cwd (the
## child process may be started from anywhere).
func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _write_log(path: String, lines: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(PackedStringArray(lines)) + "\n")
	file.close()


func _finish(code: int) -> void:
	quit(code)
