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

## 2. 目录

```
03_Game_ds/
├─ project.godot           1080×1920、stretch=canvas_items/keep；main_scene=game_screen
├─ assets/                 27 个载荷副本（20 张真实 chip 图标 + 2 个字体 + 5 个 PLACEHOLDER）+ PROVENANCE.md
│  ├─ chips/               icon_10002101..110（Ca Lv.1–10）、icon_10002201..110（Cb Lv.1–10）整字节复制
│  ├─ fonts/ · ui/         字体与 5 个 PLACEHOLDER
│  └─ PROVENANCE.md        出处/许可/尺寸/fit/sha256（含 M1 20 张表）
├─ data/
│  ├─ sample_project.json  schema v2 样例：2 关、7×9、21 条事件、30s
│  ├─ manifest_index.json  资源清单快照（180 条 + 8 条别名，id/usage/license/文件名，无绝对路径）
│  └─ themes/{default,placeholder,pet_shop}/theme.json
├─ src/
│  ├─ core/        event_model / rng / board_state / project_model / sim / sim_handlers / event_evaluator / state_digest
│  ├─ validate/    validator + 规则族（引用/等级/棋盘/时间轴/资源）
│  ├─ assets/      asset_guard.gd（usage 单点裁决 + 别名解析 + res:// 存在性两层）
│  ├─ view/        board_view / hud_view / order_panel / fly_anim / game_screen
│  ├─ theme/       theme_loader（theme > project > default；chip_icons 按 entity+level）
│  ├─ editor/      project_store / undo_stack / timeline_editor
│  ├─ render/      movie_scene / render_plan / render_manifest
│  └─ tools/       CLI、manifest 快照构建
├─ tests/          19 个套件（自动发现）+ 25 条反例夹具
├─ tools/          accept.sh / render.sh / framemd5_compare.sh / gen_fixtures.py / shot_*.gd
└─ docs/           AUDIT-S1.md、REVIEW-CORE.md、PERF-BASELINE.md
```

## 3. 资源口径（M1 / manifest v7）

`00_design/resource_manifest.json` 是唯一事实源（**180 条**）：`PRODUCTION 155` / `PLACEHOLDER 20` / `TODO 5` / `REFERENCE_ONLY 0`。`01_icon` 公司自研素材已全部登记为 `PRODUCTION`（license `公司自有/自研`），M0 的“原游戏切图一律不打包”红线因此变成**按需复制**：本工程只复制了 27 个载荷文件，其余 153 条记录一张都没进工程。

- `data/manifest_index.json` 由 `src/tools/build_manifest_index.gd` 生成，只保留 id/usage/license/文件名/尺寸，**不带绝对路径**，所以搬移后仍能执法。顶层另有 8 条 `aliases`：源 manifest 把 Ca/Cb 的 7–10 级按原始文件名登记为 `icon_10002107..110` / `icon_10002207..210`，别名把它们对齐成统一的 `chip_clean_*_lv07..10`（`AssetGuard` 的每个方法都识别别名，`entry()` 仍返回原记录）。
- 两层判定分开：`check_ref(id)` 看治理层（usage + `file_present`，即源文件是否在清单里存在），`local_path(id)` 看存在层（`res://assets/{ui,chips,fonts}/` 下是否真有这个副本）。**未复制**的 `PRODUCTION` id 会通过前者、返回 `""` 给后者——所以调色板之外的 8 条链图标“写进主题就能用”，但必须先复制。
- `REFERENCE_ONLY`（0 条）与 `TODO`（5 条音频）恒阻断；`PLACEHOLDER` 仅在 `--allow-placeholders` 且经 `AssetGuard` 放行时加载并写日志。
- 棋盘上的障碍 / 选中括角 / 完成态仍程序化绘制；chip 在主题给了 `chip_icons` 时画真实图标（fit=scale 居中，等级胶囊在上），没给时保持程序化圆角块。
- 出片时 `output/render_manifest.json` 记录实际使用的资源（字体 + 主题 `chip_refs()` 的全部 chip id + 画面用到的 `icons.ui` id）与 `blocked` 列表；git 只跟踪代码与数据，`output/` 是产物。
- **本地登记表** `data/assets_local.json`：v7 manifest 没登记、但 §20.5 画面要用的素材（`ui_bg_top`、`char_part1/part2`、`ui_items_bar`、`ui_board_frame` 等 9 条）在此登记为 `PRODUCTION` / `公司自有`，`AssetGuard` 载入时与快照合并，**快照记录永远优先**（本地同名记录会被拒并计数，`t_local_assets` 断言）。这 9 条已列入「待补登 00_design manifest」清单（见 §5.2 与本轮实施报告）。
- 载荷文件共 **48** 个：20 张 chip 图标 + 2 字体 + 5 个 PLACEHOLDER + 21 张 §20.5 界面切图。

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
| 两次出片 framemd5 一致 | ✅ | `accept.sh` 步骤 7：240 帧 `same=YES`，`0326f525…afcd9`（223 个唯一帧）；M1 样片 300 帧 `same=YES`，`37131e75…2f5`（default）/ `fa97320c…5a`（pet_shop） |
| 换 1 套主题 ≤10 分钟、不改代码 | ✅ | `accept.sh` 步骤 9：60 帧 default vs pet_shop，framemd5 `fb72776dd5b7` ≠ `633b46b48955`，sha256 也不同；300 帧样片同样不同（见下表） |
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

