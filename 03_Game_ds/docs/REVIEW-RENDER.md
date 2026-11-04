# 出片流水线 / 资源守卫 独立复审与修复记录

> 复审：独立 agent（只读 + 临时目录跑命令）　修复：Lead（逐条复核后实施）
> 结论：**7 项属实，全部已修**；确定性声明本身成立（两次独立全片 1800 帧 framemd5 相同）。

## 1. 复审发现的问题

| # | 严重度 | 问题 | 为什么算 bug |
|---|---|---|---|
| R1 | high | `render_manifest.json` 与实际成片脱钩 | 固定写 `output/render_manifest.json`，任何一次短片（含 `accept.sh` 的 120 帧）都会覆盖它；失败时还保留旧的 `ok=true`。§4.3 的导出日志无法证明所交付影片的资源 |
| R2 | high | 出片前不跑 validator | `bad_ref_only.json`（REFERENCE_ONLY）与未开闸的 PLACEHOLDER 主题都能出片（rc=0），而 `cli.gd validate` 判它们非法。违反 §7「usage 违规在出片前阻断」 |
| R3 | medium | guard 拒绝后仍写出 1 帧 | `movie_scene` 的 blocked 分支没置 `_finished`，`_process` 又跑了一帧；`render.sh` 失败时不清理 AVI，被拒字体已经进入成片首帧 |
| R4 | medium | 自动确定性门禁只比前 2 秒 | `accept.sh` 用 120 帧（最后一帧 `t=1.983`），而首个事件在 `at=2.0`：整段对比的是纯静态画面，`same=YES` 证明不了事件/动画确定性 |
| R5 | medium | 结尾零时长事件永不触发 | `frame_count=ceil(end*60)`，最后一帧 `t=(n-1)/60`；`at=end` 且 `duration=0` 的事件没有帧可落，最终状态静默缺一条命令 |
| R6 | low | 固定中间文件名 + 共享 TMP_DIR | 启动即 `rm -f take_a.avi/take_b.avi`，会删掉同目录他人的产物；并发出片互相覆盖；`--keep-frames` 产物被下一次启动删除 |
| R7 | low | 成片含未声明的静音 AAC 轨 | Movie Maker 的 AVI 带 PCM 轨，FFmpeg 未加 `-an`；产物多一条依赖音频驱动的音轨，与 §1「不做音频」和 PERF-BASELINE 的规格不一致 |

复审同时**确认无问题**：`movie_scene` 无 wall clock / `delta` 累积 / 随机 / Tween；事件按 `cursor` 单调前进不重复触发；manifest 在首帧前构建（不是帧写完后才校验）；`framemd5` 对比的是两次独立录制且帧数不一致时 `same=NO`；成片分辨率/帧率/帧数/时长与文档一致（两次独立全片 digest 相同，且当前代码可精确复现交付物）。

## 2. 修法

| # | 修法 | 位置 |
|---|---|---|
| R1 | manifest 路径由 `OUT` 派生（`${OUT%.*}.manifest.json`）；写入 `out/frames/fps/mp4_sha256`；启动时删掉同名旧 manifest 与 canonical 旧件；只有 `OUT=output/render.mp4` 才额外发布 `output/render_manifest.json` | `tools/render.sh` |
| R2 | 录制前先跑 `cli.gd validate --strict [--allow-placeholders]`，`ok=false` 直接失败退出（不产生任何帧） | `tools/render.sh` |
| R3 | blocked 分支先 `_finished = true` 再 `quit(3)`；脚本加 `trap cleanup_run EXIT`，失败也清中间件 | `src/render/movie_scene.gd` / `render.sh` |
| R4 | 验收改用 **240 帧（4s）**，覆盖 tap@2.0 / text@2.2 / merge@3.2 / select@3.8；并断言**唯一帧数 > 1**（本次实测 157 个唯一帧） | `tools/accept.sh` |
| R5 | 最后一帧在绘制前 `_advance_to(_end_time)`，把落在 `end` 上的事件补发 | `src/render/movie_scene.gd` |
| R6 | 每次运行 `mktemp -d "$TMP_ROOT/run.XXXXXXXX"`，退出 trap 只删本 run | `tools/render.sh` |
| R7 | FFmpeg 加 `-an`（`render_plan.ffmpeg_args` 与脚本同步），转码后断言音轨数 = 0 | `src/render/render_plan.gd` / `render.sh` |

## 3. 验证证据

```
# R2 拦截（改用坏工程）
$ bash tools/render.sh --frames 30 --out output/refuse.mp4 --project res://tests/fixtures/broken/bad_ref_only.json
[render] stage=validate project=res://tests/fixtures/broken/bad_ref_only.json strict=1 allow_placeholders=0
  E ASSET_REFERENCE_ONLY  entities.A.visual.icon  REFERENCE_ONLY resource "chip_clean_lv01" ...
[render] FAIL project failed validation; refusing to render      → rc=1，无 MP4

# R4/R1/R7（240 帧双次）
[md5] same=YES frames=240 digest=d3b357dbf386d57332e332320179a15d3220e84ea69c1f8dadf8b38af2d2ebfd
[render] ok=1 frames=240 ... out=output/smoke.mp4
$ ffmpeg -i output/smoke.mp4 -f framemd5 - | sort -u | wc -l   → 157 个唯一帧
$ ffprobe -show_entries stream=codec_type -of csv=p=0 output/smoke.mp4 → 只有 0,video
$ cat output/smoke.manifest.json → frames=240, out, mp4_sha256, ok=true
```

## 4. 未改的两点

1. **`ffprobe -count_frames` 全解码** 约占一轮的 55s，是录制之外的最大开销；改成读容器 `nb_frames` 可把两遍流水线压到 ~180s，但会失去"实际解码帧数"这条硬证据。保留现状。
2. **跨机确定性**（其它 GPU/驱动/FFmpeg/x264 构建）未验证；本次只在 RTX 4060 Ti + Godot 4.7.2 + FFmpeg 9.0 上确认。
