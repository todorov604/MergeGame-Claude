# MergeGame 关卡编辑器（05_editor）

网页版关卡编辑器：**改关卡 / 任务 / 图表 → 保存 → Godot 按 F5 玩一遍并录制 → 自动出片**。

## 打开

- 直接双击 `index.html`（推荐 Chrome / Edge）。
- 如果浏览器不给「选择目录」权限（少数环境），在本目录执行 `serve.bat`，
  然后访问 <http://localhost:8765/05_editor/index.html>。

## 用法

1. 点 **打开工程目录…**，选择：`E:\MergeGame-Claude\03_Game_ds\data`
   （只需授权一次；关掉标签页后要重新选）
2. 左侧选关卡 → 中间 540×960 预览 → 右侧改：
   - **格子**：点棋盘选一格，选「棋子（实体+等级）」或「障碍（锁盒/网/冰/冰盒）」，点「应用」
   - **关卡设置**：`blast`、`ice_seconds`、`safes`、`stockpile`
   - **订单**：角色、金币/星星/钻石/体力、任务行（实体/等级/数量）
3. 点 **保存（自动备份）**：会把旧文件写进 `03_Game_ds/data/backup/`，再覆盖 `sample_project.json`
4. 回 Godot 按 **F5** 玩一遍，按 **R** 停止 → 自动渲染出片

## 备份 / 恢复

- 每次保存前自动快照：`03_Game_ds/data/backup/sample_project-YYYYmmdd_HHMMSS.json`
- 左下「备份 / 恢复」列表点 **恢复** 即可回滚（恢复前也会先把当前版本存一份）
- 原始基准档：`03_Game_ds/data/backup/sample_project-original.json`（入库、只读）

## 保存后建议再跑一次 Godot 校验

```bash
"/e/Program Files/Godot/Godot_v4.7.2.exe" --headless --path 03_Game_ds \
  --script res://src/tools/cli.gd -- validate --project res://data/sample_project.json --strict --out ""
```

校验器比网页版严格（还会查订单是否可达、素材是否登记）。网页里的「校验」只做结构检查。

## 注意

- 改棋盘坐标会让**旧 take 失效**（录制里写死格子坐标），需要重新录一条。
- 图标不能手填路径：编辑器只从 `manifest_index.json` / `assets_local.json` 里列已登记的资源。
