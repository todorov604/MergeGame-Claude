# 开工入口（M0）

1. **先读 [M0-冻结规格.md](M0-冻结规格.md)**：范围、数据模型 v2、事件模型 v2、资源守卫、验收、实现顺序。
2. **资源以 [resource_manifest.json](resource_manifest.json) 为准**；[resource_manifest.csv](resource_manifest.csv) 给脚本；[资源清单模板-v7.xlsx](资源清单模板-v7.xlsx) 只是只读视图（旧版本已归档至 [archive/](archive/)，过期勿用）。
3. **主文档 [买量视频工具-需求框架.md](买量视频工具-需求框架.md)** 保留背景、资源盘点和历史；与 M0 规格冲突时以 M0 为准。
4. **第一周只做三步**：manifest + schema validator → core sim/event evaluator → 静态 board view。
5. **红线**：`REFERENCE_ONLY` 资源（原游戏 icon/UI/PSD 导出/角色）禁止打包、禁止出片；`PLACEHOLDER` 必须显式允许；`TODO`（音频）出片前阻断。

## 环境（本机）

- Godot 4.7.2：`E:\Program Files\Godot\Godot_v4.7.2.exe`（4.7.2.stable.official）
- FFmpeg / ffprobe 9.0：已在 PATH（winget Gyan.FFmpeg）

当前版本：主文档 v0.19 / 资源 v7 / M0 规格 2026-11-03。
