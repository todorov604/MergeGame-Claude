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

### 6.9 历史细节索引（§6.9~§6.23 已归档）

> 细节见 `docs/notes/agents-archive-6.09-6.23.md`。下面是**现在仍然有效**的结论：

- **卡片奖励条（§6.13/§6.14）**：蓝条 `GEM_STRIP_RATIO = 0.279`；钻石 39×32、体力按高 32 等比；
  数字白字 + 描边 `#304870`；`reward_origin(order_id, kind)` 从**这张卡自己的**图标起飞。
- **卡与任务图标（§6.15）**：`QUEUE_CARD_W 424`、`QUEUE_ORIGIN_X 208`、`VISIBLE_CARDS 2`；
  卡内最多 4 个任务图标，尺寸自适应（`CHIP_SIZE 96` 是上限）。
- **立绘（§6.16）**：`PORTRAIT_H 300.3`、`PORTRAIT_TOP_ABOVE_CARD 160`；第 1 关与第 2 关同一套几何。
- **角标（§6.17/§6.18）**：未满 `#FCFCFC/描边 #947450`、可交/已满 `#B0FC74/描边 #508018`；
  底板两态用贴图（`mission_frame_done/todo` 九宫格）；小叹号 `MISSION_BANG_SCALE 0.40` 溢出底板左上角。
- **任务行 count/need（§6.20）**：JSON 写 `count`，快照第 4 位是 `need`，
  `order_rows._mission_slot()` 两种形态都读；漏一处分母就退回 1。
- **第 2 关棋盘（§6.19）**：y=6/7 两排冰、y=8 柜子行，棋子只占 y=0..5。
- **交付三入口（§6.21/§6.22）—— 已停用**：拖到卡、右键棋子、右键任务行都注释掉了
  （2026-11-10 改版，现只认大绿底对号，见 §6.28/§6.29）；`ready` 判据 = “这行还没收满且棋盘有货”；
  拖拽交付不播棋子飞行；`_clear_drag_art()` 三条路统一清拖拽残影。
- **交付观感（§6.23）**：飞行时长 `FlyAnim.deliver_duration = clamp(距离/2400, 0.16, 0.42)`；
  光标按下 `PRESS_SECONDS 0.22 / PRESS_SCALE 0.80` + 下沉 7px，拖拽期间保持按下；
  **先画手、后画点击涟漪**；奖励必须从交付的那张卡起飞。


### 6.24 炸开范围可配 + 蓝盒子变成网/冰（2026-11-10）

**操作者原话**：「相邻合并炸开的范围不在是上下左右4个了，需要在Json里配置一下。1是上下左右。2是再向外扩一层」
→「图2的蓝盒子现在改一下类型，和那个问号的袋子一样。不过固定随机出2种类型，蜘蛛网+随机物品（被网扣住）、
冰块+随机物品（有倒计时，随机范围10分钟以内5分钟以上）」→「问炸的地方怎么先闪了一下问号袋子，这个不需要」。

| 项 | 做法 |
|---|---|
| 炸开范围 | 级别 JSON 新增 `blast`（夹 1–3），`sim.blast_radius()` 读它；`_unlock_neighbours()` 按 `\|dx\|+\|dy\| <= blast` 遍历（**菱形**，和操作者画的红框图一致） |
| 蓝盒子 `lock` | 砸开后**二选一**：`web`（网扣棋子）或 `icebox`（冰 + 5:00–10:00 倒计时），hash 用高位混（`(x*73856093 ^ y*19349663) >> 5`），局部不会整片同一种 |
| `icebox` | 新障碍 kind。**必须加进 `board_view.OBSTACLE_TYPES`**，否则 sim 已挡住、画面空白还拖不进去（操作者报的"炸开什么都没有"） |
| 解锁闪光图标 | `unlock(cell, kind, at, became)`：`kind=="box"` 时闪**它变成的东西**（网/冰），不再是 `UI_SAFE_UNKNOWN` 的问号袋子 |
| 障碍同步 | 成片每帧 `_live_board.set_obstacles(snap.board.obstacles)` —— 以前只在换关时 `build_from_level_data`，运行时解锁根本不会反映到画面 |

