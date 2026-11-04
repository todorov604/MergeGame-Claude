# 交叉审查报告：03_Game_ds（Claude → DeepSeek 工程）

> 日期：2026-11-04　审查方：02_Game（Claude）　协议：`00_design/HANDOFF.md` §2 第 3 步
> 审查目标：**commit `cf8db56`**（`03_Game_ds：M0 全 9 步 Godot 工程（含两轮独立复审修复）`，2026-11-04 15:08:37，109 个跟踪文件）
> 方式：只读审查，不修改 `03_Game_ds`、不抄其代码；用临时夹具（已删除）实际驱动其 validator。

---

## 0. 快照说明（重要）

- 审查开始时（约 15:10）`03_Game_ds/` 工作区与 `cf8db56` 一致（`git status` 干净）。
- 约 15:22 复查时，工作区**又出现未提交改动**：
  - `src/core/sim.gd`：实现 `directOrder` 语义（true=按订单门控、false=无条件稀有、缺省 true）；
  - `tests/t_sim_defects.gd`：新增 `direct_order` 回归；
  - `docs/evidence/`：新增未跟踪证据目录（accept.log、截图、render.mp4 等）。
- 因此**本报告只覆盖 commit `cf8db56`**；15:22 的在途改动不计入结论，需重新冻结后复核。

---

## 1. 实际验证（只读运行）

| 项目 | 命令 | 结果 |
|---|---|---|
| 全量测试 | `godot --headless --path 03_Game_ds --script res://tests/run_tests.gd` | **PASS 944 checks / 0 failures**（README 写 938，已过期） |
| 样例 strict 校验 | `... cli.gd -- validate --project res://data/sample_project.json --strict --out ""` | **ok=true errors=0 warnings=0**，end=30.00s |
| 资源红线 | 对比 `data/manifest_index.json` 与 `assets/` 实际文件 | 7 个载荷 + PROVENANCE；REFERENCE_ONLY 交集 **0**；5 个 PLACEHOLDER 均在允许清单 |
| 源码审查 | core / event_model / validator 规则族 / asset_guard / render_plan / movie_scene / render.sh / accept.sh / run_tests | 见下 |

未复跑出片（其 `output/` 正在被另一会话写入，避免干扰）；出片结论引用其 `docs/REVIEW-RENDER.md`、`PERF-BASELINE.md` 与 15:22 的 `docs/evidence/`。

---

## 2. 确认无问题的部分

- **REVIEW-CORE D1–D7 全部已修**，代码与回归测试一致：空订单关卡可过（`_load_level` 置 `level_complete_pending`）、满盘 tap 先判空再抽 RNG、`_sanitize_board_levels()` 与 tap 产出 clamp 到 `min(10, maxLevel)`、`board_full_pending` 每步重算、求值器拒绝未知 channel/未注册 type、`reset()` 保留 load 错误、时钟不进 snapshot。
- **事件模型 §3.2 排序**：at → channel → track → order → id，锚点缺失/自环/环均有稳定错误码，迭代解析不会死循环。
- **资源守卫**：`AssetGuard` 是唯一裁决点；REFERENCE_ONLY 文件不复制进工程且 `local_path()` 恒空；PLACEHOLDER 需显式开关；TODO 阻断；主题/实体图标/角色图标/音频引用都过 guard。
- **出片流水线**：录制前跑 strict validator（REFERENCE_ONLY 工程被拒）；每次运行独立临时目录；ffprobe 断言分辨率/帧率/帧数/时长；`-an` 去静音轨；240 帧双跑 framemd5 + 唯一帧数 >1；manifest 与成片绑定（frames/sha256/blocked）。
- **测试 runner**：自动发现、0 断言套件判失败、`_process` 兜底；`accept.sh` 额外扫描 `SCRIPT ERROR`（部分修复了 AUDIT-S1 的假 PASS 风险）。

---

## 3. 发现的问题

### F1【P0，已复现】订单可达性校验漏报（出片前应阻断却放行）

位置：`src/validate/rules_levels.gd` `_reachable_levels()` / `_check_orders()`。

