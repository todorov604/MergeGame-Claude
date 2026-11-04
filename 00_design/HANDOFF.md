# HANDOFF（新会话交接）

> 用途：换工作区 / 开新会话时，先读这份，再读权威文档。
> **这不是权威规格**：与 `M0-冻结规格.md` 冲突时，以 M0 规格为准。
> 快照日期：2026-11-04（含 03_Game_ds 冻结推送后的状态）。状态变化后请更新本文件或直接删掉。

---

## 1. 当前状态（快照）

### 工作区

- 根目录：`E:\MergeGame-Claude`
- 权威文档：`00_design/START-HERE.md`、`00_design/M0-冻结规格.md`、`00_design/resource_manifest.json`
- Excel 只读视图：`00_design/资源清单模板-v7.xlsx`
- 素材：`01_icon/HotelManor_icon`
- 不要用：`00_design/archive/`、旧 v2–v6、`资源清单模板-current.xlsx`、主文档 §9 v1 Schema

### 02_Game（Claude）

- M0 已完成并提交（`02_Game/` 自身最后一次提交 `2be09d3`；主分支此后还有 `f0e6f01`、`989d5a3` 两个 03_Game_ds 提交）。
- 实测（2026-11-04，独立复核）：**422 checks**；README 写的 366 已过期。
- **注意**：必须先 `--import`（或开一次编辑器）生成 `.godot` 导入缓存，否则干净克隆下 11 项资源加载失败；另依赖 `../00_design/resource_manifest.json` 相对路径，单独搬走工程会失败。
- 已知边界：音频 TODO、芯片/角色/棋盘仍是自绘占位、主题 `chip_icons` 映射待有非 REFERENCE_ONLY 素材。
- 下一步：按 `03_Game_ds/docs/REVIEW-02GAME.md` 的 R1–R3 对齐（merge 限定 kind、directOrder 参与筛选、去掉外部路径/缓存依赖）。

### 03_Game_ds（DeepSeek）

- M0 全 9 步已完成、已冻结并推送：`cf8db56`（工程）→ `f0e6f01`（HANDOFF）→ `989d5a3`（证据 + directOrder + 交叉审查）。`03_Game_ds/` 已是跟踪目录。
- 实测（2026-11-04）：**951 checks / 15 套件 / 0 failures**；`bash tools/accept.sh` 7 步 12 项 ALL CHECKS PASS；全片 1800 帧三份 framemd5 一致（`10b138d4…`）；整目录 tar 到临时目录后同样全绿（不依赖 `../00_design`，也不依赖导入缓存）。
- 复审记录：`docs/REVIEW-CORE.md`（core 7 项）、`docs/REVIEW-RENDER.md`（出片/守卫 7 项）、`docs/AUDIT-S1.md`（资源/可搬移/schema）、`docs/evidence/`（成片与截图 + sha256）。
- 已反向审查 02_Game：`docs/REVIEW-02GAME.md`（只读，未改对方文件）。
- 已知边界：音频 TODO；chip/角色程序化占位；主题不覆盖 chip 底色；帧级确定性仅本机验证。
- 下一步：可选吸收 02_Game 的 `sync_assets` 流程；M1 按 §5。

---

## 2. 下一步协议（两边都收口后再交叉审）

```
1. 各自跑真实验收：tests / validate / simulate / render verify
2. 各自冻结一个 commit（03_Game_ds 已于 `cf8db56` 冻结，02_Game 于 `2be09d3` 冻结）
3. 交叉审查：只读对方代码，不改对方目录、不抄代码
4. 只修自己确认的 P0 缺陷，补回归测试
5. 对比两份审查报告 → 用户拍板 merge/directOrder → 更新 M0 规格 → 开 M1
```

原则：

- 不要在对方还在写 M0 时去审它，审到的是运动中的快照。
- 不要两边同时互审；先各自冻结，再交换。
- 交叉审查只出证据和报告，不直接改对方工程。

---

## 3. 可直接复制的 Prompt

### Prompt A：Claude 02_Game 收口 + 审 03_Game_ds

```text
你是 02_Game 的 Godot 实现工程师。工作区 E:\MergeGame-Claude。

先读：
- 02_Game/README.md
- 03_Game_ds/README.md、03_Game_ds/docs/REVIEW-CORE.md、03_Game_ds/docs/AUDIT-S1.md、03_Game_ds/docs/PERF-BASELINE.md（只作对照，不照抄代码）
- 00_design/M0-冻结规格.md
- 00_design/resource_manifest.json

任务：M0 收口 + 交叉审查，不写新功能。

1) 实际跑 02_Game：
   "E:\Program Files\Godot\Godot_v4.7.2.exe" --headless --path 02_Game -s res://tests/run_tests.gd
   "E:\Program Files\Godot\Godot_v4.7.2.exe" --headless --path 02_Game -s res://tools/validate.gd -- --allow-placeholders
   "E:\Program Files\Godot\Godot_v4.7.2.exe" --headless --path 02_Game -s res://tools/simulate.gd
   记录真实 checks / failures / 输出摘要。render verify 放最后，时间允许再跑。

2) 按 03_Game_ds/docs/REVIEW-CORE.md 的 D1–D7 逐条检查 02_Game：
   有同类缺陷就修并补回归测试；没有就给出具体证据（文件/函数/测试名）。

3) 对照 AUDIT-S1 的资源红线、可搬移、manifest 快照、schema v2、事件模型，列出差异。

4) 对照 03_Game_ds README §6 的已知限制，判断 02_Game 对应项；不要为了对齐而改设计。

5) 两个待裁决问题只出方案、不改代码：
   - merge 是否限定 kind？建议 chip + generator 可合，special/character 不可合。
   - directOrder:false 语义？建议 true=只有当前订单需要时才进稀有池，false=可无条件稀有掉落。

6) 产出一页 M1 计划：从“批量变体/出片生产化、音频+特效序列、主题编辑器”里选一个推荐。

约束：不改 00_design；不 commit；不照抄 03_Game_ds 代码；先给计划再改代码。
```