**验证**：`tools/probe_blast.gd` 回放真实合并（level 1，(2,2)→(3,2)）：
`unlocks` 6 条，`(1,2)/(2,1)/(3,0)/(3,1)/(4,1)/(5,2)` 的 `lock` 分别变成 `icebox/icebox/web/web/icebox/icebox`；
出片帧 120–175 能看到 6 个盒子变成「冰 + 棋子 + 05:40/06:37/07:00/08:30」和「网 + 棋子」。
反向验证：把 `blast_radius()` 固定成 1 → `t_sim` 红 3 条；把 `icebox` 从白名单去掉 → `t_board_view` 红 3 条；
把 `became` 映射去掉 → `t_board_view` 红 1 条（`expected=["icebox","web"] actual=["box","box"]`）。恢复后 **3241 / 0**。

### 6.25 生成器拖拽也要有 ghost + 白框（2026-11-10）

**操作者原话**：「拖动生成器的时候，要选中加白框，有拖动效果。现在没有，直接就移过去了。要和 clip 的效果一样」
→「效果一般，白框加大一点儿」。

**根因**：成片 `_paint_drag()` 只查 `_chip_texture(entity, level)`，生成器（`CleanBox_C`）查不到贴图 → 直接
`return`，没有任何 ghost；实机棋盘自己会画，所以只有成片缺。

**改法**：
- `board_view.item_texture(kind, entity, level)`：先查棋子图，查不到兜底生成器图（`UI_GENERATOR`）；
  `is_generator_entity()` 判断是不是生成器。成片 ghost 走这一个函数，不再自己查。
- 白框比例：**成片**棋子 `0.72`、生成器 `1.05`（矩形比例）；**实机一律 `DRAG_FRAME_GROW 1.14`**，
  生成器不再单独放大 —— 试过 `DRAG_FRAME_GEN 1.62`，实机里框比棋盘格还大（操作者截图报"游戏里白框太大"，
  成片反而是对的）。两边坐标系不同（grow 倍数 vs 矩形比例），别互相套用。

**验证**：take `20261110_161934`，生成器 `CleanBox_C` 在 (3,4) 被拖到 (2,5)（`move` @7.36s）：
帧 376/380 生成器跟着光标、外面一圈更大的白角框；帧 384 松手后 ghost 消失、生成器出现在新格子。
测试 **3241 / 0**。

### 6.26 成片两处漏回放：订单带拖拽 + 冰块倒计时（2026-11-10）

操作者用 take `20261110_165759`（6744 帧 / 112 s）报的两个 Bug：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 帧 3606 向左拖任务栏，成片不滑 | take 里只有 `cursor` 采样，没有"按下/抬起"；成片从不调 `set_row_offset` | **最终解：take 记真实偏移**（见下），成片只回放，不猜手势 |
| 2 | 所有冰块（原有 + 盒子炸出的）倒计时不动 | 成片只调 `set_clock`，**从不调 `set_ice_elapsed`**，`ice_elapsed` 恒为 0 | `_sync_live_board()` 里每帧补 `_live_board.set_ice_elapsed(_t)` |

**验证**：帧 3616/3640 整排左移（卡片跟着手指走）；冰块倒计时按 6 s 间隔读数为
`17:03 → 16:57 → 16:51 → 16:45`、`12:22 → 12:16`、`13:00 → 12:54`，全部在跳。

**订单带拖拽：两版猜测都错，改成记数据（同一天第三次）**
1. 第一版按"光标在区域内 + 横向位移 ≥24px"反推 → 光标只是**划过**任务栏，整排就跟着走（操作者报"一直跟着鼠标走"）。
2. 第二版加"点击即取消 / 纵向 ±40px / 松手后必须离开区域才重判" → 划过仍然触发（take 里 `180515` 一次点击都没有，全是横移）。
3. **定案**：实机把真实偏移写进 take —— `band: [[t, dx], ...]`（拖动和回弹每一帧都记，
   `game_screen._record_band()`），成片 `TakeIo.band_at(take, t)` 线性插值后直接 `set_row_offset()`。
   **没有 `band` 记录 = 一次都不动**。旧 take（本次改动之前录的）没有这个字段，拖动段不会滑，需要重录。

**`band_at()` 的两个坑（同日第四次，都是成片"节奏不对"）**
1. **跨空档插值**：采样只记"值有变化"的帧，两条采样间隔 0.9s 时做线性插值 → 手没碰任务栏，
   整排却从 +0.9 慢慢漂到 -98。修法：`span > 0.12s` 一律保持上一条值（静止段不插值），
   真正拖动时采样约 13ms 一条，仍平滑。
