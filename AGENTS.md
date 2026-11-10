# AGENTS.md — 本仓库协作约束（长期记忆）

本文件是跨会话的持久约定，优先级高于临时话术；新会话开工先读这里。

> **硬规矩（2026-11-09 操作者亲自定，优先级最高）：改实机画面 = 同步改成片画面。**
> 游戏里看到的每一处（顶栏 / 订单带 / 棋盘 / 底栏 / 交付 / 金币 / 光标 / 拖拽 / 提示），
> 成片必须跟着一起变，而且要用**同一份数据、同一套组件**；改完必须出片比对并加对拍断言。
> 详见 §8「双画面同步」。

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

### 6.10 金币落点 = 顶栏图标（2026-11-09，两套顶栏并存的坑）

**症状**：金币螺旋的落点在成片里是写死的 `Vector2(473.6, 49.6)`，实机读的是
`hud.counter_center("coin") * 0.8 + hud.position` —— 同一组数，但**两个都在读一个看不见的控件**：
`hud_view.gd` 在 §20.5 chrome 模式下 `visible = false`（钱条由 `top_bar.gd` 画），
所以金币一直飞向一个隐藏控件的坐标，比顶栏里那枚金币图标的真实中心**偏右 15px、偏上 6px**。
这正是 §7.3 第 2 条禁的那类事：视图层猜坐标。

**做法（唯一来源）**：
1. `top_bar.gd` 新增 `fit_rect_for(key, rect)`（纯几何，不画）+ `COIN_ICON_RATIO`
   + `counter_center(key) -> Vector2`。比例**量自贴图**：`coin_bar.png` 里金币圆盘
   金色本体 bbox `(3,2)-(72,73)`，中心 `(37.5,37.5) / 255x82`。
2. 实机 `game_screen._coin_anchor(hud_local)`：有顶栏就问顶栏，没有才退回 hud_view 换算。
3. 成片 `movie_scene._hud_coin_anchor()`：**调同一个函数**；`_refresh_flight_anchors()`
   现在把 `_live_top` 也纳入前置判断，落点不再有任何字面量。

**验证（三层）**：
- 单测 `t_layout_parity._coin_anchor_matches`：落点 = `(458.785, 54.841)±0.1`、
  在金币条矩形内、在数字左侧、离旧硬编码 > 10px、成片锚点 == 顶栏锚点。
- 像素：成片 `frames/00040.png` 顶栏里那枚金币实测中心 `(459.0, 56.5)`，
  贴图比例映射出来 `(458.79, 54.84)`，差 1.7px（贴图带投影）。
- A/B 出片：同一 take 用旧硬编码再渲一遍，飞行中段金币整体左移约 7px
  （= 总位移 15.7px × lerp 比例），轨迹改动确实落在画面里。

**反向验证（照 §6.9 做，两处各一次）**：

```text
成片改回硬编码： FAIL t_layout_parity.gd :: 成片落点来自顶栏组件 [expected=(458.7852, 54.84165) actual=(473.6, 49.6)]
                FAIL t_layout_parity.gd :: 没有顶栏时不猜坐标 [expected=(0.0, 0.0) actual=(473.6, 49.6)]
                [tests] TOTAL checks=2523 failures=2

实机绕过顶栏：   FAIL t_layout_parity.gd :: 实机落点来自顶栏组件 [expected=(458.7852, 54.84165) actual=(592.0, 62.0)]
                [tests] TOTAL checks=2523 failures=1

恢复后：        [tests] TOTAL checks=2523 failures=0  RESULT PASS
```

**还没收口**：`hud:star` / `hud:gem` 仍来自隐藏的 `hud_view`（star 顶栏都没有对应控件）。
哪天真要画星星/钻石飞行，照本节的做法先量贴图再改，别再写死。

### 6.11 交付飞几枚 = sim 的 taken（2026-11-09，和 §6.7 同款的读数坑）

**症状**：2 行任务的订单（第 2 关 order_4 / order_5 / order_6）交付时**只飞一枚**，
第二枚棋子凭空不动，看起来像"完成任务但没飞"。

**根因**：`movie_scene._advance_to()` 里写的是 `r.get("taken", [])`，但
`evaluator.step()` 的报告把 sim 的返回字典**嵌在 `"sim"` 键下**，顶层只有
`ok / code / id / type / channel / at`。于是 `taken` 永远是空数组，成片每次都走
"飞被点击格"的兜底 —— 兜底只飞一枚。这和 §6.7 的 `payload` 是同一个坑，只是上次只修了 payload。

实机没这个问题：`game_screen._claim_from_cell()` 读的是 `sim.apply()` 原字典（`result["taken"]`）。

**修法**：`movie_scene.claim_taken(report)` 静态函数，从 `report["sim"]["taken"]` 取；
`_advance_to` 只调它。成片飞几枚从此只认这一份数据（§6.8 的规矩）。

**实测数据**（take `20261109_160815`，探针 `tools/probe_claim_taken.gd` 回放）：

```text
claim @ 2.611  order_1  TOP_taken=[]  SIM_taken=[[3,3]]
claim @ 10.624 order_4  TOP_taken=[]  SIM_taken=[[6,7],[0,7]]   ← 2 枚，原来只飞 1 枚
claim @ 16.358 order_2  TOP_taken=[]  SIM_taken=[[3,7]]
claim @ 19.944 order_5  TOP_taken=[]  SIM_taken=[[6,7],[1,7]]   ← 2 枚，原来只飞 1 枚
```

**验证**：新增 `tests/t_claim_flight.gd`（12 checks）：真 evaluator 跑一次 2 行任务交付，
断言 `claim_taken` 拿到 2 格、被点击格在内、两格不同；1 行任务只 1 枚；没有 sim 块不飞。
出片对比：帧 660 同时有两个移动体 `(743,631)` 和 `(377,871)`（一骨头一拐杖糖），
修复前只有一条轨迹从 `(962,1517)` 飞到 `(657,365)`。

**反向验证**：把 `claim_taken` 改回读顶层 →

```text
FAIL t_claim_flight.gd :: 2 行任务交付 → 飞 2 枚 [expected=2 actual=0]
FAIL t_claim_flight.gd :: 成片取的就是 sim 的 taken [expected=[[0,0],[2,0]] actual=[]]
FAIL t_claim_flight.gd :: 被点击的格子出现在 taken 里 [[]]
FAIL t_claim_flight.gd :: 1 行任务交付 → 只飞 1 枚 [expected=1 actual=0]
FAIL t_claim_flight.gd :: 只把 taken 放在顶层不算数 [expected=[] actual=[[1,1]]]
[tests] TOTAL checks=2532 failures=5
恢复后：TOTAL checks=2535 failures=0  RESULT PASS
```

