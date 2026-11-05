# MergeGame — Godot 工程（03_Game_ds）

M0 §9 全 9 步交付：**manifest/schema 校验器**、**core 模拟 + 事件求值器 v2**、**静态棋盘视图**、**订单/角色 + HUD**、**时间轴编辑器**、**出片流水线（Movie Maker + FFmpeg + framemd5）**、**主题映射**、**校验/自动保存/异常恢复**、**确定性与性能基线**。
M1 起：**真实 chip 图标接入**（`manifest_index.json` 74→180、`assets/chips/` 20 张、`theme.json` 的 `chip_icons` 按 `(entity, level)` 映射到真实图标，棋盘/成片同一条 `ThemeLoader` 路径）。
目标引擎 **Godot 4.7.2 stable**，桌面 1080×1920@60。本目录**可整体搬移**：只用 `res://` 相对路径，不引用 `01_icon/` 原目录。

## 1. 命令

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"   # git-bash(MSYS) 路径；Windows 原样路径见 00_design/START-HERE.md

# 一键总验收（9 步：测试 / 校验 / 25 条反例 / 搬移 / 两张截图 / 出片确定性 / 出片门禁 / 主题成片）
bash tools/accept.sh

# 全量测试（自动发现 tests/t_*.gd）
"$G" --headless --path . --script res://tests/run_tests.gd

# 校验一个工程（strict + 打印事件顺序）
"$G" --headless --path . --script res://src/tools/cli.gd -- \
  validate --project res://data/sample_project.json --strict --dump-order

# 截图（真窗口，不能 --headless）；不带 --theme 时用 themes/default（真实 chip 图标）
"$G" --path . --script res://tools/shot_board.gd -- --theme=themes/pet_shop
"$G" --path . --script res://tools/shot_game_screen.gd -- --t=6.2
"$G" --path . --script res://tools/shot_game_screen.gd -- --t=6.2 --theme=themes/pet_shop

# 出片（真窗口；中间产物 AVI，可 --keep-frames）；--theme 换一套主题只改数据
bash tools/render.sh                              # 全片 30s/1800 帧 -> output/render.mp4
bash tools/render.sh --frames 300 --out output/m1_icons_default.mp4
bash tools/render.sh --frames 300 --theme themes/pet_shop --out output/m1_icons_pet.mp4
bash tools/render.sh --frames 120 --determinism   # 2s 双次出片 + framemd5 对比

# 重建资源快照（唯一事实源是 00_design/resource_manifest.json，改完必须重跑）
"$G" --headless --path . --script res://src/tools/build_manifest_index.gd -- \
  --manifest ../00_design/resource_manifest.json --out res://data/manifest_index.json

