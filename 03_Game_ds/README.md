# MergeGame M0 — Godot 工程（03_Game_ds）

M0 §9 全 9 步交付：**manifest/schema 校验器**、**core 模拟 + 事件求值器 v2**、**静态棋盘视图**、**订单/角色 + HUD**、**时间轴编辑器**、**出片流水线（Movie Maker + FFmpeg + framemd5）**、**主题映射**、**校验/自动保存/异常恢复**、**确定性与性能基线**。
目标引擎 **Godot 4.7.2 stable**，桌面 1080×1920@60。本目录**可整体搬移**：只用 `res://` 相对路径，不引用 `01_icon/` 原目录。

## 1. 命令

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"   # git-bash(MSYS) 路径；Windows 原样路径见 00_design/START-HERE.md

# 一键总验收（7 步：测试 / 校验 / 25 条反例 / 搬移 / 两张截图 / 出片确定性）
bash tools/accept.sh

# 全量测试（自动发现 tests/t_*.gd）
"$G" --headless --path . --script res://tests/run_tests.gd

# 校验一个工程（strict + 打印事件顺序）
"$G" --headless --path . --script res://src/tools/cli.gd -- \
  validate --project res://data/sample_project.json --strict --dump-order

# 截图（真窗口，不能 --headless）
"$G" --path . --script res://tools/shot_board.gd                        # 静态棋盘
"$G" --path . --script res://tools/shot_game_screen.gd -- --t=6.2       # HUD+订单+棋盘
"$G" --path . --script res://tools/shot_game_screen.gd -- --t=6.2 --theme=themes/pet_shop

# 出片（真窗口；中间产物 AVI，可 --keep-frames）
bash tools/render.sh                              # 全片 30s/1800 帧 -> output/render.mp4
bash tools/render.sh --frames 120 --determinism   # 2s 双次出片 + framemd5 对比