**顺带记住**：交付取贴图时用的是 `_snap`（事件循环里还是上一帧，§7.2 #2）。
这批 take 里都取到了真实棋子；真遇到取不到的情况会退回订单图标 —— 要更稳就得让
sim 在 taken 里带 `entity/level`，属于改数据结构，别顺手改。

### 6.12 卡面装饰：绿对号与任务棋子（2026-11-09，操作者第一次改界面）

**操作者原话**：「这个红框的绿对号，先暂时给隐藏掉。然后把任务栏上的 clip 给缩小到正常尺寸。」

两条都在 `src/view/order_panel.gd` 里，成片托管同一组件 → **一次改两边都变**（§8 的正面例子）。

| 项 | 旧 | 新 |
|---|---|---|
| 绿色对号 | 无条件画（`confirm` 贴图 126×74 居中，或程序化绿胶囊） | `var draw_confirm_badge := false`，开关保留，随时能开回来 |
| 任务棋子 | `chip_size 125` + `draw_texture_rect(icon, chip.grow(6))` = **137 高**，卡片只有 140 → 顶边溢出 | `CHIP_SIZE 96` + `CHIP_GAP 14`，`mission_chip_rects()` 纯函数算出、垂直居中 |

**顺带清掉的重复实现**：`movie_scene._draw_orders()`（成片自己画卡片的旧代码，63 行）从未被调用，
但它里面也有一份绿对号和 125 的棋子图标 —— 正是 §8 说的"第二份"。连同 `MISSION_ICON` / `REWARD_ICON` 一起删掉。

**验证**：
- `t_layout_parity._card_decor_matches`：对号默认关（且开关能开）、`CHIP_SIZE == 96`、
  棋子矩形 96×96、单枚/两枚都不越出卡片、两枚不重叠、整体居中。
- 反向验证：`CHIP_SIZE` 改回 125 → 4 条红（`任务棋子 96 见方` / `留够留白` / `棋子矩形` / `两枚都不越出卡片`）；
  `draw_confirm_badge` 默认改回 true → 1 条红（`卡片绿对号默认隐藏`）；恢复后 2549 / 0。
- 两侧出图：实机 `output/orders_panel.png` 与成片 `frames/00400.png` 的任务带同形同尺寸。

### 6.13 订单卡改版：新任务栏底图 + 钻石奖励（2026-11-09，操作者第二次改界面）

**操作者原话**：「任务栏换成这个 icon（任务栏完整.png），记得归档。钻石.png 在新的任务栏底下
蓝色的地方，先居中加上钻石的 icon 和一个数字 Label。数字 Label 要活的，设在 Json 里。
扩展开，所有的任务栏都要这么改。并且默认数值是 1-5 左右，在 Json 里先随机一下。
任务完成后，钻石飞到最上面，数字跳动加上对应的数字。和任务栏飞金币一样。
要 lerp，要和金币一样的动画。」

**素材归档（§0 全流程）**：
`order_card_bar.png`（388×178，订单卡九宫格底图，贴图自带"上浅下蓝"两条）、
`gem_icon.png`（39×32，钻石图标）。1:1 复制（无裁切 → 无 `_source` 旁车），
登记了 manifest json/csv/xlsx（+2 条，230 / 233 行）、`assets_local.json`（+2，48 条）、
`PROVENANCE.md`、`LICENSES.md`、`data/themes/default/theme.json`（`order_card` / `gem` 两个槽位）。

**几何（唯一来源 → `layout_shared.gd`）**：
- `GEM_STRIP_RATIO = 0.279`（贴图上分界 124/178，九宫格角 26 不缩放铺到 250x140 后实测 39/140）
- `order_panel.mission_area_rect()` = 卡片去掉蓝条；`gem_strip_rect()` = 底部蓝条；
  `gem_icon_rect(card, text_w)` / `gem_label_rect(card, text_w)` = 图标+数字整组居中
- 成片**不许再写一份**：`game_screen` 与 `movie_scene` 都读 `Layout.GEM_STRIP_RATIO`
  （一开始试过在 movie_scene preload order_panel，直接踩到循环 preload，已改成共享常量）

**数据（可复现的随机）**：`sample_project.json` 每个订单加 `"gem"`，用固定种子 20261109
随机 1–5（order_1=2 / order_2=1 / order_3=4 / order_4=3 / order_5=5 / order_6=2）。
`rules_levels` 的奖励校验把 `gem` 一起纳入（必须 ≥0）。

**链路**：`sim._do_order_claim()` 与 coin/star 同一刻 `hud.gem += order.gem` →
`snapshot().orders[].gem` → `OrderRows.build()` 透传 → `order_panel` 卡片蓝条画数字；
交付后 `game_screen._play_gem_reward()` / `movie_scene._play_claim_effects()` 各播一次
`coin_spiral`（`anchor: "gem"`、贴图 = gem 图标），落点 `top_bar.counter_center("gem")`
（粉钻本体 bbox (2,2)-(73,60) → 比例 (37.5/246, 31/67)）；顶栏 `gem_display` + `gem_pop`
按金币那套 tick + lerp + 弹跳跳数字。

**踩到的两个坑**：
1. `movie_scene._ui("gem")` 返回 null —— `UI_KEYS` 白名单没有 `gem`，螺旋退化成金色圆点
   （看着像"钻石没飞"）。实机 `game_screen.UI_KEYS` 同样要加。
2. `order_panel._make_card()` 是字段白名单，`gem` 不加进去卡片就拿不到数（蓝条一片空白）。

**验证**：
- `t_sim`：`board-claim pays the order gems` + 快照带 `gem`（反证：关掉入账 → 1 条红）
- `t_layout_parity`：蓝条 0.30、贴底边、跨满宽、棋子不压蓝条、图标+数字整组居中；
  钻石落点实机 == 成片 == 顶栏组件给的坐标（反证：`_hud_gem_anchor` 写死 → 1 条红）
- 出片：帧 215 / 240 顶栏钻石 **99 → 100 → 101**（+2，与 order_1 的 gem 一致）；
  帧 208~216 画面里同时有金币螺旋和**粉色钻石螺旋**（3 枚带拖尾）
