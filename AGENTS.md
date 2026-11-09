# AGENTS.md — 本仓库协作约束（长期记忆）

本文件是跨会话的持久约定，优先级高于临时话术；新会话开工先读这里。

> **长期记忆载体 = 本文件**（2026-11-04 起）。`deja` 长期记忆已由操作者关闭：**不要调用 `deja_remember`**，它只会返回 `deja did not record that.`（本机 `~/.deja` 存储也不存在）。要沉淀经验，直接写进本文件，写入即对后续会话生效。

## 0. 新素材归档与登记（长期约定，2026-11-05，操作者明确要求）

操作者给的新素材，**不管来自哪个外部目录**（如 `E:\北京Icon\常用资产汇总\...`），默认落到：

```text
E:\MergeGame-Claude\01_icon\HotelManor_icon\剩余图标\
```

缺任何一步都算没做完：

1. **命名**：小写 `snake_case`、语义化英文名（`cursor_hand.png` / `board_plate.png` / `cell_light.png`），不保留中文原名。
   需要裁切/去背/缩放的，原图另存 `<name>_source.png` 放同目录。
2. **登记**：`00_design/resource_manifest.json` 增/改记录（id / category / usage / license / file / target_size / actual_size / fit / notes）
   → 同步 `00_design/resource_manifest.csv` 与 `00_design/资源清单模板-v8.xlsx`（第 4 行起的数据行，18 列）。
3. **工程副本**：进 `03_Game_ds/assets/{ui,chips,fonts}/`；`03_Game_ds/assets/PROVENANCE.md` 记 sha256/来源/许可；
   快照没有的 id 还要进 `03_Game_ds/data/assets_local.json`；许可说明补进 `01_icon/HotelManor_icon/剩余图标/LICENSES.md`。
4. **口径**：`03_Game_ds` 只引用 `res://assets/**` 的副本，不直接引用 `01_icon`；`assets/` 下每个文件都必须被登记
   （`t_relocatable` 是精确计数，多一个少一个都红）。
5. **验证**：`godot --headless --path 03_Game_ds --script res://tests/run_tests.gd`，并按需更新 README 数字。

已按此规则归档：`cursor_hand.png`（+`cursor_hand_source.png`）、`board_plate.png`（+`board_plate_source.png`）、`cell_light.png`。

## 1. 核验类工作不要外派子代理

**结论：数字核对、复核报告对照、提交前验收，一律主会话自己做。**

依据（2026-11-04，03_Game_ds M0 收口）：

| 方式 | 实测耗时 |
|---|---|
| 主会话 `run_tests.gd`（21 套件 / 1931 checks） | 约 1.9 s |
| 外派「核验」子代理（各自重跑全量套件 + 通读 300+ 行复核报告 + 写 190 行长报告） | 各约 20 分钟才返回 |

慢因不是工具慢，而是子代理每一步工具调用都是一次完整模型回合，加上「跑引擎 + 读长文档 + 写长文档」三重负载。**只有真正可并行、且不需要跑引擎的独立调研才外派**；外派时把「不要跑全量套件」写进任务书。

## 2. 怀疑子代理卡死前，先查进程证据

Windows 上 `--headless` 的 Godot **本来就没有窗口**，看到「Godot 没开」不代表没在跑。上一轮复核会话常留下僵尸进程：

```powershell
Get-CimInstance Win32_Process -Filter "Name LIKE '%Godot%'" |
  Select-Object ProcessId, CreationDate, CommandLine
```

判据：**进程 CreationDate 早于本次派发时间 → 不是本届子代理拉起的**，别误判归因（2026-11-04 就误判过一次：4 个 `ds02_review\A\probe_*.gd` 是上一轮 02_Game 复核的遗留）。

## 3. pwsh 会吞空字符串参数

`03_Game_ds` CLI 用 `--out ""` 表示「不写报告文件」。在 PowerShell 里这个空串会被吞掉，报 `[cli] flag without value: --out` 并 `exit 2`，**看着像校验失败**。要么用 git-bash 传 `--out ""`，要么给非空路径（如 `output/validation_report.json`，已 gitignore）。