2. **第一条采样之前**：原来 `if prev_t < 0: return dx` → 成片从**第 0 帧**就把整排推开
   首条采样的距离（本次是 +164px），开场就错位。修法：返回 `0.0`（开场必须归位）。

**长 take 渲染**：`tools/render.sh` 的 60 s M0 护栏（>3600 帧直接 fail）加了显式放行：
`RENDER_ALLOW_LONG=1 bash tools/render.sh --take ...`。真实长 take 用它，短跑和冒烟仍然受限。

**无损**：6744 帧 → 698 MB（`libx264rgb -qp 0 -preset veryslow -pix_fmt rgb24`），
抽帧 2400/3480/3606 与 PNG 逐字节一致。

## 6.27 自造关卡 + 脚本断言（2026-11-10，操作者要求，以后照这条走）

**操作者原话**：「你不能自己写一个关卡，跑起来，用脚本去验证么？总喜欢用我最新的录屏……
你现在改新的任务，还在总跑我原来的旧脚本。」

**规矩**：验证新功能**一律先自造关卡**，不依赖操作者的录屏。录屏只用来发现"实机哪里不对"，
不用来证明"我改的东西对"。

| 工具 | 作用 |
|---|---|
| `tests/t_harness.gd` | 内存合成工程 + take，跑真实 sim / TakeIo / 视图；新增功能先在这里加用例（`run_tests.gd` 自动带上） |
| `tools/make_probe.gd` | 生成 `output/probe/project.json`（第 1 关一块 3 秒的冰、blast=2）与合成 take（1.2s 合并、2.4~3.6s 拖任务栏） |
| `tools/verify_probe.py` | 量出片像素：冰格像素数（扛住爆炸 / 到点化掉）、订单卡蓝条左缘（拖动位移与回弹） |
| `tools/probe.sh` | 一条命令：生成 → 出片（双跑 `same=YES`）→ 断言，退出码即结论 |

**这一步踩过的坑**：`render.sh` 有**自己的** `--project`，默认 `res://data/sample_project.json`，
take 里的 `project` 字段不参与。自造关卡必须显式传
`--project res://output/probe/project.json`，否则渲染的还是样例工程（表现为"新功能全没生效"）。

**当前探针基线**（`bash tools/probe.sh`）：

```text
[verify] 冰格像素  0.5s=2249  1.6s(合并后)=2231  4.0s(3s 到点后)=169
[verify] 任务栏左缘 1.5s=490  2.9s=329(位移 -161)  4.2s=490
[verify] RESULT PASS
```

### 6.28 冰倒计时必须每帧刷新（2026-11-10，实机报"不点鼠标不跳字"）

**现象**：游戏里冰的倒计时停在初始值，鼠标点一下才跳到最新。

**根因**：剩余秒数原来是塞在 `_sync_from_sim()` 里推的，而 `_sync_from_sim()` 只在
**有事件时**调用（点击/合并/交付）。没有事件 → 视图里的 `_ice_left` 一直是旧的；
`board_view.set_ice_remaining_map()` 那时也**不触发重绘**。

**修法**：
1. `board_view.set_ice_remaining_map()` 值变了就 `queue_redraw()`
   （倒计时每秒都在变，必须自己触发重绘）。
2. `game_screen` 抽出 `_push_ice_countdown()`，在**每帧**的 `_process` 里调用，
   数据直接从 `sim.board.obstacles` + `sim.ice_remaining()` 取（不依赖快照，融化后该格自然消失）。
   `_sync_from_sim()` 也复用同一个函数，不再有第二份算法。

**验证**（headless 跑真实场景，不需要点鼠标）：

```text
[probe] t=1.0 cell=(3, 6) left=45 view=45
[probe] t=2.0 cell=(3, 6) left=44 view=44
```

`left` 是 sim 算的、`view` 是棋盘手里那份，两秒都在往前走 —— 没有任何点击事件参与。

### 6.29 任务栏排序重写：只认"绿底大对号"（2026-11-11）

**操作者口径**：「排序主要看绿底大对号显示不显示，显示就排到前面，不显示就不用动；前面也是绿的
就顺延；绿的变成不显示，后面的向前补；绿的靠前，但不插队」「先满在前，后满在后」
「屏内的也参与排」「交付动画期间不允许重新排，缩卡结束后重新算」。