- 代理产物：`output/render/gem_fly2.mp4`（300 帧短跑，`same=YES`）
**三轮反馈修正（同日）**：
1. **钻石行"卡住下面"**：蓝条实测只有 39px（比例 0.279，不是最初估的 0.30），图标 1:1 居中时底边只剩 1~2px。
   修法：`GEM_STRIP_RATIO` 改 0.279、图标保持 **1:1（39×32，操作者明确不让缩）**、整组 `GEM_ROW_RISE = 4px` 上抬 →
   图标底边留白 4px、数字底边留白 7px。断言改成"不越出卡片 / 最多越过蓝条上沿 1px / 底边留白 ≥5px"。
2. **顶栏钻石数字字号**：`top_bar` 原来给宝石单独缩到 `digit_px * 0.56`（**改动前就在**，不是本轮加的），
   操作者要求"和闪电、金币保持一致"→ 三根条统一用 `digit_px`（实测 88 / 9 / 99 同高）。
3. **钻石螺旋反向**：与金币同屏时轨迹重叠。`fly_anim._spiral_point()` 增加 `spin`（+1 顺时针 / −1 逆时针），
   `_draw_coin_spiral` 透传；钻石事件带 `"spin": -1.0`。断言：同一 t 上横偏移相同、纵偏移镜像、两向不重合
   （反证：忽略 spin → 2 条红）。

### 6.14 订单卡再加体力奖励（2026-11-09，操作者第三次改界面）

**操作者原话**：「任务栏下面我还想加上闪电，跟钻石是一个逻辑。闪电在前，后面跟着一个数字。
钻石在后，后面也跟着一个数字。任务完成各自飞向上面对应的位置。闪电飞正螺旋和金币一样就行了。
数字也是要关联上涨。闪电的 icon 用这个（体力.png），记得归档。记得写成活的关联 Json，记得 lerp。
闪电先随机一下 30-100 之间。」→ 后续追加：「闪电和钻石加一起居中」「label 数字白底描边，
参考这个描边色」→「闪电后面的数字带颜色了，和钻石一样就行」。

**素材**：`energy_icon.png`（39×53，竖长）→ 归档目录 + manifest（+1，231 条 / 234 行）+ assets_local（49 条）
+ PROVENANCE + LICENSES + 主题槽位 `energy`。**payload 88**、guard 索引 229、主题 ui 键 57。

**几何（`order_panel.reward_row_rects(card, energy_w, gem_w)`）**：
两个图标统一按**高 32** 画（钻石 39×32 正好 1:1；闪电按 39:53 等比缩到 24×32），
组内图标-数字间距 6、两组间距 16，**两组一起**在蓝条里居中（total 不含最后一组后面的间距），
整组上抬 4px。返回 `{strip, energy_icon, energy_label, gem_icon, gem_label}`，某项为 0 时矩形为空、不画。

**数字样式**：白字 + 深蓝描边 `#304870`（**从操作者给的参考图上采样**），描边半径 2px，
画法 = 同一段字按 8 方向 + 4 对角偏移先铺描边色，再压白字（和顶栏倒计时同一手法）。
两个数字共用 `REWARD_LABEL_COLOR` / `REWARD_LABEL_STROKE`，`_draw_reward_pair()` 不再收颜色参数——
颜色只有一处，不会再出现"闪电那个是黄的"。

**数据**：`orders[].energy` 固定种子随机 30–100（order_1 53 / order_2 36 / order_3 92 / order_4 67 /
order_5 47 / order_6 84）；`rules_levels` 的奖励校验把 `energy` 一起纳入。

**链路**：`sim._do_order_claim()` 同一刻 `hud.energy += order.energy` → 快照 `orders[].energy` →
`OrderRows` → 卡片蓝条；交付后实机 `_play_energy_reward()` / 成片 `_play_claim_effects()` 各播一次
`coin_spiral`（`anchor: "energy"`、`spin: +1`、贴图 = 闪电），落点 `top_bar.counter_center("energy")`
（闪电 bbox (3,3)-(57,81) → 比例 (30/243, 42/90)）；顶栏 `energy_display` / `energy_pop` 逐格 tick + lerp + 弹跳。

**三个坑**：
1. `_make_card()` 白名单 + `sync_orders` 都要加 `energy`，否则卡片拿不到数（和 §6.13 的 gem 同一个坑）。
2. **`UI_KEYS` 两处都要加 `energy`**（实机 `game_screen` + 成片 `movie_scene`），否则 `_ui("energy")` 返回 null，
   螺旋退化成金色圆点——看上去像"闪电没飞"。
3. 体力奖励进账后 `t_sim` 的基线变了：`run_all` 结束 energy 85 → **174**、level_2 `charges` 85 → **138**
   （= 关卡切换时按当时体力初始化）。

**验证**：
- `t_sim`：`board-claim pays the order energy (10 + 40)` + 快照带 energy（反证：关掉入账 → 3 条红）
- `t_layout_parity`：两组奖励尺寸/顺序（闪电在前）/不越出卡片/底边留白/两组一起居中/只配钻石时自己居中/上抬 4px
- 出片：帧 214 三种奖励同时在空中（金币 + 闪电 + 钻石）；帧 260 顶栏体力 **88 → 141**（+53）、金币 9 → 14
- 代理产物：`output/render/energy_fly2.mp4`（300 帧短跑，`same=YES`）

### 6.15 任务图标扩到 4 个 + 两个新棋子系列（2026-11-09，操作者第四次改界面）

**操作者原话**：「把红框里的任务图标改成4个。随机不重复。相应的底下的任务栏围标也拉宽一些。
注意要扩展一下，后面的任务栏和小人儿向后靠，但是逻辑不变。类似这样，显示2个小人儿就差不多了。」
→ 追加：「顺便改一下Json吧。把第2关稍微复杂一点儿，clip再加2个系列，icon应该已经在工程里了，
你自己找一下。合成难度也提高一点儿。到4，5级随机分布。」
→ 再追加：「我让你改第2关，没让你改第一关。第一关恢复回去。第2关，分别改成4个任务，3个任务，
2个任务，1个任务，1个任务。顺便第2个降一降难度。」

**素材**：工程内 `01_icon/HotelManor_icon/棋子icon/` 本来就有 12 个系列 × 10 级，
项目只引了 `100021` / `100022`。新增两个视觉最不重复的系列：
`100011`（零食袋）→ `CleanSet_Cc`、`100051`（沙滩球）→ `CleanSet_Cd`，
各 10 级（182×182）复制进 `assets/chips/`，manifest +20（251 条 / 254 行）、
assets_local +20（69 条）、PROVENANCE +20 行、LICENSES、`theme.chip_icons` 变 4 个系列。

