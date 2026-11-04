# 验收证据（evidence）

`output/` 是构建产物、已被 gitignore；这里放的是**冻结的证据副本**，clone 下来不跑引擎也能直接核对。
所有数字都能用 `03_Game_ds/README.md` 里的一条命令重新生成，`sha256` 用于确认副本与当时产物一致。

> 本轮（M0 交叉审查二轮修复，2026-11-04）重生成成片与 framemd5 证据：N4 裁决「成片必须随主题变化」后，
> `movie_scene` 接入 `ThemeLoader`（palette + metrics），default 主题成片外观随之改变，因此 `render.mp4`
> 与旧证据**逐帧不同**（1800/1800 帧）；视图片的默认渲染路径未变，四张 PNG 与旧值逐字节相同。

| 文件 | 证明什么 | sha256 |
|---|---|---|
| `render.mp4` | 成片规格：1080×1920 / 60fps / **1800 帧** / 30.000s / 单视频流（无音频）；default 主题 palette+metrics 已生效 | `663c484aba61c781e1856cf0e009f5650f6b804681d9f42f66140e15319b979c` |
| `render_manifest.json` | 出片资源清单与**这部片绑定**：`frames=1800`、`out`、`mp4_sha256=663c484a…`、`assets`（仅两个 PRODUCTION 字体）、`blocked=[]` | `ee8f372164233c3a79f199c434d1c43ccdc63d6c3fabe0ad611d97c6ec78ca2a` |
| `render_framemd5.txt` | 成片逐帧 MD5（`ffmpeg -f framemd5` 原始输出，1800 帧）；逐帧列 sha256 = `2a6f55ac5d0be53d6d2098220e80160cabb21536a13c3bbce1e8426bdb83f10f` | `9d7b9030909cc365499885c1c43069bd5e29f0e29e9c6ec9aef13a53c5e11cf6` |
| `theme_default.framemd5` / `theme_pet.framemd5` | 60 帧 default vs pet_shop 的逐帧 MD5 列表；列表 md5 = `fee247444ba2dd3f26ad7cdcea74fc69` / `633b46b48955d18e8f3acb2295704b88`，证明成片随主题变化 | `228a63d685f018f631834e248e5d522f4337265c42f3c1401a361aa9d9ed9b83` / `4d9787311e72ce5259b36a0db44bd42a94b9001bea91cae677ca3a55295ff3c7` |
| `board_1080x1920.png` | 静态棋盘：7×9、6 实体、四种障碍（lock/web/bubble/ice）、**黄框选中 + 放大/靠近**、完成绿块 | `c190a3c38c015dda81406a4f4a63d391ff9447551a0a1ded6b17e6390111a5d7` |
| `game_1080x1920.png` | 主游戏页 t=6.2s：HUD(8 字段) / 订单卡完成绿药丸 / 落点与消耗后的棋盘 | `2d8ae7d1242888a2725441c9c38fe041ac2d2d2831092563abb5f9a1fcdddcdc` |
| `orders_panel.png` | 订单卡特写（角色头像 + mission 计数 + 奖励 + DONE） | `c30dd08d843cea6e46e2d83540eb80f6ffa0632294d598407f41af9d486b8eef` |
| `game_theme_pet_shop.png` | 同一帧换主题：`--theme=themes/pet_shop`，**零代码改动** | `be574ed0a51237a0e26aa40393b9f335cf5ad53ea163c0ac1f1a71aa51e886fa` |
| `accept.log` | `bash tools/accept.sh` 的真实输出：**9 步**、1134 checks、`ALL CHECKS PASS` | `14b1072e79868dc5ea8f5094934a9311b86a0e5afeb35fe496203e37660950c5` |

## 新旧 sha256 对照

旧值 = `HEAD 4a9f20f` 的 `docs/evidence/` 内容；新值 = 本轮重生成。

| 文件 | 旧 sha256 | 新 sha256 | 说明 |
|---|---|---|---|
| `render.mp4` | `314419d3e55662040f998ed4f043fd7037ddff4b5b2dc6426c0cc271c11fa648` | `663c484aba61c781e1856cf0e009f5650f6b804681d9f42f66140e15319b979c` | 成片外观随主题（N4）；1800/1800 帧不同 |
| `render_manifest.json` | `f617b77cdc230940056af7e842fb3f2eadf6eac1e34708942db1e347ab92ac84` | `ee8f372164233c3a79f199c434d1c43ccdc63d6c3fabe0ad611d97c6ec78ca2a` | `mp4_sha256` 随成片更新 |
| `accept.log` | `3792079acf21e8ee20dd3539e78e01721dea9f339f16c0af741b2d75c589ce31` | `14b1072e79868dc5ea8f5094934a9311b86a0e5afeb35fe496203e37660950c5` | 9 步；旧 README 曾误记 `a88b4638…` |
| `board_1080x1920.png` | `c190a3c3…` | `c190a3c3…` | 不变（toast 未触发即不画） |
| `game_1080x1920.png` | `2d8ae7d1…` | `2d8ae7d1…` | 不变 |
| `orders_panel.png` | `c30dd08d…` | `c30dd08d…` | 不变 |
| `game_theme_pet_shop.png` | `be574ed0…` | `be574ed0…` | 不变 |
| `render_framemd5.txt` / `theme_*.framemd5` | —（新增） | 见上表 | 新增逐帧 framemd5 证据 |

成片确定性（同一 `sample_project.json`，`render.sh --frames 1800 --determinism`）：

```
[md5] same=YES frames=1800 digest=f85e4e51d27f15d9d3761ab645e35c431cc8cde20c5e61924b8dc3d5d61e7e19
[render] ok=1 frames=1800 fps=60 size=1080x1920 out=output/render_det.mp4 theme=project.theme mp4_bytes=891823
```

该次双跑产出的 MP4 与 `docs/evidence/render.mp4` sha256 完全相同（`663c484a…`），即证据片就是确定性产物。

## 怎么复核

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"
cd 03_Game_ds
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,nb_read_frames,duration \
  -of default=nw=1 docs/evidence/render.mp4      # 1080/1920/60/1800/30.000
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 docs/evidence/render.mp4   # 只有 video
ffmpeg -v error -i docs/evidence/render.mp4 -f framemd5 - | grep -v '^#' | awk '{print $NF}' \
  | sha256sum                                    # 2a6f55ac…
bash tools/accept.sh                              # 重新生成全部证据（约 6 分钟）
```

`accept.log` 里的关键行：

```
[tests] TOTAL checks=1134 failures=0   RESULT PASS
[PASS] all broken fixtures rejected with the expected code      (25/25)
[PASS] relocated copy ... passes the same suite
[PASS] two takes are frame-identical (framemd5)
[PASS] compared range actually animates (220 unique frames)
[PASS] manifest describes this film (frames=240, ok=true)
[PASS] REFERENCE_ONLY project is refused before recording
[PASS] payload_empty project is refused / f1_a project is refused / reject_sim project is refused
[PASS] the film follows the theme (per-frame digests differ)
ALL CHECKS PASS
```
