# 02_Game（M0 · Godot 4.7.2）

1080×1920 @ 60fps 的 merge 广告工具工程。自包含：资源、项目样例、core sim、视图、时间轴编辑器与出片脚本都在本目录内。

## 运行

```bash
godot --path 02_Game                      # 自动演示（R 重播，Space 暂停）
godot --path 02_Game res://editor/timeline_editor.tscn   # 时间轴编辑器
```

截图：`-- --capture <png> [--capture-at <秒>]`。
出片模式：`-- --project <项目> --render`（隐藏调试标签）。

## 校验 / 模拟 / 测试

```bash
godot --headless --path 02_Game -s res://tests/run_tests.gd        # 499 checks
godot --headless --path 02_Game -s res://tools/validate.gd -- --allow-placeholders
godot --headless --path 02_Game -s res://tools/simulate.gd         # 确定性双跑
```

## 自包含 / 免导入

- 本目录可单独复制运行，不依赖同级 `00_design`：manifest 快照内嵌在 `data/manifest_index.json`，测试与校验读取该快照（`simulate` 走 SimRunner，不依赖 manifest）。
- 测试 / 校验 / 模拟**不需要先执行 `--import`**。无 `.godot` 导入缓存时，资源加载回退为运行时解码（纹理 `Image.load_from_file` + `ImageTexture`，字体 `FontFile.load_dynamic_font`）；有缓存时优先使用导入资源，保持出片与既有 `framemd5` 基线一致。
- 若手动执行 `--import`，新增的 `*.uid` 已被 `.gitignore` 忽略；该命令不再是验收前置。
- 重新生成资源与内嵌快照（开发期，需显式指定源 manifest）：
  `REPO_ROOT=$(git rev-parse --show-toplevel)`
  `godot --headless --path 02_Game -s res://tools/sync_assets.gd -- --manifest "$REPO_ROOT/00_design/resource_manifest.json"`

> 样例主题 `pet_shop` 引用了 PLACEHOLDER 的 `board_frame`/`ui_icon_star`，所以样例校验需要显式 `--allow-placeholders`；不带该参数时会被资源守卫判 FAIL。

## 主题（第 7 步）

- 项目顶层 `theme` 指向 `themes/<name>/theme.json`；缺失时用 `themes/pet_shop`。
- 优先级：`theme` > 项目 `icons` > 内置默认；支持 `background.top/bottom`、`chip_palette`、`board_frame`、`fonts.ui`、`star`。
- 内置两套：`themes/pet_shop`（默认蓝）与 `themes/candy`（暖紫/粉）。换肤只需复制主题目录或改项目 `theme` 字段，不改代码。
- 主题资源只能引用 `assets.json` 中的 PLACEHOLDER（需 `allow_placeholders=true`）/PRODUCTION；REFERENCE_ONLY、TODO 会被 Validator 与运行时 AssetLoader 拒绝。

## 出片（Movie Maker + FFmpeg）

```bash
bash 02_Game/tools/render.sh                 # -> 02_Game/output/sample_30s.mp4
bash 02_Game/tools/render.sh --verify        # 双跑 + framemd5 对比
bash 02_Game/tools/render.sh --keep-frames   # 保留 PNG 序列
```

流程：`export_info` 跑 Validator 并算出帧数 → Godot Movie Maker 录制 PNG 序列（真实窗口、固定 60fps）→ FFmpeg H.264（`yuv420p`、`+faststart`、`-threads 1`）→ ffprobe 校验分辨率/帧率/帧数/时长 → 可选双跑 framemd5。

