# 02_Game（M1 · Godot 4.7.2）

1080×1920 @ 60fps 的 merge 广告工具工程。自包含：资源、项目样例、core sim、视图、时间轴编辑器与出片脚本都在本目录内。

## 运行

```bash
godot --path 02_Game                      # 自动演示（R 重播，Space 暂停）
godot --path 02_Game res://editor/timeline_editor.tscn   # 时间轴编辑器
```

截图：`-- --capture <png> [--capture-at <秒>]`。
出片模式：`-- --project <项目> --render`（隐藏调试标签）。

## 校验 / 模拟 / 测试

```bash
godot --headless --path 02_Game -s res://tests/run_tests.gd        # 717 checks
godot --headless --path 02_Game -s res://tools/validate.gd -- --allow-placeholders
godot --headless --path 02_Game -s res://tools/simulate.gd         # 确定性双跑
```

## 自包含 / 免导入

- 本目录可单独复制运行，不依赖同级 `00_design`：manifest 快照内嵌在 `data/manifest_index.json`（M1 起为 **180 条**），测试与校验读取该快照（`simulate` 走 SimRunner，不依赖 manifest）。
- 测试 / 校验 / 模拟**不需要先执行 `--import`**。无 `.godot` 导入缓存时，资源加载回退为运行时解码（纹理 `Image.load_from_file` + `ImageTexture`，字体 `FontFile.load_dynamic_font`）；有缓存时优先使用导入资源，保持出片与既有 `framemd5` 基线一致。
- 若手动执行 `--import`，新增的 `*.uid` 已被 `.gitignore` 忽略；该命令不再是验收前置。M1 新增的棋子/UI 贴图未提交 `.import`，运行时走上述回退路径。
- 重新生成资源与内嵌快照（开发期，需显式指定源 manifest、资产集合与本地登记）：
  `REPO_ROOT=$(git rev-parse --show-toplevel)`
  `godot --headless --path 02_Game -s res://tools/sync_assets.gd -- --manifest "$REPO_ROOT/00_design/resource_manifest.json" --set res://data/asset_set.json --local res://data/local_assets.json`

> 样例主题 `pet_shop` 引用了 PLACEHOLDER 的 `board_frame`/`ui_icon_star`，所以样例校验需要显式 `--allow-placeholders`；不带该参数时会被资源守卫判 FAIL。

## 主题与 chip 图标（M1）

- 项目顶层 `theme` 指向 `themes/<name>/theme.json`；缺失时用 `themes/pet_shop`。
- 优先级：`theme` > 项目 `icons` > 内置默认；chip 图标为 `theme.chip_icons` > 项目 `chips.<entity>.icons` > 自绘 chip。
- 支持 `background.top/bottom`、`chip_palette`、`board_frame`、`fonts.ui`、`star`，以及 M1 新增的 `chip_icons`（`{实体: {"等级": "资源 ID"}}`，等级 1–10）。
- 内置两套：`themes/pet_shop`（默认蓝，Ca→ca 链、Cb→cb 链）与 `themes/candy`（暖紫/粉，Ca→cb 链、Cb→ca 链，用于验证“换主题即换一套图标”）。换肤只需复制主题目录或改项目 `theme` 字段，不改代码。
- 主题资源只能引用 `assets.json` 中的 PLACEHOLDER（需 `allow_placeholders=true`）/PRODUCTION；REFERENCE_ONLY、TODO 会被 Validator 与运行时 AssetLoader 拒绝。`chip_icons` 的 20 个引用均为 PRODUCTION；`board_frame` / `star` 仍为 PLACEHOLDER（样例需 `--allow-placeholders`）。`chip_icons` 未配置的实体/等级回退为自绘彩色 chip + `Lv` 文本。

### M1 资产/主题配置流程（不改代码，≤10 分钟）

