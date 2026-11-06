# AGENTS.md — 本仓库协作约束（长期记忆）

本文件是跨会话的持久约定，优先级高于临时话术；新会话开工先读这里。

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