- M0 固定参数：1080×1920 / 60fps / 1800 帧（30s）；不满足直接失败。
- 磁盘预检 20GB（verify+keep 32GB）；帧序列用独立临时目录，转码后自动清理。
- 实测基准（2026-11-04，i7-12700 / RTX 4060 Ti 4G / 64GB RAM，最终 P0 构建）：1800 帧录制 151s / 196s，单次出片 177s / 223s（含 FFmpeg，均 ≤5 分钟），`--verify` 双跑总计 416s；两次 framemd5 sha256 均为 `17fa27c9…`，输出 sha256 `d58d91c8…`，文件 655792 字节（641K）。
- 帧数判定以每次独立临时目录的 PNG 文件序列为准（首帧 0、末帧 N-1、数量 N）；Godot 4.7.2 的退出摘要偶发少报帧数（实测一次 232 vs 实际 1800），脚本对此只告警，避免误判。
- 出片前阻断：非法项目（未定义实体、wait 事件、主题引用 REFERENCE_ONLY 等）由 `export_info` 的 Validator 门禁拦下，退出码 1，不产生视频。

## 资源策略

`assets/assets.json` 由 `tools/sync_assets.gd` 按源 `resource_manifest.json` 生成：只复制 PLACEHOLDER / PRODUCTION（22 项）；REFERENCE_ONLY（47 项）与 TODO（5 项）不进入工程。同一工具同时生成内嵌快照 `data/manifest_index.json`（74 条；打包资源指向 `res://assets/…`，其余保留无盘符的溯源路径），使工程在无 `00_design` 的干净副本中也能完成校验与测试。运行时统一经 `AssetLoader` 守卫，PLACEHOLDER 需 `allow_placeholders=true`。角色、棋盘、订单卡均为自绘占位，替换正式美术时按资源 ID 接入，不改逻辑。

## 编辑器（时间轴）

```bash
godot --path 02_Game res://editor/timeline_editor.tscn
godot --path 02_Game res://editor/timeline_editor.tscn -- --project res://tests/fixtures/broken_project.json --validate
```

- 轨道按 channel + track 分组折叠；属性面板支持绝对/相对锚点；播放/单步/重置；50 步撤销/重做。
- **自动保存**：编辑后每 30 秒写 `user://timeline_autosave.json`；窗口关闭时兜底保存。显式「保存草稿」写入 `user://timeline_draft.json` 并清除自动保存。
- **异常恢复**：启动时若存在自动保存草稿，弹窗选择「恢复草稿 / 丢弃」；capture 模式不弹窗。
- **校验面板**：工具栏「校验」列出全部 error/warning 与 JSON 路径；点击 `timeline[i]...` 条目直接选中对应事件；`--validate` 可在 capture 时直接打开面板。校验失败的项目仍可在编辑器打开定位，但 capture 默认会以退出码 1 结束（带 `--validate` 例外）。

## M0 验收状态（2026-11-04）

- ✅ 30s 固定模板出片：1080×1920@60、1800 帧、30.000s；两次 framemd5 一致。
- ✅ 两关配置与过关流程（level_1 → level_2）；订单完成链路：绿药丸 → 物品飞向角色 → 角色消失 → 金币/星星 → 新角色/新订单。
- ✅ 时间轴：绝对/相对锚点、同刻排序；预览/单步/出片共用同一求值器与快照。
- ✅ 资源守卫：REFERENCE_ONLY 禁止引用/出片；PLACEHOLDER 需 `allow_placeholders=true`；TODO 阻断。
- ✅ 换主题只改项目 `theme` 字段，两套主题（pet_shop/candy）验证。
- ✅ 顶栏 HUD：level / energy（mm:ss 倒计时）/ coin / star / gem / exp。
- ✅ 生成器棋盘已满 Toast（`board_full` 事件或满盘 tap 触发，1.5s）。
- ✅ 选中停留 3s 后，同 entity+level 的 chip 放大 1.08 并向选中格靠近 6px；时间轴 `hint` 事件同样生效。
- ✅ 订单可达性校验：初始棋盘 + 生成器 charges 推导，不可达订单在出片前阻断。
- ⏳ 音频为 TODO（M0 不出音轨）。

## 当前边界

- 音频为 TODO，出片无音轨。
- 芯片/角色/棋盘仍为自绘占位；主题 `chip_icons` 映射待有可用的非 REFERENCE_ONLY 芯片素材。
- Godot 4.7.2 Movie Maker 的退出摘要偶发少报帧数；`render.sh` 以每次独立帧目录的 PNG 文件序列为准（数量 + 首末帧编号）。