**任务数据（`sample_project.json`）**：
- **第 1 关保持原样**（1 个任务 Ca2 + 原棋盘 5 格）—— 操作者明确要求别动
- 第 2 关 5 单，任务数依次 **4 / 3 / 2 / 1 / 1**，单卡内不重复
- 难度：`order_3`（第 2 单、3 个任务）用第 **1/2 级**（降难度），其余用第 **4/5 级** × 4 系列
- 棋盘按"每次交付都付得起"补到 15 枚棋子 + 生成器（take 的 swap 起点/落点全部保留）

**布局**：`Layout.QUEUE_CARD_W 250 → 424`、`QUEUE_ORIGIN_X 250 → 208`、`VISIBLE_CARDS 3 → 2`；
`mission_chip_rects()` 改为**尺寸自适应**：`CHIP_SIZE(96)` 是上限，4 枚时按卡宽缩到 ~89，
1~3 枚仍是 96（老观感不变）。新增 `chip_size_for()` / `CHIP_MIN_SIZE` / `CHIP_SIDE_PAD`。

**校验器**：任务上限 2 → 4，并新增同卡内重复检查（`ORDER_MISSION_DUP`）。

**踩到的坑（重要）**：重复检查里写了 `String((raw_m as Dictionary).get("entity", ""))`，
`String(int)` 在 Godot 4 里直接运行时崩 —— 崩在规则模块里会**静默中断整段任务校验**
（abort gate 只认最后一行，函数中途崩掉不会再报 INTERNAL_SCRIPT_ERROR）。
表现是 `t_orders_reach` 的 N1 用例突然"没有 MISSION_ENTITY_TYPE"了。
改成 `str()` 即可。**记住：GDScript 里把任意值转字符串用 str()，别用 String()。**

**验证**：
- 探针回放该 take：4 次交付全 ok，`SIM_taken` 依次 1 / 2 / 4 / 1 枚（与任务数一致）
- 测试 **3192 checks / 0 failures**
- 出片：两张卡同屏，4 图标卡 = 4 个不同系列/等级，3 图标卡 = 降难度那单

### 6.16 立绘放大 + 第 1 关卡宽统一（2026-11-09，操作者第五次改界面）

**操作者原话**：「目前小人儿是不是下缘卡在任务栏上缘呢。现在任务栏已经变宽了。把小人儿也等比放大。
下缘和任务栏齐平，然后再被任务栏以及任务栏包含的那些 clip 之类的覆盖。总之，在任务栏下面，背景上面。」
→ 追加：「第一关的任务栏怎么没加宽呢？不应该是一样的么？」

**操作者第二张红框图才是准的**：立绘要**顶在顶栏下沿、下沿压到卡片底**（不是"下缘与卡顶齐平"）。
最终几何：
- `PORTRAIT_GROW = 1.43`（210 → **300**）
- `PORTRAIT_TOP_ABOVE_CARD = 160`：立绘头顶 = 卡片上沿 - 160（正好在顶栏药丸下面）
- `PORTRAIT_SINK = PORTRAIT_H - PORTRAIT_TOP_ABOVE_CARD`（= 140，这部分被卡面盖住）

**第 1 关与第 2 关现在**完全是同一套设计**：`order_panel` 只有一个 `_draw_card`、一套常量，
`_layout()` 里那条"单卡按 anchor 宽度"的特殊路径**已删除**（`set_card_anchors` 保留 API，
但不再参与几何）。第 1 关只是"配置了 1 张卡 + 1 个任务"。

**层级**：立绘由订单带画，带子现在是**顶栏之上**（`move_child(band, top.get_index()+1)` /
实机 `move_child(orders, top_bar.get_index()+1)`）——不然放大后的头顶会被金币/钻石药丸吃掉。
带子和顶栏在画面上不重叠，调顺序无副作用。

**顺带修掉的隐患**：`order_panel._draw_card()` 里立绘的 y 偏移原来写死 `26.0`，
和 `Layout.PORTRAIT_SINK` 是两份（§8 说的"第二份"）。现在读常量。

**验证**：
- `t_layout_parity`：单卡塞一个 190 宽的 anchor，卡矩形仍必须等于队列卡矩形（同宽同高同位置）；
  `PORTRAIT_H == 300.3`、`PORTRAIT_TOP_ABOVE_CARD == 160`
- 反向验证：把单卡分支改回按 anchor 宽度 → 1 条红；恢复后 2720 / 0
- 出片：第 1/2 关的卡完全一致；立绘头顶落在药丸下方、下沿被卡面盖住

### 6.17 任务棋子加 have/need 角标（2026-11-09，操作者第六次改界面）

**操作者原话**：「任务栏继续加逻辑，现在每个 clip 的小任务都要带上右下角的角标 Label。
格式就是数字/数字…收集程度要和任务绑定。Json 化配置。字体要用工程字体。
外面的包边颜色要参考图片上红框内的颜色。0/1 表示有一个没收集。1/1 表示任务已经收集完成。
收集完成之后字体要变颜色，字体包边的颜色也要变。」

**取色（从参考图采样）**：
- 未完成 `0/1`：字 `#FCFCFC`、描边 `#947450`（暖棕）
- 已收齐 `1/1`：字 `#B0FC74`、描边 `#508018`（深绿）

**三态（操作者最终口径：数字看交付，颜色看"能不能交"）**：

| 状态 | 数字 | 颜色 | 触发 |
|---|---|---|---|
| 还没这枚棋子 | `0/1` | 米白 + 暖棕描边 | 棋盘上没有同款 |
| 棋盘中已合出来 | `0/1` | **亮绿 + 深绿描边** | `ready`（CompletedCells 说这枚能付单） |
| 交任务之后 | `1/1` | 亮绿 + 深绿描边 | `have >= need`，或卡片处于 `claim_pending`（交付 hold 期） |

**实现**（都在 `order_panel` / `order_rows`，实机与成片同一份）：
- `mission_badge_rect(chip, text_w)`：右下角、内缩 `MISSION_BADGE_INSET = 6`，宽按字宽、高 `28 × 1.3`
- `mission_badge_done(have, need, ready)`：**纯函数**，决定绿不绿（`ready or have >= need`），便于断言
- `_draw_mission_badge(chip, have, need, ready)`：`"%d/%d"`，描边 8+4 方向铺一圈再压正文；
  字体 `_font_display()`（江城圆体 700W）
- 数字来自 sim：`orders[].mission[].have/need`；`ready` 来自 `OrderRows` 的 `_ready_keys(snap)`
  （棋盘上真的有这枚棋子）。**不新增视图侧计数**。