**唯一实现**（`order_panel.queue_order()` 纯函数 + `_sort_queue()`）：
1. 绿组 = 整卡全满（`_card_full`，即每行 `board_count >= need`），按 `_full_seq` 升序（FIFO）；
2. 非绿组保持原有相对顺序；
3. 掉出绿组 → 只挪到最后一个绿卡后面（读法 1），非绿之间不互相插队；
4. 重新变满 → 拿新序号，排绿组末尾；
5. 冻结：`is_animating()` / 未到期 `_hold` / `claim_pending` 任一成立就不排，解冻当帧一次到位。

**删掉的四套旧机制**：`_reorder_cards`（按 `sum(have)` 分区排序）、`_promote_full_cards`、
`reveal_card` 的"提到最前 + 钉住"、`hold_sort` 的钉住；`reveal_card`/`hold_sort` 保留空实现兼容调用。

**奖励飞行不受影响**：`reward_origin()` 仍用 `settled_rect()`（`_target_x + _row_offset`），
而排序在交付期间冻结，所以"在哪张卡交，就从哪张卡飞"保持原逻辑。

**自造验证**（不依赖操作者录屏）：`tools/make_queue_probe.gd` →
`output/probe/queue_project.json` + `queue.take.json`：
初始 `[c3 2/2 绿, c4 1/1 绿, c1, c2]` → 1.5s 合并掉 c3 的两枚 → `[c4, c3, c1, c2]`
→ 3.0s 交付 c4 → 缩卡消失、队列补位。出片抽帧 30 / 150 / 215 / 285 与预期一致。

测试：`tests/t_order_queue.gd`（纯函数 6 组）+ `t_layout_parity` 的面板级断言
（初始不搬卡、变绿→第一、后满顺延、掉绿沉到绿卡后、hold 期间冻结）。

### 6.30 点大对号提交：任务栏数字要**锁住**（2026-11-11）

**操作者原话**：「点大绿框提交，提交的一瞬间 clip 飞起来了，然后任务栏图标减少对应的数字并变色了。
这个地方对逻辑来说是不对的。改成点大绿底提交后，锁住提交时任务栏对应的状态和数字。」

**做法**：
1. `order_panel.lock_row_display(order_id)`：点大对号那一刻，把这张卡每行的棋盘枚数
   存进 `card["locked_board"]`，`display_locked = true`。
2. `_row_board(card, row, item)` 是**唯一取数口**：锁住就返回锁定值，否则读 `board_count()`。
   角标数字、底色、小叹号、`_card_full()`（大对号显隐）全部走它 → 提交后不会再掉数变色。
3. 实机 `_confirm_badge_hit()` 先锁再 `_confirm_order()`；成片在 `deliver` 分支同样先锁
   （take 里没有"点击对号"事件，用第一条 deliver 当作提交瞬间）。
4. 兜底：`sync_orders()` 检测到卡进入 `done/claim_pending` 且还没锁时，用**上一帧显示值**
   （`item["board"]`）补锁，避免旧 take / 其它入口漏锁。

**验证**：
- `t_layout_parity`：棋盘 2 枚 → `2/2`；`sync_orders(done)` + 棋盘清空后仍返回 `2/2`。
- 自造探针 `output/probe/queue.mp4`：帧 170/185（棋子还在）/200/230（棋子已飞走、奖励在飞）
  前卡数字始终 `1/1`，大对号不闪。

### 6.31 任务行改两态：没满就是 `0/1` 的样子（2026-11-11）

**操作者原话**：「现在子任务 3/4 这样的时候，要改成和 0/1 一样的显示，底色和字体颜色都按 0/1 显示。」

| 状态 | 底板 | 数字 | 叹号 |
|---|---|---|---|
| 未满（如 `0/1`、`2/3`、`3/4`） | 米色 `mission_frame_todo` | 米白字 + 暖棕描边 | 无 |
| 收满（`4/4`、`6/4`、`1/1`） | 浅绿 `mission_frame_done` | 亮绿字 + 深绿描边 | 有 |

- 唯一判据：`order_panel.mission_row_done(board, need)`（纯函数，`board >= need`）。
  旧的「棋盘上有 1 枚就变绿」作废。
- 数字照旧 = 棋盘枚数，不封顶；掉数跌破需求立刻回米色。
- 大对号仍要求**整卡每行收满**；数字锁（§6.30）不变。
- 测试：`t_layout_parity` 六条（`0/1`/`3/4`/`2/3` → 未满；`4/4`/`6/4`/`1/1` → 完成）。
- 探针：`tools/make_queue_probe.gd` 增加 c5（要 Ca lv1 ×3、棋盘只有 2 枚），
  `tools/probe_row_state.gd` 打印 `a board=2 need=3 full=false`；出片里该卡显示 `2/3` 米色棕字。

