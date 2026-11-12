# 资源出处（PROVENANCE）

本目录下的文件都是**复制品**，工程内只引用复制后的副本（`res://assets/...`），从不引用 `01_icon/` 原目录。
复制规则：**只允许 `PLACEHOLDER`（需 `allow_placeholders=true`）与 `PRODUCTION`**；`REFERENCE_ONLY`（原游戏 chip 图标 / 障碍 / 背景 / 角色立绘 / UI 切图）一概不复制、不引用、不进包。

源路径相对工作区根，不写盘符，保证工程可整体搬移。

| 工程内路径 | manifest id | usage | license | 源文件（工作区相对） | sha256 |
|---|---|---|---|---|---|
| `assets/fonts/font_zh.otf` | `font_zh` | PRODUCTION | 项目自有字体 | `01_icon/HotelManor_icon/剩余图标/font_zh.otf` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| `assets/fonts/font_en.ttf` | `font_en` | PRODUCTION | 项目自有字体 | `01_icon/HotelManor_icon/剩余图标/font_en.ttf` | `b85c38ecea8a7cfb39c24e395a4007474fa5a4fc864f6ee33309eb4948d232d5` |
| `assets/ui/board_frame.png` | `board_frame` | PLACEHOLDER | 占位自绘/导出，可替换 | `01_icon/HotelManor_icon/剩余图标/board_frame.png` | `fea432ed74f09ccdcf5cad49ca5e450b50a42536d2584ad38e289b0895dd3edc` |
| `assets/ui/box_safe_x.png` | `box_safe_x` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_safe_x.png` | `17887bb0dce23afcccda98a51a7fe517d4a365dfc60dd197857774b162f93113` |
| `assets/ui/box_energe_w.png` | `box_energe_w` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_energe_w.png` | `81f7ff348baaa02b8db2ab68c7a8f820404dfe81b893271c0d877336dff5af61` |
| `assets/ui/box_treasure_y.png` | `box_treasure_y` | PLACEHOLDER | 同上 | `01_icon/HotelManor_icon/剩余图标/box_treasure_y.png` | `314d61a47dbd5ddb626dfe3e269c1ed09279e96d49fbf097d789a2677119ae0c` |
| `assets/ui/order_card_bar.png` | `ui_order_card_bar` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/order_card_bar.png` | `ef645e40577fdbd0ea5b397200d5453cf7af6a775d4c0285b8e7d60ca09bb966` |
| `assets/ui/gem_icon.png` | `ui_gem_icon` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/gem_icon.png` | `b431b533aa033f06b848e22500466491fc1e7f30f337a599d49da5440ab14072` |
| `assets/ui/energy_icon.png` | `ui_energy_icon` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/energy_icon.png` | `47a024fc3cb6f5b791077b47e9b1d70d5aa400fcff68cef52b097544b4bd9f98` |

> 2026-11-09 新增两张（操作者给的 `棋盘界面拆解` 切图目录）：
> `order_card_bar.png`（388×178，订单卡九宫格底图，贴图自带上浅下蓝两条）、
> `gem_icon.png`（39×32，订单卡底部钻石奖励图标）、`energy_icon.png`（39×53，订单卡底部体力奖励图标）。
> 都是 **1:1 复制**（未裁切/未缩放/未重编码），所以同目录没有 `_source.png` 旁车。

## M1 真实图标（20 张，PRODUCTION）

M1 起 `chip_clean_*` 系列的 20 张真实棋子在工程内：Clean 家族 Ca 链 1–10 级、Cb 链 1–10 级，逐张从 `01_icon/HotelManor_icon/棋子icon/` 复制，**字节完全相同**（未重编码、未缩放、无 `.import` 旁车），sha256 由 `Get-FileHash -Algorithm SHA256` 实测。

命名落差：源 manifest（v7）把 7–10 级按原始文件名登记为 `icon_10002xx7..10`，1–6 级仍用 `chip_clean_*_lvNN`；快照的 `aliases` 把这两种叫法对齐（见 `data/manifest_index.json` 的 `aliases`），下表 lv07–10 行同时给出别名与记录 id。

| manifest id | 源文件 | 工程内路径 | actual | target | fit | usage | license | sha256 |
|---|---|---|---|---|---|---|---|---|
| `chip_clean_ca_lv01` | `01_icon/HotelManor_icon/棋子icon/icon_10002101.png` | `assets/chips/icon_10002101.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `ac6cb4728f97f44273690df8db7523c6c61e6062aa81256ba75f9af62aa641b4` |
| `chip_clean_ca_lv02` | `01_icon/HotelManor_icon/棋子icon/icon_10002102.png` | `assets/chips/icon_10002102.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `323d4d557afb55ad521b7adf314967d86628f90508abf2f14000cf4d288795b7` |
| `chip_clean_ca_lv03` | `01_icon/HotelManor_icon/棋子icon/icon_10002103.png` | `assets/chips/icon_10002103.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `472ad32c07523ea2cdfd662f960eb7031f446071442b2f102be3fda0c4d7d2a4` |
| `chip_clean_ca_lv04` | `01_icon/HotelManor_icon/棋子icon/icon_10002104.png` | `assets/chips/icon_10002104.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `cb458f1de946b4c1729708d31ed12cf8913edf52f24a27590aa3ba40b310ec56` |
| `chip_clean_ca_lv05` | `01_icon/HotelManor_icon/棋子icon/icon_10002105.png` | `assets/chips/icon_10002105.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `8fdb8c9fa1bd67755cc47b06165bd05edce8b91836341b2719a638ce553f0ae0` |
| `chip_clean_ca_lv06` | `01_icon/HotelManor_icon/棋子icon/icon_10002106.png` | `assets/chips/icon_10002106.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `1c5073a7864899905c8a77cdf03166e850d210e0521383f30508f783f652c184` |
| `chip_clean_ca_lv07`（alias → `icon_10002107`） | `01_icon/HotelManor_icon/棋子icon/icon_10002107.png` | `assets/chips/icon_10002107.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `47506d27f5d5e0bc26165463a001f4a7ddbd17049103a5273125b90d8e270d7f` |
| `chip_clean_ca_lv08`（alias → `icon_10002108`） | `01_icon/HotelManor_icon/棋子icon/icon_10002108.png` | `assets/chips/icon_10002108.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `9e616b27580da4482207b151de7ef6b06c7c5dbd28bba68219aa05d3c18a9a3d` |
| `chip_clean_ca_lv09`（alias → `icon_10002109`） | `01_icon/HotelManor_icon/棋子icon/icon_10002109.png` | `assets/chips/icon_10002109.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `f0f778b052bac6cf98bf691deffa8eafb9cc78754046277b6aa805047b241e69` |
| `chip_clean_ca_lv10`（alias → `icon_10002110`） | `01_icon/HotelManor_icon/棋子icon/icon_10002110.png` | `assets/chips/icon_10002110.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `d680a57ceb310bcc5f62cdd00d8fa3ddc12bbc700c9bb3a97359bb5eac991980` |
| `chip_clean_cb_lv01` | `01_icon/HotelManor_icon/棋子icon/icon_10002201.png` | `assets/chips/icon_10002201.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `12b1f3ef1975fc471508e3e957b5929229b557cb6a19cb7daac737770af4979f` |
| `chip_clean_cb_lv02` | `01_icon/HotelManor_icon/棋子icon/icon_10002202.png` | `assets/chips/icon_10002202.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `2ea092ae208c5b9cb4958b1cab2281beca3488821ae6f44291db82e8d01150f8` |
| `chip_clean_cb_lv03` | `01_icon/HotelManor_icon/棋子icon/icon_10002203.png` | `assets/chips/icon_10002203.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `fb54c0ded43dfb07cbaef011d1325ff25e30cd84023b035f7ddb0ff756092338` |
| `chip_clean_cb_lv04` | `01_icon/HotelManor_icon/棋子icon/icon_10002204.png` | `assets/chips/icon_10002204.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `ec3f3c2cf43b6525f8aecf7bb21f627092ce31a67f2f85435f098a239d7f5d5d` |
| `chip_clean_cb_lv05` | `01_icon/HotelManor_icon/棋子icon/icon_10002205.png` | `assets/chips/icon_10002205.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `f8cf0d55560fe21dc7bf4f7c19c50cfc5ffb3b514e839448f4cf9b4f39cf767f` |
| `chip_clean_cb_lv06` | `01_icon/HotelManor_icon/棋子icon/icon_10002206.png` | `assets/chips/icon_10002206.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `b2f335f6a3223933c46e506b87fb2866a9cfbb78c37db1c42cd030e1d374eee8` |
| `chip_clean_cb_lv07`（alias → `icon_10002207`） | `01_icon/HotelManor_icon/棋子icon/icon_10002207.png` | `assets/chips/icon_10002207.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `537e3970d0ea7afcd45098b44c2ecfa537df60dd91f6be1e91132a5c1c910917` |
| `chip_clean_cb_lv08`（alias → `icon_10002208`） | `01_icon/HotelManor_icon/棋子icon/icon_10002208.png` | `assets/chips/icon_10002208.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `4aaebee686c2a6979b08a8009808e41705ce77433f5897a6d1fd9b5d06befbc5` |
| `chip_clean_cb_lv09`（alias → `icon_10002209`） | `01_icon/HotelManor_icon/棋子icon/icon_10002209.png` | `assets/chips/icon_10002209.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `ecc71187fcc05a537a51e0ce5b3840eb0ea2fe87da3795d1b9a9fd093ae9d810` |
| `chip_clean_cb_lv10`（alias → `icon_10002210`） | `01_icon/HotelManor_icon/棋子icon/icon_10002210.png` | `assets/chips/icon_10002210.png` | 182×182 | 256×256 | scale | PRODUCTION | 公司自有/自研 | `2da6fefe930517656fabe10629a5bb9909c72d66060852b79077598646ca97c7` |

