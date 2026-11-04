extends RefCounted
## Render plan / render manifest unit tests (headless, sub-second).
##
##   godot --headless --path . --script res://tests/run_tests.gd -- --suite res://tests/t_render_plan.gd
##
## The film itself needs a real window; everything that can go wrong silently in a
## render (frame count, missing --fixed-fps, an encoder without yuv420p, a frame
## checksum parser that ignores the last line, a REFERENCE_ONLY leak) is checked
## here instead.

const RenderPlan = preload("res://src/render/render_plan.gd")
const RenderManifest = preload("res://src/render/render_manifest.gd")


## Stand-in for src/assets/asset_guard.gd: same three methods, no disk.
class FakeGuard extends RefCounted:
	var table := {}

	func check_ref(id: String) -> String:
		if not table.has(id):
			return "ASSET_UNKNOWN"
		var usage := String(table[id].get("usage", ""))
		match usage:
			"REFERENCE_ONLY":
				return "ASSET_REFERENCE_ONLY"
			"PLACEHOLDER":
				return "ASSET_PLACEHOLDER_BLOCKED"
			"TODO":
				return "ASSET_TODO"
			"PRODUCTION":
				return ""
		return "ASSET_UNKNOWN_USAGE"

	func entry(id: String) -> Dictionary:
		var e = table.get(id, {})
		if typeof(e) != TYPE_DICTIONARY:
			return {}
		return e

	func ref_message(code: String, id: String) -> String:
		return code + ":" + id


func _framemd5_text(hashes: Array) -> String:
	var lines: Array = [
		"#format: frame checksums",
		"#version: 2",
		"#hash: MD5",
		"#tb 0: 1/60",
		"#media_type 0: video",
		"#codec_id 0: mjpeg",
		"#dimensions 0: 1080x1920",
		"#sar 0: 1/1",
	]
	for i in range(hashes.size()):
		# Real framemd5 rows carry a 32-char md5; pad the short test tags so the
		# fixture stays as wide as the thing it imitates.
		lines.append("%d, %d, %d, 1, 1833, %s" % [i, i, i, String(hashes[i]).rpad(32, "0")])
	return "\n".join(PackedStringArray(lines)) + "\n"


func run(t) -> void:
	_test_frame_count(t)
	_test_movie_args(t)
	_test_ffmpeg_args(t)
	_test_probe_expectations(t)
	_test_parse_framemd5(t)
	_test_manifest_clean(t)
	_test_manifest_blocked(t)
	_test_manifest_dedup(t)


func _test_frame_count(t) -> void:
	t.eq(RenderPlan.frame_count(30.0, 60), 1800, "frame_count(30.0,60) == 1800")
	t.eq(RenderPlan.frame_count(0.3, 60), 18, "frame_count(0.3,60) == 18")
	t.eq(RenderPlan.frame_count(2.0, 60), 120, "frame_count(2.0,60) == 120")
	t.eq(RenderPlan.frame_count(1.0, 30), 30, "frame_count(1.0,30) == 30")
	t.eq(RenderPlan.frame_count(0.0, 60), 0, "frame_count(0.0,60) == 0")
	t.eq(RenderPlan.frame_count(30.0, 0), 0, "frame_count(fps=0) == 0")
	t.eq(RenderPlan.frame_count(30.05, 60), 1803, "frame_count rounds up past a partial frame")
	t.eq(RenderPlan.frame_count(29.999999, 60), 1800, "frame_count(29.999999,60) == 1800 (no phantom frame)")


