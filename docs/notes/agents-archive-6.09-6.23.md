# AGENTS.md 归档：§6.9 ~ §6.23（2026-11-09 ~ 2026-11-10）

> 这些是**历史过程**。AGENTS.md 有 65,536 字节的指令预算，正文放不下，
> 结论已浓缩在 AGENTS.md 的「6.9 历史细节索引」里，细节到此查。

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


### 6.23 新 take 复现出的三个"成片不一致"（2026-11-10）

操作者用新录制 `output/mov/20261110_112700/` 复现，逐条修：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 帧 214 拖拽中的 clip 被订单卡盖住 | 成片让 `board_view` 自己画拖拽棋子，而棋盘在订单带**下面** | 棋子改由最上层 `FilmOverlay` 画；几何**问棋盘要** `board_view.drag_chip_rect()`（不许在成片再算一份）；白角框用 `drag_frame_texture()` 画在 `rect.size × 0.72`（棋子贴图自带留白，按矩形画会显得过大） |
| 2 | 帧 361/362 点任务栏交付，clip 直接消失没有飞行 | 起点判定写成"光标在订单带内就用光标位置"——右键点任务格时指针**就在**卡上，起点≈终点 | `deliver` 事件带 `via`（`drag` / `chip` / `card`）；成片**只有 `via=="drag"`** 才用光标位置，其余从棋子那一格飞 |
| 3 | 帧 1138 交付完成只有金币飞，钻石/闪电没了 | 逐枚交付的结算走 `_play_settle_effects()`，那里只发了金币螺旋 | 补钻石（`spin=-1`）与体力（`spin=+1`）螺旋，起点 `_reward_strip_centre()`（卡片蓝条中心，`Layout.GEM_STRIP_RATIO`） |

**"闪白"= 光标点击涟漪，不是交付特效（2026-11-10）**：`_paint_press_ring()` 画的是
**按下那一刻光标位置**的白圈（0.25s，18→150px）。它属于光标反馈，不该给卡片再加一份。
右键交付"看着少了一个特效"的真正原因是**绘制顺序**：涟漪原来画在手**下面**，
指针压在卡片上时被手和卡面盖住。修法：实机 `Cursor._draw()` 与成片 `_paint_cursor()`
都改成**先画手、后画涟漪**，四个入口（拖拽 / 右键棋子 / 右键任务格 / 点卡结算）观感一致。

**奖励飞行起点 = 卡片自己那套图标（2026-11-10 操作者报的 Bug）**：以前金币从**卡片中心**飞、
钻石/体力从**蓝条中心**飞，是写死的几何。现在 `order_panel.reward_origin(order_id, kind)`：
- `coin` → 卡片上方"+N"药丸里的金币图标中心（`r.end.x - 132 + 24`、`r.y - 54 + 24.5`）
- `gem` / `energy` → 蓝条里各自图标中心（复用 `reward_row_rects()`，和自己的绘制同一份几何）
订单卡是哪一张就取哪一张 —— **第 2 张卡结算就从第 2 张卡的图标飞**。
实机 `_play_coin_reward / _play_gem_reward / _play_energy_reward` 与成片 `_play_settle_effects()`
调同一个函数（成片加 `_live_band.position`）。

**小手的"按下去"要看得见（2026-11-10 操作者要求）**：原来按下只在点击后 0.10s 内缩到 0.86，
右键一闪而过看不出来。现在：
- `TakeIo.PRESS_SECONDS 0.10 → 0.22`、`PRESS_SCALE 0.86 → 0.80`（共享常量，实机与成片同一份）
- **拖拽期间一直保持按下**（`TakeIo.drag_at()` 非空 / 实机 `_pressing || _dragging`），松手才回弹
- 按下时手整体**下沉 7px**（成片 `CURSOR_PRESS_DIP`、实机 Cursor 里的 `dip`），幅度肉眼可见

**交付必须在画面里发生（2026-11-10 操作者要求）**：卡片只显示前 2 张，右键交第 3、4 张会让
棋子飞到画面外。做法：
- `order_panel.reveal_card(order_id, 0.26)`：**把目标卡提到队伍最前**（`cards` 里挪到 index 0），
  滑行动画交给 `_x_now` 逐帧 lerp（0.22）—— 就是"整排被橡皮筋拽一下"的手感，
  返回滑行秒数；已在首位返回 0。揭示后在 `_pinned_until` 之前**固定第一**，
  否则按完成度排序会立刻把它挤回去。