合计 27 个 M0/M1 载荷文件 = 20 张 chip + 2 个字体 + 5 个 PLACEHOLDER；上节 M0 的 `REFERENCE_ONLY` 清单已被 v7 manifest 取代（这 20 个 id 现为 `PRODUCTION`，license 公司自有/自研，2026-11-04 用户确认素材可用）。

## M1 视觉素材（本地登记，待补登 00_design）

棋盘画面的 §20.5/§20.6 布局素材从 M1 起进工程：逐张从
`01_icon/HotelManor_icon/界面切图/`、`01_icon/HotelManor_icon/剩余图标/`、`00_design/images/psd_slices/`
复制到 `assets/ui/`，**字节完全相同**（未重编码、未缩放、无 `.import` 旁车），sha256 由 `Get-FileHash -Algorithm SHA256` 实测。

### 本地登记（快照 v7 尚无记录，`pending_manifest: true`）

这 9 张在 `00_design/resource_manifest.json` 里**还没有 id**，已在 `data/assets_local.json` 登记为 `PRODUCTION`，
待补登进 00_design 后本表可并入主清单。全部按原尺寸使用（`fit: exact`，不做缩放）。

| id | 源文件（工作区相对） | 工程内路径 | actual | usage | license | sha256 |
|---|---|---|---|---|---|---|
| `ui_bg_top` | `01_icon/HotelManor_icon/界面切图/main_bg_01_top.png` | `assets/ui/main_bg_01_top.png` | 1080×400 | PRODUCTION | 公司自有/自研 | `4e08f7353baf7dda7a45552a4e80e40fe8dfdd7d6e638292b70d9a1340419feb` |
| `ui_level_badge_bg` | `01_icon/HotelManor_icon/界面切图/main_bar_level_bg.png` | `assets/ui/main_bar_level_bg.png` | 118×104 | PRODUCTION | 公司自有/自研 | `94ebfda49649bafd489c9f3f8b13df8475c333cd85fc6ac08ecd71eae6357bf0` |
| `ui_icon_finish` | `01_icon/HotelManor_icon/界面切图/main_icon_finish.png` | `assets/ui/main_icon_finish.png` | 52×52 | PRODUCTION | 公司自有/自研 | `4b110fc629bd919dbfe9ba3dc0dc26784361cfd4ecc2553deb58fc7607b1dd54` |
| `ui_btn_plus` | `01_icon/HotelManor_icon/界面切图/main_btn_plussign.png` | `assets/ui/main_btn_plussign.png` | 48×48 | PRODUCTION | 公司自有/自研 | `2fb925b96e4d85d88dca6e02ba2df116d4c482f4300c22659e28b2fbdb514e41` |
| `ui_button_shop` | `01_icon/HotelManor_icon/界面切图/common_main_btn_shop.png` | `assets/ui/common_main_btn_shop.png` | 142×132 | PRODUCTION | 公司自有/自研 | `f29df363b7d67414f432ce9f45449f150abdbaf9f55569ebb47360e2ca45284e` |
| `char_part1` | `00_design/images/psd_slices/part1.png` | `assets/ui/part1.png` | 373×370 | PRODUCTION | 公司自有/自研 | `02db85c9314f660554838df233ea64097716e6ffb208035dc3ecc1db302101c0` |
| `char_part2` | `00_design/images/psd_slices/part2.png` | `assets/ui/part2.png` | 373×524 | PRODUCTION | 公司自有/自研 | `345660d30cce523d5232363d86b9a8022d546da895a894ba63959dcaa28d6b13` |
| `ui_items_bar` | `00_design/images/psd_slices/items.png` | `assets/ui/items.png` | 693×183 | PRODUCTION | 公司自有/自研 | `fede2aa3ccb5582707143e8af0e70ad29d5ecd03c7a819e2a2d4a44d86b2a944` |
| `ui_board_frame`（`supersedes: board_frame`） | `01_icon/HotelManor_icon/剩余图标/board_frame.png` | `assets/ui/board_frame.png` | 983×1263 | PRODUCTION | 公司自有/自研 | `fea432ed74f09ccdcf5cad49ca5e450b50a42536d2584ad38e289b0895dd3edc` |

