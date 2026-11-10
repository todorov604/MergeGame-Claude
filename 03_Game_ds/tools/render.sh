#!/usr/bin/env bash
# M0 render pipeline, one command, no explanations needed:
#
#   bash tools/render.sh                      # full 30 s film -> output/render.mp4
#   bash tools/render.sh --frames 120         # 2 s short take (fast smoke test)
#   bash tools/render.sh --determinism        # force two takes + framemd5 compare
#   bash tools/render.sh --keep-frames        # keep the intermediate AVIs
#   bash tools/render.sh --theme themes/pet_shop   # re-skin the film from data only
#   bash tools/render.sh --out output/x.mp4 --frames 300
#
# Stages: Godot Movie Maker (real window, MJPEG AVI) -> take-log gate -> ffprobe
# assertion -> FFmpeg H.264 MP4 -> optional second take -> framemd5 compare ->
# cleanup -> render manifest. Any failed assertion exits non-zero with a one-line
# reason. A take the sim refused is a failure, not a film: the log is scanned for
# `SCRIPT ERROR`, `[movie] rejected ...` and `rejected=N` (N > 0).
#
# Frame count comes from the project timeline (same rule as the engine:
# end = max(at + duration) over resolved anchors), never from meta.duration.
#
# Environment: GODOT_BIN overrides the engine path; FFMPEG_BIN/FFPROBE_BIN too.

set -u -o pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ_DIR" || { echo "[render] FAIL cannot cd to project dir"; exit 1; }

GODOT_BIN="${GODOT_BIN:-/e/Program Files/Godot/Godot_v4.7.2.exe}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"
FPS=60
WIDTH=1080
HEIGHT=1920
SCENE="res://src/render/movie_scene.tscn"

FRAMES_ARG=""
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="output/mov/$STAMP/film.mp4"
OUT_GIVEN=0
PROJECT="res://data/sample_project.json"
THEME=""
TAKE=""
NO_CURSOR=0
KEEP=0
DETERMINISM=0
ALLOW_PH=0

while [ $# -gt 0 ]; do
	case "$1" in
		--frames) ARG="${2:-}"; FRAMES_ARG="$ARG"; shift 2 ;;
		--frames=*) FRAMES_ARG="${1#*=}"; shift ;;
		--out) OUT="${2:-}"; OUT_GIVEN=1; shift 2 ;;
		--out=*) OUT="${1#*=}"; OUT_GIVEN=1; shift ;;
		--project) PROJECT="${2:-}"; shift 2 ;;
		--project=*) PROJECT="${1#*=}"; shift ;;
		--take) TAKE="${2:-}"; shift 2 ;;
		--take=*) TAKE="${1#*=}"; shift ;;
		--no-cursor) NO_CURSOR=1; shift ;;
		--theme) THEME="${2:-}"; shift 2 ;;
		--theme=*) THEME="${1#*=}"; shift ;;
		--keep-frames) KEEP=1; shift ;;
		--determinism) DETERMINISM=1; shift ;;
		--allow-placeholders) ALLOW_PH=1; shift ;;
		-h|--help) sed -n '2,23p' "$0"; exit 0 ;;
		*) echo "[render] FAIL unknown argument: $1" >&2; exit 2 ;;
	esac
done

# 2026-11-09：有 --take 又没指定 --out 时，成片写回 take 所在的同一个时间戳目录。
if [ "$OUT_GIVEN" -eq 0 ] && [ -n "$TAKE" ]; then
	TAKE_DIR="$(dirname "${TAKE#res://}")"
	[ "$TAKE_DIR" != "." ] && OUT="$TAKE_DIR/film.mp4"
fi

START_MS=$(date +%s%3N 2>/dev/null || echo 0)

fail() { echo "[render] FAIL $*" >&2; exit 1; }

[ -x "$GODOT_BIN" ] || fail "godot binary not found: $GODOT_BIN (set GODOT_BIN)"
command -v "$FFMPEG_BIN" >/dev/null 2>&1 || fail "ffmpeg not on PATH"
command -v "$FFPROBE_BIN" >/dev/null 2>&1 || fail "ffprobe not on PATH"

PY=""
command -v python >/dev/null 2>&1 && PY="python"
[ -z "$PY" ] && command -v python3 >/dev/null 2>&1 && PY="python3"

project_file() {
	case "$1" in
		res://*) echo "$PROJ_DIR/${1#res://}" ;;
		*) echo "$1" ;;
	esac
}