- **已经在屏上的前 `VISIBLE_CARDS` 张不换位**：`reveal_card()` 对 `idx < VISIBLE_CARDS` 直接返回 0，
  原地收集；`hold_sort()` 也只钉"真的被提上来过"的卡（`_promoted_id`）。
  否则第 2 张会先跑到第 1 位收集、收完又跳回去（操作者报的来回晃动）。
  反向验证：把这条判断关掉 → `t_layout_parity` 红 3 条（第 2 张不换位 / 留在原位 / hold 不钉第一）。
  ⚠ 第一版写的是"整排 `_row_offset = -index * (MAX_CARD_W + CARD_GAP_X)`"，结果第 6 张卡
  交付时整排滑出屏幕左侧、卡和金币药丸糊在库存面板上（操作者报"任务栏全乱了"）——别再这么写。
- 交付前先调它，**棋子的飞行与底板"吞一下"都往后推这段延迟**（实机与成片同一套）。
  顺序必须是「卡先滑到位 → 棋子再起飞 → 落袋」，所以 `_play_deliver_flight()` 的 `delay`
  是**起始时间偏移**（`at = _clock + delay`），不能塞进 `dur` —— 塞进 `dur` 会让棋子立刻起飞、
  慢慢飘过整屏，看着就是"飞出界外"（操作者报过）。
- `mission_row_center()` 同样用 `settled_rect()`：落点是卡片**滑完之后**的位置。
- `reward_origin()` 必须用**滑行结束后的位置**（`_target_x + _row_offset`），不能用 `card_rect()`
  的动画中 x：卡片刚被提到最前时还在滑动，而奖励是 0.55s 后才飞 —— 用动画中坐标会从
  **原来的位置**飞出去（操作者报的"提前了，体力/金币/钻石还从原位飞"）。
- **排序要等动画全跑完**：`order_panel.hold_sort(order_id, seconds)` 把"钉住第一位"的时长
  延到 `reveal_delay + 0.75s`（飞行 + 落袋 + 奖励起飞），时序是
  「右键 → 卡提到第一 → 棋子飞 → 落袋 → **再**按完成度重排」。
  以前排序每帧都跑，交付中途就把卡挤回后面（操作者要求"交完了再排"）。
- 卡片排序改成**按这一单已交枚数（sum of `have`）降序、同分保持原顺序**
  （比较器第二关键字是"当前相对位置"，不是 id —— 同分一张都不挪；反向验证：把第二关键字
  改成按 id 排，三张同分卡立刻换位，`t_layout_parity` 红 3 条）：
  操作者口径"1/2 与 0/1+0/1+1/1 都是一分，先来的留在前面"。

**拖拽交付不飞棋子（2026-11-10 操作者追加）**：棋子已经在手上，"从空掉的格子再飞一枚过去"
是错的 —— 拖拽入口直接落袋（底板吞一下 + 角标变化 + 奖励飞行），**不播棋子飞行**；
只有右键棋子 / 右键任务格这两种"从棋盘起飞"的入口才飞。实机与成片同一判据：
`via == "drag"`（老 take 没有 via 时用 `_dragged_from()` 兜底：交付前 1.2s 内有过从同一格起手的拖拽）。

**拖拽时源格要留空**：成片在 `_sync_live_board()` 里把拖拽源格从 `cells_now` 里滤掉
（实机也是"棋子拿在手上、源格空着"），否则上层那枚和棋盘那枚会叠成两枚。
`board_view.drag_chip_rect()` 因此**不能**用 `_items.has(from)` 当判据。

**验证**：帧 214 = 棋子+白框在卡上方；帧 361/364 = 棋子从棋盘飞进 0/4 那行；
帧 1176/1184/1194 = 金币 14→19→24→29、钻石 101→102、体力 141→150→159 同时飞。

**无损成片**：`ffmpeg -framerate 60 -i frames/%05d.png -c:v libx264rgb -qp 0 -preset veryslow
-pix_fmt rgb24 film_lossless.mp4` → 92 MB（有损 CRF18 是 7.2 MB）。
抽帧校验：帧 214 / 238 / 363 / 1176 的 rgb24 raw md5 与 PNG **逐字节相同**。

