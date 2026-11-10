# 剩余图标（v4 开源/占位补齐）许可证与来源

## Twemoji 图形
- 来源：https://github.com/jdecked/twemoji
- 许可：CC-BY 4.0（图形），代码 MIT
- 署名：Twemoji graphics © Twitter/X contributors
- 用途：v4 占位图标（特殊箱、货币、特效、CTA 等）

## Noto Sans / Noto Sans CJK
- 来源：https://github.com/googlefonts/noto-cjk ；https://github.com/googlefonts/noto-fonts
- 许可：SIL Open Font License 1.1（OFL）
- 用途：font_zh.otf / font_en.ttf

## 来自本项目的素材（非开源）
- board_frame.png、char_order_*_idle/done.png：来自 `E:\HotelManor_icon\棋盘.psd` 导出/合成
- 这些素材版权归项目方所有。


### 2026-11-09 棋盘界面拆解新增
- order_card_bar.png（订单卡九宫格底图，388×178）、gem_icon.png（钻石图标，39×32）、
  energy_icon.png（体力闪电图标，39×53）：
  来自 `E:\北京Icon\常用资产汇总\棋盘界面拆解\`，公司自有素材，1:1 复制未重编码。

## 生成占位
- ui_level_complete / ui_level_intro / ui_coin_reward_popup / ui_board_full_toast / fx_level_transition / cta_*：由 PIL 用 Twemoji + Noto 字体生成，仅作占位。

## 鼠标光标（2026-11-05，项目自有素材）
- 文件：`cursor_hand.png`（256×256 透明 PNG，sha256 `95d976801f08824ddb86ecdb8e2c7eebf786cdbfe2f582a9457f361e4b9db6eb`）
- 来源：项目方素材 `E:\北京Icon\常用资产汇总\棋盘界面拆解\手指.png`（2074×2048，白色 3D 手套）；原图另存为 `cursor_hand_source.png` 备查
- 许可：**公司自有（北京Icon 资产汇总）**，非开源素材
- 处理：PIL 按 alpha 裁边 → 透明区 RGB 填白（防缩放黑边）→ 等比放入 256×256 画布 → LANCZOS 缩放
- 用途：自由模式试玩窗口的手型光标（OS 光标隐藏，窗口内绘制）+ 成片里的光标 overlay，均按 72×72 显示，热点为指尖

## 棋盘底 / 亮格（2026-11-05，项目自有素材）
- `board_plate.png`（167×167，由 `E:\北京Icon\常用资产汇总\面板模板\素材\单独格子.png` 按 alpha 裁切，sha256 `825dad5f…`）
- `cell_light.png`（256×256，整字节复制自 `E:\北京Icon\常用资产汇总\棋盘界面拆解\浅色格.png`，sha256 `8376a77a…`）
- 许可：公司自有（北京Icon 资产汇总）；`board_plate_source.png` 为 1080×1920 原画布备份
- 用途：棋盘大底（九宫格拉伸）+ 隔格亮块

## 退出按钮（2026-11-05，项目自有素材）
- `exit_button.png`（159×176，整字节复制自 `E:\北京Icon\常用资产汇总\棋盘界面拆解\棋盘拆解_0000s_0017_返回按钮.png`，sha256 `ddf2a5a9…`）
- 许可：公司自有（北京Icon 资产汇总）
- 用途：左下退出按钮，替换程序化三角

## 底栏三件套（2026-11-05，项目自有素材）
- `bar_board.png`（388×178，任务背景板，sha256 `7fbd448f…`）
- `coin_reward.png`（146×147，奖励金币领取，sha256 `0dd0fbe6…`）
- `reminder.png`（58×58，提醒 ⓘ，sha256 `47634b03…`）
- 许可：公司自有（北京Icon 资产汇总）；用途：底栏底板 / 金币按钮 / 提示图标（分层绘制，文字由代码写）

## 生成器图标 + 体力闪电（2026-11-05，项目自有素材）
- `generator_icon.png`（182×182，猫形置物架；源 `棋子icon/icon_20001010.png`，sha256 `3d6ee6f3…`）
- `stamina.png`（39×53，黄色体力闪电；源 `棋盘界面拆解_0000s_0005_体力.png`，sha256 `d0ab4eb2…`）
- 许可：公司自有（北京Icon 资产汇总）；用途：棋盘生成器主图标 + 左下角体力徽标

## 底栏分隔线（2026-11-05，项目自有素材）
- `common_line.png`（10×4，纯白细线；源 `界面ui/common_line.png`，sha256 `7f197958…`）
- 许可：公司自有（北京Icon 资产汇总）；用途：底栏两段 label 之间的分隔线，横向拉伸后调制成 #C4D7E2

## 底栏分隔线（2026-11-05，项目自有素材）
- `common_line.png`（10×4，1.6 KB）；来源目录未保留原图，工程副本与归档副本一致
- 许可：公司自有（北京Icon 资产汇总）；用途：底栏标题与副标题之间的分隔线（运行拉伸 420×4）

## 注意
- Twemoji 是扁平 emoji 风格，与项目现有 3D 卡通宠物店风格仍有差距；正式投放前建议替换为项目自绘/外包资源。
- 音频（audio_*）未补：属于音效/BGM，不是图标。
- 2026-11-09 新增两个棋子系列（任务图标扩到 4 个）：`icon_10001101..110.png`（零食袋，实体 CleanSet_Cc）
  与 `icon_10005101..110.png`（沙滩球，实体 CleanSet_Cd），均取自工程内 `01_icon/HotelManor_icon/棋子icon/`。
- 2026-11-09 任务完成叹号：`exclamation.png`（由 `界面切图/main_icon_exclamation1.png` 复制，52×52）。

## generator_premium.png（2026-11-10）

来自 `棋子icon/icon_20002010.png`，公司自有资产（北京Icon 资产汇总），仅本项目内使用。