# 编辑器页（可独立启动）
"$G" --path . res://src/editor/timeline_editor.tscn
```

### 1.1 F5 运行窗口（2026-11-05）

设计分辨率不变：`project.godot` 仍是 `viewport_width=1080` / `viewport_height=1920` + `stretch=canvas_items/keep`。
真窗口（F5 / `--path .`）由 `src/view/game_screen.gd` 在运行期缩到**一半并居中：540×960**（0.5×），1080p 桌面能完整放下。

```text
[game] preview window=540x960 design=1080x1920 scale=0.50 screen=1920x1032
```

- 换缩放：编辑器 `项目设置 → 调试 → 运行 → 主运行参数` 填 `--window=648x1152`（0.6×）/ `--window=810x1440`（0.75×）；`--window=native` 回引擎默认（1080×1920）。命令行同理：`"$G" --path . -- --window=648x1152`。
- **为什么没写进 `project.godot`**：`window/size/window_width_override` 会连带缩小 Movie Maker 的根视口（实测 AVI 变 540×960），直接顶掉 `render.sh` 的 1080×1920 门禁。放在主场景运行期，出片/截图路径一行都不经过它。
- 证据产物实测未变：PNG `1080×1920`（bytes=900446，与 M1 基线一致）；60 帧成片 `width=1080 height=1920 nb_frames=60`，`render.sh` 分辨率门禁通过。
- 真窗口运行会在 `assets/` 下生成 `*.import` / `*.uid` 边车文件：已进 `03_Game_ds/.gitignore`，`t_relocatable` 按引擎边车跳过——**跑完 F5 再跑测试仍是 1753 checks / 0 failures**。
- `t_relocatable` 的配置断言改成读 `ProjectSettings` 有效值（不再匹配文件文本）：引擎退出时会重写 `project.godot`、省略等于默认值的键（如 `window/stretch/aspect="keep"`），按文本断言会让「干净仓库跑一次再跑第二次」变红。

### 1.2 自由模式与「玩一遍出片」（2026-11-05）

F5 默认进**自由模式**（`free_mode=true`）：没有时间轴替你走，点生成器出料、点两个同款合成、点订单卡交付、过关后点一下继续。规则全部落在 `src/core/sim.gd` 的同一套 `sim.apply` 上，`src/core/free_mode.gd` 只负责「点到哪一格 → 该发什么事件」。

```text
[game] cursor=ui_cursor_hand drawn=true os_hidden=true
[game] freeze=false autoplay=false free_mode=true rec=false clock=0.00 t=-1.00
```

- **R = 开始 / 停止录制；停下就自动出片**，不需要终端：第二次按 R 后，take 存到 `output/mov/take_<时间戳>.take.json`，同目录随后出现 `take_<时间戳>.mp4`（另有 `.manifest.json` 资源清单和 `.log` 出片日志）。成片 1080×1920@60，文件名带时间戳，不会互相覆盖。
- 出片是**后台进程**（`tools/render_take.gd`，headless）：它先等 Movie Maker 子进程录完 AVI，再调 ffmpeg 转 MP4，然后把 AVI 删掉。游戏窗口不卡，可以接着玩下一局。耗时约 **3× 片长**（2.5s 的片 ≈ 8s，30s 的片 ≈ 90–120s）。
- 窗口里的手是**画在窗口内的**（`game_screen.gd` 的 `Cursor` 层，OS 光标隐藏）：图标 `ui_cursor_hand`（[Kenney Cursor Pack](https://kenney.nl/assets/cursor-pack)，CC0），按下缩到 0.92 保持 100ms；和成片里那只手是同一张图、同一套按压规则，所以**预览就是成片**。
- 只想录、先不出片：`F5 -- --no-render`（take 照常保存，不启动出片）。想换参数重出同一条 take：

```bash
bash tools/render.sh --take output/mov/take_20261105_153012.take.json --out output/mov/clean.mp4 --no-cursor
```

- take 结构：`{schema, seed, fps, duration, project, cursor:[[t,x,y]…], clicks:[…], timeline:[…]}`；`src/core/take_io.gd` 负责采样插值 / 校验 / 读写，`tests/t_free_mode.gd` 覆盖插值、按压窗口、排序校验与点击→事件映射。
- `-- --demo`：回到自动回放（按 `sample_project.json` 的 21 条事件走一遍），用来看出片节奏；不录制、不画手。
- 自动出片依赖工程内的 `tools/render_take.gd`（和 `tools/` 其他脚本一样只在编辑器 / F5 运行时可用；导出版没有脚本源码）。

## 2. 目录

```
03_Game_ds/
├─ project.godot           1080×1920、stretch=canvas_items/keep；main_scene=game_screen
├─ assets/                 49 个载荷副本（20 张真实 chip 图标 + 2 个字体 + 5 个 PLACEHOLDER + 21 张界面切图 + 1 个 CC0 光标）+ PROVENANCE.md
│  ├─ chips/               icon_10002101..110（Ca Lv.1–10）、icon_10002201..110（Cb Lv.1–10）整字节复制
│  ├─ fonts/ · ui/         2 个字体；ui/ 共 27 张（5 个 PLACEHOLDER + 21 张 §20.5 界面切图 + cursor_hand.png）
│  └─ PROVENANCE.md        出处/许可/尺寸/fit/sha256（含 M1 20 张表）
├─ data/
│  ├─ sample_project.json  schema v2 样例：2 关、7×9、21 条事件、30s
│  ├─ manifest_index.json  资源清单快照（180 条 + 8 条别名，id/usage/license/文件名，无绝对路径）
│  └─ themes/{default,placeholder,pet_shop}/theme.json
├─ src/
│  ├─ core/        event_model / rng / board_state / project_model / sim / sim_handlers / event_evaluator / state_digest / free_mode / take_io
│  ├─ validate/    validator + 规则族（引用/等级/棋盘/时间轴/资源）
│  ├─ assets/      asset_guard.gd（usage 单点裁决 + 别名解析 + res:// 存在性两层）
│  ├─ view/        board_view / hud_view / order_panel / fly_anim / game_screen
│  ├─ theme/       theme_loader（theme > project > default；chip_icons 按 entity+level）
│  ├─ editor/      project_store / undo_stack / timeline_editor
│  ├─ render/      movie_scene / render_plan / render_manifest
│  └─ tools/       CLI、manifest 快照构建
├─ tests/          21 个套件（自动发现）+ 25 条反例夹具
├─ tools/          accept.sh / render.sh / framemd5_compare.sh / gen_fixtures.py / shot_*.gd
└─ docs/           AUDIT-S1.md、REVIEW-CORE.md、PERF-BASELINE.md
```

## 3. 资源口径（M1 / manifest v7）

`00_design/resource_manifest.json` 是唯一事实源（**192 条**，2026-11-05 追加 `ui_cursor_hand`；本工程快照仍是 v7 的 180 条，M2 重建）：`PRODUCTION 156` / `PLACEHOLDER 20` / `TODO 5` / `REFERENCE_ONLY 0`。`01_icon` 公司自研素材已全部登记为 `PRODUCTION`（license `公司自有/自研`），M0 的“原游戏切图一律不打包”红线因此变成**按需复制**：本工程只复制了 **49 个载荷文件**（覆盖 42 条快照记录 + 9 个仅本地登记的文件；`in_project=42`），其余 **138 条**快照记录（118 条 `PRODUCTION` + 15 条 `PLACEHOLDER` + 5 条 `TODO`）一张都没进工程。

- `data/manifest_index.json` 由 `src/tools/build_manifest_index.gd` 生成，只保留 id/usage/license/文件名/尺寸，**不带绝对路径**，所以搬移后仍能执法。顶层另有 8 条 `aliases`：源 manifest 把 Ca/Cb 的 7–10 级按原始文件名登记为 `icon_10002107..110` / `icon_10002207..210`，别名把它们对齐成统一的 `chip_clean_*_lv07..10`（`AssetGuard` 的每个方法都识别别名，`entry()` 仍返回原记录）。
- 两层判定分开：`check_ref(id)` 看治理层（usage + `file_present`，即源文件是否在清单里存在），`local_path(id)` 看存在层（`res://assets/{ui,chips,fonts}/` 下是否真有这个副本）。**未复制**的 `PRODUCTION` id 会通过前者、返回 `""` 给后者——所以调色板之外的 8 条链图标“写进主题就能用”，但必须先复制。
- `REFERENCE_ONLY`（0 条）与 `TODO`（5 条音频）恒阻断；`PLACEHOLDER` 仅在 `--allow-placeholders` 且经 `AssetGuard` 放行时加载并写日志。
- 棋盘上的障碍 / 选中括角 / 完成态仍程序化绘制；chip 在主题给了 `chip_icons` 时画真实图标（fit=scale 居中，等级胶囊在上），没给时保持程序化圆角块。
- 出片时 `output/render_manifest.json` 记录实际使用的资源（字体 + 主题 `chip_refs()` 的全部 chip id + 画面用到的 `icons.ui` id）与 `blocked` 列表；git 只跟踪代码与数据，`output/` 是产物。
- **本地登记表** `data/assets_local.json`：快照没登记、但画面要用的素材在此登记为 `PRODUCTION`，`AssetGuard` 载入时与快照合并，**快照记录永远优先**（本地同名记录会被拒并计数，`t_local_assets` 断言）。共 **10 条**：§20.5 布局 9 条（`ui_bg_top`、`char_part1/part2`、`ui_items_bar`、`ui_board_frame` 等）+ `ui_cursor_hand`（CC0 光标，2026-11-05 已同步登记进 00_design manifest v8，待 M2 重建快照后可删本地记录）。前 9 条仍在「待补登 00_design manifest」清单（见 §5.2）。
- 载荷文件共 **49** 个：20 张 chip 图标 + 2 字体 + 5 个 PLACEHOLDER + 21 张 §20.5 界面切图 + 1 张 CC0 光标。

