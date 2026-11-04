# core 模拟层独立复审与修复记录

> 复审：独立 agent（只读，不改代码）　修复：Lead（逐条复核后实施）　回归：`tests/t_sim_defects.gd`（35 checks）
> 结论：**7 项属实，全部已修**；修复后全量 `938 checks / 0 failures`，一键验收 `ALL CHECKS PASS`。

## 1. 复审发现了什么

| # | 严重度 | 问题 | 为什么算 bug |
|---|---|---|---|
| D1 | high | `"orders": []` 的关卡永远无法过关/前进 | `_load_level` 无条件把 `level_complete_pending` 置 false，而空订单关没有任何 claim 能把它置真；M0 §2.2 的 level_2 恰好就是空订单 |
| D2 | medium | 棋盘满时 tap 失败仍消耗一次 RNG | 先 `pick_weighted` 再判空格；RNG 不在 snapshot 里，所以 digest 看不见偏移，后续掉落会永久改变 |
| D3 | medium | core 不执行等级上限，可注入 11 级 | `board.put` 与稀有产出原样写 level；validator 只在出片前拦，直接驱动 sim/预览仍能拿到 lv11 |
| D4 | medium | `board_full_pending` 置真后不复位 | 只在 `_load_level` 复位；空位出现后提示仍在，且该字段进 digest，永久污染 |
| D5 | medium | 求值器把未知 channel / 未注册 type 当成功 | 违反 §3.3「新事件类型必须写代码/注册表」；预览与单步会静默执行垃圾事件 |
| D6 | low | `reset()` 清掉 `load_timeline` 的解析错误 | 坏时间轴 → reset → `run_all()` 返回 ok，回放路径把失败当成功 |
| D7 | low | 时钟进入 digest，且被 view 事件推进 | 被拒事件带 `at` 也能改 digest，削弱「拒命令零副作用」这条不变量 |

复审同时**确认无问题**的部分：`order_claim` 失败纯净（先算计划后落笔）、稀有进池不可被"已交付未 claim"绕过、digest 与字典插入顺序无关、无未排序 `keys()` 影响结果、事件排序符合 §3.2。

## 2. 怎么修的

| # | 修法 | 位置 |
|---|---|---|
| D1 | `_load_level` 末尾 `level_complete_pending = orders.is_empty()` | `src/core/sim.gd` |
| D2 | 先 `first_free_cell()` 判满并早退，**之后**才抽 RNG | `src/core/sim.gd` `_do_tap` |
| D3 | `_sanitize_board_levels()` 载入即 clamp 到 `[1, min(10, maxLevel)]`；tap 产出同 clamp | `src/core/sim.gd` |
| D4 | `board_full_pending` 改为派生量：每次 `apply()` 后 `_refresh_board_full()` 重算 | `src/core/sim.gd` |
| D5 | `step()` 先校验 `channel ∈ {sim,view,audio}` 与 `type_registered`，失败返回 `EV_CHANNEL` / `EV_UNKNOWN_TYPE`；`run_all().rejected` 统计**所有**通道 | `src/core/event_evaluator.gd` |
| D6 | 新增 `load_ok` 标志；`reset()` 不再清 `errors`/`load_ok`；`run_all().ok` 纳入 `load_ok` | `src/core/event_evaluator.gd` |
| D7 | `time` 移出 `snapshot()`（时钟不是游戏状态）；`set_time` 只对 sim 通道执行 | `src/core/sim.gd` / `event_evaluator.gd` |

## 3. 回归测试（`tests/t_sim_defects.gd`，35 checks）

每个缺陷都有"当年会错"的具体输入，而不是复述实现：

- **D1**：2 关工程、level_2 `orders: []` → claim → `level_next` 成功 → `level_complete` 成功
- **D2**：满盘 tap 失败后 `rng.state` 不变；解除占位后再 tap，其产出与"从未失败过"的对照组**完全相同**
- **D3**：slot 写 11 级 → 载入后为 10；rare 写 11 级 → 产出不超过 10
- **D4**：满盘 → pending=true；claim 释放格子 → pending=false；tap 恢复可用
- **D5**：未注册 view type → `EV_UNKNOWN_TYPE`；未知 channel → `EV_CHANNEL`；`run_all` 的 `rejected` 含该事件且 `ok=false`
- **D6**：坏锚点 → `load_ok=false`；`reset()` 后 `run_all().ok=false`
- **D7**：同一 sim 命令序列 + 额外推进时钟 → digest 相同；带 `at=99` 的被拒事件 → digest 不变

## 4. 复审提出但未改的两点（需要设计裁决，不是 bug）

1. ~~**merge 是否只允许 chip**~~ → **已裁决并实施（选项 A），并写入 M0 v0.20 §2.1.9**：只有 `kind=chip` 能合并，其余返回 `SIM_NOT_MERGEABLE`。
   理由：`generator_state` 按 entity id 共享电量，合成出的 lv2 生成器会与 lv1 共用同一电荷池，语义无法自圆；`special` 没有等级对应的美术/玩法。
   实现：`src/core/sim.gd` `_do_merge()` 在 entity 相等之后加 kind 判定；回归：`tests/t_sim_defects.gd::_test_merge_kind_gate`（special/generator 被拒且 digest 不变，chip 仍可合到 lv2）。
2. ~~**`directOrder` 字段从未被读取**~~ → **已裁决并实施，并写入 M0 v0.20 §2.1.10**：`directOrder=true`（**缺省值**，保持旧数据行为）时，rare 仅在未完成订单缺该 `entity+level` 时进池；`directOrder=false` 表示普通大奖，**无条件**进池。
   实现：`src/core/sim.gd::tap_pool()`；回归：`tests/t_sim_defects.gd::_test_direct_order_semantics`（有订单/无订单/缺省/显式 false 四种输入）。

## 5. 复现命令

```bash
G="/e/Program Files/Godot/Godot_v4.7.2.exe"
"$G" --headless --path . --script res://tests/run_tests.gd -- --suite res://tests/t_sim_defects.gd
"$G" --headless --path . --script res://tests/run_tests.gd     # 938 checks
bash tools/accept.sh                                          # ALL CHECKS PASS
```