- `sync_orders()` 里 `done or claim_pending` 时把 `have` 抬到 `need` —— 交任务那一刻起就读 `1/1` 绿，
  但 sim 的 `have` 不改（纯显示推导，和 `_do_order_claim` 把 have 归零不冲突）

**为什么成片里也能看到三态**：第 1 关 take 在 1.86s 有一次合并（两枚 Ca1 → Ca2，正好是 order_1 要的），
所以帧 60 = `0/1` 棕、帧 130 = `0/1` 绿、帧 175（claim 之后）= `1/1` 绿。

**顺手修掉的一个大坑**：`t_local_assets` 里 `LOCAL_FILES[id]` 用下标取字典，缺条目会**运行时崩**、
整段循环静默中断 —— 之前 20 个新 chip 的 400 多条断言根本没跑过。改成 `.get(key, "<missing>")`
+ 先断言 `has()`，一崩变红；补条目后 checks 从 2720 涨到 **3138**。
**这类"下标取字典 + 静默崩"是本项目最容易骗过测试的写法，见到就改成 `.get`。**

### 6.18 任务完成：浅绿底板 + 绿色叹号（2026-11-09，操作者第七次改界面）

**操作者原话**：「追加逻辑，当任务完成的时候，比如 1/1 或者 2/2，右上角加一个绿色的小叹号。
icon 地址如下 `…/界面切图/main_icon_exclamation1.png`，记得归档。」→ 随后给了参考图。

**素材**：`main_icon_exclamation1.png`（52×52）→ 归档目录 `剩余图标/exclamation.png`，
工程副本**沿用快照里的文件名** `assets/ui/main_icon_exclamation1.png`。
⚠ 坑：v7 快照里**已经有** `ui_exclamation` 这条记录（`in_project=false`），
所以**不能**再往 `assets_local.json` 加同 id 的本地记录——guard 会把它记为 `local_override_rejected`
（t_local_assets 立刻红），而且贴图解析不到。正确做法：按快照的 `file_name` 放文件 + 把 `in_project` 翻成 true。

**两态底板都用贴图（2026-11-09 第二次追加）**：
- 完成 = `main_menu_frame1.png`（浅绿圆角框）→ `ui_mission_frame_done`
- 未完成 = `main_menu_frame2.png`（米色圆角框）→ `ui_mission_frame_todo`
两个都是 40×40，画的时候用**九宫格**（`_draw_nine` + 角 14），所以放大到 ~86px 时倒角不变形。
两个状态**底板一样大**（操作者：「一样的，和绿框一样大」），`mission_plate_rect(chip)` 里算一次：
横向各缩 6%、上方缩 10%，**底边贴着蓝条**。

**叹号的时机（操作者 2026-11-09 第三次修正）**：**只认"真收齐"**——
`mission_bang_visible(have, need)` = `have >= need`，所以 `0/1`（哪怕棋盘上已经合出来、底板已绿）、
`1/2` 都**不给**叹号；只有 `1/1`、`2/2`、`3/2` 这种才显示。
**底板/角标的绿色**仍然是 `mission_badge_done(have, need, ready)`（就绪就绿），
两套判定分开：绿色地板 = "能交"，叹号 = "已交"。

**叹号几何**：`mission_bang_rect(chip)` **以叹号的右下角为锚点**，
锚点落在底板左上角往里 `0.55 × 叹号边长` 处（约等于"叹号中心压住底板左上角"），
边长 `MISSION_BANG_SCALE = 0.40 × 棋子宽`，所以会**溢出底板**——参考图就是这么画的。
`MISSION_BANG_TOP_RIGHT` 改 `true` 可以整组翻到右上角（操作者文字说过右上角，图里是左上角）。

**素材归档**：两张 frame 都按 §0 走了全流程——
归档目录 `剩余图标/mission_frame_done.png` / `mission_frame_todo.png`，
工程副本沿用原名 `assets/ui/main_menu_frame1.png` / `main_menu_frame2.png`，
manifest（253 条 / 256 行）、assets_local（71 条）、PROVENANCE、主题槽位
`mission_frame_done` / `mission_frame_todo`。

**踩到的两个坑**：
1. `var plate` 在同函数里已经有一份（卡片底图那条），内层再声明直接 Parse Error —— 改名 `done_plate`。
2. `t_local_assets` 里 `LOCAL_FILES[id]` 用下标取字典，缺条目会**运行时崩**、整段循环静默中断
   —— 之前 20 个新 chip 的 400 多条断言根本没跑过。改成 `.get(key, "<missing>")` + 先断言 `has()`。

**验证**：
- `t_layout_parity`：叹号右下角收在底板左上角内 0.55 边长处、叹号**溢出**棋子、边长 = 棋子宽 × 0.40、
  底板比棋子小一圈
- 素材计数：payload **111**、guard 索引 251（strict 226 / loose 246）、主题 ui 键 **60**、
  validator 主题引用 **100**、`t_local_assets` 本地 id **71**
- 出片：帧 60 = 米色底板 + `0/1` 棕；帧 130 = 绿色底板 + 左上叹号 + `0/1` 绿
- 测试 **3192 checks / 0 failures**

### 6.19 第 2 关棋盘重排：柜子行不再压棋子 + 两排冰块（2026-11-09，操作者第八次改界面）

**操作者原话**：「第 2 关的 Json 好好配置一下。最下面的一排都和占位数的 Safe 重叠了呀。
多加几个 7*1 那样的盒子，加 2，3 个带冰块的。」→ 看到我加了 3 个 1x7 柜子后纠正：
「错了，加这个盒子。不是最下面的那个 Safe。」（配图是**冰块那个蓝盒子**）

**问题**：`safes: ["1x7"]` 按 `Safeboxes.layout` 钉在**最后一行**（y=8），而第 2 关的 6 枚棋子
也摆在 y=8 → 棋子和柜子占位重叠，画面上棋子"飘"在柜子上。

**改法**：
1. **棋子全部退出盒子行**：原来 y=7 / y=8 的 8 枚棋子搬到 y=3 / y=5 / y=2；
   现在 y=6 / y=7 是冰块行、y=8 是柜子行，棋子只占 y=0..5。
2. **两排"7×1 的冰块盒子"**：`obstacles` 里 `ice` 铺满 y=7 与 y=6 两整行（7×2 = 14 块），
   加上原来的 `web` + `lock`，第 2 关共 **16 个障碍**。
3. **`Safeboxes.layout` 支持多个 1x7**：原来 `sizes.has("1x7")` 只会放**一个**，多写的静默丢掉；
   改成按个数从最后一行往上叠（`["1x7","1x7","1x7"]` → y=8/7/6），两行盒子带的起点也跟着下移。
   （这一轮虽然最后没多用，但能力留着：以后要"多加几个柜子"直接写进 JSON 就行。）

