# 出片性能基线（M0 §6 / §9-9）

> 实测日期：2026-11-04　工程：`03_Game_ds`　样例：`data/sample_project.json`（30.0 s / 21 事件 / 2 关）
> 结论：**1800 帧全片 = 234 s（3 分 54 秒）**，满足 M0「5 分钟内」目标；两次独立出片 framemd5 完全一致（`10b138d4…`）。
> 成片为**单视频流**（M0 不做音频，已用 `-an` 去掉 Movie Maker 的静音轨）；manifest 与影片绑定（`frames/out/mp4_sha256`）。

---

## 1. 机器

| 项 | 值 |
|---|---|
| CPU | 12th Gen Intel(R) Core(TM) i7-12700（12 核 20 线程） |
| 内存 | 63.8 GB |
| GPU | NVIDIA GeForce RTX 4060 Ti（Vulkan 可用，另有 OrayIddDriver 虚拟显示器） |
| OS | Windows 11 专业版 |
| Godot | 4.7.2.stable.official.ed1daf0bf（真窗口 + Vulkan，**未使用 `--headless`**） |
| FFmpeg / ffprobe | 9.0-full_build-www.gyan.dev |

## 2. 分段实测

| 阶段 | 命令要点 | 耗时 | 折算速率 |
|---|---|---|---|
| Godot Movie Maker 录制 | `--write-movie x.avi --fixed-fps 60 --quit-after 1800` | 13.42 s / 300 帧 → **≈ 80.5 s / 1800 帧** | 22.4 帧/秒写出 |
| FFmpeg 转码 | MJPEG AVI → H.264（1080×1920 / 60 / crf 18 / yuv420p / +faststart） | **5.42 s / 1800 帧** | 332 帧/秒 |
| framemd5 对比 | 两遍各 1800 帧解码 + 逐帧哈希 | **13.58 s** | — |
| ffprobe 断言 | `-count_frames` 全解码（2×AVI + 1×MP4） | ≈ 18 s / 次（推算，见 §5） | — |
| **整条流水线（两遍 + 转码 + 校验）** | `bash tools/render.sh --determinism` | **234 s** | — |
| **整条流水线（单遍 1800 帧 + 转码 + 校验）** | `bash tools/render.sh` | **102 s** | — |
| 单遍整条流水线（短样 240 帧 = 4s） | `bash tools/render.sh --frames 240` | 31 s | — |

## 3. 产物规格（ffprobe 实测）

```
# output/render.mp4
codec_name=h264          width=1080      height=1920
r_frame_rate=60/1        avg_frame_rate=60/1
nb_read_frames=1800      duration=30.000000
bit_rate=233236          size=897016 B
```

```
# 中间件 output/render/full2/take_a.avi
codec_name=mjpeg         width=1080      height=1920
r_frame_rate=60/1        nb_read_frames=1800
size=168,549,024 B       (≈ 93.6 KB/帧)
```

## 4. 确定性证据

| 项 | digest |
|---|---|
| 全片 take A vs take B（同参数两次独立录制） | `10b138d47d7d57f209f14298c683fcff629263d0cb5767cf78d53d2fcdd24071` **一致** |
| 短片 120 帧，两次**独立进程**（run1 / run2） | `5eeae98186b6e4da0a4b9b0da8f547c0d28d9c5b7a78bd5a3c9bb105d984d297` **一致** |
| 第三次全片取（改完 `--probe-ref` 之后重跑） vs 已交付 take A | `10b138d47d7d57f209f14298c683fcff629263d0cb5767cf78d53d2fcdd24071` **一致（3 次全片逐帧相同）** |
| 修正订单卡显示（`1/1`）之前的旧全片 | `30e3e35eebfc19974b8960ec70aa3dc92cfc9fc381ae85e6d29b4ed892568ac8`（历史值，产物已重出） |

为什么稳：`movie_scene.gd` 只有一条时钟 `t = (frame - 1) / 60`，`_process` 每帧把 `at <= t` 的事件一次性喂给共享 `event_evaluator`，所有动画位置由帧号或事件时间算出；无 `Time.get_ticks_*()`、无 Tween、无 `delta` 累积、无 wall clock。

## 5. 成本结构与可选优化

- 录制 22 帧/秒是纯渲染写盘上限（1080×1920 逐帧 MJPEG ~94 KB，写盘 ≈ 2 MB/s，**不是** I/O 瓶颈，主要是 CanvasItem 绘制 + 编码）。
- 两遍出片 = 2 × 80.5 s；若只信一次出片，`--determinism` 可关（默认帧数 > 600 时关闭）。
- `ffprobe -count_frames` 会全解码，三份媒体合计约 55 s，是除录制外最大开销。可改为读容器 `nb_frames`（MJPEG AVI 有该字段），预计整条流水线降到 ≈ 180 s；本版保留 `-count_frames`，因为它对「实际帧数」是硬证据。
- 磁盘：一次全片 = 2 × 168 MB AVI（`--keep-frames`）+ 0.9 MB MP4。默认清理中间件；M0 §6 预留的「1800 张 PNG ≈ 15 GB」路径本版不采用。

## 6. 目标判定

| M0 §7 判据 | 实测 | 判定 |
|---|---|---|
| 1080×1920 / 60 fps / 1800 帧 | 1080×1920 / 60/1 / 1800 | 通过 |
| 两次出片 framemd5 一致 | 1800 帧 digest 相同 | 通过 |
| 全流程 ≤ 5 分钟 | 234 s | 通过 |
| 中间产物不落 PNG 序列 | 直接 AVI | 通过 |

## 7. 可搬移性

- 流水线只认 `res://` 与相对路径；`GODOT_BIN` / `FFMPEG_BIN` / `FFPROBE_BIN` / `RENDER_TMP_DIR` 全部可用环境变量覆盖。
- 字体用 `FontFile.load_dynamic_font()`、贴图用 `Image.load()` 直读磁盘，**不依赖 `.godot/` 导入缓存**：工程整体复制到新目录后首次跑 `bash tools/render.sh` 即可出片。