PROJECT_FILE="$(project_file "$PROJECT")"
[ -f "$PROJECT_FILE" ] || fail "project file not found: $PROJECT_FILE"

# ---------------------------------------------------------------- frame plan
if [ -n "$FRAMES_ARG" ]; then
	FRAMES="$FRAMES_ARG"
elif [ -n "$TAKE" ]; then
	# A take is its own timeline: the film runs to max(last event, recorded duration),
	# which is what movie_scene's `_end_time` computes. Planning from the project here
	# used to ask for 1800 frames while the take only had 138, and the frame gate
	# failed every replay.
	[ -n "$PY" ] || fail "--take needs python to plan the take length (or pass --frames)"
	TAKE_FILE="$(project_file "$TAKE")"
	[ -f "$TAKE_FILE" ] || fail "take file not found: $TAKE_FILE"
	FRAMES="$("$PY" - "$TAKE_FILE" <<'PYEOF'
import json, math, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
end = float(data.get("duration", 0) or 0)
for e in data.get("timeline", []) or []:
    if not isinstance(e, dict):
        continue
    at = e.get("at")
    if isinstance(at, (int, float)):
        end = max(end, float(at) + float(e.get("duration", 0) or 0))
fps = float(data.get("fps", 60) or 60)
print(int(math.ceil(end * fps - 1e-6)))
PYEOF
)"
else
	[ -n "$PY" ] || fail "--frames not given and python is unavailable to plan the timeline"
	FRAMES="$("$PY" - "$PROJECT_FILE" <<'PYEOF'
import json, math, sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
events = data.get("timeline", []) or []
by_id = {}
order = []
for e in events:
	if isinstance(e, dict) and e.get("id"):
		by_id[e["id"]] = e
		order.append(e)

resolved = {}
def resolve(eid, seen):
	if eid in resolved:
		return resolved[eid]
	if eid in seen or eid not in by_id:
		return None
	e = by_id[eid]
	at = e.get("at")
	if isinstance(at, (int, float)):
		value = float(at)
	elif isinstance(at, dict):
		base = resolve(at.get("after"), seen | {eid})
		if base is None:
			return None
		value = base + float(at.get("offset", 0) or 0)
	else:
		return None
	resolved[eid] = value
	return value

end = 0.0
for e in order:
	v = resolve(e.get("id"), frozenset())
	if v is None:
		continue
	d = e.get("duration", 0) or 0
	end = max(end, v + float(d))
fps = float((data.get("meta") or {}).get("fps", 60) or 60)
print(int(math.ceil(end * fps - 1e-6)))
PYEOF
)"
fi
case "$FRAMES" in ''|*[!0-9]*) fail "invalid frame count: '$FRAMES'" ;; esac
[ "$FRAMES" -gt 0 ] || fail "frame count must be > 0"
# 60 s M0 护栏：默认仍然拦，但**长录制（操作者的真实 take）**可以显式放行：
#   RENDER_ALLOW_LONG=1 bash tools/render.sh --take <长 take>
if [ "$FRAMES" -gt 3600 ] && [ "${RENDER_ALLOW_LONG:-0}" != "1" ]; then
	fail "frame count $FRAMES exceeds the 60 s M0 guard (set RENDER_ALLOW_LONG=1 for a real long take)"
fi

# Determinism needs two takes. Short takes are cheap, so they always get one;
# a full 30 s film needs --determinism to opt in.
if [ "$DETERMINISM" -eq 0 ] && [ "$FRAMES" -le 600 ]; then
	DETERMINISM=1
fi

