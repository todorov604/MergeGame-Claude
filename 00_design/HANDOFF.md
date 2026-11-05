# HANDOFF（新会话交接）

> 用途：换工作区 / 开新会话时，先读这份，再读权威文档。
> **这不是权威规格**：与 `M0-冻结规格.md` 冲突时，以 M0 规格为准。
> 快照日期：2026-11-05（**M1 实施与复核完成，待用户 PK 择优**；规格仍为 v0.21，v0.22 未写）。

---

## 1. 当前状态（M1 实施与复核完成，待 PK）

- 02_Game（Claude lane）与 03_Game_ds（DeepSeek lane）的 M1 均已完成并独立复核：两 lane 复核结论均为 **0 项未达成**（02 的「视觉对齐 §20.5」为部分达成，差异已逐条登记）；**尚未判定**，PK 由用户拍板。
- M1 期间**未改规格**；`track`/`order` 排序键、`audio` 语义、`deliver`/`order_claim`/`energy_tick` 等分歧仍留到 PK 后按择优结果写入 **v0.22**。
- 权威文档：`00_design/START-HERE.md`、`00_design/M0-冻结规格.md`（**v0.21**）、`00_design/resource_manifest.json`（**v8**，191 条）。
- Excel 只读视图：`00_design/资源清单模板-v8.xlsx`；CSV：`00_design/resource_manifest.csv`（均于 2026-11-05 随 v8 重生成）。
- 素材：`01_icon/HotelManor_icon`。
- 不要用：`00_design/archive/`、旧 v2–v7、`资源清单模板-current.xlsx`、主文档 §9 v1 Schema。

## 2. 提交链

```text
cf8db56 → 2be09d3 → 989d5a3 → 2845b85 → 4a9f20f → d73eaa3 → 44e067e → 75329e9
→ 97387a2 → 4ce1e57 → 75637a9 → 3f13c75 → 05d6083 → 3219211
→ f3454fa（03 M1）→ bcbf06a（02 M1）→ 7514926（03 收口）→ 本轮收口 3 个提交
```

- **M1 两 lane 提交**：`f3454fa` 03_Game_ds（180 快照 + 20 张真实图标 + `chip_icons` + §20.5 画面重建）；`bcbf06a` 02_Game（真实图标 / 资产主题配置 / PSD 画面对齐）。
- **03 收口提交**：`7514926`（README 数字对齐复核实测值 + 已知视觉差异 D1–D11 登记 + 9 条待补登清单）。
- **本轮收口 3 个提交**（hash 见 `git log`）：commit 1 = 02_Game 工作区清理 + README（P1-1/P1-2/已知差异）；commit 2 = 00_design manifest v8 补登 + xlsx/CSV + HANDOFF + M1 实施步骤；commit 3 = 10_report 归档（M1 复核报告、话术）。
- 关键节点（M0 及以前）：`cf8db56` 03 lane 全 9 步；`2be09d3` 02 lane 出片/主题/P0；`989d5a3` 证据 + `directOrder` + 02 交叉审查；`2845b85` 规格 v0.20；`4a9f20f` 02 收口 D3/D5；`d73eaa3` 02 落地 v0.20 + 可搬移/免导入；`44e067e` 03 缺陷修复（F1、N1–N5）+ 证据重生成；`75329e9`/`97387a2` 03 README 收口与表述修正；`4ce1e57` 根 `AGENTS.md` 长期记忆；`05d6083` M0 收口（manifest 180 条 + 规格 v0.21）。

## 3. 两 lane 终验数字（M1，实测）

### 02_Game（Claude）