`ui_board_frame` 是**提交给 00_design 的 usage 升级建议**：快照把同一个 `board_frame.png` 记为 `PLACEHOLDER`（PIL 生成），
而 §20.5 的 983×1263 棋盘容器必须在 strict 渲染里出现，所以本地另立一条 PRODUCTION 记录指向同一张 PNG——
`board_frame` 仍是 `PLACEHOLDER`（strict 模式照旧阻断），两条记录 `local_path()` 指向同一个文件。

### 自由模式光标（2026-11-05，项目自有素材，已处理）

| id | 源文件（工作区相对） | 工程内路径 | actual | usage | license | sha256 |
|---|---|---|---|---|---|---|
| `ui_cursor_hand` | `北京Icon/常用资产汇总/棋盘界面拆解/手指.png` | `assets/ui/cursor_hand.png` | 256×256（源图 2074×2048） | PRODUCTION | 公司自有（北京Icon 资产汇总） | `95d976801f08824ddb86ecdb8e2c7eebf786cdbfe2f582a9457f361e4b9db6eb` |

- 来源：项目方素材 `北京Icon/常用资产汇总/棋盘界面拆解/手指.png`（工作区外的素材目录，白色 3D 手套，原图 2074×2048、自带 alpha）。
- 处理：PIL 按 alpha 裁掉四周留白 → 透明 RGB 填白（避免缩放出黑边）→ 等比放入 256×256 画布（底边对齐）→ LANCZOS 缩放。原图另存为同目录 `cursor_hand_source.png` 备查。
- 已在 `00_design/resource_manifest.json` v8 登记（2026-11-05，id 同名；原 CC0 记录已改为项目自有），`data/assets_local.json` 仍保留一条本地记录，因为本工程快照还是 v7/180 条；M2 重建快照后本地记录可删。
- 用途：自由模式试玩窗口的手型光标（OS 光标隐藏，画在 `game_screen.gd` 的 `Cursor` 层）+ 成片光标 overlay（`src/render/movie_scene.gd` 的 `_draw_cursor()`），两处都按 **96×96** 绘制，热点 = 指尖（纹理比例 `0.135, 0.004`）。
### 棋盘底 / 亮格（2026-11-05 改版，项目自有素材）

| id | 源文件（工作区相对） | 工程内路径 | actual | usage | license | sha256 |
|---|---|---|---|---|---|---|
| `ui_board_plate` | `北京Icon/常用资产汇总/面板模板/素材/单独格子.png` | `assets/ui/board_plate.png` | 167×167（源画布 1080×1920） | PRODUCTION | 公司自有（北京Icon 资产汇总） | `825dad5f53dbbd462958996157f344030263bcd4024190bb3baf590b828ad9de` |
| `ui_cell_light` | `北京Icon/常用资产汇总/棋盘界面拆解/浅色格.png` | `assets/ui/cell_light.png` | 256×256 | PRODUCTION | 公司自有（北京Icon 资产汇总） | `8376a77a4bbebadbd4a58a4c2868273a429b3deb9814f670f7b807c4a608f0b0` |

- 大底：PIL 按 alpha 裁切出中间 167×167 的圆角格；运行时九宫格拉伸到 983×1263（`board_view._draw_plate` / `movie_scene._draw_plate`，角 30px 不缩放）。
- 亮格：整字节复制；只在 `(x+y)%2==0` 的格位绘制，其余格子露出大底，形成棋盘格。
- 原画布备份：`01_icon/HotelManor_icon/剩余图标/board_plate_source.png`（1080×1920，未裁切原图）。

| `ui_exit_button` | `北京Icon/常用资产汇总/棋盘界面拆解/棋盘拆解_0000s_0017_返回按钮.png` | `assets/ui/exit_button.png` | 159×176 | PRODUCTION | 公司自有（北京Icon 资产汇总） | `ddf2a5a991cb5e99ca1b9a80304fc3d028cd063a73dbab9e59bd74b616ac04eb` |

- 来源：项目方素材（蓝色返回按钮），整字节复制；运行时按 `LAYOUT_EXIT` 164×174 槽位等比适配，替换原程序化三角。
- 已在 `00_design/resource_manifest.json` v8 登记（id `ui_exit_button`），`assets_local.json` 保留本地记录至 M2 快照重建。

| `ui_bar_board` | `北京Icon/常用资产汇总/棋盘界面拆解/棋盘拆解_0000s_0019_任务背景板.png` | `assets/ui/bar_board.png` | 388×178 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 九宫格 28px 四角 |
| `ui_coin_reward` | `北京Icon/常用资产汇总/棋盘界面拆解/棋盘拆解_0000s_0008_奖励金币领取.png` | `assets/ui/coin_reward.png` | 146×147 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 底栏金币按钮，按 124px 等比 |
| `ui_reminder` | `北京Icon/常用资产汇总/棋盘界面拆解/提醒.png` | `assets/ui/reminder.png` | 58×58 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 底栏 ⓘ 提示图标 |