### Prompt B1：DeepSeek 03_Game_ds 先收口

```text
你是 03_Game_ds 的 Godot 实现工程师。工作区 E:\MergeGame-Claude。

先读：
- 03_Game_ds/README.md
- 00_design/M0-冻结规格.md
- 00_design/resource_manifest.json

任务：只做 M0 收口，不开 M1，不审 02_Game。

1) 实际跑，不要只看 README：
   bash tools/accept.sh
   全量 tests
   validate / simulate
   render verify（时间允许）
   记录真实 checks / failures / 耗时 / 输出路径。

2) 按 M0 §7 逐条对照；未通过项只修 P0，补回归测试；不要加新功能。

3) 如果 README 说完成、但测试或审计有失败，以实际结果为准，先修失败。

4) 收口后把 03_Game_ds 冻结成一个 commit（我确认后再 commit），报告：通过项、未通过项、已知限制、commit hash。

不要动 02_Game；不要改 00_design。
```

### Prompt B2：DeepSeek 收口后审 02_Game

```text
你是 03_Game_ds 的审查者。工作区 E:\MergeGame-Claude。
只读 02_Game，不改它、不抄代码、不 commit。

先读 02_Game/README.md、02_Game/core/*.gd、02_Game/tests/*.gd、02_Game/tools/*.sh。
跑 02_Game 的测试（只读，不改文件）。

任务：交叉审查 02_Game。
- 对照 03_Game_ds/docs/REVIEW-CORE.md 的 D1–D7，逐条判断 02_Game 是否有同类缺陷；
- 对照 AUDIT-S1 的资源红线/可搬移/manifest/schema/事件模型；
- 列出 02_Game 的缺陷、差异、可借鉴点；
- 产出 1 页报告 + M1 建议。

不要修改 02_Game；不要开始 M1 代码。
```

---

## 4. 待用户拍板的两个设计问题

> **已写入 `00_design/M0-冻结规格.md` v0.20（2026-11-04）**；两边按同一版继续。

1. **merge 限定 kind** — **已裁决（2026-11-04），已入规格 v0.20 §2.1.9：只允许 `chip`**
   - 实现：`03_Game_ds` `_do_merge()` 返回 `SIM_NOT_MERGEABLE`（`special` / `generator` / `character` 一律不合），回归 `tests/t_sim_defects.gd::_test_merge_kind_gate`。
   - 理由：`generator_state` 按 entity id 共享电量，合成出的 Lv2 生成器会与 Lv1 共用同一电荷池，语义无法自圆；`special` 没有等级对应的美术与玩法。
   - 原建议「chip + generator 可合」作废；如坚持生成器可合，需先把电量改成 per-cell 并补 Lv2 生成器表现。02_Game 目前仍是任意 entity 可合，待对齐。

2. **`directOrder` 语义** — **已裁决并实现（2026-11-04），已入规格 v0.20 §2.1.10**
   - `true`（**缺省值**）= 只有未完成订单缺该 `entity+level` 时才进稀有池；`false` = 无条件稀有掉落。
   - 实现：`03_Game_ds` `sim.tap_pool()`；回归 `tests/t_sim_defects.gd::_test_direct_order_semantics`。缺省取 `true`，避免旧数据静默获得无条件稀有。
   - 02_Game 现状：`directOrder` 被读入但**未参与筛选**，`rareOutputs` 无条件进池，待对齐。

---

## 5. M1 建议顺序

1. **批量变体 / 出片生产化**（最推荐）
   - 复用现有 `render.sh`：project × theme × 文案多 variant、队列、命名、manifest、失败重试。
   - 纯代码，直接服务视频团队复用。
2. **音频 + 特效序列**
   - 音频 5 项仍 TODO；特效目前是静态占位。
3. **主题编辑器 UI**
   - 价值高但工作量最大，放批量之后。

---

## 6. 新会话怎么开

- 在 `E:\MergeGame-Claude` 里新开一个 **fresh** 会话（不要 fork 这段长对话）。
- 第一句：

```text
先读 00_design/HANDOFF.md、00_design/START-HERE.md、00_design/M0-冻结规格.md、00_design/resource_manifest.json。
按 HANDOFF.md 的“下一步协议”执行；不要用 00_design/archive/、旧 v2–v6 或主文档 §9 v1。
```

- 如果只想让新会话做 M0 收口，用 Prompt A / B1；不要一上来就做 M1。
- 如果要继续 M0 之后的功能，先完成交叉审查和设计裁决，再开 M1。

---

## 7. 环境

- Godot 4.7.2：`E:\Program Files\Godot\Godot_v4.7.2.exe`（4.7.2.stable.official）
- FFmpeg / ffprobe 9.0：已在 PATH（winget Gyan.FFmpeg）
- 资源唯一事实源：`00_design/resource_manifest.json`（v7，74 条；69 条有路径，5 条音频 TODO）
- 红线：`REFERENCE_ONLY` 禁止打包/出片；`PLACEHOLDER` 需显式允许；`TODO` 出片前阻断。

---

## 8. 不要做

- 不要用 `00_design/archive/` 里的旧 Excel / CSV。
- 不要把主文档 §9 v1 当 Schema 权威；v2 在 `M0-冻结规格.md` §2/§3。
- 不要在 03_Game_ds 未 commit 时审它。
- 不要两个会话同时互审同一个运动中的快照。
- 不要为了“对齐对方”而改设计；先出方案，用户拍板。