TMP_ROOT="${RENDER_TMP_DIR:-output/render/tmp}"
mkdir -p "$TMP_ROOT" "$(dirname "$OUT")" || fail "cannot create output directories"
# one private directory per run: concurrent renders (and --keep-frames leftovers)
# can no longer overwrite or delete each other's takes
TMP_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXXXX")" || fail "cannot create a run directory"
MANIFEST_TMP="$TMP_DIR/render_manifest.json"
MANIFEST_OUT="${OUT%.*}.manifest.json"
cleanup_run() { [ "${KEEP:-0}" -eq 0 ] && rm -rf "$TMP_DIR"; }
trap cleanup_run EXIT
# a manifest must never outlive the film it describes
rm -f "$MANIFEST_OUT"
[ "$OUT" = "output/render.mp4" ] && rm -f output/render_manifest.json
AVI_A="$TMP_DIR/take_a.avi"
AVI_B="$TMP_DIR/take_b.avi"
LOG_A="$TMP_DIR/take_a.log"
LOG_B="$TMP_DIR/take_b.log"

echo "[render] godot=$GODOT_BIN"
THEME_LABEL="${THEME:-project.theme}"
echo "[render] project=$PROJECT scene=$SCENE frames=$FRAMES fps=$FPS out=$OUT determinism=$DETERMINISM allow_placeholders=$ALLOW_PH theme=$THEME_LABEL"

MOVIE_EXTRA=("--frames=$FRAMES" "--project=$PROJECT")
[ "$ALLOW_PH" -eq 1 ] && MOVIE_EXTRA+=("--allow-placeholders")
[ -n "$THEME" ] && MOVIE_EXTRA+=("--theme=$THEME")
[ -n "$TAKE" ] && MOVIE_EXTRA+=("--take=$TAKE")
[ "$NO_CURSOR" -eq 1 ] && MOVIE_EXTRA+=("--no-cursor")

take() { # take <avi> <log>
	"$GODOT_BIN" --path . --resolution "${WIDTH}x${HEIGHT}" --write-movie "$1" \
		--fixed-fps "$FPS" --quit-after "$FRAMES" "$SCENE" -- "${MOVIE_EXTRA[@]}" \
		"--out-manifest=$MANIFEST_TMP" \
		> "$2" 2>&1
}

# A take the sim refused is not a film. The scene exits 3 on rejected events, but
# the log is the contract as well: a take can still write frames while the log
# carries SCRIPT ERROR lines or per-event rejections. `rejected=0` must not match.
TAKE_REFUSAL_RE='SCRIPT ERROR|\[movie\] rejected |rejected=[1-9][0-9]*'
assert_take_log() { # assert_take_log <log> <label>
	local log="$1" label="$2" hits
	[ -f "$log" ] || fail "$label wrote no log ($log)"
	if ! grep -q "\[movie\] done " "$log"; then
		tail -20 "$log" >&2 || true
		fail "$label never finished a take (no [movie] done line)"
	fi
	if grep -q "\[movie\] FAIL" "$log"; then
		grep "\[movie\]" "$log" | tail -6 >&2 || true
		fail "movie scene reported a failure ($label)"
	fi
	hits="$(grep -cE "$TAKE_REFUSAL_RE" "$log" || true)"
	hits="${hits:-0}"
	if [ "$hits" -gt 0 ]; then
		grep -nE "$TAKE_REFUSAL_RE" "$log" | head -8 | sed 's/^/[render] refused-line: /' >&2
		fail "$label has $hits rejected/SCRIPT-ERROR line(s); refusing the film"
	fi
	echo "[render] take check $label clean (no SCRIPT ERROR, rejected=0)"
}

probe_num() { # probe_num <file> <entry>
	"$FFPROBE_BIN" -v error -select_streams v:0 -count_frames \
		-show_entries "stream=$2" -of default=noprint_wrappers=1:nokey=1 "$1" \
		2>/dev/null | head -1 | tr -d '\r'
}

