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

### 6.3 库存点击进 take（2026-11-09）

`stockpile_tap` 现在是**一等 sim 事件**，录制/回放/成片全链路通：

1. `src/core/event_model.gd` 的 `SIM_TYPES` 里登记 `"stockpile_tap"`
   （不登记的话 take 校验会报 `EV_UNKNOWN_TYPE`，渲染 exit 3）
2. `src/core/sim.gd` 的 `snapshot()` 增加 `stockpile: {enabled, count, entity, level}`，
   实机与成片读同一份 → 成片里次数会跟着 take 里的点击递减
3. `movie_scene._sync_live_band()` 改成读 `_snap["stockpile"]`（原来读关卡配置，所以永远 9）

验证方式：往任意 take 的 timeline 里插 3 个 `stockpile_tap`（at 1.0/1.4/1.8），
`bash tools/render.sh --take <该 take> --frames 130`，抽 00010/00070/00100/00125 四帧的库存区域：
数字必须是 9 → 8 → 7 → 6。

### 6.4 2026-11-09 收口状态（未提交，等审）

已完成并验证：
1. **金币数字 tick（成片）**：order_claim 时把显示值压在交付前的数字上，按 amount/n 分批涨 + 数字弹跳。
   ⚠ 实测仍有偏差：take 里 claim 后快照金币瞬时 +N，电影端初次读到的 `_coin_display` 可能已被快照同步成 N，
   导致 `gained` 计算成 0、数字仍是一步跳到 14。修法已定位：在 claim 分支用 **claim 前** 缓存的显示值，
   或让 sim 在快照里同时给出 `coin_before_claim`。
2. **交付 1.55s hold（成片）**：`_live_band.hold_done(ord, 1.55)`，卡片等到金币起飞 1s 后才缩（帧序列已验证卡片延后消失）。
3. **拖拽回放**：未做（需要 take 记录 drag_trace，属于新数据结构；实机拖拽 ghost/白框/整排橡皮筋在成片里仍缺失）。
4. **光标按下反馈**：实机与成片都已用 `TakeIo.click_at` 的 PRESS_SCALE（原本就有，无需改动）。
5. **合成解锁动画**：代码已接（`board.unlock`），用一个 move+merge+claim 的合成 take 渲染验证过棋盘状态推进，但没抓到解锁那一瞬的放大淡出帧。
6. **交付飞行/金币螺旋**：代码已接（实机 FlyAnim），claim take 渲染时卡片延后消失说明时序生效，但空中飞行帧未抓到。

回归基线：`[tests] TOTAL checks=2500 failures=0`；`check_portability.ps1` blocking=none；
`bash tools/render.sh --take output/mov/take_20261106_162601.take.json --frames 90` → 1080x1920、md5 same=YES、
`output/mov/<stamp>/frames/*.png` 齐全。

未提交（操作者要求先审）。临时探针 take：`output/mov/take_fx_full.take.json`（move/merge/claim 三条事件），
可复现第 5、6 条的验证。

### 6.5 分辨率与录制目录（2026-11-09）

- **拉伸模式改成 `viewport`**（原来是 `canvas_items`）：
  窗口仍是 540x960 玩，但根视口固定 1080x1920，所以 Movie Maker 录出来是**真 1080 像素**；
  之前 `canvas_items` 下窗口被系统钳到 1080x1061，画布按 0.55 渲染再被放大，成片发虚。
  改完 `t_relocatable` 里对 stretch 的断言同步改成 `viewport`。
- **录制目录**：`_stop_recording()` 现在建 `output/mov/<时间戳>/`，take JSON 与成片都进这个目录：
  `output/mov/<stamp>/take_<stamp>.take.json`、`output/mov/<stamp>/film.mp4`，
  `render_take.gd` 再把 `frames/%05d.png` 与 `film.manifest.json` 放进同一目录。
  （需要一次真实按 R 录制来验证，静态代码已改。）
- 出片前记得用**当前存在的** take：`output/mov/` 下旧的 `take_20261106_*.take.json` 已被清掉，
  现在只剩 `take_20261109_121836.take.json`。

### 6.6 光标（2026-11-09）

- **坐标**：`stretch=viewport` 下窗口 540x960、画布 1080x1920，两者差 2 倍。
  统一用 `game_screen._mouse_canvas_point()`（`DisplayServer.mouse_get_position() - window_get_position()` 再乘 `vp/win`）；
  录制采样、点击命中、自绘光标三处共用，别再直接 `get_global_mouse_position()`。
