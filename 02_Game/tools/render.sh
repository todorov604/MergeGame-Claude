#!/usr/bin/env bash
# M0 出片脚本：Godot Movie Maker (PNG 序列) -> FFmpeg H.264 MP4 -> ffprobe 校验。
# 用法：
#   tools/render.sh [--project <path>] [--out <file.mp4>] [--keep-frames] [--verify]
#                   [--crf N] [--preset P]
# 环境变量：GODOT_BIN 可覆盖 Godot 可执行文件路径。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-E:/Program Files/Godot/Godot_v4.7.2.exe}"
PROJECT_PATH="res://data/projects/sample_30s.json"
OUT_MP4=""
KEEP_FRAMES=0
VERIFY=0
CRF=18
PRESET="medium"
MIN_FREE_GB=20

usage() {
	cat <<'EOF'
用法: tools/render.sh [选项]
  --project <path>   项目 JSON（默认 res://data/projects/sample_30s.json）
  --out <file.mp4>   输出 MP4（默认 02_Game/output/<项目名>.mp4）
  --keep-frames      保留 PNG 序列（默认转码后删除）
  --verify           连跑两遍并比对 framemd5（确定性验收）
  --crf <n>          x264 CRF（默认 18）
  --preset <p>       x264 preset（默认 medium）
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--project) PROJECT_PATH="$2"; shift 2 ;;
		--out) OUT_MP4="$2"; shift 2 ;;
		--keep-frames) KEEP_FRAMES=1; shift ;;
		--verify) VERIFY=1; shift ;;
		--crf) CRF="$2"; shift 2 ;;
		--preset) PRESET="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "未知参数: $1" >&2; usage; exit 1 ;;
	esac
done

[ -x "$GODOT_BIN" ] || { echo "Godot 不存在或不可执行: $GODOT_BIN" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg 未安装" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe 未安装" >&2; exit 1; }

if [ -z "$OUT_MP4" ]; then
	base="$(basename "$PROJECT_PATH" .json)"
	OUT_MP4="$PROJECT_ROOT/output/${base}.mp4"
fi
OUT_DIR="$(dirname "$OUT_MP4")"
mkdir -p "$OUT_DIR"

if [ "$KEEP_FRAMES" != "1" ]; then
	trap 'rm -rf "$OUT_DIR"/.frames_render.*' EXIT
fi

echo "== 导出信息 =="
if ! info="$("$GODOT_BIN" --headless --path "$PROJECT_ROOT" -s res://tools/export_info.gd -- --project "$PROJECT_PATH" --allow-placeholders 2>&1)"; then
	echo "$info" >&2
	exit 1
fi
echo "$info"
grep -q '^ok=true$' <<<"$info" || { echo "项目不可出片" >&2; exit 1; }

WIDTH="$(sed -n 's/^width=//p' <<<"$info")"
HEIGHT="$(sed -n 's/^height=//p' <<<"$info")"
FPS="$(sed -n 's/^fps=//p' <<<"$info")"
FRAMES="$(sed -n 's/^frames=//p' <<<"$info")"
DURATION="$(sed -n 's/^duration=//p' <<<"$info")"

[ "$WIDTH" = "1080" ] && [ "$HEIGHT" = "1920" ] && [ "$FPS" = "60" ] \
	|| { echo "M0 固定参数要求 1080x1920@60，实际 ${WIDTH}x${HEIGHT}@${FPS}" >&2; exit 1; }
[ -n "$FRAMES" ] && [ "$FRAMES" -gt 0 ] || { echo "帧数非法" >&2; exit 1; }

if [ "$VERIFY" = "1" ] && [ "$KEEP_FRAMES" = "1" ]; then
	MIN_FREE_GB=32
fi
AVAIL_KB="$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $4}')"
NEED_KB=$((MIN_FREE_GB * 1024 * 1024))
if [ -z "$AVAIL_KB" ] || [ "$AVAIL_KB" -lt "$NEED_KB" ]; then
	echo "磁盘空间不足：需要 ${MIN_FREE_GB}GB，可用 $(( ${AVAIL_KB:-0} / 1024 / 1024 ))GB（$OUT_DIR）" >&2
	exit 1
fi