**联动改动（不 hip 就会踩）**：棋盘一变，录制的 take 里第 2 关的落点全废了——
原来 swap/claim 都指向 y=7，那里现在是冰块行。做法是把 take 里第 2 关的
`to` / `src` 从 y=7 批量改到 y=4，再把踩到生成器格 (3,4) 的两个事件挪到 (3,5)
（`SIM_NOT_SWAPPABLE`），最后 `rejected=0`、4 次交付 `ok=true`、`SIM_taken` 仍是 1/2/4/1。

**验证**：
- 测试 **3192 checks / 0 failures**
- 探针回放：4 次 claim 全 `ok=true`
- 出片：第 2 关棋盘下半部分是「两排冰块 + 一排柜子」，棋子不再压柜子

### 6.20 任务行支持「要几枚」+ 第 1 关两个任务（2026-11-10）

**操作者原话**：「把第一关的任务栏配置成 2 个任务。」→「一个要 0/1，另一个要 0/2。」
—— 即**同一个任务行可以要 2 枚**，角标写 `0/2`、`1/2`、`2/2`。

**数据**：`sample_project.json` 第 1 关
`mission: [{CleanSet_Ca, level 2, count 1}, {CleanSet_Ca, level 1, count 2}]`。
棋盘不用动（3 枚 Ca1 本来就在，2 枚付 lv1 那行、合并出的 Ca2 付 lv1 那行），
take 的 claim 现在一次取 **3 枚**（`SIM_taken = [[3,3],[1,4],[5,5]]`）。

**改动链路（一处都不能漏，漏一处角标分母就退回 1）**：
1. `sim._make_order()`：任务行存 `need = max(count, 1)`（JSON 字段名 `count`，缺省 1）
2. `sim._unsatisfied_match()` / `_do_order_claim()`：按 `need` 逐枚结算——
   已交付的先记账，剩下的从棋盘取（`src` 优先、再行优先），取不够就报 `SIM_ORDER_UNSATISFIED`
3. `sim.snapshot()`：mission 行从 3 位扩到 4 位 `[entity, level, have, need]`
4. `order_rows._mission_slot()`：字典/数组两种形态都读 `count`，**快照里叫 `need`**
   （`m.get("count", m.get("need", 1))` —— 只读 count 的话成片里分母又变回 1）
5. `order_rows`：`ready` 改成**计数判断**（`_ready_keys` 由 set 变 count map），
   要 2 枚的任务必须棋盘上真有 2 枚才算"能交"
6. `order_panel._make_card()`：从关卡 JSON 建卡时 `need = max(count, 1)`

**验证**：
- 测试 **3192 checks / 0 failures**
- 探针回放：第 1 关 claim `ok=true`、`taken` 3 枚；第 2 关 4 次交付仍全过
- 出片帧 60：两张 clip 并排，角标分别是 **`0/1`（棕）** 和 **`0/2`（绿，棋盘上已有 2 枚 Ca1）**

**顺带记一笔**：`output/mov/` 被操作者的清理快捷方式清空过，录制原件已不在；
本轮用 `output/render/take_badge.take.json`（同一次录制的派生件）恢复了一份 take 到
`output/mov/20261109_160815/`，并重新做了第 2 关的落点迁移（y=7 → y=4、(3,4) → (3,5)）。

### 6.21 交付改成"一枚一枚交"（2026-11-10，操作者第十次改界面）

**操作者原话**：「点击 clip 右键，不再一起算所有的 clip 一起飞了，右键点一下只飞点击的 clip，
并优先飞第一个任务栏，没有了再飞第 2 个任务栏。」→「clip 交付要单独拖动到任务栏交付……
拖进去一个，就交对应的，并变换数字和颜色还有图标。如果 1/1 和 2/2 全都满足了，算交付完成。」
→「再加一个交付方法：右键点击任务栏对应已经变绿可以交付的图标，下面随机飞一个对应的 clip。」
→「拖到 0/2 这样变绿的才算交付完成，拖到 0/1 这样的再回去……范围就是底色的范围。」
→「顺便把第一关的 Json 里的 0/2 改成 0/4。」

**三个交付入口，都只推进"一行的一枚"**：
| 入口 | 行为 |
|---|---|
| 右键棋盘棋子 | 找**第一张**卡里还没收满的行（同系列同等级），只飞这一枚；都没有就不飞 |
| 拖到卡上 | 只认**底板矩形**（`mission_plate_rect`）里、且已经变绿的行；棕色/空白处 = 不收，棋子回原位 |
| 右键卡上的任务图标 | 同上命中规则，从棋盘**随机挑一枚**对应的，飞进那一行 |

**sim**：
- `_do_deliver` 支持 `payload.row` 精确指定行；返回 `row / have / need / settled`
- 每行都收满（`have >= need`）→ `_order_rows_full()` → `_settle_order()`：入账奖励、`done`、
  关卡完成标记，`out.settled = true`。**交付完成不需要再点卡**
- `_do_order_claim` 保留原样（没交满时仍可从棋盘取棋，兼容老 take 与老测试），入账部分抽成
  `_settle_order()` 与交付共用
- `snapshot()` 的 mission 行第 4 位是 `need`，`completed_cells` 也按 `need` 判断"这行还要不要"——
  不然交付一枚之后整行会被误判为已满足，棋盘上的同款棋子就不再变绿

**视图**：
- `order_panel.mission_row_at(point)`：命中区 = 底板矩形，**只返回绿色行**（棕色直接空）
- `order_panel.mission_row_center(order_id, row)`：飞行落点 = 那一行的底板中心（不是卡中心）
- 实机 `game_screen`：`_deliver_to()` 统一三个入口；`_deliver_target_for()` / `_random_cell_for()`
  负责选目标；`_play_deliver_flight()` 只飞一枚；`_after_settle()` 播放结算
- 成片 `movie_scene`：新增 `deliver` 分支（飞一枚到行中心）+ `_play_settle_effects()`
  （`settled` 时才播奖励/缩卡），与实机同一份数据

**数据**：第 1 关 `mission = [{Ca lv2, count 1}, {Ca lv1, count 4}]`；棋盘补到 6 枚 Ca1
（合并吃掉 2 枚后还剩 4 枚，正好付 0/4）。新补的两枚放在 (2,2)/(3,2)——**不能放在 lock 格子上**，
否则 `completed_cells` 把它们当"被障碍盖住"，`0/4` 会一直显示棕色。