## 4. 本轮已验证的事实锚点（03_Game_ds，2026-11-05）

- 套件 **21** / checks **2304** / failures **0**（`t_local_assets` 418、`t_free_mode` 98、`t_sim_defects` 48）。
- 反例夹具 `tests/fixtures/broken/*.json` = 25 个。
- `00_design/resource_manifest.json`：**224 条**（`PRODUCTION 165` / `PLACEHOLDER 20` / `TODO 5` / `REFERENCE_ONLY 0`）；
  `03_Game_ds/data/manifest_index.json` 仍是 **v7 的 180 条**（M2 重建），工程靠 `data/assets_local.json` 的 **42 条**本地记录补齐。
- `03_Game_ds/assets/` 载荷 **81** 个：20 chip + 2 字体 + 5 PLACEHOLDER + 21 界面切图 + 1 光标 + 2 棋盘底/亮格 + 1 退出按钮 + 3 底栏素材 + 生成器图标 + 体力闪电 + 底栏分隔线；`PROVENANCE.md` 是唯一出处表。
- 出片：`bash tools/render.sh --take output/mov/take_<时间戳>.take.json`，1080×1920@60，双跑 framemd5 相同；游戏内按 R 停止会自动在后台出片到 `output/mov/`。
- 长期记忆不依赖 deja（已被操作者关闭）：经验写本文件，不写 `deja_remember`。

## 5. 订单队列（进行中，2026-11-06）

- 队列机制已在 `order_panel.gd`：多卡时等间距横排（卡宽 250 / 间距 18）、只渲染前 3 张、`set_row_offset()` 整排位移；
  `game_screen` 负责推拽（阈值 12px、阻尼 0.55）与松手回弹（每帧 0.22 缓动）；完成卡按 `DONE_SHRINK=0.35` 缩放消失后从 `cards` 移除并重排。
- **尚未切换数据**：`data/sample_project.json` 第 2 关仍是 1 个订单。改成 5 个订单时，必须同步改：
  `tests/t_sim.gd`（领单后的 coin/star/level_complete_pending/剩余棋子）、`tests/t_orders_reach.gd`（多订单可达性）、
  `tests/t_order_view.gd`（cards.size()==5）。
- 5 个订单样例（任务不重复、≤2 任务、金币 20–30）：
  Ca2 / Cb2 / Ca1+Cb1 / Ca2+Cb1 / Cb2+Ca1，金币 25/22/26/30/20，人物 char_01/char_02 交替。
- 待做：每张卡带自己的小人头像；完成时小人一起缩放消失（目前只缩卡片）。

## 6. 渲染收口（C/A 完成，B 待做）2026-11-06

- **出片目录**：每次渲染一个时间戳目录 `output/mov/<YYYYmmdd_HHMMSS>/`，里面放
  `film.mp4`、`film.manifest.json`、`frames/%05d.png`（1080x1920 PNG 序列）。
  `tools/render.sh` 默认输出即此结构；`tools/render_take.gd` 同样会补 PNG 序列。
- **窗口尺寸坑**：`window/size/window_width_override` 会盖掉命令行 `--resolution`，
  出片会被压成 540 宽。已改成普通 `window/size/window_width=540/height=960`，
  这样 F5 仍是 540x960，而 `--resolution 1080x1920` 生效。
- **C（对拍护栏）已完成**：`tests/t_layout_parity.gd`，断言实机/成片/库存面板
  三方几何常量与 `Layout.card_rects()` 逐张矩形一致，共 40 checks。
- **A（共享布局）已完成**：`src/view/layout_shared.gd` 是唯一几何来源
  （QUEUE_ORIGIN_X 250 / QUEUE_CARD_W 250 / CARD_GAP_X 18 / CARD_H 140 /
  PORTRAIT_H 210 / PORTRAIT_SINK 26 / STOCKPILE_RECT），
  `order_panel.gd`、`movie_scene.gd`、`game_screen.gd` 均改为引用它。