render_once() {
	local out_file="$1"
	local frames_dir
	local log_file="$OUT_DIR/.render_log.txt"
	frames_dir="$(mktemp -d "$OUT_DIR/.frames_render.XXXXXX")"
	echo ""
	echo "== 录制：$FRAMES 帧 @ ${FPS}fps -> $frames_dir =="
	local start_ts
	start_ts="$(date +%s)"
	"$GODOT_BIN" --path "$PROJECT_ROOT" \
		--write-movie "$frames_dir/frame.png" \
		--fixed-fps "$FPS" --quit-after "$FRAMES" \
		-- --project "$PROJECT_PATH" --render 2>&1 | tee "$log_file"
	local recorded_frames
	recorded_frames="$(sed -n 's/^\([0-9][0-9]*\) frames at .*/\1/p' "$log_file" | tail -1)"
	local count
	count="$(find "$frames_dir" -maxdepth 1 -name 'frame*.png' | wc -l | tr -d ' ')"
	local first_name last_name last_expected
	first_name="$(find "$frames_dir" -maxdepth 1 -name 'frame*.png' -printf '%f\n' | sort | head -1)"
	last_name="$(find "$frames_dir" -maxdepth 1 -name 'frame*.png' -printf '%f\n' | sort | tail -1)"
	last_expected="$(printf 'frame%08d.png' $((FRAMES - 1)))"
	if [ "$count" != "$FRAMES" ] \
		|| [ "$first_name" != "frame00000000.png" ] || [ "$last_name" != "$last_expected" ]; then
		echo "帧数校验失败：文件数=$count，首帧=${first_name:-?}，末帧=${last_name:-?}（期望 $FRAMES）" >&2
		exit 1
	fi
	# Godot 4.7.2 的退出摘要偶发少报实际帧数（曾见 232 vs 1800 个完整文件）；
	# 帧目录是每次渲染独立的临时目录，因此以文件序列为准，摘要仅告警。
	if [ "$recorded_frames" != "$FRAMES" ]; then
		echo "WARN Godot 摘要帧数=${recorded_frames:-?}，与文件数 $count 不一致；以文件序列为准" >&2
	fi
	# 每次录制后立即扫描本次日志；$log_file 会被下一次录制覆盖，不能延后扫描。
	if grep -q "SCRIPT ERROR" "$log_file"; then
		echo "检测到 SCRIPT ERROR，出片失败（日志: $log_file）" >&2
		grep -n "SCRIPT ERROR" "$log_file" >&2 || true
		exit 1
	fi
	local record_ts=$(( $(date +%s) - start_ts ))
	echo "录制完成：$count 帧，用时 ${record_ts}s"

	echo "== FFmpeg 转码 -> $out_file =="
	ffmpeg -y -v error -framerate "$FPS" -start_number 0 \
		-i "$frames_dir/frame%08d.png" -frames:v "$FRAMES" \
		-c:v libx264 -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -r "$FPS" \
		-an -map_metadata -1 -fflags +bitexact -flags:v +bitexact -threads 1 \
		-movflags +faststart "$out_file"

	local fw fh fr fnb fdur
	fw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$out_file")"
	fh="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$out_file")"
	fr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$out_file")"
	fnb="$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$out_file")"
	fdur="$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$out_file")"
	[ "$fw" = "$WIDTH" ] && [ "$fh" = "$HEIGHT" ] || { echo "ffprobe 分辨率不符：${fw}x${fh}" >&2; exit 1; }
	[ "$fr" = "60/1" ] || { echo "ffprobe 帧率不符：$fr" >&2; exit 1; }
	if [ "$fnb" != "N/A" ] && [ -n "$fnb" ]; then
		[ "$fnb" = "$FRAMES" ] || { echo "ffprobe 帧数不符：$fnb/$FRAMES" >&2; exit 1; }
	fi
	echo "ffprobe 校验通过：${fw}x${fh} ${fr} frames=${fnb} duration=${fdur}s"
	ls -lh "$out_file" | awk '{print "输出大小: "$5}'
	echo "单次出片耗时: $(( $(date +%s) - start_ts ))s（录制 ${record_ts}s）"

	if [ "$KEEP_FRAMES" != "1" ]; then
		rm -rf "$frames_dir"
	else
		echo "已保留帧序列: $frames_dir"
	fi
}

total_start="$(date +%s)"
render_once "$OUT_MP4"

if [ "$VERIFY" = "1" ]; then
	verify_mp4="$OUT_DIR/.verify_$(basename "$OUT_MP4")"
	echo ""
	echo "== 确定性校验：第二次渲染 =="
	render_once "$verify_mp4"
	md5_a="$OUT_DIR/.framemd5_a"
	md5_b="$OUT_DIR/.framemd5_b"
	ffmpeg -v error -i "$OUT_MP4" -map 0:v -f framemd5 "$md5_a"
	ffmpeg -v error -i "$verify_mp4" -map 0:v -f framemd5 "$md5_b"
	if diff -q "$md5_a" "$md5_b" >/dev/null; then
		echo "结果: PASS framemd5 一致"
		verify_ok=1
	else
		echo "结果: FAIL framemd5 不一致" >&2
		verify_ok=0
	fi
	echo "framemd5 sha256: A=$(sha256sum "$md5_a" | cut -d' ' -f1) B=$(sha256sum "$md5_b" | cut -d' ' -f1)"
	rm -f "$verify_mp4" "$md5_a" "$md5_b"
	[ "$verify_ok" = "1" ] || exit 1
fi

echo ""
echo "输出 sha256: $(sha256sum "$OUT_MP4" | cut -d' ' -f1)"
echo "完成：$OUT_MP4（总用时 $(( $(date +%s) - total_start ))s）"