| 项 | 实测 |
|---|---|
| tests | **717 checks / 0 failures**，exit 0；干净副本（无 `00_design`、无 `.godot`）同样 717/0 |
| validate | `PASS (0 errors, 0 warnings)`（`--allow-placeholders`） |
| simulate | 双跑同 hash **`44999ee5…`**（seed=12345） |
| 出片 | 1800 帧 / 1080×1920@60 / 30.000s；单跑 **107–114s**（≤5 分钟） |
| 主题差异 | pet vs candy **1800/1800 帧不同**；新增主题（2 个 JSON、零 `.gd`）亦 1800/1800 帧不同 |
| 资产合规 | 66/66 与源文件逐字节相同；`REFERENCE_ONLY` 0；`assets/` PNG 64 张 = `assets.json` 精确相等 |

**framemd5 依赖导入缓存态（P1-2）**：同一 HEAD 有三种稳定输出（各自双跑稳定），验收建议统一用**无缓存态**：

| 缓存态 | framemd5 | mp4 sha256 |
|---|---|---|
| 无缓存（纯净副本） | `4dc74c8168ab3bda…` | `361ce1088c7a71e1…` |
| 22 个 M0 ctex（作者态） | `6accae7c697c264c…` | `0acc8978e066f398…` |
| 全量缓存（编辑器打开过） | `f7f28fc8a10876f0…` | `08674e20f4ec800a…` |

### 03_Game_ds（DeepSeek）

| 项 | 实测 |
|---|---|
| tests | **20 套件 / 1681 checks / 0 failures**，exit 0 |
| strict validate | `ok=true errors=0 warnings=0`（`sample_project.json`；`asset_refs=41`、`index_ids=189`） |
| `accept.sh` | **9/9 ALL CHECKS PASS**（25 条反例、搬移副本 1681/0、240 帧双跑 `b42fff51…`、门禁拒绝、主题成片差异） |
| 30s 出片 | 1800 帧 / 1080×1920@60 / 30.000s / **128s**（≤5 分钟） |
| 主题差异 | 60 帧 default `f81c1cb311d6` ≠ pet `65a941acded1`；300 帧 `e2c7f9ba…` / `bb92abd5…`；三套主题均零 `.gd` 改动 |
| 快照重建 | 与提交版**字节相同** `c36f7261…`（180 条、10 字段 0 差异） |

### 03_Game_ds 冻结证据 sha256（`docs/evidence/`，M0 归档，仍有效）

| 文件 | sha256 |
|---|---|
| `render.mp4` | `663c484aba61c781e1856cf0e009f5650f6b804681d9f42f66140e15319b979c` |
| `render_manifest.json` | `ee8f372164233c3a79f199c434d1c43ccdc63d6c3fabe0ad611d97c6ec78ca2a` |
| `render_framemd5.txt` | `9d7b9030909cc365499885c1c43069bd5e29f0e29e9c6ec9aef13a53c5e11cf6` |
| `theme_default.framemd5` | `228a63d685f018f631834e248e5d522f4337265c42f3c1401a361aa9d9ed9b83` |
| `theme_pet.framemd5` | `4d9787311e72ce5259b36a0db44bd42a94b9001bea91cae677ca3a55295ff3c7` |
| `accept.log` | `14b1072e79868dc5ea8f5094934a9311b86a0e5afeb35fe496203e37660950c5` |

## 4. 复核与审查报告

**M1 实施报告**：`10_report/CC02/M1实施报告-1105.md`（02）、`10_report/DS03/M1实施报告-1105.md`（03）。
**M1 独立复核报告**：`10_report/CC02/M1实施复核-1105.md`（DSH→02：P1-1/P1-2、V1–V10、P2-a..f）、`10_report/DS03/M1实施复核-1105.md`（Claude→03：P2-1..8、D1–D11、PK 观察）。

**02 收口处理（本轮）**：
- P1-1 已处理：`git checkout -- 02_Game/project.godot 02_Game/assets/*.import`，删除 44 个未跟踪 `.import`；`git status --short -- 02_Game` 已为空；新增 `02_Game/.gitattributes`（`*.import text eol=lf`）防再犯。
- P1-2 已处理：`02_Game/README.md` 新增「framemd5 与导入缓存态」表（无缓存 / 22 ctex / 全缓存三态 + 双跑稳定说明），验收统一建议用无缓存态；旧基线表述已加缓存态限定。
- 已知差异 V1–V10 与 P2-a..f 已补进 `02_Game/README.md`（「M1 复核登记：已知视觉差异」），不修代码。

