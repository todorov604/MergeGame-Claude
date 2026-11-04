# 资源出处（PROVENANCE）

本目录下的文件都是**复制品**，工程内只引用复制后的副本（`res://assets/...`），从不引用 `01_icon/` 原目录。
复制规则：**只允许 `PLACEHOLDER`（需 `allow_placeholders=true`）与 `PRODUCTION`**；`REFERENCE_ONLY`（原游戏 chip 图标 / 障碍 / 背景 / 角色立绘 / UI 切图）一概不复制、不引用、不进包。

源路径相对工作区根，不写盘符，保证工程可整体搬移。

| 工程内路径 | manifest id | usage | license | 源文件（工作区相对） | sha256 |
|---|---|---|---|---|---|
| `assets/fonts/font_zh.otf` | `font_zh` | PRODUCTION | 项目自有字体 | `01_icon/HotelManor_icon/剩余图标/font_zh.otf` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| `assets/fonts/font_en.ttf` | `font_en` | PRODUCTION | 项目自有字体 | `01_icon/HotelManor_icon/剩余图标/font_en.ttf` | `b85c38ecea8a7cfb39c24e395a4007474fa5a4fc864f6ee33309eb4948d232d5` |
| `assets/ui/board_frame.png` | `board_frame` | PLACEHOLDER | 占位自绘/导出，可替换 | `01_icon/HotelManor_icon/剩余图标/board_frame.png` | `fea432ed74f09ccdcf5cad49ca5e450b50a42536d2584ad38e289b0895dd3edc` |
| `assets/ui/ui_icon_star.png` | `ui_icon_star` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/ui_icon_star.png` | `cd1b8201bebadd5a6c3430738a29f0c4c0cc0674e6c0ee97b2da5624d2bafa83` |
| `assets/ui/box_safe_x.png` | `box_safe_x` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_safe_x.png` | `17887bb0dce23afcccda98a51a7fe517d4a365dfc60dd197857774b162f93113` |
| `assets/ui/box_energe_w.png` | `box_energe_w` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_energe_w.png` | `81f7ff348baaa02b8db2ab68c7a8f820404dfe81b893271c0d877336dff5af61` |
| `assets/ui/box_treasure_y.png` | `box_treasure_y` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_treasure_y.png` | `314d61a47dbd5ddb626dfe3e269c1ed09279e96d49fbf097d789a2677119ae0c` |

## 不复制清单（红线）

`chip_clean_ca_lv01..06`、`chip_clean_cb_lv01..06`、`box_clean_c_lv01..03`、`obstacle_web/bubble/lock/ice`、`board_bg`、`slot_empty`、`slot_locked`、`ui_*`、`char_order_0*_idle/done`、`token_coin`、`fx_web_break` —— 全部 `REFERENCE_ONLY`，仅用于看构图与尺寸。

因此棋盘上的 chip / 障碍 / 选中框 / 完成态**一律程序化绘制**（自绘圆角矩形 + 家族色相 + 等级角标 + 白色括角 + 勾选）。这是 M0 的刻意选择：既守住版权红线，又让 `03_Game_ds` 不依赖外部素材即可启动。