## 4. 数据 / 事件模型 v2 要点

- 关卡顺序 = `levels` 数组顺序，**无 `next`**（发现即 `LEVEL_NEXT_REMOVED`）。
- `entities` 声明 `kind`；`board.slots` 用 `entity`（旧 `chip` 键 → `SLOT_CHIP_KEY_LEGACY`）；`generators` 只存行为（混入实体字段 → `GEN_NON_BEHAVIOR_FIELD`）。
- 引用 ID 必须已定义；M0 等级上限 10；HUD 8 字段显式；`meta.duration` 不作为时长来源（`--strict` 升错误）。
- 事件：`channel = sim|view|audio`；`at` 绝对秒或 `{after, offset}`；排序 `at → channel → track → order → id`；**禁 `wait`**；锚点缺失/自指/环报错且不死循环。
- 校验器、预览、单步、离线出片**共用** `src/core/event_model.gd` + `src/core/event_evaluator.gd`，不存在"校验一套、播放另一套"。
- **主题的 `chip_icons`（M1）**：`{ "<entity>": { "<level>": "<manifest id>" } }`。chip 是 `(entity, level)` 二维键，`icons` 表表达不了，所以单列一块；`ThemeLoader` 每片叶子都过 `AssetGuard`（未知 → `ASSET_UNKNOWN`，`REFERENCE_ONLY`/`TODO` → 阻断，`PLACEHOLDER` 需放行），`resolve_chip_icon()` 的优先级是 `theme.chip_icons` > `entities[e].visual.icons[level]` > `entities[e].visual.icon` > 默认（程序化）。校验器的 `rules_usage` 也走同一张表，所以坏 chip id 在 `validate --strict` 阶段就被拦下，不必等到出片。`chip_texture()` 按 `entity@level` 缓存，1800 帧只读一张 PNG 一次。

