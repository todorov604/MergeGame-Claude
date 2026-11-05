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

## 生成占位
- ui_level_complete / ui_level_intro / ui_coin_reward_popup / ui_board_full_toast / fx_level_transition / cta_*：由 PIL 用 Twemoji + Noto 字体生成，仅作占位。

## 鼠标光标（2026-11-05，项目自有素材）
- 文件：`cursor_hand.png`（256×256 透明 PNG，sha256 `95d976801f08824ddb86ecdb8e2c7eebf786cdbfe2f582a9457f361e4b9db6eb`）
- 来源：项目方素材 `E:\北京Icon\常用资产汇总\棋盘界面拆解\手指.png`（2074×2048，白色 3D 手套）；原图另存为 `cursor_hand_source.png` 备查
- 许可：**公司自有（北京Icon 资产汇总）**，非开源素材
- 处理：PIL 按 alpha 裁边 → 透明区 RGB 填白（防缩放黑边）→ 等比放入 256×256 画布 → LANCZOS 缩放
- 用途：自由模式试玩窗口的手型光标（OS 光标隐藏，窗口内绘制）+ 成片里的光标 overlay，均按 72×72 显示，热点为指尖

## 注意
- Twemoji 是扁平 emoji 风格，与项目现有 3D 卡通宠物店风格仍有差距；正式投放前建议替换为项目自绘/外包资源。
- 音频（audio_*）未补：属于音效/BGM，不是图标。