1. **加图标**：把资源 ID 加入 `data/asset_set.json` 的 `ids`（PLACEHOLDER 或 PRODUCTION）；未进 00_design manifest 的 PSD 切片加入 `data/local_assets.json`（usage=PRODUCTION、license=公司自有、local=true）。重跑上面的 `sync_assets.gd` 命令；`assets.json` 与 `data/manifest_index.json` 同步更新，文件复制到 `assets/`。
2. **配映射**：在 `themes/<name>/theme.json` 的 `chip_icons` 里把 `实体 -> 等级 -> 资源 ID` 指向新图标（或在项目 `chips.<entity>.icons` 配置、由主题覆盖）。
3. **出片**：`bash 02_Game/tools/render.sh --project res://data/projects/sample_30s.json`；换主题时复制项目 JSON 只改 `theme` 字段（示例 `output/sample_30s_candy.json`），再 `--project res://output/sample_30s_candy.json --out <abs.mp4>`。
4. **验收**：`validate --allow-placeholders` + `render.sh --verify`；不同主题的 framemd5 必须不同。

## 出片（Movie Maker + FFmpeg）

```bash
bash 02_Game/tools/render.sh                 # -> 02_Game/output/sample_30s.mp4（默认 AVI/MJPEG 中间产物）
bash 02_Game/tools/render.sh --verify        # 双跑 + framemd5 对比
bash 02_Game/tools/render.sh --png-frames    # M0 PNG 序列路径（素材细节多时慢，仅调试）
bash 02_Game/tools/render.sh --keep-frames   # 保留 PNG 序列（隐含 --png-frames）
```

流程：`export_info` 跑 Validator 并算出帧数 → Godot Movie Maker 录制（AVI/MJPEG，真实窗口、固定 60fps）→ ffprobe 校验 AVI 分辨率/帧率/帧数 → FFmpeg H.264（`yuv420p`、`+faststart`、`-threads 1`）→ ffprobe 校验输出 → 可选双跑 framemd5。

- M1 默认 AVI/MJPEG + `--disable-vsync`：1080×1920 / 60fps / 1800 帧（30s）；`--disable-vsync` 用于避免 vsync 帧节奏漂移（否则双跑 framemd5 可能不一致）。M0 的 PNG 序列路径保留为 `--png-frames`（逐帧 PNG 对复杂背景编码很慢，单条可能 >5 分钟）。
- 磁盘预检 20GB（verify+keep 32GB）；中间产物用独立临时目录，转码后自动清理。
- 实测基准（2026-11-05，i7-12700 / RTX 4060 Ti 4G / 64GB RAM）：AVI/MJPEG 中间产物约 23ms/帧；`--verify` 双跑的总耗时与 framemd5 见根目录 `10_report/CC02/M1实施报告-1105.md`。M0 PNG 基线（2026-11-04）：1800 帧录制 151s / 196s，单次出片 177s / 223s，framemd5 `17fa27c9…`，输出 sha256 `d58d91c8…`。
- 帧数判定：PNG 路径以独立临时目录的文件序列为准（首帧 0、末帧 N-1、数量 N）；AVI 路径以 ffprobe 的 `nb_frames` 为准。Godot 4.7.2 的退出摘要偶发少报帧数，脚本只告警。
- 出片前阻断：非法项目（未定义实体、wait 事件、主题引用 REFERENCE_ONLY 等）由 `export_info` 的 Validator 门禁拦下，退出码 1，不产生视频。

## 资源策略

`assets/assets.json` 由 `tools/sync_assets.gd` 按源 `resource_manifest.json` + `data/asset_set.json` + `data/local_assets.json` 生成：M1 起只复制资产集合内的 PLACEHOLDER / PRODUCTION（当前 **61 项 manifest 资源** = 20 张 PLACEHOLDER（UI/特效/棋盘框/特殊箱）+ 2 个字体 + 20 张真实棋子图标 + 19 张棋盘/订单/顶栏 UI），另有 **5 项本地登记**（`local_assets.json`：顶部房间背景、底部信息条、退出图标、宝石图标、完成对号；未进 00_design manifest，`assets.json` 中标记 `local=true`）。合计 **66 项**；其余 100 张图标（100 张棋子 + 20 张生成器箱 − 已打包 20 张）不进入工程，按需加入 `asset_set.json` 后重跑。REFERENCE_ONLY 与 TODO 永不进入工程。同一工具同时生成内嵌快照 `data/manifest_index.json`（**180 条**；已复制资源的 `file` 指向 `res://assets/…`，未复制的 PRODUCTION 保留无盘符的 `01_icon/…` 溯源路径），使工程在无 `00_design` 的干净副本中也能完成校验与测试。运行时统一经 `AssetLoader` 守卫，PLACEHOLDER 需 `allow_placeholders=true`。角色/棋盘/顶栏/底栏已接入 PSD 素材；生成器、障碍外的特效仍为自绘占位；`CleanSet_Ca` / `CleanSet_Cb` 的 1–10 级已接入真实图标，其余实体替换正式美术时按资源 ID 接入，不改逻辑。