## 5. 验收对照（M0 §7 + M1）

| 条目 | 状态 | 证据 |
|---|---|---|
| 30s / 1080×1920 / 60fps / 1800 帧 | ✅ | `ffprobe`：`1080x1920 / 60\/1 / nb_frames=1800 / duration=30.000` |
| 2 关可配置，完成第 1 关订单 → 过关 → 第 2 关 | ✅ | `t_sim` 越关断言 + `output/game_level2.png` |
| 订单完成：绿药丸 → 物品飞向角色 → 角色 → 金币/星星 → 新订单 | ✅（角色用溶解表现） | `output/game_1080x1920.png`(t=6.2)、`t_order_view` |
| 生成器：点击产出、稀有直出订单物品、棋盘满提示 | ✅ | `t_sim`（rare 进池条件、`SIM_BOARD_FULL`）+ `t_board_toast`（view 端 1.5s toast 消费 `board.full`；成片端同风格提示条） |
| 选中提示：黄框 + 停留放大/靠近 | ✅ | `output/board_1080x1920.png`（黄括角 + 黄光 + 放大 8% 并向盘心偏移 7px） |
| 时间轴：锚点、同刻排序、预览/单步/渲染一致 | ✅ | `t_event_model` 排序用例 + 编辑器单步 + 出片共用求值器 |
| 资源守卫：`REFERENCE_ONLY`/`TODO` 无法出片；`PLACEHOLDER` 需显式 | ✅ | 25 条反例逐条命中 + `t_guard`（M1 快照已无 `REFERENCE_ONLY` 记录，该分支用注入合成记录的单测保住，`accept.sh` 步骤 7 另用未知 id 做端到端拒绝） |
| 校验：缺图/越界/不可达/usage 违规在出片前阻断 | ✅ | `output/validation_report.json`、`accept.sh` 步骤 2–3、8（`payload_empty` / `f1_a` / `reject_sim`） |
| 两次出片 framemd5 一致 | ✅ | `accept.sh` 步骤 7：240 帧 `same=YES`，`b42fff51…c3d68f`（195 个唯一帧）；M1 样片 300 帧 `same=YES`，`e2c7f9ba…956189ce`（default）/ `bb92abd5…cb15e2fc`（pet_shop） |
| 换 1 套主题 ≤10 分钟、不改代码 | ✅ | `accept.sh` 步骤 9：60 帧 default vs pet_shop，framemd5 `f81c1cb311d6` ≠ `65a941acded1`，sha256 `ab76cc21a5d9` ≠ `df39b1b1c0c4`；300 帧样片同样不同（见下表） |
| **M1 真实图标**：chip 不是占位 | ✅ | 棋盘截图 `[shot] chip_icons resolved=4 of 6 items`、游戏页 `3 of 5`、成片抽帧 `output/m1_frame_t2.6.png` 可见骨头/三文鱼卷图标；pet_shop 同命令 `resolved=0 of 6`（对照） |
| **M1 资产配置**：一套资产 = 数据，不改代码 | ✅ | `manifest_index.json` 180 条 + `assets/chips/` 20 张 + `themes/default/theme.json` 的 `chip_icons`；见 §5.1 |
| **M1 画面贴近 棋盘.psd（§20.5）** | ✅ | 棋盘容器 983×1263 @ (48,466)、7×9 格 140.43×140.33 精确铺满、背景 `main_bg_01_bottom/top`、顶栏 money、订单角色 part1/part2、底部 items 693×183 @ (193,1731)、左下退出/右下背包、冰/泡/网/锁切图；并排对照见 §5.2 |

### 5.1 配一套资产 / 换主题（≤10 分钟，全程不碰代码）