func _test_movie_args(t) -> void:
	var plan := {
		"avi": "output/tmp/a.avi",
		"frames": 1800,
		"fps": 60,
		"scene": "res://src/render/movie_scene.tscn",
		"project_dir": ".",
	}
	var args := RenderPlan.movie_args(plan)
	var joined := " ".join(args)
	t.ok(args.has("--write-movie"), "movie_args has --write-movie")
	t.ok(args.has("--fixed-fps"), "movie_args has --fixed-fps")
	t.ok(args.has("60"), "movie_args pins 60 fps")
	t.ok(args.has("--quit-after"), "movie_args has --quit-after")
	t.ok(args.has("1800"), "movie_args quits after 1800 frames")
	t.ok(args.has("--resolution") and args.has("1080x1920"), "movie_args pins 1080x1920")
	t.ok(args.has("res://src/render/movie_scene.tscn"), "movie_args runs the movie scene")
	t.ok(args.has("--path") and args.has("."), "movie_args sets --path .")
	t.ok(not args.has("--headless"), "movie_args never requests --headless")
	t.ok(joined.contains("--write-movie output/tmp/a.avi"), "write-movie path is passed through")
	t.ok(args.has("--frames=1800"), "scene gets its own --frames=N user arg")
	var dd := args.find("--")
	t.ok(dd > 0 and dd == args.size() - 2, "user args come after a single -- separator")

	var extra := RenderPlan.movie_args({
		"avi": "output/tmp/a.avi", "frames": 120, "project_dir": ".",
		"extra_args": ["--project=res://data/sample_project.json"],
	})
	t.ok(extra.has("--frames=120"), "extra args keep the frame cap")
	t.ok(extra.has("--project=res://data/sample_project.json"), "extra args carry the project path through")


func _test_ffmpeg_args(t) -> void:
	var args := RenderPlan.ffmpeg_args("output/tmp/a.avi", "output/render.mp4")
	var joined := " ".join(args)
	t.ok(args.has("-i") and args.has("output/tmp/a.avi"), "ffmpeg_args reads the AVI")
	t.ok(args.has("output/render.mp4"), "ffmpeg_args writes the MP4")
	t.ok(args.has("-r") and args.has("60"), "ffmpeg_args forces 60 fps")
	t.ok(joined.contains("1080") and joined.contains("1920"), "ffmpeg_args scales to 1080x1920")
	t.ok(joined.contains("-vf"), "ffmpeg_args uses a video filter")
	t.ok(args.has("yuv420p"), "ffmpeg_args outputs yuv420p")
	t.ok(args.has("+faststart"), "ffmpeg_args sets +faststart")
	t.ok(args.has("libx264"), "ffmpeg_args uses libx264")
	t.ok(args.has("-crf") and args.has("18"), "ffmpeg_args pins crf 18")
	t.ok(not joined.contains("copy"), "ffmpeg_args never stream-copies (MJPEG must be re-encoded)")


func _test_probe_expectations(t) -> void:
	var p := RenderPlan.probe_expectations(60, 1800)
	t.eq(int(p["width"]), 1080, "probe expects width 1080")
	t.eq(int(p["height"]), 1920, "probe expects height 1920")
	t.eq(int(p["fps"]), 60, "probe expects 60 fps")
	t.eq(int(p["frames"]), 1800, "probe expects 1800 frames")
	t.ok(absf(float(p["duration"]) - 30.0) < 0.0001, "probe expects 30.0 s")
	t.ok(float(p["duration_tolerance"]) > 0.0, "probe exposes a duration tolerance")
	var s := RenderPlan.probe_expectations(60, 120)
	t.ok(absf(float(s["duration"]) - 2.0) < 0.0001, "2 s clip -> 2.0 s duration")


func _test_parse_framemd5(t) -> void:
	var a := _framemd5_text(["aa11", "bb22", "cc33", "dd44"])
	var a2 := _framemd5_text(["aa11", "bb22", "cc33", "dd44"])
	var b := _framemd5_text(["aa11", "bb22", "cc33", "ee55"])

	var ra := RenderPlan.parse_framemd5(a)
	var ra2 := RenderPlan.parse_framemd5(a2)
	var rb := RenderPlan.parse_framemd5(b)

	t.eq(int(ra["count"]), 4, "framemd5 parses 4 frames")
	t.ok(bool(ra["ok"]), "framemd5 parse reports ok")
	t.eq(int(ra["width"]), 1080, "framemd5 parses the dimensions line")
	t.eq(int(ra["height"]), 1920, "framemd5 parses the dimensions height")
	t.eq(String(ra["tb"]), "1/60", "framemd5 parses the timebase")
	t.eq(String(ra["digest"]), String(ra2["digest"]), "identical framemd5 -> identical digest")
	t.ne(String(ra["digest"]), String(rb["digest"]), "one different frame -> different digest")
	t.ok(String(ra["digest"]).length() == 64, "digest is a sha256 hex string")
	t.eq((ra["hashes"] as Array).size(), 4, "framemd5 keeps every hash")

	var truncated := RenderPlan.parse_framemd5(_framemd5_text(["aa11", "bb22"]))
	t.eq(int(truncated["count"]), 2, "a 2-frame clip parses as 2 frames")
	t.ne(String(truncated["digest"]), String(ra["digest"]), "different frame counts never collide")
	var empty := RenderPlan.parse_framemd5("#format: frame checksums\n")
	t.ok(not bool(empty["ok"]), "empty framemd5 is not ok")
	t.eq(int(empty["count"]), 0, "empty framemd5 has zero frames")


