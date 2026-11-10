#!/usr/bin/env bash
# 自造关卡的自验流水线：生成 → 出片 → 脚本断言，一条命令跑完。
#
#   bash tools/probe.sh            # 生成 + 出片 + 校验
#   bash tools/probe.sh --verify   # 只校验已有帧（跳过生成/出片）
#
# 产物：output/probe/{project.json,probe.take.json,film.mp4,frames/}
# 退出码：0 = 全过；非 0 = 生成/出片/校验有一步失败。
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
PY="${PY:-python}"
MODE="${1:-all}"

if [ "$MODE" != "--verify" ]; then
	echo "[probe] 1/3 生成合成关卡与 take"
	"$GODOT" --headless --path . --script res://tools/make_probe.gd 2>&1 | grep -E "^\[probe\]" || true

	echo "[probe] 2/3 出片（1080x1920@60，双跑 md5 对拍）"
	rm -rf output/probe/frames
	bash tools/render.sh --take output/probe/probe.take.json \
		--project res://output/probe/project.json \
		--keep-frames --out output/probe/film.mp4 2>&1 | grep -E "^\[render\] (ok=|FAIL)" || true
fi

echo "[probe] 3/3 像素断言"
"$PY" tools/verify_probe.py
