"""把每个 case 的出片按"每次点击后"抽帧拼成一张对比图（棋盘区域）。"""
from pathlib import Path
import subprocess
import json
from PIL import Image

FF = "ffmpeg"
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'output/render'

CASES = [
    ("case1_random", [1.05, 1.75, 2.45, 3.15, 3.85, 4.55]),
    ("case2_sequence", [1.05, 1.75, 2.45, 3.15]),
    ("case3_per_cell", [1.05, 1.75]),
    ("case4_stockpile_chip", [1.55, 3.0]),
    ("case5_stockpile_generator", [2.2]),
    ("case6a_level1_random", [1.05, 2.45, 3.15]),
    ("case6b_level2_sequence", [1.75, 3.0]),
]

BOARD = (48, 466, 1031, 1729)

for name, times in CASES:
    mp4 = OUT / f"gen_{name}.mp4"
    if not mp4.exists():
        print(f"[sheet] missing {mp4}")
        continue
    frames = []
    tmpdir = OUT / f"f_{name}"
    tmpdir.mkdir(exist_ok=True)
    for i, t in enumerate(times):
        out = tmpdir / f"{i:02d}.png"
        subprocess.run([FF, "-v", "error", "-ss", f"{t:.3f}", "-i", str(mp4),
                        "-frames:v", "1", "-y", str(out)], check=True)
        frames.append(out)
    ims = [Image.open(f).crop(BOARD).resize((240, 421)) for f in frames]
    sheet = Image.new('RGB', (240 * len(ims) + 8 * (len(ims) - 1), 421), (18, 26, 40))
    for i, im in enumerate(ims):
        sheet.paste(im, (i * 248, 0))
    dst = OUT / f"sheet_{name}.png"
    sheet.save(dst)
    print(f"[sheet] {dst.name} frames={len(ims)}")
