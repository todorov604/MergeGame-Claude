#!/usr/bin/env python3
"""合成关卡的自验脚本：量出片像素，证明两条需求真的成立。

    python tools/verify_probe.py [frames_dir]

检查项（全部为**合成关卡**，不依赖操作者录屏）：
  1. 冰扛得住爆炸：1.2s 合并（blast=2 覆盖冰格）之后，冰格仍是"冰"的样子；
  2. 冰到点自己化掉：3s 之后冰格变成棋子（冰的像素基本消失）；
  3. 任务栏回放：拖动段（2.4→3.0s）整排左移约 200px，3.6s 回到原位。

退出码 0 = 全过；1 = 有失败项。数值会打印出来，方便调阈值或改需求。
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except Exception:  # pragma: no cover
    print("[verify] 需要 Pillow")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
FRAMES = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "output/probe/frames"
FPS = 60


def cell_rect(col, row, cols=7, rows=9):
    """§20.5：棋盘容器 (48,466) 983x1263，7x9 等分。"""
    cw, ch = 983.0 / cols, 1263.0 / rows
    return (48 + col * cw, 466 + row * ch, 48 + (col + 1) * cw, 466 + (row + 1) * ch)


def ice_pixels(frame, rect):
    """冰 = 大片浅蓝白；数一下这块区域里"淡蓝"像素。"""
    im = Image.open(FRAMES / ("%05d.png" % frame)).convert("RGB").crop(tuple(int(v) for v in rect))
    px = im.load()
    w, h = im.size
    n = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if b > 200 and b - r > 12 and g > 205:
                n += 1
    return n


def band_left(frame, y=380):
    """订单卡"蓝条"的左边缘：找 y 行上最长的一段卡片蓝（≈121,166,217）。"""
    im = Image.open(FRAMES / ("%05d.png" % frame)).convert("RGB")
    px = im.load()
    best = (-1, -1, 0)
    cur = None
    for x in range(60, 1040):
        r, g, b = px[x, y]
        hit = abs(r - 121) < 26 and abs(g - 166) < 26 and abs(b - 217) < 26
        if hit and cur is None:
            cur = x
        elif not hit and cur is not None:
            if x - cur > best[2]:
                best = (cur, x, x - cur)
            cur = None
    if cur is not None and 1040 - cur > best[2]:
        best = (cur, 1040, 1040 - cur)
    return best[0] if best[2] >= 120 else -1


def main():
    if not FRAMES.is_dir():
        print("[verify] 缺帧目录：%s" % FRAMES)
        return 1
    failures = []

    ice = cell_rect(3, 3)
    before = ice_pixels(int(0.5 * FPS), ice)
    after_merge = ice_pixels(int(1.6 * FPS), ice)
    after_timer = ice_pixels(int(4.0 * FPS), ice)
    print("[verify] 冰格像素  0.5s=%d  1.6s(合并后)=%d  4.0s(3s 到点后)=%d" %
          (before, after_merge, after_timer))

    if before < 40:
        failures.append("0.5s 处看不到冰（基线不对，先确认合成关卡）")
    if after_merge < before * 0.8:
        failures.append("爆炸把冰炸开了：合并后只剩 %.0f%%" % (100.0 * after_merge / max(before, 1)))
    if after_timer > before * 0.2:
        failures.append("3 秒到点后冰没化掉：还剩 %.0f%%" % (100.0 * after_timer / max(before, 1)))

    home = band_left(int(1.5 * FPS))
    dragged = band_left(int(2.9 * FPS))
    released = band_left(int(4.2 * FPS))
    shift = dragged - home
    print("[verify] 任务栏左缘 1.5s=%d  2.9s=%d(位移 %+d)  4.2s=%d" % (home, dragged, shift, released))

    if home < 0 or dragged < 0:
        failures.append("量不到任务栏卡片")
    else:
        if shift > -120:
            failures.append("拖动段位移不够：%+d px（应约 -200）" % shift)
        if abs(released - home) > 8:
            failures.append("松手后没回原位：%d vs %d" % (released, home))

    if failures:
        print("[verify] RESULT FAIL")
        for f in failures:
            print("  - " + f)
        return 1
    print("[verify] RESULT PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