## 画面贴近棋盘.psd（M1 追加）

按 `00_design/买量视频工具-需求框架.md` §20.5/§20.6 与 `00_design/images/psd_slices/board_full_preview.jpg` 对齐：

| 元素 | §20.5 数值 | 实现 |
|---|---|---|
| 画布 | 1080×1920 | `project.godot` viewport 1080×1920 |
| 背景 | `main_bg_01_bottom` 1080×1536 铺底 + `main_bg_01_top` 1080×400 叠顶 | `board_bg` + `local_bg_top`，位置 (0,384) / (0,0) |
| 棋盘容器 | `board_frame` 983×1263 @ (48,466) | `BOARD_ORIGIN`/`BOARD_SIZE`，7×9，单格约 140.4×140.3 |
| 格底 | `main_checkerboard_bg` 94×94 | `slot_empty` 缩放到格内 126×126（缺失回退同色系圆角 StyleBox） |
| 棋子 | 182×182 缩放到约 132–140，底边对齐、轻阴影 | `_draw_chip_icon`：最大 140、底边对齐、半透明阴影 |
| 选中 | `common_main_frame_s` 160×164 | `ui_select_frame` 覆盖选中格 |
| 顶栏 money | 等级/能量/金币/宝石 | `ui_level_badge`（98×84）/ `ui_icon_energy` / `ui_energy_timer` / `ui_icon_coin` / `local_icon_gem` + 白色 pill（`ui_topbar` 九宫格）；额外保留 M0 的 star pill |
| 订单角色 | `part1` 373×370 / `part2` 373×524 | `char_order_01_idle/done` / `char_order_02_idle/done`，按源尺寸绘制；char_01 左、char_02 右 |
| 订单卡 | `main_frame_message` | `ui_order_card` 九宫格，任务行显示真实 chip 图标；卡宽 560（为容纳标题/奖励行，比 PSD 预览略宽） |
| 底部信息条 | `items` 693×183 @ (193,1731) | `local_items_bar` |
| 左下退出 / 右下背包 | 164×174 / 109×147 | `local_icon_exit` @ (20,1734) / `ui_button_secondary` @ (938,1739) |
| 障碍 | 锁/泡泡/冰/网 | `obstacle_lock` / `obstacle_bubble` / `obstacle_ice` / `obstacle_web` 贴图（缺失回退自绘） |

- 已知差异（不阻塞）：样例只有 1 个活动订单，所以只显示当前角色与 1 张订单卡（参考图同时展示 part1/part2 两张卡）；生成器仍为自绘 `Lv CleanBox`（manifest 的 `box_clean_c_*` 实为宠物床，非 PSD 蓝色储物箱）；多格锁/冰冻组/区域遮罩按单格障碍实现，未整组使用 `区域遮罩1.png`；`main_icon_finish`/`main_icon_ice`/`main_frame_nonactivated` 已有文件但未进 00_design manifest，其中 finish 已本地登记，ice/web 使用已登记的 `obstacle_ice`/`obstacle_web`。
- 1080×1920 对比图（`output/` 已 gitignore）：`output/m1_side_by_side_static.png`、`output/m1_side_by_side_ingame.png`、`output/m1_static_board_1080x1920.png`、`output/m1_ingame_chips_1080x1920.png`。

## 编辑器（时间轴）

```bash
godot --path 02_Game res://editor/timeline_editor.tscn
godot --path 02_Game res://editor/timeline_editor.tscn -- --project res://tests/fixtures/broken_project.json --validate
```