assert_video() { # assert_video <file> <label>
	local f="$1" label="$2"
	local w h fps nbf
	w="$(probe_num "$f" width)"
	h="$(probe_num "$f" height)"
	fps="$(probe_num "$f" r_frame_rate)"
	nbf="$(probe_num "$f" nb_read_frames)"
	[ "$w" = "$WIDTH" ] || fail "$label width=$w (expected $WIDTH)"
	[ "$h" = "$HEIGHT" ] || fail "$label height=$h (expected $HEIGHT)"
	case "$fps" in
		"60/1"|"60") : ;;
		*) fail "$label fps=$fps (expected 60)" ;;
	esac
	[ "$nbf" = "$FRAMES" ] || fail "$label frames=$nbf (expected $FRAMES)"
	echo "[render] probe $label ok ${w}x${h} fps=$fps frames=$nbf"
}

# ---------------------------------------------------------------- validate
# Section 7: usage / reference / timeline violations block the film BEFORE recording.
echo "[render] stage=validate project=$PROJECT strict=1 allow_placeholders=$ALLOW_PH"
VALIDATE_ARGS=(validate --project "$PROJECT" --strict --out "")
[ "$ALLOW_PH" -eq 1 ] && VALIDATE_ARGS+=(--allow-placeholders)
if ! "$GODOT_BIN" --headless --path . --script res://src/tools/cli.gd -- \
	"${VALIDATE_ARGS[@]}" > "$TMP_DIR/validate.log" 2>&1; then
	grep -E "^\[validate\]|^  E " "$TMP_DIR/validate.log" | head -12 >&2
	fail "project failed validation; refusing to render"
fi
grep -E "^\[validate\]" "$TMP_DIR/validate.log" | head -2 | sed 's/^/[render] /'

# ------------------------------------------------------------------- take A
echo "[render] stage=record take=a frames=$FRAMES theme=$THEME_LABEL"
if ! take "$AVI_A" "$LOG_A"; then
	grep "\[movie\]\|SCRIPT ERROR" "$LOG_A" | tail -8 | sed 's/^/[render] take-fail: /' >&2 || true
	tail -20 "$LOG_A" >&2 || true
	fail "godot movie maker failed (take a); see $LOG_A"
fi
[ -s "$AVI_A" ] || fail "take a produced no AVI ($AVI_A)"
assert_take_log "$LOG_A" "take a"
grep "\[movie\] theme=" "$LOG_A" | tail -1 | sed 's/^/[render] /'
grep "\[movie\] manifest" "$LOG_A" | tail -1 | sed 's/^/[render] /'
AVI_BYTES=$(wc -c < "$AVI_A" | tr -d ' ')
echo "[render] avi a bytes=$AVI_BYTES"
assert_video "$AVI_A" "avi"

# ------------------------------------------------------------------- ffmpeg
# Mirrors RenderPlan.ffmpeg_args() (unit-tested in tests/t_render_plan.gd):
# H.264 / yuv420p / crf 18 / 60 fps / +faststart, always a real re-encode.
FF_ARGS=(-y -hide_banner -loglevel error
	-i "$AVI_A"
	-vf "scale=1080:1920:flags=lanczos,fps=60"
	-c:v libx264 -preset medium -crf 18
	-pix_fmt yuv420p -r 60
	-movflags +faststart
	-an
	"$OUT")
echo "[render] stage=transcode out=$OUT"
"$FFMPEG_BIN" "${FF_ARGS[@]}" || fail "ffmpeg transcode failed"
[ -s "$OUT" ] || fail "ffmpeg produced no MP4"
assert_video "$OUT" "mp4"
AUDIO_STREAMS=$("$FFPROBE_BIN" -v error -select_streams a -show_entries stream=index \
	-of csv=p=0 "$OUT" 2>/dev/null | grep -c . || true)
[ "$AUDIO_STREAMS" -eq 0 ] || fail "mp4 carries $AUDIO_STREAMS audio stream(s); M0 renders silent video only"
MP4_BYTES=$(wc -c < "$OUT" | tr -d ' ')
echo "[render] mp4 bytes=$MP4_BYTES"

