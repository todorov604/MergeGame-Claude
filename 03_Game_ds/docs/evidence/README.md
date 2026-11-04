# 验收证据（evidence）

`output/` 是构建产物、已被 gitignore；这里放的是**冻结的证据副本**，clone 下来不跑引擎也能直接核对。
所有数字都能用 `03_Game_ds/README.md` 里的一条命令重新生成，`sha256` 用于确认副本与当时产物一致。

| 文件 | 证明什么 | sha256 |
|---|---|---|
| `render.mp4` | 成片规格：1080×1920 / 60fps / **1800 帧** / 30.000s / 单视频流（无音频） | `314419d3e55662040f998ed4f043fd7037ddff4b5b2dc6426c0cc271c11fa648` |
| `render_manifest.json` | 出片资源清单与**这部片绑定**：`frames=1800`、`out`、`mp4_sha256`、`assets`（仅两个 PRODUCTION 字体）、`blocked=[]` | `f617b77cdc230940056af7e842fb3f2eadf6eac1e34708942db1e347ab92ac84` |
| `board_1080x1920.png` | 静态棋盘：7×9、6 实体、四种障碍（lock/web/bubble/ice）、**黄框选中 + 放大/靠近**、完成绿块 | `c190a3c38c015dda81406a4f4a63d391ff9447551a0a1ded6b17e6390111a5d7` |
| `game_1080x1920.png` | 主游戏页 t=6.2s：HUD(8 字段) / 订单卡完成绿药丸 / 落点与消耗后的棋盘 | `2d8ae7d1242888a2725441c9c38fe041ac2d2d2831092563abb5f9a1fcdddcdc` |
| `orders_panel.png` | 订单卡特写（角色头像 + mission 计数 + 奖励 + DONE） | `c30dd08d843cea6e46e2d83540eb80f6ffa0632294d598407f41af9d486b8eef` |
| `game_theme_pet_shop.png` | 同一帧换主题：`--theme=themes/pet_shop`，**零代码改动** | `be574ed0a51237a0e26aa40393b9f335cf5ad53ea163c0ac1f1a71aa51e886fa` |
| `accept.log` | `bash tools/accept.sh` 的真实输出：7 步 12 项 **ALL CHECKS PASS** | `14178a6ab89fb0d72ef86c7594561758dcaeb09838678d77a142f2bf45e9cc13` |

> 附注：三张 PNG 在两次独立 `accept.sh` 运行中 **sha256 完全相同**（`c190a3c3…` / `2d8ae7d1…` / `be574ed0…`），截图本身也是确定性的。

## 怎么复核

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"
cd 03_Game_ds
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,nb_read_frames,duration \
  -of default=nw=1 docs/evidence/render.mp4      # 1080/1920/60/1800/30.000
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 docs/evidence/render.mp4   # 只有 video
bash tools/accept.sh                              # 重新生成全部证据（约 2.5 分钟）
```

`accept.log` 里的关键行：

```
[tests] TOTAL checks=944 failures=0   RESULT PASS
[PASS] all broken fixtures rejected with the expected code      (24/24)
[PASS] relocated copy ... passes the same suite
[PASS] two takes are frame-identical (framemd5)
[PASS] compared range actually animates (157 unique frames)
[PASS] manifest describes this film (frames=240, ok=true)
[PASS] REFERENCE_ONLY project is refused before recording
ALL CHECKS PASS
```