### 显示字体（用户提供，未复制进 assets/）

底栏两条文案使用 `font/源字体/中文-江城圆体600W/` 里的 **江城圆体 700W（标题，加粗）** 与 **400W（副标题）**。
字体文件由操作者直接放进工程（`03_Game_ds/font/源字体/`，单文件 15 MB 级），
运行时用 `FontFile.load_dynamic_font()` 从 `res://font/源字体/...` 直读，**不复制到 `assets/`**，
因此不进入 52→55 载荷计数，也不参与 `AssetGuard` 登记；授权状态待操作者确认。

| `ui_generator_icon` | `北京Icon/常用资产汇总/棋子icon/icon_20001010.png` | `assets/ui/generator_icon.png` | 182×182 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 生成器主图标，按 132px 与 chip 同尺寸 |
| `ui_stamina` | `北京Icon/常用资产汇总/棋盘界面拆解/棋盘拆解_0000s_0005_体力.png` | `assets/ui/stamina.png` | 39×53 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 生成器左下角体力闪电，26×35 |

| `ui_common_line` | `01_icon/HotelManor_icon/剩余图标/common_line.png`（原图未随包提供，按归档副本登记） | `assets/ui/common_line.png` | 10×4 | PRODUCTION | 公司自有（北京Icon 资产汇总） | 底栏标题/副标题之间 4px 分隔线，运行时拉伸到 420×4 |

本地表只做**加法**：与快照同名的 id 一律拒绝并计入 `AssetGuard.local_override_rejected`，本地记录不会改写、升级或降级任何 manifest 记录。

### 快照已登记、本次才复制的布局文件（13 个文件 / 15 条记录）

这些在 v7 manifest 里早已是 `PRODUCTION`，但此前从未复制进工程（`in_project=false`）；M1 视觉目标把它们补齐，
快照随后由 `src/tools/build_manifest_index.gd` 重算，`in_project` 已与磁盘一致（42 条）。

| 记录 id | 源文件（工作区相对） | 工程内路径 | actual | usage | license | sha256 |
|---|---|---|---|---|---|---|
| `board_bg` | `01_icon/HotelManor_icon/界面切图/main_bg_01_bottom.png` | `assets/ui/main_bg_01_bottom.png` | 1080×1536 | PRODUCTION | 公司自有/自研 | `c3d7a4c062d5ff6243008418380333851acf5f7a838392fabeab27317a5bbe6a` |
| `slot_empty` | `01_icon/HotelManor_icon/界面切图/main_checkerboard_bg.png` | `assets/ui/main_checkerboard_bg.png` | 94×94 | PRODUCTION | 公司自有/自研 | `63162c924ad5fb4982efd3e85e2aad5db95aebe81c3324ca93a35c63be839a5e` |
| `ui_select_frame` | `01_icon/HotelManor_icon/界面切图/common_main_frame_s.png` | `assets/ui/common_main_frame_s.png` | 160×164 | PRODUCTION | 公司自有/自研 | `c3cd2d6663a9100b8f4c8d248a559ff464bc8bd1e5825aabc051c93d176bb20f` |
| `ui_level_badge` | `01_icon/HotelManor_icon/界面切图/main_bar_level.png` | `assets/ui/main_bar_level.png` | 98×84 | PRODUCTION | 公司自有/自研 | `7ed05753cf0d7d99b33c0c2493179e977ff39a4dc99ac13ebbbdb87115871833` |
| `ui_energy_timer` | `01_icon/HotelManor_icon/界面切图/main_icon_countdown.png` | `assets/ui/main_icon_countdown.png` | 52×52 | PRODUCTION | 公司自有/自研 | `4aa74263dca51f200763d0756d0aa05b4cfb90b63c6e916aad9165966c690841` |
| `ui_topbar` | `01_icon/HotelManor_icon/界面切图/main_money_bg.png` | `assets/ui/main_money_bg.png` | 68×66 | PRODUCTION | 公司自有/自研 | `8c6cb8807c7fce025b2dd78513b6ec579d04da938a9ff78821be47237bf514c3` |
| `obstacle_bubble` | `01_icon/HotelManor_icon/界面切图/main_btn_bubble.png` | `assets/ui/main_btn_bubble.png` | 140×140 | PRODUCTION | 公司自有/自研 | `0ba7fb5547d3ca4dd57b30b4ab3190f1554dfa7c2f8750f38c40fa77c011f6c9` |
| `obstacle_lock` / `slot_locked` | `01_icon/HotelManor_icon/界面切图/common_main_icon_lock_1x1.png` | `assets/ui/common_main_icon_lock_1x1.png` | 140×140 | PRODUCTION | 公司自有/自研 | `45f9f7decd1257513a12a5f3a2530dff07dae11fc1aab1e55977e438b3c1eaf4` |
| `ui_button_secondary` | `01_icon/HotelManor_icon/界面切图/common_main_btn_cabinet.png` | `assets/ui/common_main_btn_cabinet.png` | 144×180 | PRODUCTION | 公司自有/自研 | `a8e599836aa0db5f73303e6368f7bde2fd3bf62beaf609c60a3fcaa8a7733acc` |
| `ui_button_primary` | `01_icon/HotelManor_icon/界面切图/main_btn1.png` | `assets/ui/main_btn1.png` | 156×174 | PRODUCTION | 公司自有/自研 | `d601c5fe8220999bc5961457a14955509bf232b7b6fb4b630d439621aec3d548` |
| `ui_order_card` / `ui_order_card_done` | `01_icon/HotelManor_icon/界面切图/main_frame_message.png` | `assets/ui/main_frame_message.png` | 120×180 | PRODUCTION | 公司自有/自研 | `d4f3b016bdc803b42ed45b6d0b3a8046e9de621bd5b4c651918e0db5edfabe58` |
| `obstacle_web` | `01_icon/HotelManor_icon/剩余图标/obstacle_web.png` | `assets/ui/obstacle_web.png` | 140×140 | PRODUCTION | 公司自有/自研 | `bbc786eb23730ac494826dc1e36a53465c2267f0ecf71e19a23419072879b791` |
| `obstacle_ice` | `01_icon/HotelManor_icon/剩余图标/obstacle_ice.png` | `assets/ui/obstacle_ice.png` | 140×140 | PRODUCTION | 公司自有/自研 | `8c627b502a72de1acf4dd5af6b00d365eaa3ebd9db909d70e1f15d3e7fafb06e` |