### 6.32 锁盒只出蜘蛛网（2026-11-11）

**操作者原话**：「锁盒现在是生成带蜘蛛网或者冰块的。我需要改成只要带蜘蛛网的。冰块可以去掉了。」

- `sim._unlock_neighbours()`：`lock` 被砸开 → `board.add_obstacle(cell, "web")`，`became = "web"`。
  原来那条按坐标 hash 二选一（web / icebox + 冰倒计时）的分支**删除**。
- `icebox` 类型仍保留在代码里（老 take 回放要认），但**没有任何新关卡/盒子会再产出它**。
- 关卡自己摆的 `ice`（`ice_seconds` 倒计时）不受影响，照旧到点自化。
- 验证：`tools/probe_blast.gd` 六格全 `lock -> ["web"]`；探针出片帧 150/200 新开出来的都是网。
  测试 `t_sim` 改为 `t.eq(touched, ["web"], ...)`；全量 3310 / 0。

### 6.33 蜘蛛网：爆炸无效，只能"拖同款"解锁并升级（2026-11-11）

**操作者原话**：「现在蜘蛛网不能被炸开了。蜘蛛网逻辑改成拖一个相同的旗子过来，可以解锁蜘蛛网，
并且合并更高一级的棋子。」

| 项 | 做法 |
|---|---|
| 爆炸免疫 | `_unlock_neighbours()` 里 `web` 与 `ice`/`icebox` 一样直接 `continue`，永远不因合并被炸开 |
| 网下压棋子 | `_load_level()` 给每个 `web` 格放一枚 `IceCell.chip()` 的棋子（和视图画的同一枚），
没有比较对象就没法判"同款" |
| 拖同款解锁 | `_do_merge()`：目标格只被 `web` 盖住时不再一律 `SIM_BLOCKED`；
同款同级的棋子压上去 → 移除 `web` → 合成 lv+1 → 返回 `web_unlocked = true` |
| 不同款 | 仍然被拒（`SIM_ENTITY_MISMATCH` / `SIM_LEVEL_MISMATCH`），网保留 |
| 拖拽判定 | `free_mode.drag_action()` 允许"目标是网且源是同款棋子"走 `ACTION_MERGE`，其它障碍照旧 `ACTION_BLOCKED` |

**验证**：
- 数据探针 `tools/probe_web.gd`（第 1 关 (2,5)）：
  `web_cell=(2,5) item={CleanSet_Cd, lv2}` → `merge ok=true web_unlocked=true` →
  `after obstacle=[] item={CleanSet_Cd, lv3}`；不同款 → `SIM_ENTITY_MISMATCH`，网还在。
- 出片探针 `output/probe/queue.mp4`：帧 196 网 + 下面压着饼干、旁边是同款；
  帧 210 网消失、那格变成大一号（lv3）的甜甜圈。
- 测试：`t_sim` 新增"同款压上去解锁并升级 / 不同款拒绝"；blast=2 的两条改成"网还在"；
  第 2 关棋子数回到 11（网下压着一枚）。

**2026-11-11 追加两条（实机反馈）**：
1. **网下的棋子拖不动**：`_maybe_start_drag()` 加 `if sim.board.is_blocked(_press_cell): return`
   （以前能把网下的棋子拽出来，看着像把网一起拖走）。
2. **网必须画在棋子上面**：棋子现在是"真实 item"，item 层画在障碍层之后 → 会盖住网。
   `board_view._draw()` 的 item 循环里跳过被 `web` / `ice` / `icebox` 盖住的格子
   （障碍层自己会画"被扣住的那一枚"）。探针帧 180 确认：网纹在上、饼干在下。

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

## 9. 术语表（2026-11-11 定，后续一律用这套称呼）

操作者问「这个盒子在你这里叫什么」时定的口径 —— 以后不再用"那个盒子/那个数字"这种指代。

### 9.1 棋盘