func _test_manifest_clean(t) -> void:
	var guard := FakeGuard.new()
	guard.table["font_zh"] = {"usage": "PRODUCTION", "license": "self-made"}
	var m := RenderManifest.build({
		"project": "res://data/sample_project.json",
		"project_title": "Merge Ad 30s (M0 sample)",
		"fps": 60,
		"frames": 1800,
		"end_time": 30.0,
		"allow_placeholders": false,
		"refs": ["font_zh"],
	}, guard)
	t.ok(bool(m["ok"]), "manifest: production-only render is ok")
	t.ok((m["blocked"] as Array).is_empty(), "manifest: no blocked refs")
	t.eq((m["assets"] as Array).size(), 1, "manifest: one asset row per used id")
	t.eq(String((m["assets"] as Array)[0]["id"]), "font_zh", "manifest: asset id recorded")
	t.eq(String((m["assets"] as Array)[0]["usage"]), "PRODUCTION", "manifest: usage recorded")
	t.eq(String((m["assets"] as Array)[0]["license"]), "self-made", "manifest: licence recorded")
	t.eq(int(m["frames"]), 1800, "manifest: frame count recorded")
	t.ok(absf(float(m["end_time"]) - 30.0) < 0.0001, "manifest: end_time recorded")
	t.eq(int(m["schema"]), 1, "manifest: schema version present")


func _test_manifest_blocked(t) -> void:
	var guard := FakeGuard.new()
	guard.table["font_zh"] = {"usage": "PRODUCTION", "license": "self-made"}
	guard.table["chip_clean_ca_lv01"] = {"usage": "REFERENCE_ONLY", "license": "original game"}
	var m := RenderManifest.build({
		"project": "res://data/sample_project.json",
		"fps": 60,
		"frames": 120,
		"end_time": 2.0,
		"refs": ["font_zh", "chip_clean_ca_lv01"],
	}, guard)
	t.ok(not bool(m["ok"]), "manifest: a REFERENCE_ONLY reference fails the render")
	var blocked: Array = m["blocked"]
	t.eq(blocked.size(), 1, "manifest: exactly one blocked ref")
	t.eq(String(blocked[0]["id"]), "chip_clean_ca_lv01", "manifest: blocked id recorded")
	t.eq(String(blocked[0]["code"]), "ASSET_REFERENCE_ONLY", "manifest: blocked code recorded")
	t.ok(String(blocked[0]["message"]).contains("chip_clean_ca_lv01"), "manifest: blocked message names the id")
	var rows: Array = m["assets"]
	t.eq(rows.size(), 2, "manifest: blocked asset still appears in assets with allowed=false")
	t.eq(bool(rows[1]["allowed"]), false, "manifest: blocked asset is marked not allowed")

	var todo := FakeGuard.new()
	todo.table["audio_bgm"] = {"usage": "TODO", "license": "n/a"}
	var mt := RenderManifest.build({"refs": ["audio_bgm"]}, todo)
	t.eq(String((mt["blocked"] as Array)[0]["code"]), "ASSET_TODO", "manifest: TODO blocks the render")


func _test_manifest_dedup(t) -> void:
	var guard := FakeGuard.new()
	guard.table["font_zh"] = {"usage": "PRODUCTION", "license": "self-made"}
	var m := RenderManifest.build({"refs": ["font_zh", "font_zh", "font_zh"]}, guard)
	t.eq((m["assets"] as Array).size(), 1, "manifest: repeated refs are deduped")
	var text := RenderManifest.to_text(m)
	t.ok(text.contains("\"assets\""), "manifest: serialises to JSON text")
	t.ok(RenderManifest.summary(m).contains("ok=true"), "manifest: summary is a one-line ASCII status")
	t.eq(RenderManifest.detail(m), "font_zh(PRODUCTION)", "manifest: detail lists id+usage")
