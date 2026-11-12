#!/usr/bin/env bash
# 编辑器自测：headless 跑一遍 index.html 的全部渲染路径（?selftest=1）。
# 用法：bash 05_editor/selftest.sh   （退出码 0 = PASS）
set -u
cd "$(dirname "$0")"

CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"

if [ -x "$CHROME" ]; then
  BROWSER="$CHROME"
elif [ -x "$EDGE" ]; then
  BROWSER="$EDGE"
else
  echo "[selftest] 找不到 Chrome / Edge，跳过" >&2
  exit 2
fi

URL="file:///$(pwd -W 2>/dev/null || pwd)/index.html?selftest=1"

# 只认结果节点 #selftestResult：页面脚本里也含 "SELFTEST ..." 字面量，不能全文 grep
DUMP="$("$BROWSER" --headless=new --disable-gpu --no-sandbox --virtual-time-budget=4000 \
  --dump-dom "$URL" 2>/dev/null)"
OUT="$(printf '%s' "$DUMP" | grep -o 'id="selftestResult">[^<]*' | sed 's/.*>//' | head -1)"

echo "[selftest] $OUT"
case "$OUT" in
  "SELFTEST PASS") exit 0 ;;
  *) exit 1 ;;
esac