1. **素材入库**：把 PNG 放进 `assets/chips/`（或 `assets/ui/`），文件名与 manifest 的 `file_name` 一致；在 `assets/PROVENANCE.md` 记出处/许可/尺寸/sha256。
2. **登记 id**：在 `00_design/resource_manifest.json` 里把该文件登记为 `PRODUCTION`（`PLACEHOLDER` 需显式放行，`TODO` 不可用），然后重跑快照生成器（命令见 §1）。快照不是手写文件，`count`/`usage_counts`/`in_project` 全部由源 manifest 与 `assets/` 现状算出。
3. **映射到 chip**：在主题里写 `chip_icons`：
   ```json
   "chip_icons": { "CleanSet_Ca": { "1": "chip_clean_ca_lv01", "2": "chip_clean_ca_lv02" } }
   ```
   键是 `entities` 里的实体 id，二级键是等级（十进制字符串）；值可以是快照 id，也可以是 `aliases` 里的别名。没映射的槽位继续程序化绘制。
4. **换主题出片**：`bash tools/render.sh --frames 300 --theme themes/<name> --out output/x.mp4`；预览截图 `--script res://tools/shot_board.gd -- --theme=themes/<name>`。`theme.json` 里 palette/metrics/chip_icons 三者都是纯数据，**改完不需要动任何 `.gd`**。
5. **自检**：`validate --strict`（chip id 会出现在 `[guard] used id=…` 清单里）+ `run_tests.gd`。新增一套主题的最短路径就是复制 `themes/pet_shop/theme.json` 再改字段。

### 5.2 画面按 棋盘.psd（§20.5）重建

几何全部来自 `00_design/买量视频工具-需求框架.md` §20.5，写死为 `BoardView` / `game_screen` 的常量（测试逐条断言，不是"看着像"）：

| 元素 | §20.5 数值 | 落点 |
|---|---|---|
| 画布 | 1080×1920 | `BoardView.PAGE_SIZE` |
| 棋盘容器 `board_frame` | 983×1263 @ (48,466) | `BOARD_ORIGIN` / `BOARD_SIZE`，63 格并集精确等于容器 |
| 单格 | 140.428571×140.333333 | `CELL_W = 983/7`、`CELL_H = 1263/9`（`CELL=140` 仅保留给格索引算术） |
| 背景 | `main_bg_01_bottom` 1080×1536 @ (0,384)、`main_bg_01_top` 1080×400 @ (0,0) | `BG_BOTTOM_RECT` / `BG_TOP_RECT` |
| 顶栏 `money` | 等级/能量/金币/星星/宝石 + 商店按钮 | `Chrome._draw_topbar()`，数字由 chrome 自己画（hud_view 在 chrome 模式下隐藏，避免双画） |
| 订单角色 | `part1` 373×370、`part2` 373×524 | `LAYOUT_PART1/PART2` |
| 底部 `items` | 693×183 @ (193,1731) | `LAYOUT_ITEMS` |
| 左下退出 / 右下背包 | 164×174 / 109×147 | `LAYOUT_EXIT` / `LAYOUT_BAG` |
| 特殊格（选中） | 160×164 | `ui_select_frame`，格心对齐 |
| 冻结 | 冰块 + `19:28` | `obstacle_ice` + 倒计时文本 |
| 棋子 | 182→132（§20.6 的 132–140 带），格内底边对齐 + 轻阴影 | `CHIP_DRAW_SIZE` |

并排对照（左＝`board_full_preview.jpg`，右＝本工程截图）：
`output/m1_side_by_side_board.png`、`output/m1_side_by_side_game.png`。

**与参考图仍存在的差异（已知，见 §6.1）**：格底多一圈"lip"边、棋子没有皇冠/角标态、生成器仍是程序化闪电方块（PSD 的箱堆图未导出）、`box24.png` 只作参考未使用。

#### 待补登 00_design manifest 的本地素材（9 条，`data/assets_local.json`，`pending_manifest: true`）

由 Claude 收口会话统一补登 v0.22；**本 lane 不改 `00_design`**。全部 `usage=PRODUCTION`、`license=公司自有/自研`。
（第 10 条 `ui_cursor_hand` 不在此表：它已在 v8 manifest 登记，`pending_manifest: true` 只表示本工程快照仍是 v7/180 条。）

| 本地 id | 工程文件（`assets/ui/`） | 源路径 | 尺寸 | fit |
|---|---|---|---|---|
| `ui_bg_top` | `main_bg_01_top.png` | `01_icon/HotelManor_icon/界面切图/main_bg_01_top.png` | 1080×400 | exact |
| `ui_level_badge_bg` | `main_bar_level_bg.png` | `01_icon/HotelManor_icon/界面切图/main_bar_level_bg.png` | 118×104 | exact |
| `ui_icon_finish` | `main_icon_finish.png` | `01_icon/HotelManor_icon/界面切图/main_icon_finish.png` | 52×52 | exact |
| `ui_btn_plus` | `main_btn_plussign.png` | `01_icon/HotelManor_icon/界面切图/main_btn_plussign.png` | 48×48 | exact |
| `ui_button_shop` | `common_main_btn_shop.png` | `01_icon/HotelManor_icon/界面切图/common_main_btn_shop.png` | 142×132 | exact |
| `char_part1` | `part1.png` | `00_design/images/psd_slices/part1.png` | 373×370 | exact |
| `char_part2` | `part2.png` | `00_design/images/psd_slices/part2.png` | 373×524 | exact |
| `ui_items_bar` | `items.png` | `00_design/images/psd_slices/items.png` | 693×183 | exact |
| `ui_board_frame` | `board_frame.png` | `01_icon/HotelManor_icon/剩余图标/board_frame.png` | 983×1263 | exact |