**顺带修的"飘棋子"**（操作者看到第 2 关总有一枚 clip 飘来飘去，还带四个选中角标）：
交付/结算只清了 `ghost`，没清 `board.drag_chip_visible` 和 `_selected`——
被交走的那一格仍是"选中"，拖拽层又把棋子画在最后的位置上，看起来就是一枚飘着的棋子。
新增 `_clear_drag_art()`：`set_drag_state({})` + `drag_chip_visible = true` + `ghost.clear()`
+ `_selected = (-1,-1)` + `apply_state(selected/completed)`，拖拽交付、右键交付、拖到卡上结算三条路统一调它。

**验证**：
- 测试 **3205 checks / 0 failures**（新增：底板命中/棕色拒收/落点=行中心、逐行交付、自动结算、行号精确指定）
- take 改成"合并 → 5 次 deliver（1 枚 Ca2 + 4 枚 Ca1）→ level_next"，回放 `rejected=0`
- 出片：帧 130 = `1/1` 绿+叹号 与 `0/4` 绿；帧 168 = `3/4` 绿、第三枚在空中；帧 186 = 第二枚飞行中

### 6.22 交付落地统一动作 + 两个 Bug（2026-11-10）

**操作者报的 Bug**：第 1 关 `2/4` 明明棋盘上有对应棋子却一直是**棕色**（先绿过、合成掉之后又变褐，
再等生成器出新棋子也不变绿）。

**根因**：`ready` 写成了 `棋盘枚数 + have >= need` —— 2 + 1 = 3 < 4，所以永远不够。
**正解**：绿色 = **这一行还没收满（have < need）且棋盘上现在有 ≥1 枚对应的**；
"够不够凑满整行"不是绿色的判据（那一行可以继续一枚一枚交）。
`order_rows` 里改成 `int(slot.have) < need and int(ready_keys[key]) >= 1`。

**反向验证**：`t_order_rows` 用手搓的 snapshot（have=2 / need=4 / 棋盘 1 枚）钉死这条；
把公式改回 `have + 棋盘 >= need` → 1 条红，恢复后 **3205 / 0**。

**帧 1129 那枚"飘着的棋子"**：`TakeIo.drag_at()` 只要 `t` 落在整段 drag 采样的首尾之间就插值返回，
而采样只在真正拖拽的瞬间密集 —— 两次手势之间的空档会把**上一次拖拽的棋子**一直画在原地
（还带四边白角框）。修法：相邻样本间隔 > 0.25s 视为空档，直接返回 `{}`。
复检帧 1129：干净，没有残留。

**交付落地动作统一（A 方案，操作者拍板）**：
| 拍 | 内容 |
|---|---|
| 起飞 | 拖拽 → 从**松手点**；右键棋子/右键任务图标 → 从**棋子那一格** |
| 落点 | 那一行的**底板中心**（`mission_row_center`） |
| 落袋 | 底板 `1.10 → 1.00` 弹回（`order_panel.punch_row()`，0.18s） |
| 记账 | 角标 `have/need` 跟着变，颜色/叹号按三态刷新 |

时长统一按距离：`FlyAnim.deliver_duration(from, to) = clamp(距离/2400, 0.16, 0.42)`
（实机与成片共用同一个函数），短距离就是"啪"一下，远距离速度一致不拖沓。

**拖拽高亮**：拖动时指针落在可交付行 → 该行底板 `1.04` 微放大（`order_panel.set_hover_row`），
松手命中后回到 1.0 并接"吞一下"。不可交付的行不响应，避免无效拖拽。

**左键点卡整单结算 —— 已屏蔽（2026-11-10 操作者要求）**：
`game_screen` 顶部加 `const CLICK_CARD_CLAIMS := false`，两处调用点都挂上它：
1. `_free_click_at()` 里"点订单卡 → `order_claim`"那条（点一下就把整单的行全收掉）
2. 双击同一枚棋子触发 `_claim_from_cell()` 的那条
要恢复整单结算，把常量改回 `true` 即可。交付仍走三条逐枚入口（右键棋子 / 拖到卡上 / 右键任务格子）。

## 7. 接力须知（2026-11-09 收口，最新事实覆盖 §4 的旧数字）

**状态快照在 `03_Game_ds/docs/HANDOFF-2026-11-09.md`**，开工先读它；本节只记"规则"和"别再踩的坑"。

### 7.1 当前锚点

- 分支 `main` @ `d30574d`（tag `录屏内容基本完成` 仍在 4943b0e）：§6.10 金币落点 / §6.11 交付枚数 / §6.12 卡面装饰（a50ff3c）、§6.13 / §6.14 新底图 + 钻石 + 体力奖励（2465f32）、§6.15 / §6.16 4 个任务图标 + 两个新系列 + 立绘放大（a4a20d1）、**§6.17 / §6.18 / §6.19 角标三态 + 完成叹号 + 第 2 关棋盘重排（0df30ea）**、**§6.20 / §6.21 / §6.22 逐枚交付三入口 + 落地统一动作 + 三个 Bug（d30574d）** 均已提交；之后的改动按 §7.3-6 等操作者说「提」再提
- 测试 **3205 checks / 0 failures**（`t_sim.gd` 226、`t_layout_parity` 111、`t_claim_flight` 17）；`check_portability.ps1` blocking = none
- 玩 540×960 / 录 1080×1920（`stretch=viewport` + `window_width_override/height_override`）
- 一次录制 = `output/mov/<stamp>/`（take / film.mp4 / frames / manifest 同目录）

### 7.2 今天踩过的坑（每条都真金白银）