**与参考图仍存在的差异（已知，见 §6）**：格底多一圈"lip"边、棋子没有皇冠/角标态、生成器仍是程序化闪电方块（PSD 的箱堆图未导出）、`box24.png` 只作参考未使用。

**待补登 00_design manifest（9 条，`pending_manifest: true`）**：`ui_bg_top`、`ui_level_badge_bg`、`ui_icon_finish`、`ui_btn_plus`、`ui_button_shop`、`char_part1`、`char_part2`、`ui_items_bar`、`ui_board_frame`（最后一条同时是对 `board_frame` 的 usage 升级建议：v7 里它是 PLACEHOLDER，§20.5 要求容器在 strict 模式也可见，故本地以 `ui_board_frame` 指向同一文件、usage=PRODUCTION，并在记录里写了 `supersedes: board_frame`）。

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

### M0 已知限制（收口登记）

以下为 M0 修复复核 `10_report/DS03/M0修复复核-1104.md` 确认、本轮不修的 P2 级残留：**不阻塞 M0 交付，列入 M1 待办**。同日 `10_report/CC02/M0修复复核-1104.md` 属 `02_Game` lane 的复核，无 03 未修项（其 P2-3 是同名不同项），不在本表登记。

| 编号 | 级别 | 残留 | 现状 / 兜底 |
|---|---|---|---|
| P2-3 | P2 | 成片端未消费 `camera` / `character_leave` / `character_next`：`src/core/event_model.gd:19-21` 注册 12 类 view 事件，`src/render/movie_scene.gd:562` 的 `_draw_view_layer()` 只画其中 9 类 | `character_leave` / `character_next` 预览端有实现（`src/view/fly_anim.gd:16,144-149`），缺的只有成片端；`camera` **两端都没有消费者**（全 `src/` 仅注册 `event_model.gd:20` 与注释 `movie_scene.gd:327`）。样片用到 `camera`（`sample_project.json:168`，24.0s，`payload.zoom=1.0`），被忽略不产生画面差异；另两类样片未使用 |
| NEW-1 | P2 | 订单**多件需求**与生成器**共享 `charges`** 未做联合容量扣减：`src/validate/rules_levels.gd:461-467` 逐条查 bucket 计数但**不扣减**，`:348-366` 把同一 `charges` 池对每个 `(chain, level)` 产出各计满额 → validator 假绿 | 出片阶段由 `tools/render.sh:180` 的 `TAKE_REFUSAL_RE`（`SCRIPT ERROR` / `[movie] rejected ` / `rejected=N>0`）拒绝该 take 兜底，不会交付坏片；只跑 strict 不出片的 CI 会漏过 |
| NEW-2 | P2 | `outputs[].level` **无校验也无诊断**：`src/validate/rules_levels.gd:283-290` 对非整数、越界只静默 `continue`，不产生 error/warning；只有 `rareOutputs.level` 有 `GEN_RARE_LEVEL`（`:212-219`） | sim 侧 `src/core/sim.gd:330` 用 `clampi(level, 1, _level_cap(entity))` 夹取，声明的产出等级可能被夹到实体上限后实际不可达（订单随之不可达） |

- 三项均属**校验器过松边界 / 表现层覆盖面**：不产生坏成片，也不改变本轮 25 条反例与 1347 checks 的结论；最小复现与修法建议见 `10_report/DS03/M0修复复核-1104.md`（P2-3 见 §3，NEW-1/NEW-2 见 §4）。
- 同一报告里的文档漂移 **NEW-DOC-1**（`tests/` 套件数 15 → 19）已随 §2 目录树修正**关闭**，不再登记。
- `data/manifest_index.json` 已在 M1 按 v7 manifest **重建为 180 条**（`PRODUCTION 155` / `PLACEHOLDER 20` / `TODO 5` / `REFERENCE_ONLY 0` + 8 条别名，`snapshot_date` 由生成器写入当天）；详见 `10_report/DS03/M1实施报告-1105.md`。

## 7. 证据文件

| 文件 | 内容 |
|---|---|
| `output/accept.log` | 一键验收 9 步全量日志（ALL CHECKS PASS） |
| `output/tests.log` | 19 套件 / 1347 checks |
| `output/validation_report.json` | 样例工程校验报告（ok=true, 0 error, 0 warning, asset_refs=20） |
| `output/board_1080x1920.png` | 静态棋盘（7×9、4 种障碍、选中、完成）+ 真实 chip 图标（resolved 4/6） |
| `output/game_1080x1920.png` · `orders_panel.png` | 主游戏页（HUD+订单+棋盘，resolved 3/5）与订单卡特写 |
| `output/game_level2.png` · `game_levelup_banner.png` · `game_theme_pet_shop.png` | 第 2 关 / 过关横幅 / 换主题同帧 |
| `output/m1_icons_default.mp4` · `m1_icons_default.manifest.json` | M1 样片：300 帧（5s），default 主题带真实图标；manifest `assets=22`（2 字体 + 20 chip）`blocked=0` |
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