> `ui_board_frame` 同时是对 `board_frame` 的 **usage 升级建议**：v7 里 `board_frame` 是 `PLACEHOLDER`（PIL 生成），§20.5 要求容器在 strict 模式也可见，故本地以 `ui_board_frame` 指向同一文件、`usage=PRODUCTION`，并在记录里写了 `supersedes: board_frame`。补登时建议直接升级 `board_frame` 的 usage，或在 v0.22 并档。
> 另：`ui_icon_coin`、`ui_icon_energy` **无需补登**——它们在 v7 快照里已是 `PRODUCTION`（`file_present=true`），只是 `in_project=false`（未复制/未映射）；需要时复制进 `assets/ui/` 并在主题 `icons.ui` 映射即可。真正缺登记的只有宝石图标（`icon_90000003` / `ui_icon_gem`，见 §6.1 D5）。

## 6. 已知限制 / 与规格文字的偏差

1. **选中"停留放大/靠近"是静态量**：选中 chip 由 1.0 放大到 1.08 并向盘心偏移 7px，用几何表达"靠近"，没有 Tween 过渡——出片要求逐帧确定性，动画一律由帧号/事件时间算出，不做补间累积。
2. **角色消失**：用页面色溶解 + 收拢环表现，没有真正隐藏订单卡头像（FlyAnim 不反写 panel 状态）。
3. **主题覆盖面**：HUD / 订单卡 / 棋盘底色与面板 / 横幅 / CTA / 底栏 / 圆角与间距随主题 palette+metrics 变（预览与成片一致）；chip 有真实图标时画图标（透明 PNG，不铺底色块），没有映射时仍用实体 `visual.hue` 的程序化色块——主题 palette 不覆盖 entity hue。
4. `tap` 只支持 `{target:{slot:[x,y]}}`，旧文档的 `{generator:id}` 形式未支持。
5. 无按帧自动回能：能量只由 `energy_tick` 事件改变（确定性要求）。
6. 编辑器属性面板不做格子坐标编辑（只做错误定位）；折叠状态不持久化。
7. 并发跑出片会共用临时目录，需用 `RENDER_TMP_DIR=<dir>` 隔离（`accept.sh` 已隔离）。
8. 音频仍为 `TODO`（M0 不做）；帧级确定性只在本机验证，未做跨机验证。
9. **merge 限定 chip、`directOrder` 已实现（均已写入 M0 v0.20 §2.1.9/§2.1.10）**：非 chip 合并返回 `SIM_NOT_MERGEABLE`；`directOrder=true`（缺省）稀有产出只在该 `entity+level` 被未完成订单需要时进池，`false` 为无条件大奖。见 `docs/REVIEW-CORE.md` §4。
10. **M1 chip 图标只接入棋盘与成片**：订单卡的 mission 小药丸、角色头像、HUD 图标仍是程序化绘制（本轮范围就是 chip + 成片可见）。
11. **只复制了两条链**：`assets/chips/` 只有 Ca/Cb 各 10 级；另外 8 条链（80 张）在快照里是 `PRODUCTION`，写进 `chip_icons` 即可用，但要先把文件复制进 `assets/chips/` 并登记 `PROVENANCE.md`——`local_path()` 只认工程内副本。
12. **图标无底色**：真实 chip 直接画透明 PNG（不铺 entity hue 底色块），主题若需要彩色底板得在主题层另做；程序化路径（未映射时）像素与 M0 一致。

### 6.1 M1 视觉已知差异（对照 `board_full_preview.jpg`，**不阻塞 M1**）

来源：`10_report/DS03/M1实施复核-1105.md` §7.2（D 编号沿用该报告）。几何/布局已按 §20.5 精确落位（见 §5.2），下表全部是**美术/内容层**差异，不影响 tests / strict / accept / 出片确定性。

