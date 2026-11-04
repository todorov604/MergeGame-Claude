# AGENTS.md — 本仓库协作约束（长期记忆）

本文件是跨会话的持久约定，优先级高于临时话术；新会话开工先读这里。

> **长期记忆载体 = 本文件**（2026-11-04 起）。`deja` 长期记忆已由操作者关闭：**不要调用 `deja_remember`**，它只会返回 `deja did not record that.`（本机 `~/.deja` 存储也不存在）。要沉淀经验，直接写进本文件，写入即对后续会话生效。

## 1. 核验类工作不要外派子代理

**结论：数字核对、复核报告对照、提交前验收，一律主会话自己做。**

依据（2026-11-04，03_Game_ds M0 收口）：

| 方式 | 实测耗时 |
|---|---|
| 主会话 `run_tests.gd`（19 套件 / 1134 checks） | 约 1.2–1.4 s |
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

## 4. 本轮已验证的事实锚点（03_Game_ds）

- 套件 19 / checks 1134 / failures 0；`t_sim_defects` 48 checks。
- 反例夹具 `tests/fixtures/broken/*.json` = 25 个。
- `data/manifest_index.json` = 74 条（`REFERENCE_ONLY` 47 / `PLACEHOLDER` 20 / `PRODUCTION` 2 / `TODO` 5），是 **M0 快照**，M1 按新 manifest 重建。
- `assets/` 只允许 7 个复制品 + `PROVENANCE.md`；`REFERENCE_ONLY` 一张都没进工程。
- 长期记忆不依赖 deja（已被操作者关闭）：经验写本文件，不写 `deja_remember`。