- 轨道按 channel + track 分组折叠；属性面板支持绝对/相对锚点；播放/单步/重置；50 步撤销/重做。
- **自动保存**：编辑后每 30 秒写 `user://timeline_autosave.json`；窗口关闭时兜底保存。显式「保存草稿」写入 `user://timeline_draft.json` 并清除自动保存。
- **异常恢复**：启动时若存在自动保存草稿，弹窗选择「恢复草稿 / 丢弃」；capture 模式不弹窗。
- **校验面板**：工具栏「校验」列出全部 error/warning 与 JSON 路径；点击 `timeline[i]...` 条目直接选中对应事件；`--validate` 可在 capture 时直接打开面板。校验失败的项目仍可在编辑器打开定位，但 capture 默认会以退出码 1 结束（带 `--validate` 例外）。

## M0 验收状态（2026-11-04）

- ✅ 30s 固定模板出片：1080×1920@60、1800 帧、30.000s；两次 framemd5 一致。
- ✅ 两关配置与过关流程（level_1 → level_2）；订单完成链路：绿药丸 → 物品飞向角色 → 角色消失 → 金币/星星 → 新角色/新订单。
- ✅ 时间轴：绝对/相对锚点、同刻排序；预览/单步/出片共用同一求值器与快照。
- ✅ 资源守卫：REFERENCE_ONLY 禁止引用/出片；PLACEHOLDER 需 `allow_placeholders=true`；TODO 阻断。
- ✅ 换主题只改项目 `theme` 字段，两套主题（pet_shop/candy）验证。
- ✅ 顶栏 HUD：level / energy（mm:ss 倒计时）/ coin / star / gem / exp。
- ✅ 生成器棋盘已满 Toast（`board_full` 事件或满盘 tap 触发，1.5s）。
- ✅ 选中停留 3s 后，同 entity+level 的 chip 放大 1.08 并向选中格靠近 6px；时间轴 `hint` 事件同样生效。
- ✅ 订单可达性校验：初始棋盘 + 生成器 charges 推导，不可达订单在出片前阻断（保守近似，不保证完备；见「M0 已知限制」P2-3）。
- ⏳ 音频为 TODO（M0 不出音轨）。

## M1 验收状态（2026-11-05）

- ✅ manifest 快照 74→**180 条**（PRODUCTION 155 / PLACEHOLDER 20 / TODO 5 / REFERENCE_ONLY 0），逐条与 `00_design/resource_manifest.json` 一致；`assets.json` **66 项**（61 manifest + 5 local）。
- ✅ `chip_clean_ca` / `chip_clean_cb` lv01–10 共 20 张真实图标入库；`theme.chip_icons` 优先级 theme > project > default；BoardView 真实图标绘制（底边对齐、轻阴影）。
- ✅ 主题切换：复制项目 JSON 只改 `theme` 字段 → 出片（candy 109s）；pet_shop framemd5 `6accae7c…`、candy `135f1bea…`，**不同**（candy 的 Ca/Cb 图标互换）。
- ✅ 画面贴近棋盘.psd：背景/容器/格底/顶栏/订单角色/底栏按 §20.5 数值；1080×1920 对比图见 `output/m1_side_by_side_*.png`。
- ✅ tests **717 checks / 0 failures**；validate `PASS (0 errors, 0 warnings)`；simulate 双跑同 hash；干净副本（无 `00_design` / `.godot`）同样 717/0 + validate PASS。
- ✅ 出片 1080×1920@60 / 1800 帧 / 30.000s，单次 **109–111s**（含 FFmpeg，≤5 分钟）；`render.sh --verify` 双跑 framemd5 **A=B=`6accae7c…`**，输出 sha256 `0acc8978…`（详见 `10_report/CC02/M1实施报告-1105.md`）。
- ⏳ 音频仍为 TODO；其余 100 张棋子图标未打包，按需加入 `data/asset_set.json`。

## 当前边界