| `ui_common_line` | `01_icon/HotelManor_icon/剩余图标/common_line.png` | `assets/ui/common_line.png` | 10×4 | PRODUCTION | 公司自有（北京Icon 资产汇总） | `7f1979582d8f989d8c22422e4fde8e55c9688b41f842a62463fd800c18c0b1ea` |

## 未复制清单（M1 口径）

v7 manifest 已把 `01_icon` 公司自研素材全部登记为 `PRODUCTION`（`REFERENCE_ONLY` 0 条），所以“红线”不再是某批原游戏切图，而是**按需复制**：本工程只复制了上面 **49** 个载荷文件（27 个 M0/M1 载荷 + 21 个 M1 布局素材 + 1 个项目自有光标），其余 **138 条** manifest 记录一张都没进工程——

- 另外 8 条链的棋子图标（`icon_10001xxx` / `icon_10004xxx` / `icon_10005xxx` / `icon_10007xxx` / `icon_10008xxx`，共 80 张）：留待后续主题，主题里写 id 即用，不复制就不占体积；
- 15 个未使用的 `PLACEHOLDER`（`ui_level_*`、`fx_*`、`cta_*` 等）：需要时才复制，且必须 `allow_placeholders=true`；
- 5 条 `TODO` 音频：没有文件，`AssetGuard` 恒阻断。

规则仍由 `src/assets/asset_guard.gd` 单点裁决，与本文件是否列出无关：`REFERENCE_ONLY` 恒阻断、`TODO` 恒阻断、`PLACEHOLDER` 需显式放行、`PRODUCTION` 放行，且 `local_path()` 只会返回 `res://assets/{ui,chips,fonts}/` 下真实存在的副本。`data/assets_local.json` 并入同一套判定，但只做加法（快照同名的 id 一律拒绝，见 `local_override_rejected`）。