| # | 坑 | 后果 | 正解 |
|---|---|---|---|
| 1 | `evaluator.step()` 结果里没有 `payload` | `order_claim` 分支整段没执行：金币不动、hold 不存在、飞行不出 | 读事件本体 `ev.get("payload")` |
| 2 | `_snap` 在事件循环里是上一帧 | 跨关查订单拿错关卡（第 2 关用了第 1 关的表） | 用 `_evaluator.sim.level_index` |
| 3 | 交付只取"行优先第一枚匹配格" | 玩家点的格子不动（交了但没消失、绿框不退） | payload `src` 优先，回退循环加 `if found.x < 0` |
| 4 | 视图层自己按任务行数循环飞芯片 | 凭空多飞一枚、棋盘留一个 | 一切以 sim 返回的 `taken` 为准 |
| 5 | FlyAnim 没喂 `cell:x,y` 锚点 | 芯片从棋盘中心飞出来（看着像从 2×2/2×3 飞） | 每帧 `_refresh_flight_anchors()` 喂 63 个格心 + 订单卡中心 |
| 6 | 交付飞行画在父层 `_draw()` | 被订单带盖住（"一个在上面一个在下面"） | 飞行层 add_child 在订单带之后；成片自绘那份删掉 |
| 7 | 成片自绘 + 实机 FlyAnim 同时画 | 同一次交付两个芯片 | 只留一份（FlyAnim） |
| 8 | `canvas_items` + 内嵌窗口被钳到 1080×1061 | 成片发虚、AVI 只有 540 宽 | `stretch=viewport`，窗口尺寸靠 override |
| 9 | Godot 4 没有 `window/size/window_width` | 540 从来没生效 | 用 `window_width_override` |
| 10 | 内嵌窗口无视 `get_window().size` | 运行时改窗口无效 | 同上，靠 override |
| 11 | 自绘光标用 `get_local_mouse_position()` | 指针飘走 / 看不见 | 统一 `_mouse_canvas_point()`（窗口→画布换算） |
| 12 | 成片手型光标画在父层 | 被棋盘盖住，渲染里没手 | `FilmOverlay` 用自己的 canvas item 画 |
| 13 | `render.sh` 短跑没给 `--out` | 把成品 film.mp4 覆盖成 120 帧 | 短跑必须 `--out output/render/...` |
| 14 | `frames/` 里残留半截 PNG | ffmpeg 抽帧退 -22 | 抽帧前先清空 `frames/` |
| 15 | 大幅文件用正则盲改 | `Chrome._draw()` 被换成光标代码、编译报重名 | >500 行文件只用 read + 精确上下文 edit；脚本改要打印命中行 |
| 16 | 拿过期截图当证据 | 同一个 48px 反复测、白烧几十分钟 | 比对 mtime / 字节数变了才可信 |
| 17 | `output/` 下 PNG 被编辑器导入 | 每轮录制都触发导入、卡编辑器 | `output/.gdignore` |

### 7.3 规矩（不是建议）

1. **改 `src/core/` 必须配一条能反向失败的单测**，并亲手验证它会红（§6.9）。
2. **视图层不许猜数量/位置**：一律用 sim 的 `taken` / `spawn` / 快照。
3. **短跑不进成品目录**；完整出片才写 `output/mov/<stamp>/film.mp4`。
4. **先打数据再改代码**：涉及"从哪飞到哪"，先打印起点/落点/来源格子三个数。
5. **一次只改一个行为**：改完 编译 → 测试 → 一张图，再进下一个。
6. **不要自动提交**（2026-11-09 操作者定）：改完把代码**注释写清楚**、测试与出片跑完就停；
   `git commit` / `git push` 等操作者说「提」再执行。工作区留脏是常态，别自作主张清理。

## 8. 双画面同步（2026-11-09 操作者亲自定的硬规矩，优先级最高）

**一句话**：**我改实机（游戏里玩的那个画面）的任何东西，成片（`output/mov/<stamp>/film.mp4`）必须跟着一起改。**
两个画面是同一个产品的两种呈现，不允许"游戏里改了、片子里还是老样子"。

### 8.1 为什么这条必须成文

成片的四层界面（顶栏 / 订单带 / 棋盘 / 底栏）已经是**托管实机组件**（§6.2），
成片自己只负责：取快照、推进时钟、画光标/飞行/提示。也就是说：

- **几何**只有一份：`layout_shared.gd` + `top_bar.bar_rects()` + `bottom_bar` 常量；
- **数据**只有一份：`sim.snapshot()` / `sim.apply()` 的返回值；
- **动画起点/数量**只有一份：`taken` / `spawn` / `unlock`。

所以"改实机不用改成片"这件事**本来就不该存在**——真出现，就说明有人在成片侧自己算了一份，
那就是 §6.8 和 §6.10 / §6.11 那三个 bug 的成因。

### 8.2 改实机画面时的必做清单（缺一条都算没做完）

1. **问自己这一改会不会出现在成片里**：顶栏数字/布局、订单卡、棋盘棋子/高亮、底栏、
   光标、飞行、提示 toast、关卡切换 —— 只要会出现在画面里，就走完下面全部步骤。
2. **改共享来源，不改两份**：几何进 `layout_shared.gd`；顶栏几何进 `top_bar`；
   能复用的组件就让成片实例化它，**不要在 `movie_scene` 里再画一遍**。
3. **数据只从 sim 来**：`snapshot()` 缺字段就在 `snapshot()` 里加（实机与成片同时拿到），
   顺序是"先让 sim 快照带上这个数 → 两边一起读"，不是"成片自己算一个"。
4. **加对拍断言**：`tests/t_layout_parity.gd`（几何/锚点）、`tests/t_order_rows.gd`（行数据）、
   `tests/t_claim_flight.gd`（动画数量）—— 断言"实机 == 成片"，不是各自对一个常量。
5. **反向验证**：把实机这侧改动关掉 → 断言必须红（§6.9 同一套做法）。
6. **出片比对**：`bash tools/render.sh --take <take> --frames N --out output/render/xxx.mp4`
   抽帧看改动区域；确认无误再完整出片写回 `output/mov/<stamp>/`。
7. **文档留痕**：AGENTS 本节 + HANDOFF 的"待定/已收口"表同步更新。

### 8.3 判断"改了哪个画面"的实操办法

| 改的是 | 谁看得见 | 必做 |
|---|---|---|
| `src/core/**`（规则） | 两边 | 反向失败单测（§6.9）+ 成片抽帧 |
| `src/view/**`（组件） | 两边 | 对拍断言 + 成片抽帧（成片实例化同一组件） |
| `src/render/movie_scene.gd`（成片专属） | 只有成片 | 抽帧 + 说明实机对应行为是否也变了 |
| 数据 `data/*.json` | 两边 | 跑 `t_local_assets` / `t_sim` / `t_orders_reach` + 出片 |

成片专属的改动（比如只画在成片上的光标热点）也必须回答一句："实机里对应的是什么？"
如果实机没有对应物，说明这块是成片自绘的，写进文档别让人以为两边一样。

### 8.4 已经吃过亏的地方（都是"画面没同步"）

- §6.10 金币落点：成片写死坐标，实机读另一个控件 → 落点偏 15px；
- §6.11 交付枚数：2 行任务的订单成片只飞 1 枚 → 画面少了半拍；
- §7.2 #7：成片自绘 + 实机 FlyAnim 同时画 → 一次交付两个芯片。

**判据**：只要你在成片侧看到"又一个坐标/又一个数量/又一份文案"，
那它迟早会和实机分叉 —— 当场改成共享来源。