# ------------------------------------------------------------- png sequence
# 交付要求：同一时间戳目录下再存一份 1080x1920 的 PNG 序列，方便对拍与二次剪辑。
OUT_DIR="$(dirname "$OUT")"
FRAMES_DIR="$OUT_DIR/frames"
mkdir -p "$FRAMES_DIR" || fail "cannot create frames dir: $FRAMES_DIR"
# 2026-11-09：先清空 frames/，上一轮残留的半截 PNG 会让 ffmpeg 抽帧退 -22。
rm -f "$FRAMES_DIR"/*.png
"$FFMPEG_BIN" -y -hide_banner -loglevel error -i "$OUT" \
	-vf "scale=${WIDTH}:${HEIGHT}:flags=lanczos" "$FRAMES_DIR/%05d.png" \
	|| fail "png extraction failed"
PNG_COUNT=$(ls -1 "$FRAMES_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$PNG_COUNT" -gt 0 ] || fail "no png frames written to $FRAMES_DIR"
echo "[render] png frames=$PNG_COUNT dir=$FRAMES_DIR"

# -------------------------------------------------------------- determinism
MD5_LINE="skipped"
if [ "$DETERMINISM" -eq 1 ]; then
	echo "[render] stage=record take=b (determinism)"
	if ! take "$AVI_B" "$LOG_B"; then
		grep "\[movie\]\|SCRIPT ERROR" "$LOG_B" | tail -8 | sed 's/^/[render] take-fail: /' >&2 || true
		tail -20 "$LOG_B" >&2 || true
		fail "godot movie maker failed (take b); see $LOG_B"
	fi
	assert_take_log "$LOG_B" "take b"
	if ! bash tools/framemd5_compare.sh "$AVI_A" "$AVI_B"; then
		fail "framemd5 mismatch: two takes of the same timeline are not deterministic"
	fi
	MD5_LINE="$(bash tools/framemd5_compare.sh "$AVI_A" "$AVI_B" | head -1)"
	echo "[render] $MD5_LINE"
fi

# ------------------------------------------------------------------ manifest
[ -f "$MANIFEST_TMP" ] || fail "movie scene wrote no render manifest ($MANIFEST_TMP)"
if ! grep -q '"ok": true' "$MANIFEST_TMP"; then
	cat "$MANIFEST_TMP" >&2
	fail "render manifest reports blocked assets"
fi
# Published copy is derived from OUT, carries frames/fps/sha256, and is the only
# file a later run can overwrite for that specific film.
python - "$MANIFEST_TMP" "$MANIFEST_OUT" "$OUT" "$FRAMES" "$FPS" <<'PYMANIFEST'
import hashlib, json, sys
src, dst, out, frames, fps = sys.argv[1:6]
data = json.load(open(src, encoding="utf-8"))
data["out"] = out
data["frames"] = int(frames)
data["fps"] = int(fps)
try:
    with open(out, "rb") as fh:
        data["mp4_sha256"] = hashlib.sha256(fh.read()).hexdigest()
except OSError:
    data["mp4_sha256"] = ""
with open(dst, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
print("[render] manifest " + dst)
PYMANIFEST
if [ "$OUT" = "output/render.mp4" ]; then
	cp "$MANIFEST_OUT" output/render_manifest.json
	echo "[render] manifest output/render_manifest.json"
fi

# ------------------------------------------------------------------- cleanup
if [ "$KEEP" -eq 0 ]; then
	rm -f "$AVI_A" "$AVI_B"
	echo "[render] cleanup removed intermediate AVIs (use --keep-frames to keep them)"
else
	echo "[render] kept intermediates: $AVI_A${AVI_B:+ $AVI_B}"
fi

END_MS=$(date +%s%3N 2>/dev/null || echo 0)
ELAPSED_MS=$((END_MS - START_MS))
[ "$START_MS" -eq 0 ] && ELAPSED_MS=0
ELAPSED_S=$((ELAPSED_MS / 1000))

echo "[render] ok=1 frames=$FRAMES fps=$FPS size=${WIDTH}x${HEIGHT} out=$OUT theme=$THEME_LABEL mp4_bytes=$MP4_BYTES md5=${MD5_LINE} elapsed=${ELAPSED_S}s"
exit 0
