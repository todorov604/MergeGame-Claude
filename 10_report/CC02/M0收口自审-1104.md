# M0 收口 + 交叉审查报告（02_Game / Claude）

> 日期：2026-11-04　协议：`00_design/HANDOFF.md` §2「下一步协议」+ §3 Prompt A
> 范围：只做 M0 收口与只读交叉审查，不写新功能；本报告不改 `00_design`，不 commit。
> 说明：本会话在 git worktree（分支 `claude/m0-handoff-protocol-a657b1`）中执行；`03_Game_ds/` 与 `00_design/HANDOFF.md` 是主 checkout 的未跟踪文件，按绝对路径只读。

---

## 1. 02_Game 真实验收（实际输出）

环境：Godot 4.7.2.stable.official（`E:\Program Files\Godot\Godot_v4.7.2.exe`）。

| 项目 | 命令 | 结果 |
|---|---|---|
| 全量测试 | `godot --headless --path 02_Game -s res://tests/run_tests.gd` | **PASS 442 checks**（修复前 422；新增回归 20） |
| 校验 | `... -s res://tools/validate.gd -- --allow-placeholders` | **PASS（0 errors, 0 warnings）** |
| 模拟确定性 | `... -s res://tools/simulate.gd` | **PASS 确定性一致（2 runs, seed=12345）** |
| 出片确定性 | `bash 02_Game/tools/render.sh --verify` | **PASS framemd5 一致**（见 §1.2） |

### 1.1 新 worktree 的导入前置（重要环境事实）

全新 checkout 直接跑测试会 **11/422 失败**，全部是资源加载类（`board_frame.png`/字体“资源类型不符”）。根因是 `.godot/` 导入缓存被 gitignore；先跑一次：

```bash
"E:\Program Files\Godot\Godot_v4.7.2.exe" --headless --path 02_Game --import
```

后 422/422 通过。所以 **02_Game 在无 `.godot/` 的干净副本上必须先导入**（这与 03_Game_ds 宣称的“不依赖导入缓存、复制即出片”不同，见 §4）。

### 1.2 出片确定性（render verify）

- 命令：`bash 02_Game/tools/render.sh --verify`（双跑 + framemd5 对比；1080×1920@60、1800 帧）。
- 结果：**PASS**。两次录制各 1800 帧 / 30.000s；framemd5 A=B=`17fa27c9130bb5012ff16ad53442f8c65b91c10fdc66a5d68ba0fb310b1970ed`；输出 sha256 `d58d91c8f13b7277606b55b4593e5eb8d8f4ebe66f4c7916dbc87e684457bf96`；总用时 341 s（单次 165 s / 162 s）。
- 该 framemd5 与输出 sha256 和 README 记录的上一 worktree 基线完全相同——说明本工程在该机器上可跨目录复现。

---

## 2. 按 REVIEW-CORE 的 D1–D7 逐条检查 02_Game

| # | 03_Game_ds 的问题 | 02_Game 结论 | 证据 |
|---|---|---|---|
| D1 | `orders: []` 关卡永远无法过关 | **不存在** | `OrderEngine.all_claimed()` 空订单返回 true；`SimState.load_current_level()` 置 `level_complete`；`test_sim.gd` L228–241 已覆盖空订单切关 |
| D2 | 满盘 tap 仍消耗 RNG | **不存在** | `generator_engine.gd` `tap()` 第 7 步先判 `board.first_empty_slot()` 并早退，之后才 `rng.randf()`；本次补了回归测试 |
| D3 | core 不执行等级上限，可注入 11 级 | **存在 → 已修** | 原 `board_state.gd` 载入不过滤等级，`generator_engine.gd` 产出等级原样写入；validator 只在出片前拦 |
| D4 | `board_full_pending` 置真后不复位 | **不存在** | 02_Game 无持久 `board_full` 状态；它是 `tap()` 返回值里的瞬态字段，不进 digest |
| D5 | 求值器把未知 channel / 未注册 type 当成功 | **存在 → 已修** | 原 `event_evaluator.gd` 只解析锚点；`SIM_TYPES/VIEW_TYPES/AUDIO_TYPES` 仅 validator 使用；预览/单步路径静默接受垃圾事件 |
| D6 | `reset()` 清掉解析错误 | **不存在** | 求值器无持久 load 状态；`evaluate()` 每次重算并返回 bool，`sim_runner.run()` 出错即 `ok=false` |
| D7 | 时钟进 digest 且被 view 事件推进 | **不存在** | `SimState.snapshot()` 只含 seed/hud/level/board/orders/level_complete，无时钟；`state_hash()` 基于该快照 |

---

## 3. 本次修复（uncommitted，待用户审阅）