# 编辑器页（可独立启动）
"$G" --path . res://src/editor/timeline_editor.tscn
```

## 2. 目录

```
03_Game_ds/
├─ project.godot           1080×1920、stretch=canvas_items/keep；main_scene=game_screen
├─ assets/                 仅 7 个允许的复制品 + PROVENANCE.md（出处/许可/sha256）
├─ data/
│  ├─ sample_project.json  schema v2 样例：2 关、7×9、21 条事件、30s
│  ├─ manifest_index.json  资源清单快照（id/usage/license/文件名，无绝对路径）
│  └─ themes/{default,placeholder,pet_shop}/theme.json
├─ src/
│  ├─ core/        event_model / rng / board_state / project_model / sim / sim_handlers / event_evaluator / state_digest
│  ├─ validate/    validator + 规则族（引用/等级/棋盘/时间轴/资源）
│  ├─ assets/      asset_guard.gd（三种 usage 的唯一裁决点）
│  ├─ view/        board_view / hud_view / order_panel / fly_anim / game_screen
│  ├─ theme/       theme_loader（theme > project > default）
│  ├─ editor/      project_store / undo_stack / timeline_editor
│  ├─ render/      movie_scene / render_plan / render_manifest
│  └─ tools/       CLI、manifest 快照构建
├─ tests/          15 个套件（自动发现）+ 25 条反例夹具
├─ tools/          accept.sh / render.sh / framemd5_compare.sh / gen_fixtures.py / shot_*.gd
└─ docs/           AUDIT-S1.md、REVIEW-CORE.md、PERF-BASELINE.md
```

## 3. 资源红线（M0 §4）

`00_design/resource_manifest.json` 是唯一事实源（74 条）：`REFERENCE_ONLY` 47 / `PLACEHOLDER` 20 / `PRODUCTION` 2 / `TODO` 5（5 条音频未补）。

- `REFERENCE_ONLY`（原游戏 chip 图标 12、`obstacle_*`、`board_bg`、`slot_*`、`char_*`、`ui_*`）**一张都没有复制进本工程**；`AssetGuard.local_path()` 对它们恒返回 `""`，代码里拿不到可加载路径。
- 因此棋盘、chip、生成器、障碍、选中括角、完成块、HUD、订单卡、角色头像、过关横幅**全部程序化绘制**——既守版权红线，又保证脱离 `01_icon/` 也能启动出图。
- `PLACEHOLDER` 仅在 `--allow-placeholders` 且经 `AssetGuard` 放行时加载，并写日志；`TODO` 永远阻断；`PRODUCTION` 只有两个字体。
- 出片时 `output/render_manifest.json` 记录实际使用资源（当前仅两个字体，license=Noto Sans OFL 1.1）与 `blocked` 列表。

## 4. 数据 / 事件模型 v2 要点

- 关卡顺序 = `levels` 数组顺序，**无 `next`**（发现即 `LEVEL_NEXT_REMOVED`）。
- `entities` 声明 `kind`；`board.slots` 用 `entity`（旧 `chip` 键 → `SLOT_CHIP_KEY_LEGACY`）；`generators` 只存行为（混入实体字段 → `GEN_NON_BEHAVIOR_FIELD`）。
- 引用 ID 必须已定义；M0 等级上限 10；HUD 8 字段显式；`meta.duration` 不作为时长来源（`--strict` 升错误）。
- 事件：`channel = sim|view|audio`；`at` 绝对秒或 `{after, offset}`；排序 `at → channel → track → order → id`；**禁 `wait`**；锚点缺失/自指/环报错且不死循环。
- 校验器、预览、单步、离线出片**共用** `src/core/event_model.gd` + `src/core/event_evaluator.gd`，不存在"校验一套、播放另一套"。

## 5. 验收对照（M0 §7）

| §7 条目 | 状态 | 证据 |
|---|---|---|
| 30s / 1080×1920 / 60fps / 1800 帧 | ✅ | `ffprobe`：`1080x1920 / 60\/1 / nb_frames=1800 / duration=30.000` |
| 2 关可配置，完成第 1 关订单 → 过关 → 第 2 关 | ✅ | `t_sim` 越关断言 + `output/game_level2.png` |
| 订单完成：绿药丸 → 物品飞向角色 → 角色 → 金币/星星 → 新订单 | ✅（角色用溶解表现） | `output/game_1080x1920.png`(t=6.2)、`t_order_view` |
| 生成器：点击产出、稀有直出订单物品、棋盘满提示 | ✅ | `t_sim`（rare 进池条件、`SIM_BOARD_FULL`） |
| 选中提示：黄框 + 停留放大/靠近 | ✅ | `output/board_1080x1920.png`（黄括角 + 黄光 + 放大 8% 并向盘心偏移 7px） |
| 时间轴：锚点、同刻排序、预览/单步/渲染一致 | ✅ | `t_event_model` 排序用例 + 编辑器单步 + 出片共用求值器 |
| 资源守卫：REFERENCE_ONLY 无法出片；PLACEHOLDER 需显式 | ✅ | 25 条反例逐条命中 + `t_guard` |
| 校验：缺图/越界/不可达/usage 违规在出片前阻断 | ✅ | `output/validation_report.json`、`accept.sh` 步骤 2–3 |
| 两次出片 framemd5 一致 | ✅ | 全片 `10b138d4…4071`（1800 帧，A/B/第三次重跑三份一致，整条流水线 234s）；4s 短片 `d3b357db…ebfd`（240 帧，157 个唯一帧） |
| 换 1 套主题 ≤10 分钟、不改代码 | ✅ | `--theme=themes/pet_shop` → `output/game_theme_pet_shop.png`，零代码改动 |

## 6. 已知限制 / 与规格文字的偏差

1. **选中"停留放大/靠近"是静态量**：选中 chip 由 1.0 放大到 1.08 并向盘心偏移 7px，用几何表达"靠近"，没有 Tween 过渡——出片要求逐帧确定性，动画一律由帧号/事件时间算出，不做补间累积。
2. **角色消失**：用页面色溶解 + 收拢环表现，没有真正隐藏订单卡头像（FlyAnim 不反写 panel 状态）。
3. **主题覆盖面**：HUD/订单卡/横幅/底栏/画板边框随主题变；chip 与格子底色不随主题变（受"不改 board_view 行为"约束）。
4. `tap` 只支持 `{target:{slot:[x,y]}}`，旧文档的 `{generator:id}` 形式未支持。
5. 无按帧自动回能：能量只由 `energy_tick` 事件改变（确定性要求）。
6. 编辑器属性面板不做格子坐标编辑（只做错误定位）；折叠状态不持久化。
7. 并发跑出片会共用临时目录，需用 `RENDER_TMP_DIR=<dir>` 隔离（`accept.sh` 已隔离）。
8. 音频仍为 `TODO`（M0 不做）；帧级确定性只在本机验证，未做跨机验证。
9. **merge 限定 chip、`directOrder` 已实现（均已写入 M0 v0.20 §2.1.9/§2.1.10）**：非 chip 合并返回 `SIM_NOT_MERGEABLE`；`directOrder=true`（缺省）稀有产出只在该 `entity+level` 被未完成订单需要时进池，`false` 为无条件大奖。见 `docs/REVIEW-CORE.md` §4。

## 7. 证据文件

| 文件 | 内容 |
|---|---|
| `output/accept.log` | 一键验收 7 步全量日志（ALL CHECKS PASS） |
| `output/tests.log` | 15 套件 / 938 checks |
| `output/validation_report.json` | 样例工程校验报告（ok=true, 0 error, 0 warning） |
| `output/board_1080x1920.png` | 静态棋盘（7×9、4 种障碍、选中、完成） |
| `output/game_1080x1920.png` · `orders_panel.png` | 主游戏页（HUD+订单+棋盘）与订单卡特写 |
| `output/game_level2.png` · `game_levelup_banner.png` · `game_theme_pet_shop.png` | 第 2 关 / 过关横幅 / 换主题同帧 |
| `output/render.mp4` · `render_manifest.json` | 全片 30s / 1800 帧 / 单视频流成片 + 与之绑定的资源清单（frames/out/sha256） |
| `output/render_manifest.json` | 出片资源清单（id/usage/license/blocked） |
| `docs/PERF-BASELINE.md` | 性能基线（机器配置 + 实测耗时 + 判据） |
| `docs/AUDIT-S1.md` | 资源/可搬移/schema 独立审计 + 验收追记 |
| `docs/REVIEW-CORE.md` | core 层独立复审：7 项缺陷、修法、回归测试 |
| `docs/REVIEW-RENDER.md` | 出片/守卫独立复审：7 项缺陷、修法、验证证据 |
| `docs/REVIEW-02GAME.md` | 只读交叉审查 02_Game：422 checks 复现、3 项实质问题、3 处可借鉴 |
| `docs/evidence/` | 冻结证据（成片 / 两张 1080×1920 截图 / 订单卡 / 换主题 / manifest / accept.log + sha256） |

`output/` 与 `.godot/` 已 gitignore；本工程不产生 commit（由会话主人决定）。