**03 收口（`7514926`）**：README 7 处旧数字已对齐复核实测值（1681 checks、`b42fff51…`、`asset_refs=41`、`assets=43` 等）；D1–D11 视觉差异已登记；9 条本地登记素材的补登清单已写入 README §5.2 与实施报告 §8.1（本轮已由 00_design 补登，见 §6）。

M0 报告：`10_report/CC02/M0交叉审查一轮/二轮-1104.md`、`10_report/DS03/…`、`10_report/M0二轮对读-1104.md`、`10_report/CC02|DS03/M0修复复核-1104.md`、`10_report/CC02/M0收口自审-1104.md`。

## 5. 已知限制与视觉差异

- **02_Game**：M0 P2 残留（P2-3/4/5/6/9、B1/B2、D1、E1，见 README「M0 已知限制」）+ M1-1（其余 100 张棋子图标未打包）+ M1-3（画面非阻塞差异）；P1-1/P1-2 已在本轮收口闭合。
- **03_Game_ds**：M0 P2-3 / NEW-1 / NEW-2；M1 视觉差异 D1–D11（格底 lip、生成器程序化、冻结/区域遮罩单格、游戏页顶栏货币图标空缺、退出按钮无箭头、底栏文案、静态棋盘调试层等，见 `03_Game_ds/README.md` §6.1）。
- **两 lane 共同的视觉缺口**：part2 第二张订单卡（样例数据只有 1 单）、商店按钮/货币图标映射、多格障碍组（冻结/区域遮罩）、无缝棋盘格、生成器箱体美术。均不阻塞 M1，列入 M2/v0.22 候选。
- 以上均为 P2 级、不阻塞 M1 交付；M1 已收口，PK 由用户决定。

## 6. 资源口径（manifest v8）

- `00_design/resource_manifest.json` 已由 **v7/180 条** 补登为 **v8/191 条**：`PRODUCTION 166 / PLACEHOLDER 20 / TODO 5 / REFERENCE_ONLY 0`。
- 本轮补登 **11 条**（均为 `PRODUCTION`、`status=可用`、`license=公司自有/自研`、`file` 指向真实源文件）：
  - 03 侧 9 条：`ui_bg_top`、`ui_level_badge_bg`、`ui_icon_finish`、`ui_btn_plus`、`ui_button_shop`、`char_part1`、`char_part2`、`ui_items_bar`、`ui_board_frame`（`ui_board_frame` 同时是对 `board_frame`（v7 PLACEHOLDER）的 usage 升级提案）。
  - 02 侧新增 2 条：`ui_icon_exit`（`main_icon_exit.png`，82×80，绘制到 164×174）、`ui_icon_gem`（`raw_icon_90000003.png`，35×30）；02 的另 3 条（`local_bg_top`/`local_items_bar`/`local_icon_finish`）分别与 03 的 `ui_bg_top`/`ui_items_bar`/`ui_icon_finish` 同源，各合并为一条记录。
- 视图已同步：`00_design/资源清单模板-v8.xlsx`（在 v7 工作簿上追加 11 行，标题/筛选范围已更新）、`00_design/resource_manifest.csv`（192 行 = 表头 + 191 条）。
- 两 lane 的 `data/manifest_index.json` **仍是 v7/180 条快照**（02：180；03：180 + 8 别名 + 9 本地登记）。v8 新增条目尚未进入 lane 快照；M2 重建快照后再引用这些 id。M1 PK 的证据仍以各 lane 的 v7/180 快照为准。

## 7. M1 计划（已完成，2026-11-05 收口）