问题：判定“订单可达”时——
1. 只看 `generators` 配置，**不看生成器是否放在本关棋盘上**；
2. 完全**忽略 `charges`**（1 次电量和 10 次电量同样视为可达）；
3. 把**所有关卡**棋盘上的物品混进同一张可达表（关卡隔离失效）。

复现（基于其 `data/sample_project.json` 做三处最小改动，用其 CLI 实际运行）：

| 用例 | 改动 | 03_Game_ds 结果 | 02_Game 结果 |
|---|---|---|---|
| A | 把 `CleanBox_C` 从 level_1 棋盘移除；order_1 改为需要 `CleanSet_Cb Lv2`（棋盘只有 1 个 Cb Lv1） | **ok=true errors=0 warnings=0** | `订单物品不可达: CleanSet_Cb Lv2` |
| B | 保留生成器但 `charges: 0`；order_1 改为 `CleanSet_Cb Lv2` | **ok=true errors=0 warnings=0** | `订单物品不可达: CleanSet_Cb Lv2` |
| C | level_1 无生成器、只有 2 个 Ca Lv1；order_1 要 `Ca Lv3`；level_2 棋盘放一个 `Ca Lv3` | **ok=true errors=0 warnings=0**（用了 level_2 的棋盘） | `订单物品不可达: CleanSet_Ca Lv3` |

影响：M0 §7 要求“订单不可达在出片前阻断”。当前实现会把**物理上不可能完成**的订单放行，成片链路在 order_claim 处静默失败，属于验收级缺陷。

建议修法：按“本关棋盘 + 本关生成器 + charges 作为可得数量”做合并容量推导（例如 02_Game `core/validator.gd::_check_order_reachability` 的做法：同 charge 可全部产出同一种，然后低一级两枚合成高一级一枚），并补 A/B/C 三类回归夹具；`directOrder` 的稀有产出按最终裁决计入或不计入可得数量。

### F2【设计裁决，未定】merge 限定 kind：03 已单方面实现“仅 chip”

- `cf8db56` 中 `src/core/sim.gd::_do_merge()` 对 `kind != "chip"` 返回 `SIM_NOT_MERGEABLE`，回归在 `t_sim_defects::_test_merge_kind_gate`；README §6 第 9 条写“已裁决”。
- 但 HANDOFF §4 仍写“待用户拍板”，且建议 **chip + generator 可合、special/character 不可合**。
- 02_Game 当前仍是“同 entity + 同 level 即可合”（未限定 kind）。
- 需要用户裁决；无论选哪种，两边必须同步，否则同一 timeline 在两个引擎里行为不同。其代码里的理由（generator_state 按 entity id 共享电荷池）对 02_Game 同样成立，值得纳入裁决依据。

### F3【设计裁决，进行中】directOrder 语义

- `cf8db56` 中该字段仍未被读取；稀有产出按“当前关有未完成订单且缺该 entity+level”进池。
- 15:22 的在途改动把它实现为：`true`（缺省）=按订单门控，`false`=无条件稀有（jackpot）。这与 HANDOFF §4 的建议一致，但尚未 commit，也未经用户拍板。
- 02_Game 当前：`rareOutputs` **无条件**进池，`directOrder` 只解析不使用。
- 需要用户确认语义后，02_Game 补对应逻辑（以及默认值行为）。

### F4【规格缺口】同一 project.json 在两边的运行时语义不同

M0 §3.4 只列事件名，没有定义 payload/状态机，导致两边实现分叉：

| 事件 | 02_Game | 03_Game_ds |
|---|---|---|
| `deliver` | payload 只需 `order`；要求 mission 全部物品已在棋盘，置 ready | payload 需 `order` + `from [x,y]`；逐件交付并入 mission `have` |
| `order_claim` | 必须先 `deliver` 置 ready；claim 时消耗棋盘物品 | 可直接 claim：已交付或棋盘上恰好有 mission 物品即可 |
| `energy_tick` | 按 `hud.energyTickMode` 对 energy ±1 | 按 `payload.delta` 增减 |

