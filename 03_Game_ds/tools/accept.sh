#!/usr/bin/env bash
# M0 总验收：一条命令跑完 §7 全部硬指标。
#
#   bash tools/accept.sh
#
# 1) headless 全量测试（tests/t_*.gd 自动发现）+ 引擎级错误门禁
# 2) CLI 校验样例工程（strict）+ 打印事件顺序
# 3) 全部反例夹具逐条命中预期错误码
# 4) 可搬移：整目录复制到临时目录再跑全量测试
# 5) 静态棋盘截图（真窗口）+ PNG 尺寸断言
# 6) 主游戏页截图（HUD + 订单 + 棋盘，t=6.2）
# 7) 出片确定性：两次 120 帧出片 + framemd5 一致
# 8) 出片门禁：校验放行但 sim 拒绝 / payload 非法的工程必须拒绝出片（N2）
# 9) 成片随主题变化：default 与 pet_shop 各 60 帧，framemd5 与 sha256 都必须不同（N4）
#
# 任何一步失败 -> 非 0 退出。输出汇总写入 output/accept.log。

set -uo pipefail

GODOT="${GODOT:-/e/Program Files/Godot/Godot_v4.7.2.exe}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/output/accept.log"
mkdir -p "$ROOT/output"
: > "$LOG"

FAILS=0
step() { printf '\n===== %s =====\n' "$1" | tee -a "$LOG"; }
pass() { printf '[PASS] %s\n' "$1" | tee -a "$LOG"; }
fail() { printf '[FAIL] %s\n' "$1" | tee -a "$LOG"; FAILS=$((FAILS + 1)); }

png_size() { # $1=path -> prints WxH, exits non-zero on mismatch
python - "$1" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read(33)
w, h = struct.unpack(">II", data[16:24])
print("%dx%d" % (w, h))
sys.exit(0 if (w, h) == (1080, 1920) else 1)
PY
}

cd "$ROOT" || exit 2

# ---------------------------------------------------------------- 1) 全量测试
step "1/9 headless test suite"
timeout 240 "$GODOT" --headless --path . --script res://tests/run_tests.gd > "$ROOT/output/tests.log" 2>&1
TESTS_RC=$?
tail -25 "$ROOT/output/tests.log" | tee -a "$LOG"
if [ $TESTS_RC -eq 0 ] && grep -q "RESULT PASS" "$ROOT/output/tests.log"; then
  pass "test suite (rc=0)"
else
  fail "test suite (rc=$TESTS_RC)"
fi
# a suite can abort mid-run and still look green by assertion count; engine-level
# errors are the reliable signal, so they gate acceptance too
if grep -q "SCRIPT ERROR\|Failed to load script\|Parse Error" "$ROOT/output/tests.log"; then
  grep -n "SCRIPT ERROR\|Failed to load script\|Parse Error" "$ROOT/output/tests.log" | head -5 | tee -a "$LOG"
  fail "engine reported script errors during the test run"
else
  pass "no engine-level script errors"
fi

# ------------------------------------------------------- 2) 样例工程 strict
step "2/9 validate sample (strict, no placeholders)"
timeout 120 "$GODOT" --headless --path . --script res://src/tools/cli.gd -- \
  validate --project res://data/sample_project.json --strict --dump-order \
  > "$ROOT/output/validate_sample.log" 2>&1
VAL_RC=$?
sed -n '1,12p' "$ROOT/output/validate_sample.log" | tee -a "$LOG"
if [ $VAL_RC -eq 0 ] && grep -q "ok=true errors=0 warnings=0" "$ROOT/output/validate_sample.log"; then
  pass "sample validates clean in strict mode"
else
  fail "sample validation (rc=$VAL_RC)"
fi
if grep -q "end=30.00s" "$ROOT/output/validate_sample.log"; then
  pass "timeline ends at 30.00s"
else
  fail "timeline end is not 30.00s"
fi