| 缺陷 | 修法 | 文件 |
|---|---|---|
| D3 | 新增 `BoardState.clamp_levels(entities, hard_cap)`，载入关卡后把等级夹到 `[1, min(10, 实体 maxLevel)]`；生成器产出同样夹取 | `core/sim/board_state.gd`、`core/sim/sim_state.gd`、`core/sim/generator_engine.gd` |
| D5 | `EventEvaluator.evaluate()` 校验 `channel ∈ sim/view/audio` 与 `type` 是否已注册；非法事件记 error 且不进入执行列表（与 validator 口径一致） | `core/event_evaluator.gd` |
| 回归 | 新增 `tests/test_core_defects.gd`（D2/D3/D5，20 checks）；同步调整 `test_event_evaluator.gd` 的排序用例；注册进 `run_tests.gd` | `tests/test_core_defects.gd`、`tests/test_event_evaluator.gd`、`tests/run_tests.gd` |

验证：442 checks 全过；validate/simulate 无回归。

---

## 4. 对照 AUDIT-S1 的差异（资源 / 可搬移 / manifest / schema / 事件模型）

| 审计项 | 03_Game_ds | 02_Game | 判定 |
|---|---|---|---|
| 资源红线 | 7 个载荷资产；REFERENCE_ONLY 交集 0；其余程序化绘制 | `assets.json` 仅 **PLACEHOLDER 20 + PRODUCTION 2**，REFERENCE_ONLY/TODO 0；`sync_assets.gd` 只复制允许项 | 两边都 PASS；02_Game 复制了 22 个允许占位，03_Game_ds 只留 7 个并程序化绘制 |
| 可搬移 | 文本文件零盘符路径；无 `.godot` 依赖；整目录 tar 后可直接跑 | 运行数据用 `res://`；但 `assets/assets.json` 含**绝对路径**（`manifest_path` + 22 条 `source`），`render.sh` 默认 `GODOT_BIN=E:/...`（可环境变量覆盖）；无 `.godot` 时需 `--import` | **02_Game 达不到 03_Game_ds 的“零盘符 + 免导入”严格口径**（运行不依赖绝对路径，属元数据/脚本层面差异） |
| manifest 快照 | `data/manifest_index.json`：74 条、计数/缺失/字段/basename 全审计 | `assets/assets.json`：只记录**已复制的 22 条**（id/usage/license/source），非 74 条全量快照 | 02_Game 缺全量快照与漂移审计；单条 `source` 还是机器绝对路径 |
| schema v2 | strict 模式把 `meta.duration` 升为错误 | 同一项是 **warning**（“已废弃，不作为时长来源”）；`next` 指针、kind、HUD、maxLevel=10、slot `entity` 均有校验 | 主规则一致；02_Game 的 strict 档更松 |
| 事件模型 | `event_model.gd` + `event_evaluator.gd` 共享；禁 wait；排序 §3.2 | `event_evaluator.gd` 被 validator / 预览 / 单步 / 出片共用；排序一致；**修复后**未注册 channel/type 在求值层即报错 | 修复后两边口径一致 |

---

## 5. 对照 03_Game_ds README §6「已知限制」的 02_Game 对应项

| 03_Game_ds 已知限制 | 02_Game 对应情况 |
|---|---|
| merge 不限定 kind；`directOrder:false` 未定义 | **同样存在**，两边都待设计裁决（见 §7） |
| 选中放大/靠近为静态量，无 Tween | 02_Game 有 Tween 表现，但出片用 `--fixed-fps`，确定性已由两次 framemd5 验证 |
| 角色消失用溶解，不隐藏订单卡头像 | 02_Game 有角色 idle/done 切换与消失流程（`order_view.gd`） |
| 主题不覆盖 chip/格子底色 | 02_Game 主题覆盖 `chip_palette`、`board_frame`、字体、背景、star，覆盖面更广 |
| 能量只由 `energy_tick` 事件改变 | 02_Game 顶栏倒计时由**时间轴 elapsed** 推导（`main.gd` 的 `_elapsed`，固定帧步长），非 wall clock；`energy_tick` 改数值 |
| `tap` 只支持 `{target:{slot}}` | 02_Game 同为该形式 |
| 编辑器不做格子坐标编辑、折叠不持久化 | 02_Game 时间轴编辑器同理（M0 允许） |
| 中间产物为 AVI（非 PNG 序列） | 02_Game 按 M0 §6 用 **PNG 序列**（1800 帧，转码后清理） |
| 音频 TODO；帧级确定性仅本机 | 02_Game 相同（音频 TODO；仅本机验证） |
| 测试 runner 可能把运行期错误误报 PASS（AUDIT-S1 风险 2） | **02_Game 同类风险存在**：`run_tests.gd` 仅在 `failures` 非空时失败，无“最小断言数/结束哨兵” |

---

## 6. 对 03_Game_ds 的代码级交叉审查：已完成（对象为 commit cf8db56）