**状态：三步全部完成；两 lane 已实施并独立复核；待用户 PK 择优。未判定，未写 v0.22。**

**目标**：资产/主题配置化出片——配置一套资产（不同 icon 等）→ 出一条片；批量为后续可选项（P2），本轮不做。

**视觉目标（2026-11-05 追加）**：画面（尤其背景）尽量贴近主文档 §20.5「棋盘.psd 结构」与 `00_design/images/psd_slices/board_full_preview.jpg`（1080×1920）；版权无问题（公司自有），除合成 chip 用自有 icon 链外，布局与素材尽量一致；验收为 1080×1920 截图并排对比。

| # | 步骤 | 状态 | 证据 |
|---|---|---|---|
| 1 | 真实 icon 接入（最优先） | ✅ 完成 | 两 lane 快照 74→180；Ca/Cb 各 10 级 20 张真实图标 sha256 与源一致；`chip_icons` 打通棋盘/成片 |
| 2 | 资产/主题配置流程 | ✅ 完成 | 换主题只改 JSON、零 `.gd`；framemd5 不同；配置+出片约 2 分钟（≤10 分钟） |
| 3 | README + 验收 | ✅ 完成 | 02：717/0 + validate PASS + sim 一致；03：1681/0 + strict + accept 9/9；30s 出片均 ≤5 分钟 |

**验收**：真实图标样片/截图（chip 非占位）✅；换主题不改代码 ✅；单条 30s 出片 ≤5 分钟 ✅；双跑 framemd5 一致（同缓存态）✅；不同主题 framemd5 不同 ✅。

**不做（当前目标）**：批量调度器、变体契约、重试/日志、第二主题变体、`batch_accept.sh`、断点续跑、并行 worker、队列 UI、全量双跑；音频、序列帧、主题编辑器 UI、经济/商店。批量能力留作后续 P2。

**执行方式**：双 lane 并行、同题 PK——02_Game 与 03_Game_ds 各做一版，不合并代码、不互相改目录；择优后**未选中版本归档不删**；分歧语义以择优结果写入规格 **v0.22**（待用户 PK 后执行）。

## 8. 环境与红线

- Godot 4.7.2：`E:\Program Files\Godot\Godot_v4.7.2.exe`（4.7.2.stable.official）。
- FFmpeg / ffprobe 9.0：已在 PATH（winget Gyan.FFmpeg）。
- 资源唯一事实源：`00_design/resource_manifest.json`（v8）；Excel 只读、CSV 给脚本。
- 红线：`REFERENCE_ONLY` 禁止打包/出片；`PLACEHOLDER` 需显式允许（`allow_placeholders=true`）；`TODO` 出片前阻断。
- 02_Game 的 `.import` 行尾由 `02_Game/.gitattributes` 固定为 LF；03_Game_ds 无 `.import` 旁车。

## 9. 新会话怎么开（M1 之后）

```text
先读 00_design/HANDOFF.md、00_design/START-HERE.md、00_design/M0-冻结规格.md（v0.21）、00_design/resource_manifest.json（v8）。
M1 已完成并复核，等待用户 PK 择优；PK 后按择优结果语义写 v0.22，并把未选中版本归档（不删）。
不要用 00_design/archive/、旧 v2–v7 或主文档 §9 v1。
```

## 10. 不要做

- 不要用 `00_design/archive/` 里的旧 Excel / CSV。
- 不要把主文档 §9 v1 当 Schema 权威；v2 在 `M0-冻结规格.md` §2/§3。
- 不要在 PK 前下结论，或以对方 lane 的现行语义为缺陷互判（v0.21 §10 已列待定项）。
- 不要为了“对齐对方”而改设计；先出方案，用户拍板。
- 不要在未重建 lane 快照前引用 v8 新增 id（两 lane `manifest_index.json` 仍为 v7/180 条）。
- 不要提交 `output/`、`.godot/` 等构建产物。