- **B（成片直接跑实机界面）未开始**：可行方案已探明——`order_panel.gd` 的
  对外 API（`set_asset_theme/set_palette/set_metrics/set_clock/build_from_level/sync_orders`）
  足够让成片把订单带交给实机组件渲染，位置 `ORDER_RECT.position=(0,210)`、尺寸 1080x250。
  需要一并解决：snapshot.orders 到 sync_orders 行格式的转换（实机是
  `_order_rows_with_ready`），以及去掉成片自己的 `_draw_characters/_draw_orders`。
  验收方式：`bash tools/render.sh --frames 60` 出片 + PNG 逐帧对比。

### 6.1 B 第一增量（已完成，2026-11-06）

成片不再自己画订单带 —— `movie_scene` 里实例化实机的 `order_panel.gd`：
`_live_band.position=(0,210)`、`size=(1080,250)`、`set_palette/_metrics/set_asset_theme`，
每帧 `set_clock(_t)` + `sync_orders(OrderRows.build(_snap, _model))` + `set_stockpile(...)`。

- `src/view/order_rows.gd` 是 **snapshot → sync_orders 行的唯一转换处**（字典行，
  `mission:[{entity,level,have,need,ready,hue,label}]`），实机与成片共用；新增 `tests/t_order_rows.gd`。
- `order_panel` 新增两个开关：`draw_portraits`（成片关掉，立绘仍由成片画，保持"顶栏压在头发上"的层级）、
  `draw_page_strip`（成片关掉，成片自己画背景；开着的实机底条会盖住立绘下半身）。
- `layout_shared` 的矩形改为**页面坐标**语义：`BAND_Y=210`、`CARD_LOCAL_Y=55`，
  `card_rect(i)` 返回页面坐标；面板是局部坐标，比对时 +BAND_Y（`t_layout_parity` 已断言）。
- 验收：`bash tools/render.sh --take ... --frames 60` → 1080x1920、md5 双跑一致、
  `output/mov/<stamp>/frames/*.png` 与实机 `band_live.png` 逐元素一致
  （立绘位置/卡片 250 宽 x=250/库存面板 9+箭头）。

**尚未收口**：顶栏、底栏、棋盘仍由成片自绘（与实机有细微差异，例如倒计时位置）；
库存面板在成片里显示的是关卡配置次数，不跟随 take 里的点击（take 未记录 stockpile_tap 回放）。

### 6.2 B 全部收口（2026-11-09）

成片的四层界面全部改成托管实机组件，`movie_scene` 只负责：取快照、推进时钟、画光标/飞行/提示。

| 层 | 组件 | 挂载位置 |
|---|---|---|
| 顶栏 | `src/view/top_bar.gd`（新建） | (0,0)，1080x150 |
| 订单带 | `src/view/order_panel.gd`（复用） | (0,210)，1080x250 |
| 棋盘 | `src/view/board_view.tscn`（复用） | (0,0) |
| 底栏 | `src/view/bottom_bar.gd`（新建） | (0,0)，1080x1920 |

关键开关/坑：
- 子节点绘制在父 `_draw()` 之后，所以棋盘会盖住父层画的立绘 —— 立绘改由**订单面板**画
  （`draw_portraits=true`），面板在棋盘之上、顶栏之下，正好复现实机层级。
- 面板的 `draw_page_strip` 在成片里必须 false（实机那条不透明底条会盖住立绘下半身），
  背景由成片的 band/背景层提供。
- `board_view.show_debug_labels = false`，否则成片会露出 "LEVEL 1 / level_1" 调试字样。
- 顶栏倒计时算法两边一致：`1800 - (floor(时钟) % 1800)`。
- 底栏文案/几何常量来自 `FilmLayout`（= `movie_scene.gd` 的布局表），`bottom_bar.gd` 直接 preload。

验收：`bash tools/render.sh --take ... --frames 60` → 1080x1920、md5 双跑一致；
`output/mov/<stamp>/frames/00040.png` 与实机截图逐区域对比一致（顶栏/订单带/棋盘/底栏）。
测试：2500 checks / 0 failures（新增 `t_layout_parity` 顶栏黄金值断言）。