- 03_Game_ds 已提交 `cf8db56`（15:08:37，109 个跟踪文件）；main 上另有 `f0e6f01` 收录 HANDOFF 文档。
- 只读代码审查与实测已完成，详见 [CROSS-REVIEW-03_Game_ds-2026-11-04.md](CROSS-REVIEW-03_Game_ds-2026-11-04.md)。
- 复审时（15:22）其工作区又出现未提交改动（`src/core/sim.gd` 的 directOrder、`tests/t_sim_defects.gd`、`docs/evidence/`），需重新冻结后复核；本报告与交叉审查结论均以 `cf8db56` 为准。

---

## 7. 两个待裁决问题（只出方案，不改代码）

### 7.1 merge 是否限定 kind

- 现状：两边都只判 `同 entity + 同 level`，`SafeBox_X` 等 special 也能互合。
- 建议（同 HANDOFF）：**chip + generator 可合；special / character 不可合**。
- 依据：实机截图里生成器 Lv6 明确可合成升级；保险箱/能量箱/角色不应互合。
- 落地影响：`merge_engine.merge()` 需要 `entities` 表判断双方 kind；02_Game 的 `sim_runner._apply_merge` 已能拿到 `project_data`，改动局限在 core + 1 组回归测试；03_Game_ds 同理。

### 7.2 `directOrder` 语义

- 建议：`true` = 只有当前关卡存在未完成订单且缺该 `entity+level` 时才进稀有池；`false` = 可无条件稀有掉落。
- 02_Game 现状：`rareOutputs` **无条件**进入权重表；`direct_order` 只被解析并随 tap 结果返回，未参与过滤。
- 03_Game_ds 现状（其 REVIEW-CORE §4）：稀有产出已按“当前关有未完成订单且缺该物品”进池，`directOrder` 字段同样未被读取。
- 若采纳建议：02_Game 需在 `generator_engine.tap()` 组表时按语义过滤；03_Game_ds 需补齐 `false` 分支。该改动会改变产出概率与确定性 hash，必须在 M0 规格升版后两边同步改。

---

## 8. M1 计划建议（一页）

**推荐：批量变体 / 出片生产化**（优先于音频+特效、主题编辑器）。

- 目标：让视频团队不改代码即可批量产出 `project × theme × 文案` 变体。
- 范围：
  1. 变体清单（JSON/CSV）：`{project, theme, locale/文案覆盖, seed, 输出名}`；
  2. 队列执行：复用现有 `render.sh`，串行/并发上限、失败重试、断点续跑；
  3. 产物命名与 manifest：每个 MP4 绑定 variant 参数、资源 usage/license、framemd5；
  4. 失败汇总报告与退出码；磁盘清理策略。
- 验收：≥3 个变体一次跑完；单个失败不拖垮队列；每个产物 manifest 可追溯到资源 ID 与实际方；`--verify` 抽检 framemd5 一致。
- 理由：纯代码、直接服务复用；两边 M0 出片链路都已就绪，是投入产出比最高的一项。音频 5 项仍 TODO、特效静态占位，适合作为第二批；主题编辑器 UI 工作量最大，放第三。

---

## 9. 残余风险与建议

1. **测试 runner 假 PASS 风险**（同 AUDIT-S1 风险 2）：建议后续加“每套件最小断言数/结束哨兵”，或 CI 扫描 `SCRIPT ERROR`。
2. **assets.json 绝对路径**：建议在 M0 收口时把 `manifest_path` / `source` 改为相对路径或仅保留 basename + sha256（对齐 03_Game_ds 的可搬移口径）。
3. **免导入运行**：若要求“复制即出片”，需要像 03_Game_ds 那样用 `Image.load()` / `FontFile.load_dynamic_font()` 绕过 `.godot`；否则文档需写明首次 `--import`。
4. **03_Game_ds 未冻结**：代码级交叉审查与“两份审查报告对比”尚不能完成。

---

## 附：render verify 原始结果（2026-11-04，本 worktree）

```text
project=res://data/projects/sample_30s.json
width=1080  height=1920  fps=60  duration=30.000  frames=1800

第一次录制：1800 帧，用时 147s；转码后 ffprobe：1080x1920 60/1 frames=1800 duration=30.000000s
第二次录制：1800 帧，用时 145s；转码后 ffprobe：同上

结果: PASS framemd5 一致
framemd5 sha256: A=17fa27c9130bb5012ff16ad53442f8c65b91c10fdc66a5d68ba0fb310b1970ed
                 B=17fa27c9130bb5012ff16ad53442f8c65b91c10fdc66a5d68ba0fb310b1970ed
输出 sha256: d58d91c8f13b7277606b55b4593e5eb8d8f4ebe66f4c7916dbc87e684457bf96
总用时 341s（RENDER_EXIT=0）
```

产物：`02_Game/output/sample_30s.mp4`（641K，output/ 已 gitignore）。