| # | 差异 | 参考图 | 本工程 | 处置 |
|---|---|---|---|---|
| D1 | 格底"lip"边 | 更平的浅蓝格底，格间缝隙细 | 圆角格 + 较粗浅蓝外环（lip） | 已知，未修（§6 第 4 条） |
| D2 | 生成器美术 | 3D 箱堆 + `x10` + `Lv.22` + 锁 | 程序化蓝色方块 + 闪电 + `x9` | 已知，PSD 箱堆未导出 |
| D3 | 安全箱 | 灰色 3D 袋 + 猫图标 + 蛛网 | 灰色圆角块 + 文本 `Safe` | 已知，程序化兜底 |
| D4 | 冻结组 / 区域遮罩 / 存储 / 特殊格角标 | 4 格冰、2×3 多格锁、存储角标、皇冠/满级角标 | 单格冰 + `19:28`；无多格遮罩/存储/角标 | 已知（`冻结.png`/`区域遮罩1.png`/`棋盘特殊格子.png`/`存储.png` 未复制） |
| **D5** | **游戏页顶栏货币图标**（复核 P2-4） | 闪电/金币/宝石图标 + 加号 | 游戏页预览为**空白胶囊 + 数字**；**成片**由 `src/render/movie_scene.gd` 的 `_draw_topbar()` 画程序化闪电/金币/宝石图标，故预览与成片不一致 | 已知，不阻塞；修法：把 `movie_scene` 的 `_coin/_gem/_star` 画法复用到 `src/view/game_screen.gd` 的 `Chrome._draw_topbar()`（M2） |
| **D6** | **左下退出按钮无箭头**（复核 P2-5） | 蓝色箭头按钮 | 空白五边形：`data/themes/default/theme.json` 的 `exit` 映射到 `ui_button_primary`（文件 `main_btn1.png`）；参考图的 `main_icon_exit.png` 存在于 `01_icon/HotelManor_icon/界面切图/`，但既不在 180 条快照、也不在 `assets_local.json` | 已知，不阻塞；修法：复制并登记 `main_icon_exit.png` 后在主题 `icons.exit` 指向它（M2） |
| D7 | 订单区内容 | SALE/NEW 标签、罐子红点 3、两张订单卡、物品缩略图、资源徽章 | 单张订单卡（数据只有 1 单）、DONE 绿条、无 SALE/NEW/罐子 | 数据/内容级；布局槽位一致 |
| **D8** | **底栏文案/信息图标** | `Items name Lv.3` + 信息图标 | `LEVEL 1 / level_1` + 白色胶囊底，无信息图标（文本为程序化数据） | 已知，不阻塞（本轮新登记） |
| D9 | 背景台面起点 | 米色台面自 y≈386 开始 | 米色台面自 y≈400 开始（`main_bg_01_top` 覆盖 0–400） | 轻微 14px 差；蓝区起点两者均约 y=454 |
| **D10** | **静态棋盘截图带调试层**（复核 P2-6） | 无 | `output/board_1080x1920.png` / `m1_side_by_side_board.png` 右侧含 `LEVEL 1 / level_1` 与 `CHIP/GENERATOR/...` 图例（`src/view/board_view.gd` 的 `show_debug_labels` 默认 true；`game_screen.gd` chrome 模式已关闭） | 已知；读图时忽略该图层，或给 `tools/shot_board.gd` 加 `--no-debug-labels`（M2） |
| D11 | chip 本身的美术 | 三文鱼/肉/奶等 | 骨头/三文鱼卷/饼干 | **任务明确允许**，不视为偏差 |

> 复核报告同时引用：P2-1（README 旧数字）、P2-2（反例 26→25）、P2-3（货币图标"未登记"措辞）已在本轮文档收口中修正；P2-7（9 条本地登记）见 §5.2 清单；P2-8 已由本表归并关闭。

### M0 已知限制（收口登记）

以下为 M0 修复复核 `10_report/DS03/M0修复复核-1104.md` 确认、本轮不修的 P2 级残留：**不阻塞 M0 交付，列入 M1 待办**。同日 `10_report/CC02/M0修复复核-1104.md` 属 `02_Game` lane 的复核，无 03 未修项（其 P2-3 是同名不同项），不在本表登记。

