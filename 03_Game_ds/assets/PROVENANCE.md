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

## 未复制清单（M1 口径）

v7 manifest 已把 `01_icon` 公司自研素材全部登记为 `PRODUCTION`（`REFERENCE_ONLY` 0 条），所以“红线”不再是某批原游戏切图，而是**按需复制**：本工程只复制了上面 48 个载荷文件（27 个 M0/M1 载荷 + 21 个 M1 布局素材），其余 **138 条** manifest 记录一张都没进工程——

- 另外 8 条链的棋子图标（`icon_10001xxx` / `icon_10004xxx` / `icon_10005xxx` / `icon_10007xxx` / `icon_10008xxx`，共 80 张）：留待后续主题，主题里写 id 即用，不复制就不占体积；
- 15 个未使用的 `PLACEHOLDER`（`ui_level_*`、`fx_*`、`cta_*` 等）：需要时才复制，且必须 `allow_placeholders=true`；
- 5 条 `TODO` 音频：没有文件，`AssetGuard` 恒阻断。

规则仍由 `src/assets/asset_guard.gd` 单点裁决，与本文件是否列出无关：`REFERENCE_ONLY` 恒阻断、`TODO` 恒阻断、`PLACEHOLDER` 需显式放行、`PRODUCTION` 放行，且 `local_path()` 只会返回 `res://assets/{ui,chips,fonts}/` 下真实存在的副本。`data/assets_local.json` 并入同一套判定，但只做加法（快照同名的 id 一律拒绝，见 `local_override_rejected`）。

因此 M1 起棋盘画面按主题数据取真图：`themes/default` 的 `icons.ui` 把背景两层、棋盘容器、格子底、选中框、顶栏等级/能量/货币、完成对号、冰/气泡/锁/蛛网障碍、退出/背包/商店按钮、底部信息条、订单角色 part1/part2 全部指向 PRODUCTION id（不含任何 PLACEHOLDER，strict 模式即可渲染）；`themes/pet_shop` 故意不写 `icons.ui`，走程序化绘制，用来证明换主题只换数据。chip 在主题给了 `chip_icons` 时画真实图标（fit=scale 居中），主题没给时保持原来的程序化圆角块。
