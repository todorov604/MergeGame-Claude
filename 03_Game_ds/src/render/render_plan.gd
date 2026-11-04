extends RefCounted
## Deterministic render plan: pure functions, no engine state, no side effects.
##
## The movie scene, the shell wrapper and the tests all have to agree on the same
## four things (frame count, quit-after, encoder settings, expected probe result).
## Keeping them in one testable object is what stops "the film came out 1799
## frames" from becoming a mystery two weeks later.
##
## Nothing here touches the filesystem or the clock, so every function is safe to
## call from a headless unit test.

const DEFAULT_FPS := 60
const DEFAULT_WIDTH := 1080
const DEFAULT_HEIGHT := 1920
const DEFAULT_SCENE := "res://src/render/movie_scene.tscn"


## 30.0 s at 60 fps -> 1800 frames. 0.3 s at 60 -> 18 frames (not 19: 0.3 * 60 is
## 17.999999999999996 in binary, and the epsilon keeps that rounding artefact from
## adding a phantom frame to every short test render).
static func frame_count(end_time: float, fps: int) -> int:
	if fps <= 0:
		return 0
	if end_time <= 0.0:
		return 0
	return int(ceil(end_time * float(fps) - 1e-6))


## Command line for the Godot Movie Maker pass.
##
## plan keys: avi, frames, fps, width, height, project_dir, scene, extra_args.
## The result never contains --headless: Movie Maker needs a real window, and the
## whole point of this argument builder is to make that impossible to forget.
static func movie_args(plan: Dictionary) -> PackedStringArray:
	var fps := int(plan.get("fps", DEFAULT_FPS))
	var frames := int(plan.get("frames", 0))
	var width := int(plan.get("width", DEFAULT_WIDTH))
	var height := int(plan.get("height", DEFAULT_HEIGHT))
	var avi := String(plan.get("avi", "output/render.avi"))
	var scene := String(plan.get("scene", DEFAULT_SCENE))
	var project_dir := String(plan.get("project_dir", "."))

	var out := PackedStringArray()
	out.append("--path")
	out.append(project_dir)
	out.append("--resolution")
	out.append("%dx%d" % [width, height])
	out.append("--write-movie")
	out.append(avi)
	out.append("--fixed-fps")
	out.append(str(fps))
	out.append("--quit-after")
	out.append(str(frames))
	out.append(scene)
	out.append("--")
	out.append("--frames=" + str(frames))
	var extra = plan.get("extra_args", [])
	if typeof(extra) == TYPE_ARRAY:
		for a in extra:
			out.append(String(a))
	return out


## FFmpeg transcoding step: MJPEG AVI -> H.264 MP4 that any player/browser takes.
static func ffmpeg_args(avi: String, mp4: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("-y")
	out.append("-hide_banner")
	out.append("-loglevel")
	out.append("error")
	out.append("-i")
	out.append(avi)
	out.append("-vf")
	out.append("scale=1080:1920:flags=lanczos,fps=60")
	out.append("-c:v")
	out.append("libx264")
	out.append("-preset")
	out.append("medium")
	out.append("-crf")
	out.append("18")
	out.append("-pix_fmt")
	out.append("yuv420p")
	out.append("-r")
	out.append("60")
	out.append("-movflags")
	out.append("+faststart")
	# M0 has no audio: strip the Movie Maker's silent PCM track so the deliverable
	# has exactly one stream and does not depend on the machine's audio driver.
	out.append("-an")
	out.append(mp4)
	return out


## What ffprobe must report for a 1080x1920 60 fps film of `frames` frames.
## `duration_tolerance` is two frames: containers round the last packet's
## duration, and a 1/60 disagreement is never a real defect.
static func probe_expectations(fps: int, frames: int) -> Dictionary:
	var f := fps if fps > 0 else DEFAULT_FPS
	return {
		"width": DEFAULT_WIDTH,
		"height": DEFAULT_HEIGHT,
		"fps": f,
		"frames": frames,
		"duration": float(frames) / float(f),
		"duration_tolerance": 2.0 / float(f),
	}


## Parses `ffmpeg -f framemd5 -` output.
##
## Returns {ok, count, hashes, digest, width, height, tb}. `digest` is the sha256
## of the per-frame hashes joined by newlines, so two renders can be compared with
## one short string instead of 1800 lines of transcript.
static func parse_framemd5(text: String) -> Dictionary:
	var hashes: Array = []
	var width := 0
	var height := 0
	var tb := ""
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			if line.begins_with("#dimensions"):
				var di := line.find(":")
				if di >= 0:
					var dim := line.substr(di + 1).strip_edges()
					var parts := dim.split("x")
					if parts.size() == 2:
						width = int(parts[0])
						height = int(parts[1])
			elif line.begins_with("#tb"):
				var ti := line.find(":")
				if ti >= 0:
					tb = line.substr(ti + 1).strip_edges()
			continue
		var cols := line.split(",")
		if cols.size() < 6:
			continue
		var h := String(cols[cols.size() - 1]).strip_edges()
		if h.length() < 8:
			continue
		hashes.append(h)
	var digest := ""
	if not hashes.is_empty():
		digest = "\n".join(PackedStringArray(hashes)).sha256_text()
	return {
		"ok": not hashes.is_empty(),
		"count": hashes.size(),
		"hashes": hashes,
		"digest": digest,
		"width": width,
		"height": height,
		"tb": tb,
	}