# --------------------------------------------------------- 3) 反例逐条命中
step "3/9 broken fixtures hit their own rule codes"
BROKEN_FAIL=0
for f in tests/fixtures/broken/*.json; do
  name="$(basename "$f" .json)"
  code="$(python - "$ROOT/tests/fixtures/cases.json" "$name" <<'PY'
import json, sys
for c in json.load(open(sys.argv[1], encoding="utf-8"))["cases"]:
    if c["file"].endswith("/" + sys.argv[2] + ".json"):
        print(c["code"]); break
PY
)"
  flags=""
  python - "$ROOT/tests/fixtures/cases.json" "$name" <<'PY' > /dev/null 2>&1 && flags="$flags --allow-placeholders"
import json, sys
cases = json.load(open(sys.argv[1], encoding="utf-8"))["cases"]
sys.exit(0 if any(c["file"].endswith("/"+sys.argv[2]+".json") and c["allow_placeholders"] for c in cases) else 1)
PY
  python - "$ROOT/tests/fixtures/cases.json" "$name" <<'PY' > /dev/null 2>&1 && flags="$flags --strict"
import json, sys
cases = json.load(open(sys.argv[1], encoding="utf-8"))["cases"]
sys.exit(0 if any(c["file"].endswith("/"+sys.argv[2]+".json") and c["strict"] for c in cases) else 1)
PY
  timeout 120 "$GODOT" --headless --path . --script res://src/tools/cli.gd -- \
    validate --project "res://$f" $flags --out "" > "$ROOT/output/fixture_$name.log" 2>&1
  if grep -q "$code" "$ROOT/output/fixture_$name.log"; then
    printf '  ok   %-30s -> %s\n' "$name" "$code" | tee -a "$LOG"
  else
    printf '  MISS %-30s -> %s\n' "$name" "$code" | tee -a "$LOG"
    BROKEN_FAIL=$((BROKEN_FAIL + 1))
  fi
done
if [ $BROKEN_FAIL -eq 0 ]; then pass "all broken fixtures rejected with the expected code"; else fail "$BROKEN_FAIL fixture(s) did not produce their code"; fi

# -------------------------------------------------------------- 4) 可搬移
step "4/9 relocate the whole project and re-run the suite"
TMP="$(mktemp -d)"
tar -C "$(dirname "$ROOT")" -cf - \
  --exclude='.godot' --exclude='output' "$(basename "$ROOT")" | tar -C "$TMP" -xf -
RELOC_RC=1
(
  cd "$TMP/$(basename "$ROOT")" || exit 1
  timeout 240 "$GODOT" --headless --path . --script res://tests/run_tests.gd > "$TMP/relocated.log" 2>&1
) && RELOC_RC=0
tail -6 "$TMP/relocated.log" 2>/dev/null | tee -a "$LOG"
if [ $RELOC_RC -eq 0 ] && grep -q "RESULT PASS" "$TMP/relocated.log" && ! grep -q "SCRIPT ERROR" "$TMP/relocated.log"; then
  pass "relocated copy at $TMP passes the same suite"
else
  fail "relocated copy failed (see $TMP/relocated.log)"
fi
rm -rf "$TMP"

# --------------------------------------------------------------- 5) 棋盘截图
step "5/9 static board screenshot (real window)"
if [ -f "$ROOT/tools/shot_board.gd" ]; then
  rm -f "$ROOT/output/board_1080x1920.png"
  timeout 180 "$GODOT" --path . --script res://tools/shot_board.gd > "$ROOT/output/shot.log" 2>&1
  tail -4 "$ROOT/output/shot.log" | tee -a "$LOG"
  if [ -f "$ROOT/output/board_1080x1920.png" ] && png_size "$ROOT/output/board_1080x1920.png" > /dev/null; then
    pass "board screenshot is 1080x1920"
  else
    fail "board screenshot missing or wrong size"
  fi
else
  fail "tools/shot_board.gd missing"
fi

# ------------------------------------------------------------ 6) 游戏页截图
step "6/9 game screen screenshot (HUD + orders + board, t=6.2)"
if [ -f "$ROOT/tools/shot_game_screen.gd" ]; then
  rm -f "$ROOT/output/game_1080x1920.png"
  timeout 240 "$GODOT" --path . --script res://tools/shot_game_screen.gd -- --t=6.2 > "$ROOT/output/shot_game.log" 2>&1
  grep "^\[shot\]\|^\[game\] LEVEL\|^\[game\] hud" "$ROOT/output/shot_game.log" | head -8 | tee -a "$LOG"
  if [ -f "$ROOT/output/game_1080x1920.png" ] && png_size "$ROOT/output/game_1080x1920.png" > /dev/null; then
    pass "game screen screenshot is 1080x1920"
  else
    fail "game screen screenshot missing or wrong size"
  fi
  if grep -q "\[shot\] panel .*done=1" "$ROOT/output/shot_game.log"; then
    pass "order card reaches its done state at t=6.2"
  else
    fail "order card done state not observed"
  fi
else
  fail "tools/shot_game_screen.gd missing"
fi

# ---------------------------------------------------------- 7) 出片确定性
step "7/9 render determinism (240 frames = 4s, two takes, framemd5)"
if [ -f "$ROOT/tools/render.sh" ]; then
  RTMP="$(mktemp -d)"
  RENDER_TMP_DIR="$RTMP" timeout 600 bash tools/render.sh --frames 240 --determinism \
    --out "$ROOT/output/accept_render.mp4" > "$ROOT/output/render_accept.log" 2>&1
  RENDER_RC=$?
  grep "^\[md5\]\|^\[render\] ok=" "$ROOT/output/render_accept.log" | tail -4 | tee -a "$LOG"
  if [ $RENDER_RC -eq 0 ] && grep -q "same=YES" "$ROOT/output/render_accept.log"; then
    pass "two takes are frame-identical (framemd5)"
  else
    fail "render determinism (rc=$RENDER_RC)"
  fi
  # identical frames could also mean "nothing ever moved" - require real variety
  UNIQ=$(ffmpeg -v error -i "$ROOT/output/accept_render.mp4" -f framemd5 - 2>/dev/null \
    | grep -v '^#' | awk '{print $NF}' | sort -u | wc -l | tr -d ' ')
  if [ "${UNIQ:-0}" -gt 1 ]; then
    pass "compared range actually animates ($UNIQ unique frames)"
  else
    fail "compared range is static ($UNIQ unique frame(s)); determinism is not exercised"
  fi
  MANIFEST="$ROOT/output/accept_render.manifest.json"
  if [ -f "$MANIFEST" ] && grep -q '"ok": true' "$MANIFEST" && grep -q '"frames": 240' "$MANIFEST"; then
    pass "manifest describes this film (frames=240, ok=true)"
  else
    fail "render manifest missing or not tied to this film"
  fi
  if timeout 180 bash tools/render.sh --frames 30 --out "$ROOT/output/refuse.mp4" \
      --project res://tests/fixtures/broken/bad_ref_only.json > "$ROOT/output/render_refuse.log" 2>&1; then
    fail "REFERENCE_ONLY project was allowed to render"
  else
    pass "REFERENCE_ONLY project is refused before recording"
  fi
  rm -rf "$RTMP"
else
  fail "tools/render.sh missing"
fi

# ------------------------------------------------- 8) 出片门禁（N2）
# "校验放行" is not "可以出片". Three probes:
#   payload_empty  e01.payload={}      -> validator payload contract (rules_timeline)
#   f1_a           generator removed, order unreachable -> validator order reachability
#   reject_sim     payload shape legal, sim says SIM_SLOT_OOB -> movie_scene gate
# The first two are generated from the real sample so they cannot rot; the last one
# is the proof that movie_scene/_finish itself refuses a refused take.
step "8/9 refuse films the sim rejects (empty payload / unreachable order / out-of-board merge)"
AT="$ROOT/output/accept_tmp"
rm -rf "$AT"
mkdir -p "$AT"
if python - "$ROOT/data/sample_project.json" "$AT" <<'PYGEN'
import copy, json, sys
src, out = sys.argv[1], sys.argv[2]
base = json.load(open(src, encoding="utf-8"))

payload_empty = copy.deepcopy(base)
for e in payload_empty["timeline"]:
    if e["id"] == "e01":
        e["payload"] = {}
json.dump(payload_empty, open(out + "/payload_empty.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

f1_a = copy.deepcopy(base)
level = f1_a["levels"][0]
level["board"]["slots"] = [s for s in level["board"]["slots"] if s.get("entity") != "CleanBox_C"]
for order in level["orders"]:
    if order.get("id") == "order_1":
        order["mission"] = [{"entity": "CleanSet_Cb", "level": 2}]
json.dump(f1_a, open(out + "/f1_a.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("[accept] generated payload_empty.json f1_a.json in " + out)
PYGEN
then
  pass "generated the two N2 probe projects"
else
  fail "cannot generate the N2 probe projects"
fi

for probe in payload_empty f1_a; do
  if RENDER_TMP_DIR="$AT/tmp" timeout 180 bash tools/render.sh --frames 30 \
      --out "$AT/$probe.mp4" --project "$AT/$probe.json" > "$ROOT/output/render_$probe.log" 2>&1; then
    fail "$probe project was allowed to render"
  else
    pass "$probe project is refused"
  fi
  grep -E "^\[render\] FAIL|^\[render\] stage=validate|ok=true errors=" \
    "$ROOT/output/render_$probe.log" | tail -2 | sed 's/^/  /' | tee -a "$LOG"
done

if RENDER_TMP_DIR="$AT/tmp" timeout 180 bash tools/render.sh --frames 30 \
    --out "$AT/reject_sim.mp4" --project res://tests/fixtures/render/reject_sim.json \
    > "$ROOT/output/render_reject_sim.log" 2>&1; then
  fail "reject_sim project was allowed to render (movie gate ineffective)"
else
  pass "reject_sim project is refused"
fi
if grep -q "ok=true errors=" "$ROOT/output/render_reject_sim.log"; then
  pass "reject_sim passes validation, so only the take gate can stop it"
else
  fail "reject_sim did not reach the take gate (validation refused it first)"
fi
if grep -qE "movie scene reported a failure|rejected=[1-9]|SIM_SLOT_OOB" \
    "$ROOT/output/render_reject_sim.log"; then
  pass "reject_sim was stopped by the movie/sim rejection gate"
  grep -E "rejected=|SIM_SLOT_OOB|refused-line|movie scene reported" \
    "$ROOT/output/render_reject_sim.log" | head -4 | sed 's/^/  /' | tee -a "$LOG"
else
  fail "reject_sim log carries no rejection evidence"
fi

# ------------------------------------------------- 9) 成片随主题（N4）
# A theme that only re-skins the preview is not a theme. Two 60-frame takes of the
# same timeline, one per theme, must differ per frame (framemd5) and per file.
step "9/9 theme changes the film (default vs pet_shop, 60 frames each)"
frame_digest() { # frame_digest <mp4> <out-list> -> prints md5 of the framemd5 list
  ffmpeg -v error -i "$1" -f framemd5 - 2>/dev/null \
    | grep -v '^#' | awk '{print $NF}' > "$2"
  md5sum "$2" | awk '{print $1}'
}
THEME_DEFAULT_MP4="$ROOT/output/theme_default.mp4"
THEME_PET_MP4="$ROOT/output/theme_pet.mp4"
THEME_DEFAULT_TXT="$ROOT/output/theme_default.framemd5"
THEME_PET_TXT="$ROOT/output/theme_pet.framemd5"

if timeout 300 bash tools/render.sh --frames 60 --out "$THEME_DEFAULT_MP4" \
    > "$ROOT/output/render_theme_default.log" 2>&1; then
  pass "default theme film rendered"
else
  fail "default theme film failed"
  tail -5 "$ROOT/output/render_theme_default.log" | tee -a "$LOG"
fi
if timeout 300 bash tools/render.sh --frames 60 --theme themes/pet_shop \
    --out "$THEME_PET_MP4" > "$ROOT/output/render_theme_pet.log" 2>&1; then
  pass "pet_shop theme film rendered"
else
  fail "pet_shop theme film failed"
  tail -5 "$ROOT/output/render_theme_pet.log" | tee -a "$LOG"
fi
if grep -q "\[movie\] theme=themes/pet_shop ok=true" "$ROOT/output/render_theme_pet.log"; then
  pass "the take reports theme=themes/pet_shop"
else
  fail "the take did not report the pet_shop theme"
fi

D_DEFAULT="$(frame_digest "$THEME_DEFAULT_MP4" "$THEME_DEFAULT_TXT")"
D_PET="$(frame_digest "$THEME_PET_MP4" "$THEME_PET_TXT")"
S_DEFAULT="$(sha256sum "$THEME_DEFAULT_MP4" | awk '{print $1}')"
S_PET="$(sha256sum "$THEME_PET_MP4" | awk '{print $1}')"
printf '  framemd5 default=%s pet=%s\n' "${D_DEFAULT:0:12}" "${D_PET:0:12}" | tee -a "$LOG"
printf '  sha256  default=%s pet=%s\n' "${S_DEFAULT:0:12}" "${S_PET:0:12}" | tee -a "$LOG"
if [ "$D_DEFAULT" != "$D_PET" ] && ! cmp -s "$THEME_DEFAULT_TXT" "$THEME_PET_TXT"; then
  pass "the film follows the theme (per-frame digests differ)"
else
  fail "both themes produced identical frames (theme does not reach the film)"
fi
if [ "$S_DEFAULT" != "$S_PET" ]; then
  pass "the two theme films are different files"
else
  fail "the two theme films are byte-identical"
fi

# ----------------------------------------------------------------- 汇总
printf '\n================ ACCEPT SUMMARY ================\n' | tee -a "$LOG"
if [ $FAILS -eq 0 ]; then
  printf 'ALL CHECKS PASS\n' | tee -a "$LOG"
  exit 0
else
  printf 'FAILURES: %d (see output/accept.log)\n' "$FAILS" | tee -a "$LOG"
  exit 1
fi