| 术语 | 代码 / 数据 | 说明 |
|---|---|---|
| 棋盘 | `board` | `sim.board`，7×9（`board.width/height`） |
| 格子 | `cell` | `Vector2i(x, y)`，左上角 (0,0) |
| 障碍 | `obstacle` | `level.obstacles: [{slot, type}]` |
| **蓝盒子 / 锁盒** | **`lock`** | 主题槽 `lock` → `obstacle_lock` → `assets/ui/common_main_icon_lock_1x1.png`；被合并爆炸扫到后**只变成 `web`**（2026-11-11 起不再出冰），底下压一枚棋子 |
| 蜘蛛网 | `web` | 压着一枚棋子；**爆炸不再炸开**，只能拖一枚同款棋子压上去 → 解锁网 + 合成高一级（§6.33） |
| 冰 | `ice`（关卡摆的）/ `icebox`（盒子变的） | 带倒计时；`ice_seconds` 配关卡冰时长；到点自己化（`melt`） |
| 问号袋 | `bag` | 未知道具袋 |
| 柜子 | `safe` | 多格大块 `1x7` / `2x2` / `2x3` / `2x4`，`level.safes` |
| 泡泡 | `bubble` | 气泡障碍 |

### 9.2 棋子与生成器

| 术语 | 代码 | 说明 |
|---|---|---|
| 棋子 / clip | `chip` | `entity` + `level` |
| 系列 | `entity` | `CleanSet_Ca`（饼干）/`Cb`/`Cc`（零食袋）/`Cd`（沙滩球） |
| 等级 | `level` | 1~10；两枚同级合并升一级 |
| 生成器 | `generator` | `CleanBox_C`（棋盘原有）、`CleanBox_P`（库存面板投放的高级生成器） |
| 闪电 / 体力 | `energy` | 点生成器扣 1；右下角小闪电图标 |
| 炸开半径 | `blast` | 关卡 JSON，1=上下左右，2=再外一层（菱形） |
| 产出池 | `outputs` / `missionPool` | 普通生成器按 `outputs`；高级生成器按本关每个子任务"次一级" |

### 9.3 任务栏（订单带）

| 术语 | 代码 | 说明 |
|---|---|---|
| 任务栏 / 订单带 | `order_panel` | 顶部横条；成片托管同一组件（§8） |
| 订单卡 / 卡 / 小人儿 | `order` / `card` | 一张单：立绘 + 子任务行 + 奖励 |
| 子任务行 / 一行 | `mission row` | 卡内一格任务（`entity` + `level` + `count`/`need`） |
| 角标 | `badge` | 右下角 `3/4` 数字（= 棋盘枚数 / 需求，不封顶） |
| 底板 | `mission_plate_rect` | 任务格背后的米色（未满）/ 浅绿（收满）框 |
| 小叹号 | `bang` | 该行**收满**才出现（§6.31） |
| 大绿底对号 / 对号 | `confirm badge` | 整卡每行收满才出现，**唯一交付按钮** |
| 立绘 | `portrait` | 卡片后的人像 |
| 绿组 / 非绿组 | `full` / `not full` | 排序唯一判据（§6.29） |
| 锁数字 | `lock_row_display()` | 点对号那一瞬把该卡数字与颜色定住（§6.30） |
| 结算 | `settle` / `claim_pending` / `done` | 收满 → 飞棋子 → 缩卡 → 奖励 → 移出队列 |

### 9.4 左上角库存面板

| 术语 | 代码 | 说明 |
|---|---|---|
| 库存面板 | `stockpile` | 左上角书架图标 + 红点次数 |
| 投放 | `stockpile_tap` 事件 | 点它 → 生成器（当前是 `CleanBox_P`）飞到随机空格 |

### 9.5 流程与数据

| 术语 | 代码 / 文件 | 说明 |
|---|---|---|
| 实机 | `src/view/game_screen.gd` | 玩家实际玩的画面 |
| 成片 | `src/render/movie_scene.gd` + `film.mp4` | 按 take 渲染的视频 |
| take / 录屏数据 | `output/mov/<stamp>/take_*.take.json` | `timeline` + `cursor` + `band` + `drag` |
| 快照 | `sim.snapshot()` | 实机与成片的唯一数据源 |
| 交付 | `deliver` 事件 | 一枚棋子飞进某一行 |
| 奖励飞行 | `reward flight` / `coin_spiral` | 金币 / 钻石 / 体力螺旋 |
| 整排拖拽 | `band` 采样 / `_row_offset` | 手拖任务栏左右滑动 |
| 自造关卡 | `tools/make_*_probe.gd` + `output/probe/` | 验证新功能只用这个，不依赖操作者录屏（§6.27） |