- **成片里的手**：`movie_scene` 的 `_draw()` 画在**托管子组件之前**，手会被棋盘/订单带盖住。
  修法：新增内部类 `FilmOverlay`（最后 add_child 的 Control），用**它自己的 canvas item** 画：
  `host._paint_cursor(self)`；`_draw_cursor()` 保留给父层调用（内部转 `_paint_cursor(self)`）。
- 录制的 take 里 cursor 是 `[t, x, y]`（画布坐标）；旧 take（12:28 之前）坐标是坏的（x≈4560），必须重录。

### 6.7 金币 tick 定位（2026-11-09）

**根因**：`_advance_to()` 里所有分支都用 `r.get("payload")` 取事件参数，但 evaluator 返回的结果字典
**没有 payload 字段**（打印出来是 `<null>`）。于是 `order_claim` 分支里的 `src_raw` 永远为空，
整段（交付飞行、gold 计数、hold）从来没执行过 —— 之前"卡片延后消失"的观察其实是别的原因。

修法三条：
1. payload 从**事件本体**取：`ev.get("payload", {})`（`_advance_to` 里改 3 处）
2. 订单奖励金币用 **sim 当前关卡索引**查：`_order_coin_from_model(ord, int(_evaluator.sim.level_index))`
   （`_snap` 在事件循环里还是上一帧的关卡，跨关会查错）
3. 显示值下限夹紧：`_coin_display = minf(_coin_display, coin_after - gained)`
   （连续交付时不会把数字压回到旧值）

验证（真实 take `20261109_143132`，第 1 关 claim 1.36s）：
帧 114→120→126→134→150 金币数字 **9 → 11 → 11 → 13 → 14**（3 次 tick：1/2/2）。
第 2 关两次交付：**14 → 40 → 65**（+26、+25，与 `sample_project.json` 的订单奖励一致）。

### 6.8 成片动画不得多于 sim（2026-11-09，踩过的坑）

**原则**：成片的每一段动画，起点/数量/贴图都必须来自 **sim 真正消耗或产生的那一份数据**，
绝不能在成片侧"按任务行数猜"。

反面案例（我自己写出来的 bug）：
为了让「两行任务的订单飞两枚芯片」，交付飞行改成按 `mission.size()` 循环、
用 `_cell_for_item()` 在棋盘上"找一枚匹配的棋子"当起点。结果：

- `sim._do_order_claim()` 里 `have >= 1` 的任务行标成 `delivered: true`，**不会 `board.take()`**
- 成片却照样给它找一枚飞出去 → **凭空多一枚**，棋盘上那枚原地不动
- 留下的棋子仍匹配未完成任务行 → **格子一直绿**（看起来像"交付没生效"）

正确做法：实机 `_claim_from_cell()` 一次交付只飞**一枚**，
起点 = 被点击的格子，贴图 = 该格子的实际棋子（`_item_at_cell`），落点 = `_live_band.card_rect(id)` 中心；
被消耗的棋子由 sim 的 `board.take()` 消失，绿框随之消失。

已删除不再使用的 `_order_mission()` / `_cell_for_item()`。

**同源教训（同一天）**：`_advance_to()` 里 payload 必须从**事件本体** `ev` 取，
`evaluator.step()` 的结果字典里没有 payload（见 §6.7）。

### 6.9 反向验证（2026-11-09，操作者要求写死）

**规矩**：凡改动 `src/core/` 里的规则逻辑（sim / event_model / take_io），
必须同时补一条**能反向失败**的单元测试，并在提交前亲手验证它会红：

1. 写测试 → 跑一遍确认 PASS
2. **把修复临时关掉**（`if false and ...` 或改回旧逻辑）→ 跑一遍，确认这条测试 FAIL，并记下失败输出
3. 恢复修复 → 再跑一遍，确认全绿

只写"能过"的测试不算数；抓不住原有 bug 的测试等于没写。
本轮实测样例（点击格交付）：

```text
关掉修复： FAIL t_sim.gd :: the clicked cell is consumed
           FAIL t_sim.gd :: the earlier row-major match is left alone
           [tests] TOTAL checks=2509 failures=2
恢复修复： [tests] TOTAL checks=2509 failures=0  RESULT PASS
```

现有钉死的用例：
- `_test_claim_consumes_the_clicked_cell`：交付必须消耗"被点击的那一格"
- `_test_claim_reports_consumed_cells`：交付要把被消耗的格子回报给视图层

**配套规则（同一天踩的坑）**：交付飞行的数量 = `sim` 返回的 `taken` 数量，
不再由视图层按任务行数猜；2 行任务的订单就是 2 枚、各自从自己的格子起飞（实机与成片同一份数据）。