- 音频为 TODO，出片无音轨。
- `CleanSet_Ca` / `CleanSet_Cb` 已用真实图标；其余 10 条链等 100 张图标未进工程（按需加 `asset_set.json`）；生成器、特效、多格锁/冰冻组仍为自绘/单格占位。
- 5 项本地登记素材（顶部房间背景、底部信息条、退出、宝石、完成对号）待补登 `00_design/resource_manifest.json`；本 lane 未改 00_design，清单见 `10_report/CC02/M1实施报告-1105.md`。
- Godot 4.7.2 Movie Maker 的退出摘要偶发少报帧数；`render.sh` 在 PNG 路径以帧文件序列为准（数量 + 首末帧编号），在默认 AVI 路径以 ffprobe `nb_frames` 为准。

## M0 已知限制（收口登记）

以下为 M0 修复复核（`10_report/CC02/M0修复复核-1104.md`）确认、M0 阶段不修、列入 M1 待办的 P2 级残留。它们**不阻塞 M0 交付**。

| 编号 | 残留 | 现状 / 兜底 |
|---|---|---|
| P2-3 | 订单可达性为保守近似 | 障碍格（lock 等）、生成器共享 charges、mission 重复需求三类会漏杀；validate PASS 不代表运行时一定可达。收口口径见 M0 规格 v0.21：保守近似、不保证完备。 |
| P2-4 | 门禁口径不一 | preview / 单步 / simulate 传 null manifest；export_info 不校验 manifest / assets 记录。 |
| P2-5 | `core/resource_guard.gd` 未接入运行时 | 死代码，且 fail-open；运行时实际走 `game/asset_loader.gd`。 |
| P2-6 | 快照不含生成器 charges / next_time 与 RNG | 同 seed 不同 charges 可得到同 hash。 |
| P2-9 | audio 通道恒拒 | `AUDIO_TYPES := []`，audio / bgm 在 evaluate / validate / export_info / simulate 四道门禁均判「未注册的事件类型」；M0 无音轨。 |
| B1 | `SIM_NOT_MERGEABLE` 只是 message 前缀 | 事件无结构化 code。 |
| B2 | validator 不校验 merge 命令语义 | `kind=chip`、`level+1 ≤ min(10, maxLevel)` 未前置校验。 |
| D1 | `render.sh` 只认字面 `SCRIPT ERROR` | 不认运行期 `ERROR:`（push_error）。 |
| C1 | `.uid` 跟踪不一致 | 10 个已跟踪与 `*.uid` 忽略并存；`*.import` 的 CRLF 噪声取决于客户端 `core.autocrlf`，仓库无 `.gitattributes`。M1 新增 66 项资源未提交 `.import`，运行时回退解码。 |
| E1 | validator 可达性对 rareOutputs 无条件计 charges | 与运行时 directOrder 门控分叉，只会加剧 P2-3 漏杀。 |
| M1-1 | 其余 100 张棋子图标未打包 | 只有 ca/cb 两条链的 20 张进入 `assets/`；其余按需加入 `data/asset_set.json` 后重跑 `sync_assets.gd`。 |
| M1-2 | 5 项本地登记素材未进 00_design manifest | `local_assets.json` 记录 usage=PRODUCTION / license=公司自有 / `local=true`；待补登清单见 `10_report/CC02/M1实施报告-1105.md`。 |
| M1-3 | 画面与 PSD 的非阻塞差异 | 仅 1 个活动订单/角色；生成器无合适箱体图标；多格锁/冰冻/区域遮罩按单格障碍实现；订单卡宽 560×190（为容纳标题/奖励行，比 PSD 预览宽）；顶栏额外保留 M0 star pill、未做商店按钮；详见「画面贴近棋盘.psd」。 |

证据与最小复现见 `10_report/CC02/M0修复复核-1104.md`（§3.7–§3.14、§4）。M1 修复时逐项补回归。

**M1 快照说明**：`data/manifest_index.json` 已按 `00_design/resource_manifest.json`（v7，180 条：PRODUCTION 155 / PLACEHOLDER 20 / TODO 5 / REFERENCE_ONLY 0）重建；已复制资源指向 `res://assets/…`，未复制的 PRODUCTION 保留 `01_icon/…` 仓库相对溯源路径。`assets.json` = 61 项 manifest 资源 + 5 项 `local_assets.json` 本地登记（`local=true`），共 66 项。