| 编号 | 级别 | 残留 | 现状 / 兜底 |
|---|---|---|---|
| P2-3 | P2 | 成片端未消费 `camera` / `character_leave` / `character_next`：`src/core/event_model.gd:19-21` 注册 12 类 view 事件，`src/render/movie_scene.gd:562` 的 `_draw_view_layer()` 只画其中 9 类 | `character_leave` / `character_next` 预览端有实现（`src/view/fly_anim.gd:16,144-149`），缺的只有成片端；`camera` **两端都没有消费者**（全 `src/` 仅注册 `event_model.gd:20` 与注释 `movie_scene.gd:327`）。样片用到 `camera`（`sample_project.json:168`，24.0s，`payload.zoom=1.0`），被忽略不产生画面差异；另两类样片未使用 |
| NEW-1 | P2 | 订单**多件需求**与生成器**共享 `charges`** 未做联合容量扣减：`src/validate/rules_levels.gd:461-467` 逐条查 bucket 计数但**不扣减**，`:348-366` 把同一 `charges` 池对每个 `(chain, level)` 产出各计满额 → validator 假绿 | 出片阶段由 `tools/render.sh:180` 的 `TAKE_REFUSAL_RE`（`SCRIPT ERROR` / `[movie] rejected ` / `rejected=N>0`）拒绝该 take 兜底，不会交付坏片；只跑 strict 不出片的 CI 会漏过 |
| NEW-2 | P2 | `outputs[].level` **无校验也无诊断**：`src/validate/rules_levels.gd:283-290` 对非整数、越界只静默 `continue`，不产生 error/warning；只有 `rareOutputs.level` 有 `GEN_RARE_LEVEL`（`:212-219`） | sim 侧 `src/core/sim.gd:330` 用 `clampi(level, 1, _level_cap(entity))` 夹取，声明的产出等级可能被夹到实体上限后实际不可达（订单随之不可达） |

- 三项均属**校验器过松边界 / 表现层覆盖面**：不产生坏成片，也不改变本轮 25 条反例与 1753 checks 的结论；最小复现与修法建议见 `10_report/DS03/M0修复复核-1104.md`（P2-3 见 §3，NEW-1/NEW-2 见 §4）。
- 同一报告里的文档漂移 **NEW-DOC-1**（`tests/` 套件数 15 → 19，M1 又增至 20）已随 §2 目录树修正**关闭**，不再登记。
- `data/manifest_index.json` 已在 M1 按 v7 manifest **重建为 180 条**（`PRODUCTION 155` / `PLACEHOLDER 20` / `TODO 5` / `REFERENCE_ONLY 0` + 8 条别名，`snapshot_date` 由生成器写入当天）；详见 `10_report/DS03/M1实施报告-1105.md`。

## 7. 证据文件

| 文件 | 内容 |
|---|---|
| `output/accept.log` | 一键验收 9 步全量日志（ALL CHECKS PASS） |
| `output/tests.log` | 21 套件 / 1753 checks |
| `output/validation_report.json` | 样例工程校验报告（ok=true, 0 error, 0 warning, asset_refs=41） |
| `output/board_1080x1920.png` | 静态棋盘（7×9、4 种障碍、选中、完成）+ 真实 chip 图标（resolved 4/6） |
| `output/game_1080x1920.png` · `orders_panel.png` | 主游戏页（HUD+订单+棋盘，resolved 3/5）与订单卡特写 |
| `output/game_level2.png` · `game_levelup_banner.png` · `game_theme_pet_shop.png` | 第 2 关 / 过关横幅 / 换主题同帧 |
| `output/m1_icons_default.mp4` · `m1_icons_default.manifest.json` | M1 样片：300 帧（5s），default 主题带真实图标；manifest `assets=43`（2 字体 + 20 chip + 21 界面切图）`blocked=0` |
| `output/m1_icons_pet.mp4` · `m1_icons_pet.manifest.json` | 同一时间轴换 `themes/pet_shop`：`assets=2`（chip 走程序化），framemd5 与 default 不同 |
| `output/m1_frame_t2.6.png` · `m1_frame_pet_t2.6.png` | 两支样片同时刻抽帧，肉眼对照图标/配色 |
| `output/render.mp4` · `render_manifest.json` | 全片 30s / 1800 帧 / 单视频流成片 + 与之绑定的资源清单（frames/out/sha256） |
| `docs/PERF-BASELINE.md` | 性能基线（机器配置 + 实测耗时 + 判据） |
| `docs/AUDIT-S1.md` | 资源/可搬移/schema 独立审计 + 验收追记 |
| `docs/REVIEW-CORE.md` | core 层独立复审：7 项缺陷、修法、回归测试 |
| `docs/REVIEW-RENDER.md` | 出片/守卫独立复审：7 项缺陷、修法、验证证据 |
| `docs/REVIEW-02GAME.md` | 只读交叉审查 02_Game：422 checks 复现、3 项实质问题、3 处可借鉴 |
| `docs/evidence/` | 冻结证据（成片 / 逐帧 framemd5 / 两张 1080×1920 截图 / 订单卡 / 换主题 / manifest / accept.log + sha256 新旧对照） |

`output/` 与 `.godot/` 已 gitignore；本工程不产生 commit（由会话主人决定）。