后果：同一时间轴在两边会得到不同的模拟结果/失败码。M1 之前必须在 M0 规格 v0.20 里钉死这三类事件的 payload 与状态机。

### F5【规格缺口】schema/类型口径不一致

- `track`：03 接受字符串（样本用 `"text"`/`"board"`/`"cam"`）并按字符串排序；02_Game 要求整数（同一份 03 样本在 02_Game 报 `track 必须是整数`）。
- `order`：03 对非数字静默按 0 排序；02_Game 要求整数并报错。
- `energyTickMode`：03 允许 `decrement`/`static`（其余仅警告，strict 升错误）；02_Game 允许 `decrement`/`increment`。
- 音频事件：03 注册了 `bgm`/`sfx`/`stop` 且 validator 放行，但渲染端 `on_event` 为空实现、成片 `-an`——**音频事件会被静默忽略**；02_Game 的音频类型表为空，直接判未注册。
- `meta.duration`：03 在 `--strict` 下把警告升为错误；02_Game 始终只是 warning。

这些都应写进 M0 v0.20 的同一张表；否则“换工程/换引擎”无法保证一致。

### F6【文档小问题】

- README §7 写“15 套件 / 938 checks”，实测 **944**（`cf8db56`）。
- README 末尾“本工程不产生 commit（由会话主人决定）”已过期（现已 commit）。
- README §6 第 9 条写 merge“已裁决”，与 HANDOFF §4“待拍板”不一致（见 F2）。

---

## 4. 02_Game vs 03_Game_ds 能力对照（供选型参考）

| 维度 | 02_Game（Claude） | 03_Game_ds（DeepSeek） |
|---|---|---|
| 测试规模 | 442 checks | 944 checks |
| 订单可达性 | **按本关棋盘 + charges + 合并容量**（更严谨） | 链级判断，漏报（F1） |
| 素材加载 | 需 `.godot` 导入缓存（干净副本先 `--import`） | `Image.load` / `FontFile.load_dynamic_font`，免导入、整目录可搬移 |
| 出片中间产物 | PNG 序列（M0 §6 优先路径，占盘大） | MJPEG AVI（轻量，成片前 ffprobe 硬断言） |
| 出片前门禁 | validator + evaluator | strict validator + guard + manifest 绑定 |
| 主题覆盖 | chip_palette/board_frame/字体/背景/star | HUD/订单卡/横幅/边框；chip 与格底不随主题 |
| 编辑/撤销/自动保存 | 有（50 步、30s 自动保存、崩溃恢复） | 有（同左，独立实现） |
| 事件 payload 契约 | deliver(order) / claim 需 ready / energy_tick 按 mode | deliver(order,from) / claim 可直接 / energy_tick 按 delta |
| 资源红线 | 22 个允许占位复制进工程，守卫拦截 | 仅 7 个载荷，其余程序化绘制 |

结论：两边都达到 M0 主体能力；02_Game 强在可达性校验与主题覆盖面，03_Game_ds 强在免导入可搬移、测试密度与出片门禁细节。**建议 M1 只保留一个代码基**（否则维护成本翻倍），选型放在用户拍板 F2/F3 之后。

---

## 5. M1 建议（不变）

1. 先完成 M0 收口：修 F1、冻结 03_Game_ds（含 15:22 的在途改动），把 F2–F5 写进 M0 规格 v0.20。
2. M1 第一项仍推荐 **批量变体 / 出片生产化**（project × theme × 文案变体、队列、命名、manifest、重试）；两边出片链路都已具备基础。
3. 若选 02_Game 作为 M1 代码基，需要补：免导入资源加载（可选）、03 的验证用例中确认有价值的反例、以及 F2/F3 裁决后的对齐逻辑。

---

## 6. 复现命令（F1）

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"
# 以 03_Game_ds/data/sample_project.json 为基础，按 §3 F1 表格改动得到 case_a/b/c.json
"$G" --headless --path 03_Game_ds --script res://src/tools/cli.gd -- \
  validate --project <case.json> --strict --out ""
# 观察：ok=true errors=0 warnings=0（应报 ORDER_UNREACHABLE）
```
