# HANDOFF（新会话交接）

> 用途：换工作区 / 开新会话时，先读这份，再读权威文档。
> **这不是权威规格**：与 `M0-冻结规格.md` 冲突时，以 M0 规格为准。
> 快照日期：2026-11-04（M0 收口完成，规格 v0.21）。

---

## 1. 当前状态（M0 已收口）

- **02_Game（Claude lane）与 03_Game_ds（DeepSeek lane）的 M0 均已于 2026-11-04 收口。**
- 权威文档：`00_design/START-HERE.md`、`00_design/M0-冻结规格.md`（**v0.21**）、`00_design/resource_manifest.json`。
- Excel 只读视图：`00_design/资源清单模板-v7.xlsx`；CSV：`00_design/resource_manifest.csv`。
- 素材：`01_icon/HotelManor_icon`。
- 不要用：`00_design/archive/`、旧 v2–v6、`资源清单模板-current.xlsx`、主文档 §9 v1 Schema。

## 2. 提交链

```text
cf8db56 → 2be09d3 → 989d5a3 → 2845b85 → 4a9f20f → d73eaa3 → 44e067e → 75329e9 → 97387a2 → 4ce1e57 → 本次收口 3 个提交
```

- 本次收口 3 个提交：`75637a9` 10_report 归档 → `3f13c75` 02 README 已知限制 → 本提交（00_design 收口；hash 见 `git log -1`）。
- 关键节点：`cf8db56` 03 lane 全 9 步；`2be09d3` 02 lane 出片/主题/P0；`989d5a3` 证据 + `directOrder` + 02 交叉审查；`2845b85` 规格 v0.20；`4a9f20f` 02 收口 D3/D5；`d73eaa3` 02 落地 v0.20 + 可搬移/免导入；`44e067e` 03 缺陷修复（F1、N1–N5）+ 证据重生成；`75329e9` 03 README 收口登记；`97387a2` 03 已知限制表述修正；`4ce1e57` 根 `AGENTS.md` 长期记忆。

## 3. 两 lane 终验数字

### 02_Game（Claude）

| 项 | 实测 |
|---|---|
| tests | **499 checks / 0 failures**，exit 0；干净副本（无 `00_design`、无 `.godot`）同样 499/0（复核报告实测） |
| validate | `PASS (0 errors, 0 warnings)`（`--allow-placeholders`） |
| simulate | 双跑同 hash **`44999ee5…`**（seed=12345） |
| render `--verify` | **1800 帧 / 1080×1920@60 / 30.000s**；framemd5 **A=B=`17fa27c9…`**；输出 sha256 **`d58d91c8…`**（655792 字节） |

### 03_Game_ds（DeepSeek）

| 项 | 实测 |
|---|---|
| tests | **19 套件 / 1134 checks / 0 failures**，exit 0 |
| strict validate | `ok=true errors=0 warnings=0`（sample_project.json） |
| `accept.sh` | **9/9 ALL CHECKS PASS**（含 240 帧双跑 `same=YES`、25/25 反例、门禁拒绝、主题成片差异） |
| 可搬移 | `/tmp` 整目录副本 1134/0、strict 通过、未生成 `.godot`（复核报告实测） |

### 03_Game_ds 冻结证据 sha256（`docs/evidence/`，已逐项实算核对）

| 文件 | sha256 |
|---|---|
| `render.mp4` | `663c484aba61c781e1856cf0e009f5650f6b804681d9f42f66140e15319b979c` |
| `render_manifest.json` | `ee8f372164233c3a79f199c434d1c43ccdc63d6c3fabe0ad611d97c6ec78ca2a` |
| `render_framemd5.txt` | `9d7b9030909cc365499885c1c43069bd5e29f0e29e9c6ec9aef13a53c5e11cf6` |
| `theme_default.framemd5` | `228a63d685f018f631834e248e5d522f4337265c42f3c1401a361aa9d9ed9b83` |
| `theme_pet.framemd5` | `4d9787311e72ce5259b36a0db44bd42a94b9001bea91cae677ca3a55295ff3c7` |
| `accept.log` | `14b1072e79868dc5ea8f5094934a9311b86a0e5afeb35fe496203e37660950c5` |

## 4. 复核与审查报告

