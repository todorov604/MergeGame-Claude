# 交叉审查：02_Game（只读）

> 审查对象：`02_Game/` @ `2be09d3`（另一条 lane 的 M0 实现）
> 方式：复制到 `/tmp/repo`（保留 `../00_design` 布局）后只读运行，**未修改 02_Game 任何文件、未复制其代码**
> 对照基准：`00_design/M0-冻结规格.md` + 本 lane 已修复的 7 项 core 缺陷（`docs/REVIEW-CORE.md` D1–D7）
> 结论：**功能完整、结构清晰、可出片**；发现 3 项实质问题（merge kind、rare 筛选、可搬移/缓存依赖），另有 2 项文档不一致。

## 1. 实测

| 场景 | 结果 |
|---|---|
| 仓库原位（无 `.godot`） | **11 / 422 failed**，全部为 `资源类型不符: res://assets/board_frame.png` / `font_en.ttf` |
| 复制到 `/tmp/repo`（保留 `../00_design`，无 `.godot`） | 11 / 422 failed（同上） |
| 复制到 `/tmp/repo` + `--import` 生成缓存后 | **422 / 422 PASS** |
| 只复制 `02_Game` 到 `/tmp/g2`（无同级 `00_design`） | **32 / 411 failed**，含 `文件不存在: .../00_design/resource_manifest.json` |

结论：测试本身是可靠的，但**结果依赖两件工程外的东西**——编辑器导入缓存、以及 `../00_design` 的相对位置。

## 2. 逐条对照 D1–D7

| 编号 | 我修的缺陷 | 02_Game | 证据 |
|---|---|---|---|
| D1 | 空订单关永远过不了关 | **无此问题** ✅ | `order_engine.all_claimed()` 对空集返回 `true`；`_apply_level_complete` 据此置 `state.level_complete` |
| D2 | 满盘时失败 tap 仍消耗 RNG | **无此问题** ✅（而且做得比我初版好） | `generator_engine.tap` 第 7 步先 `board.first_empty_slot()` 判满并早退，第 9 步才 `rng.randf()` |
| D3 | core 不执行 10 级上限 | **同类问题** ⚠️ | `merge` 的 `max_level` 直接取 `entity.maxLevel`（数据写 11 就允许合到 11）；`generator` 的 `level` 原样取 `rareOutputs[].level`，不 clamp；校验器会拦，但直接驱动 sim/预览时不受保护 |
| D4 | `board_full_pending` 不复位 | **机制不同，不算缺陷** ➖ | 无该字段；`tap` 返回 `{"ok":false,"board_full":true}`，由 `board_full` 事件驱动提示，不进入 state/digest |
| D5 | 求值器放行未注册事件 | **基本覆盖** ✅ | `validator.gd:632-639` 对 sim/view/audio 三张注册表校验；`sim_runner` 默认分支返回"未实现的事件类型" |
| D6 | `reset()` 抹掉加载失败 | **不存在等价 API** ➖ | 其 evaluator 没有 load/reset 语义，风险点不存在 |
| D7 | 时钟进 digest | **无此问题** ✅ | `sim_state.snapshot()` 只含 seed/hud/level/board/orders/level_complete；`state_hash()` = sha256(JSON) |

## 3. 三项实质问题

### R1 merge 不限定 kind（与我的初版同款）— 中
`core/sim/merge_engine.gd`：只判 `entity` 相等、`level` 相等、`level < max_level`，从不看 `kind`。
→ 两个 `SafeBox_X`（special）或两个生成器可以被合成升级。本 lane 已按用户裁决改为**仅 `kind=chip`**（`SIM_NOT_MERGEABLE`），建议对方对齐。

### R2 `directOrder` 被记录但未参与筛选 — 中
`core/sim/generator_engine.gd:130` 把 `directOrder` 读进 `table` 条目，但**没有用它过滤**：
`rareOutputs` 全部无条件进入权重表。这与我修的"稀有产出只在订单需要时进池"相反——"直出订单物品"会变成无条件掉落。
本 lane 的裁决：`directOrder=true`（缺省）→ 仅当未完成订单缺该 `entity+level` 时进池；`false` → 无条件。

### R3 可搬移性 / 导入缓存依赖 — 中
- `tools/export_info.gd:17`、`tools/sync_assets.gd:25` 用 `res:// + "/../00_design/resource_manifest.json"`；项目单独移走即失效（实测 21 项失败）。
- 资源加载走 `load()` → 依赖 `.godot` 导入缓存；**干净克隆下 11 项测试失败**，必须先 `--import` 或开一次编辑器。
本 lane 的做法：manifest 走 `data/manifest_index.json` 快照（无绝对路径、无外部目录），字体用 `FileAccess` 原始字节 + `FontFile`，因此**无缓存也能全绿、整目录搬移后仍通过**。

## 4. 文档不一致（小）

1. `02_Game/README.md` 自述 **366 checks**，实测 **422 checks**（缓存就绪后全过）——README 落后于代码。
2. `00_design/HANDOFF.md` §1 记录 02_Game 为"已完成"，但没说清"测试需要先导入缓存"这个前提。

## 5. 02_Game 值得我借鉴的地方

1. **按 manifest 同步资源**：`tools/sync_assets.gd` 把 usage 允许的资源按规则复制进工程，比我"手工复制 + PROVENANCE 表"更流程化，M1 可以直接吸收这个思路（配合我的 `AssetGuard` 做双保险）。
2. **引擎拆分更细**：`core/sim/{merge,generator,order,level_flow,sim_state}_engine` 单文件职责更窄，可读性好；我的 `sim.gd` 偏大（~500 行）。
3. **`board_full` 用事件而非状态位**，天然免疫我修过的 D4/D7 那类"派生状态污染 digest"的问题。

## 6. 一句话结论

02_Game 是**合格的 M0 实现**，缺陷集中在"语义边界"（kind、directOrder）与"工程可复现性"（外部 manifest 路径、导入缓存依赖），不在主流程。
两条 lane 的差异是取舍不同，不是对错：它更细粒度、依赖编辑器工作流；本 lane 更自包含、以可搬移与逐帧确定性为先。

复核命令（只读）：

```bash
cd /tmp && rm -rf repo && mkdir repo && cp -r <workspace>/02_Game <workspace>/00_design repo/
cd repo/02_Game && "/e/Program Files/Godot/Godot_v4.7.2.exe" --headless --path . -s res://tests/run_tests.gd   # 11/422 fail
"/e/Program Files/Godot/Godot_v4.7.2.exe" --headless --path . --import
"/e/Program Files/Godot/Godot_v4.7.2.exe" --headless --path . -s res://tests/run_tests.gd                     # 422 PASS
```