因此 M1 起棋盘画面按主题数据取真图：`themes/default` 的 `icons.ui` 把背景两层、棋盘容器、格子底、选中框、顶栏等级/能量/货币、完成对号、冰/气泡/锁/蛛网障碍、退出/背包/商店按钮、底部信息条、订单角色 part1/part2 全部指向 PRODUCTION id（不含任何 PLACEHOLDER，strict 模式即可渲染）；`themes/pet_shop` 故意不写 `icons.ui`，走程序化绘制，用来证明换主题只换数据。chip 在主题给了 `chip_icons` 时画真实图标（fit=scale 居中），主题没给时保持原来的程序化圆角块。
| `assets/chips/icon_10001101.png` | `chip_clean_cc_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001101.png` | `6a2625746d96f3ec3b6e801f1aef7727fc61eee53f6c244b426f9a574fb588f3` |
| `assets/chips/icon_10001102.png` | `chip_clean_cc_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001102.png` | `da1ea8989dd35d15722c29c0e6181cab6fba2abc40831d3505fc9cbf95f83388` |
| `assets/chips/icon_10001103.png` | `chip_clean_cc_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001103.png` | `067284e0264b5e6715afda9de28b36976822f7499acbecec75f66a515ece1841` |
| `assets/chips/icon_10001104.png` | `chip_clean_cc_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001104.png` | `be29a078a16d690a3a7494d5de628c7d4ed60ea74830540c75c6e993db54a0a3` |
| `assets/chips/icon_10001105.png` | `chip_clean_cc_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001105.png` | `73364b3344fe7825ca89144cfd535c6c5adcefefa33061ce83aff6cbea368c78` |
| `assets/chips/icon_10001106.png` | `chip_clean_cc_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001106.png` | `5f40085c901b6743383140267830921b3a5ce6272a460ef5a29e8d9af55f9333` |
| `assets/chips/icon_10001107.png` | `chip_clean_cc_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001107.png` | `4f376ff02bc69996514173b7c8b18c73762cdd8a8ecb523e477ba3ccd280e6ee` |
| `assets/chips/icon_10001108.png` | `chip_clean_cc_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001108.png` | `1bfecbdb4a0aba31f6d2c041748773920dbd609c9ba2e8503882154039fa6bf3` |
| `assets/chips/icon_10001109.png` | `chip_clean_cc_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001109.png` | `c696d20075eba8e7eeaf81a6db53853b97c2c6feea14ca4a404d2536f78efb79` |
| `assets/chips/icon_10001110.png` | `chip_clean_cc_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001110.png` | `a4c8992649e29307e6891c9c3c66183a1d5788a18cca1a6c0546729cc4313f76` |
| `assets/chips/icon_10005101.png` | `chip_clean_cd_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005101.png` | `690ed1db10dd9c775d8a64245d50a93a3393dc632ec9a6b7e0717be60c7f7b34` |
| `assets/chips/icon_10005102.png` | `chip_clean_cd_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005102.png` | `743f38e2aefee8eb3aa0d8c187b06dd1c6c6ed29357ff131a5e163faaebc8663` |
| `assets/chips/icon_10005103.png` | `chip_clean_cd_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005103.png` | `d308fe7b78a31a8ed11ca7f9f79433cff77ad757d09f6c2afc353a52b6f0e982` |
| `assets/chips/icon_10005104.png` | `chip_clean_cd_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005104.png` | `5373da01e202c1b8692c545a2d77cbf27bcd3e8037713636d1699721262fcebf` |
| `assets/chips/icon_10005105.png` | `chip_clean_cd_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005105.png` | `9fd8831e6f32418ad2730902f450a443349d463f8f10b7e93873dde69c0dadae` |
| `assets/chips/icon_10005106.png` | `chip_clean_cd_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005106.png` | `2c735b04e3c5e6d25aebcbb49b1f383225d5897b2ce9b0266c07d9dc25e75d21` |
| `assets/chips/icon_10005107.png` | `chip_clean_cd_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005107.png` | `0bc3164b6c15e22ba71ff8f45fb02c43df3a0f028589bdc79c0f276ae21ba1a5` |
| `assets/chips/icon_10005108.png` | `chip_clean_cd_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005108.png` | `d19629f562cf204e53843a00514b5aef4d65598e631d832235023b0fb8abb16d` |
| `assets/chips/icon_10005109.png` | `chip_clean_cd_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005109.png` | `4075bdc92a56b10282b9351010a5271b7d8b28e4b4233f54cffb79d9b3b1524f` |
| `assets/chips/icon_10005110.png` | `chip_clean_cd_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10005110.png` | `8b23c826b9a971b090837b965eccd0199126132863a5f6d00989a43420cf504a` |
| `assets/ui/main_icon_exclamation1.png` | `ui_exclamation` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/exclamation.png` | `f64d3fefca1ff3f5e70602400ae1b462a86332accbb9ef1842c1d25b56a66616` |
| `assets/ui/main_menu_frame1.png` | `ui_mission_frame_done` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/mission_frame_done.png` | `5f8e40d36b172f0d0d170506643f2d97bf499cb456e9ceb9225459bbc4acb5b9` |
| `assets/ui/main_menu_frame2.png` | `ui_mission_frame_todo` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/剩余图标/mission_frame_todo.png` | `133eb167ee6f73ce0591fc344323bc8ca682edb585c6e2a0b4aa235f7585dd97` |

## 2026-11-10 `ui_generator_premium`（generator_premium.png）

- 来源：`北京Icon/常用资产汇总/棋子icon/icon_20002010.png`（182×182 RGBA）
- 归档：`01_icon/HotelManor_icon/剩余图标/generator_premium.png`
- 工程副本：`assets/ui/generator_premium.png`（1:1 复制，未裁切）
- sha256：`fef0836ee4b0...`
- 用途：库存面板（左上角）投放的高级生成器图标

## 2026-11-12 棋子补齐 12 套 × 10 级（新增 8 套，80 张）

操作者口径：「用原始素材 01_icon/HotelManor_icon/棋子icon 补吧。ca,cb 长到 10 级。其它的系列也给补全。总共 120 个 icon，应该是 12 套，每套 10 个，都补上。」

新增实体 `CleanSet_Ce..Cl`（宠物勺 / 毛刷 / 绿猫垫 / 紫猫垫 / 喷雾瓶 / 泡泡 / 方形爪垫 / 水碗），每套 10 级；源文件与 `01_icon` 字节完全相同（只复制、未重编码/缩放）。

| 工程内路径 | manifest id | usage | license | 源文件 | sha256 |
|---|---|---|---|---|---|
| `assets/chips/icon_10001201.png` | `chip_clean_ce_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001201.png` | `b98b2cefef6271d480ff16573b63e693400c5c3a333ede4716c8a121a395d392` |
| `assets/chips/icon_10001202.png` | `chip_clean_ce_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001202.png` | `24474d91abe0fd249d0bb3041696c761b9f6fe03210fb8a9d0c8da5c03f40f51` |
| `assets/chips/icon_10001203.png` | `chip_clean_ce_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001203.png` | `c1f7757347b94012bf348c8d0f5515923054af42049992a6f7c9b8d68ec34200` |
| `assets/chips/icon_10001204.png` | `chip_clean_ce_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001204.png` | `ac2f15b0b2fae7ff23902522d81a9e3e7a937bc416431defc1ad860b6fcc411a` |
| `assets/chips/icon_10001205.png` | `chip_clean_ce_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001205.png` | `4e0321bf2e417756b214c036d5c6f0ba57632b8cd17d6295fcb96600e5def6fa` |
| `assets/chips/icon_10001206.png` | `chip_clean_ce_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001206.png` | `ce8bf591eaa79615c141581677e9a2301364b0ba5541168f5a181f023d9516d6` |
| `assets/chips/icon_10001207.png` | `chip_clean_ce_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001207.png` | `bf778d528ad20ce46f99bd5f9b9d4a754f1bf5420821f916752ca23199ba8818` |
| `assets/chips/icon_10001208.png` | `chip_clean_ce_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001208.png` | `f4190a05b7b4d9c0c49b2a3e8873f2bd5af66e44c9a407ded01fe7ab224e99b3` |
| `assets/chips/icon_10001209.png` | `chip_clean_ce_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001209.png` | `96ea2bed4e353d6a97f610a1e200af387f34818388e9ba66e78b5f343812f71b` |
| `assets/chips/icon_10001210.png` | `chip_clean_ce_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10001210.png` | `3e11523b4f1284e6f9b7c21c65364843c8ad55ad2493a3cb70b11f6534ba8b11` |
| `assets/chips/icon_10004201.png` | `chip_clean_cf_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004201.png` | `eab07d77a6b400d417ff355530f3e8a5336afe9fa0dff729bb33d187f2adf742` |
| `assets/chips/icon_10004202.png` | `chip_clean_cf_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004202.png` | `14dae5b058e4cf28376b12660314f6783d9929d82aaa46b0a388a9fe17e6a8d8` |
| `assets/chips/icon_10004203.png` | `chip_clean_cf_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004203.png` | `8a985e7b0d7ce0690d1a2a5ec501b95515be6227abe95df0137bcd91a3af6936` |
| `assets/chips/icon_10004204.png` | `chip_clean_cf_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004204.png` | `2cbc95b1303ebd558f4cc42df3a452526dbea1e5503c73698a8b707c24ed6b73` |
| `assets/chips/icon_10004205.png` | `chip_clean_cf_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004205.png` | `3a610e1346f9a6bb7148fc752cf1d3625d7e0a0ab4688a7282e62fa4a6f7eb07` |
| `assets/chips/icon_10004206.png` | `chip_clean_cf_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004206.png` | `c50e0cc5e5c07b383e7491d01a77b1bdef9b378dc4ea606847ea60fbf404e874` |
| `assets/chips/icon_10004207.png` | `chip_clean_cf_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004207.png` | `dc34bc2b41df1687ecdb13304887503e599bc0c38c41214af011c063fa08286b` |
| `assets/chips/icon_10004208.png` | `chip_clean_cf_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004208.png` | `cf391478459f8c1195e9e49ff5de234b28a386e774d1f7bfbf41682beb8d7b88` |
| `assets/chips/icon_10004209.png` | `chip_clean_cf_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004209.png` | `9813fa748cd4e56c495fd8b1e5995836a9cb5cd981ae0a60caea03012529f0ac` |
| `assets/chips/icon_10004210.png` | `chip_clean_cf_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10004210.png` | `0ba1800cc98b26285e6a55b1bada7dcdc8439d3214ec5d49885a261ee08c304d` |
| `assets/chips/icon_10007101.png` | `chip_clean_cg_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007101.png` | `6cb8c75d8ad0ed9d62712cdf83f8e12ccf0f536e40905818cfaef9e353d7a3c1` |
| `assets/chips/icon_10007102.png` | `chip_clean_cg_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007102.png` | `95be1fa246cfc6ccea88d42657903506bd102f3850d90c6d5740f86e068e51b3` |
| `assets/chips/icon_10007103.png` | `chip_clean_cg_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007103.png` | `09698264c5bd007e04f53a55ab9cf283c437b226bb008770664d609621169e0e` |
| `assets/chips/icon_10007104.png` | `chip_clean_cg_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007104.png` | `c88a112f67a99835bf97697ae4d6725c209fbb1297ac14c2b714d674c8be30af` |
| `assets/chips/icon_10007105.png` | `chip_clean_cg_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007105.png` | `75faa0cb59f2811be3a851e43895196f5804f7086c0894ec5d3927c478ad5e36` |
| `assets/chips/icon_10007106.png` | `chip_clean_cg_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007106.png` | `bb76c05b3944c1766eab1acabde3ae7ca32f40c4aa36e92812969b0bdcfe7c3f` |
| `assets/chips/icon_10007107.png` | `chip_clean_cg_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007107.png` | `23ec5e29642c4c9a8a948d469f9fa7b7d5a434dc9cb4f5f0ef7d8d40492c50cf` |
| `assets/chips/icon_10007108.png` | `chip_clean_cg_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007108.png` | `004ac625278f52d991d440d8495b96d63d672920f69331900bcacbfbd6ae7774` |
| `assets/chips/icon_10007109.png` | `chip_clean_cg_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007109.png` | `cc2d79f29c3354e032b4de93af815c91cac785a69123ef0e230e2719becdc6a2` |
| `assets/chips/icon_10007110.png` | `chip_clean_cg_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007110.png` | `3b662dea73640dc1f08b318acfd354c05e8fbb95073e9bf230b39e8004cba23a` |
| `assets/chips/icon_10007201.png` | `chip_clean_ch_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007201.png` | `81fbf2012c2a3083db9cdb3473621a10aaf14adad9c6ad3a9f0a7ed4a97349bb` |
| `assets/chips/icon_10007202.png` | `chip_clean_ch_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007202.png` | `bbde6452b6b5f40c91d3e39f1a314e88b53b1dcf0d465a5872601f4f61796892` |
| `assets/chips/icon_10007203.png` | `chip_clean_ch_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007203.png` | `79963993538de423eadcc8deb8eefd9847f1f459000d742ff9df3ac79e680008` |
| `assets/chips/icon_10007204.png` | `chip_clean_ch_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007204.png` | `48014be6aa0944d12720ec4f5d98daae2d91981dbe5e47007cabebac19f7050c` |
| `assets/chips/icon_10007205.png` | `chip_clean_ch_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007205.png` | `3df46b92a59001ca3bc65d341b9bb44d8d038c48c9b3a4ebcfb85051318ce041` |
| `assets/chips/icon_10007206.png` | `chip_clean_ch_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007206.png` | `5e947b91574e8f77916b21fe6777a9b3f85173e4109d2b9ce0717c523b5ceb18` |
| `assets/chips/icon_10007207.png` | `chip_clean_ch_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007207.png` | `f86efb1bc47c47a8da3f62f2869801d3d09e588a52b69c4e51946f81c8605879` |
| `assets/chips/icon_10007208.png` | `chip_clean_ch_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007208.png` | `1bae797ffd60177145ff628235c1078945baed865dba46baeda93b3a5b93079e` |
| `assets/chips/icon_10007209.png` | `chip_clean_ch_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007209.png` | `2241f62db5e517f259b7d09c0954c77e886dab98272d17fd546778c9667824d3` |
| `assets/chips/icon_10007210.png` | `chip_clean_ch_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10007210.png` | `ee036abae9d5412fd2b7f02bcda31b93cbff661602f47e43798d4d008df18a19` |
| `assets/chips/icon_10008101.png` | `chip_clean_ci_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008101.png` | `d757156c30c37fefb0bfa2ad2aeb90f56e7ef8116211561cb2585135af38fa13` |
| `assets/chips/icon_10008102.png` | `chip_clean_ci_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008102.png` | `99e5cad40747da4b513e5993dd2525e63b213045ba3355296d75470fc8d07c8c` |
| `assets/chips/icon_10008103.png` | `chip_clean_ci_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008103.png` | `47061b4486b552f76dd826b5737aef2db7f0c6f86a3411737e991be39ecb47a7` |
| `assets/chips/icon_10008104.png` | `chip_clean_ci_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008104.png` | `19d07e214d51e3ec32e24b168ff76c6a20e0bda3c1ec2d6117ce2adb88928883` |
| `assets/chips/icon_10008105.png` | `chip_clean_ci_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008105.png` | `eba1d08fddb75e06467da28b44e98d45345bb2b01af58c930456b69cede219ed` |
| `assets/chips/icon_10008106.png` | `chip_clean_ci_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008106.png` | `b85bb7f8be6df866093cdc38ddde62883bf7d41d85db5870f01c4b3db97c7c8a` |
| `assets/chips/icon_10008107.png` | `chip_clean_ci_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008107.png` | `2dce40e35b48d92533b0119121ed60365ad04879c5fb96edce0a3b5662996992` |
| `assets/chips/icon_10008108.png` | `chip_clean_ci_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008108.png` | `cb4c868bb8fbdb252173245c9bfa9c5bb2b5a121a0f4094810bc926ab263ac29` |
| `assets/chips/icon_10008109.png` | `chip_clean_ci_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008109.png` | `f54351695f0448fa3def810693a12f1a4e201ca738e799f9198017da83ffae30` |
| `assets/chips/icon_10008110.png` | `chip_clean_ci_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008110.png` | `dfa6d46acf7eeab457a66c79c3d55d6858df5ad11e7c6811a6461f9fb86eba18` |
| `assets/chips/icon_10008201.png` | `chip_clean_cj_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008201.png` | `9d234a4cf2a3a571f0ff9fde005653468b5fb1828826ed23829342c8bea6b05c` |
| `assets/chips/icon_10008202.png` | `chip_clean_cj_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008202.png` | `12977f455c1d4e006ed7dd61f7f88d1205d90ad63917de5c0b489b2fffff9aec` |
| `assets/chips/icon_10008203.png` | `chip_clean_cj_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008203.png` | `99c3a315cd0ce91cff73f914c5729f4f07257ff9e809e5d48b556d36411482f4` |
| `assets/chips/icon_10008204.png` | `chip_clean_cj_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008204.png` | `bbec8dd5d981eb7e9e0dd77779bd411dc4a9d72f6a80d5019b895d6faf219451` |
| `assets/chips/icon_10008205.png` | `chip_clean_cj_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008205.png` | `0ed9d3f9c1c0b23ab79de19cf57cc97495927075a2d2a61dd862c68c58987b72` |
| `assets/chips/icon_10008206.png` | `chip_clean_cj_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008206.png` | `8810213a9da0f98827715a239bc4584e805f1ac6e89ac3ba068fd76fa5589eb6` |
| `assets/chips/icon_10008207.png` | `chip_clean_cj_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008207.png` | `28d56aa73f47d6003ab266a870dfd7d06e273188dd104758153e97fd3d89eb31` |
| `assets/chips/icon_10008208.png` | `chip_clean_cj_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008208.png` | `b0115d1ed5ea88318889e535446cf7e0543bc146342b544660a066d98a96c113` |
| `assets/chips/icon_10008209.png` | `chip_clean_cj_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008209.png` | `3f339d185e624c4c951244b844ea4a6170f25855aeb02110ecb781188f618f00` |
| `assets/chips/icon_10008210.png` | `chip_clean_cj_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_10008210.png` | `6c1fd36ca823a742e5458bd7e3cd06fdf21ebf245db3a6eadf197b7f7c2072f1` |
| `assets/chips/icon_20001001.png` | `chip_clean_ck_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001001.png` | `bc4e12c654739f7244361984b8dd053c86af7ebb8588fe7f4f7f33fa5820be86` |
| `assets/chips/icon_20001002.png` | `chip_clean_ck_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001002.png` | `a7411551dbb37ebe5c0a30397e142887efa51ec9f3d37c335e38f0c59531294c` |
| `assets/chips/icon_20001003.png` | `chip_clean_ck_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001003.png` | `7c7ec648ec694d8467fe8978cc09103735067d6e8b952f8b9144109f1e6fb584` |
| `assets/chips/icon_20001004.png` | `chip_clean_ck_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001004.png` | `e76fd64c3b29ae15f7bb8d48795814af00e7f570c7c1c612785ed3f9f578a478` |
| `assets/chips/icon_20001005.png` | `chip_clean_ck_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001005.png` | `7a8e3451489a0c183442a8fe8fac8eaa8bdfc7e948c9e01085c10cee016674d7` |
| `assets/chips/icon_20001006.png` | `chip_clean_ck_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001006.png` | `554304e9f53a7388c1f67a97b7795eb536fb66aef02f1d04d616210713b8a043` |
| `assets/chips/icon_20001007.png` | `chip_clean_ck_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001007.png` | `77265cabcd7da5789b8ffae1b4e4a3be493cd81e9d9472b07a830328bc9d5ce3` |
| `assets/chips/icon_20001008.png` | `chip_clean_ck_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001008.png` | `1570645afb781f6f02ba17388a542c902c7edf51fe731de0d8fc1fb19557cb83` |
| `assets/chips/icon_20001009.png` | `chip_clean_ck_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001009.png` | `ad9ea629c4b8f88d330338025d87f4fe75299fb88edc8f338242a361e59ea2bd` |
| `assets/chips/icon_20001010.png` | `chip_clean_ck_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20001010.png` | `36746bf0d808d368ecf09013d10b3aa1a841d25940594a82fa8f9c38dbbc33e3` |
| `assets/chips/icon_20002001.png` | `chip_clean_cl_lv01` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002001.png` | `5215444851746c9fdb0ba67180ea467bdc22633100110004d009887adac88ab7` |
| `assets/chips/icon_20002002.png` | `chip_clean_cl_lv02` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002002.png` | `133896573422cf15e83902c0400af224e72758bde52bd7bb28628b37e7f60162` |
| `assets/chips/icon_20002003.png` | `chip_clean_cl_lv03` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002003.png` | `222addce5cb630e55a5dfd58d4226a263fde1e9069a5653684bac869b435b721` |
| `assets/chips/icon_20002004.png` | `chip_clean_cl_lv04` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002004.png` | `d32d788df3e6c953f7347ccb85bd15bb0fb48416acb0586bd1813cdf22d4c0b5` |
| `assets/chips/icon_20002005.png` | `chip_clean_cl_lv05` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002005.png` | `e0af7e51cbf9d5396860fa70f4408782705f1eba9938a8e0780fd2e3411d3202` |
| `assets/chips/icon_20002006.png` | `chip_clean_cl_lv06` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002006.png` | `b63bbcbfefdd4d8b88fe55c544487a4b6564539eaa9ac5040c84a803990af548` |
| `assets/chips/icon_20002007.png` | `chip_clean_cl_lv07` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002007.png` | `f1ab051486d6894650c42639ec23fcb8c034e4b620446dc78145668a8a7445ef` |
| `assets/chips/icon_20002008.png` | `chip_clean_cl_lv08` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002008.png` | `eae16966c7534a3a5a321c50dabc944e0c49ea2a395252f2576c08147b5fd82b` |
| `assets/chips/icon_20002009.png` | `chip_clean_cl_lv09` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002009.png` | `b777e76cdbb87d21bf440947f1e077da0f1e0f538cf7b816938ae3940b6d110c` |
| `assets/chips/icon_20002010.png` | `chip_clean_cl_lv10` | PRODUCTION | 公司自有（来源 Icon / HotelManor） | `01_icon/HotelManor_icon/棋子icon/icon_20002010.png` | `fef0836ee4b0f31c561e4ee69cc66ca30cdb890f3e0dc94bca23c5ca7c3a8fd0` |