- 一轮交叉审查：`10_report/CC02/M0交叉审查一轮-1104.md`（DeepSeek→02_Game）、`10_report/DS03/M0交叉审查一轮-1104.md`（Claude→03_Game_ds）。
- 二轮交叉审查：`10_report/CC02/M0交叉审查二轮-1104.md`、`10_report/DS03/M0交叉审查二轮-1104.md`；对读结论：`10_report/M0二轮对读-1104.md`。
- 修复复核：`10_report/CC02/M0修复复核-1104.md`（DeepSeek→02_Game）、`10_report/DS03/M0修复复核-1104.md`（Claude→03_Game_ds）。
- 02 收口自审：`10_report/CC02/M0收口自审-1104.md`。

## 5. 已知限制

- **02_Game**：见 `02_Game/README.md` 的「M0 已知限制（收口登记）」——P2-3（订单可达性漏杀）、P2-4（校验门禁口径不一）、P2-5（`resource_guard` 未接入）、P2-6（快照不含生成器/RNG）、P2-9（audio 通道不可用）、B1（错误码非结构化）、B2（validator 不校验 merge 语义）、D1（不扫运行期 `ERROR:`）、C1（`.uid`/`.import` 策略）、E1（可达性对 rareOutputs 无条件计 charges）。
- **03_Game_ds**：见 `03_Game_ds/README.md` 的「M0 已知限制」——P2-3（成片端未消费 `camera` / `character_leave` / `character_next`，样片 `camera` 被忽略）、NEW-1（订单多件需求/共享 `charges` 未联合扣减）、NEW-2（`outputs[].level` 无校验/无诊断）。
- 以上均为 P2 级、不阻塞 M0 交付，列入 M1 待办。

## 6. 资源口径

- `00_design/resource_manifest.json` 现为 **180 条**：`01_icon` 公司自研素材全部登记为 `PRODUCTION`（`REFERENCE_ONLY` 0 条），棋子icon 120 张全部登记为可用；另有 `PLACEHOLDER` 20 条（Twemoji/PIL 占位）与 `TODO` 5 条（音频）保留。CSV 与 Excel 视图已同步重生成。
- 两 lane 的 `data/manifest_index.json` 仍是 **74 条 M0 快照**（`REFERENCE_ONLY` 47 / `PLACEHOLDER` 20 / `PRODUCTION` 2 / `TODO` 5）。M1 主题接入时按新 manifest 重建；期间主题仍只能引用快照中已有的 `PLACEHOLDER` / `PRODUCTION`，不得引用新 icon。

## 7. M1 计划（已裁决）

1. **双 lane 并行、同题 PK**：02_Game 与 03_Game_ds 各做一版，不合并代码、不互相改目录。
2. **首个功能：批量变体 / 出片生产化**（project × theme × 文案多 variant、队列、命名、manifest、失败重试）。
3. **统一验收口径**：tests / validate / simulate / render 确定性 + 可搬移 + 证据，两 lane 用同一套判据。
4. 各出一版后择优；**败者归档不删**。
5. 分歧语义（规格 v0.21 §10 所列 `track`/`order`、`audio`、`deliver`/`order_claim`/`energy_tick` 等）以胜者实现写入 **v0.22**。

## 8. 环境与红线

- Godot 4.7.2：`E:\Program Files\Godot\Godot_v4.7.2.exe`（4.7.2.stable.official）。
- FFmpeg / ffprobe 9.0：已在 PATH（winget Gyan.FFmpeg）。
- 资源唯一事实源：`00_design/resource_manifest.json`；Excel 只读、CSV 给脚本。
- 红线：`REFERENCE_ONLY` 禁止打包/出片；`PLACEHOLDER` 需显式允许（`allow_placeholders=true`）；`TODO` 出片前阻断。

## 9. 新会话怎么开（M1 入口）

```text
先读 00_design/HANDOFF.md、00_design/START-HERE.md、00_design/M0-冻结规格.md（v0.21）、00_design/resource_manifest.json。
按 HANDOFF.md §7 的 M1 计划执行：两 lane 并行、同题 PK，首个功能=批量变体/出片生产化；不要用 00_design/archive/、旧 v2–v6 或主文档 §9 v1。
```

## 10. 不要做

- 不要用 `00_design/archive/` 里的旧 Excel / CSV。
- 不要把主文档 §9 v1 当 Schema 权威；v2 在 `M0-冻结规格.md` §2/§3。
- 不要在 M1 PK 期间以对方 lane 的现行语义为缺陷互判（v0.21 §10 已列待定项）。
- 不要为了“对齐对方”而改设计；先出方案，用户拍板。
- 不要在未同步 180 条 manifest 前引用/打包新 icon（两 lane 快照仍为 74 条）。
- 不要提交 `output/`、`.godot/` 等构建产物。
