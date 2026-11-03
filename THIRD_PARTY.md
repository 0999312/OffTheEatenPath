# 第三方组件与许可（THIRD PARTY）

> 这份清单是发布合规的**权威来源**；游戏里的「设置 → 致谢与第三方许可」面板是它的摘要。
> 新增任何第三方资源（字体、音效、音乐、图标、插件）都要先更新本文件，再提交资源。

## 一览

| 组件 | 版本 | 许可 | 用途 | 在仓库中的位置 |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.7.2（mono 版） | MIT | 引擎本体 | 不随仓库分发 |
| mc_game_framework | 1.0.0（作者 SyameimaruZheng） | **本项目自有插件**，不属第三方（对外许可由项目所有者决定） | 事件总线 / 注册表 / UI 栈 / Codec | `addons/mc_game_framework/` |
| Sound Manager | 未标注版本 | MIT（`addons/sound_manager/LICENSE.md`） | 音频播放池与总线 | `addons/sound_manager/` |
| Kenney Interface Sounds | 1.0 | CC0 1.0（`addons/kenney_interface_sounds/LICENSE.txt`） | 界面音效（除环境音外的全部意图） | `addons/kenney_interface_sounds/`（只取 16 个文件） |
| Kenney Impact Sounds | 1.0 | CC0 1.0（`assets/audio/sfx/Kenney_Impact_Sounds_LICENSE.txt`） | 氛围层环境音：敲门、杯碟轻碰 | `assets/audio/sfx/`（只取 2 个文件） |
| Cozy Tunes | EULA 2026-08-16 | **单座 EULA**（`assets/audio/music/Cozy_Tunes_EULA.pdf`）：允许用于个人与商业游戏，**禁止再分发原始资产** | 背景音乐（14 首随机轮播） | `assets/audio/music/`（私有仓库内保存，不对外分发） |
| MiSans（MiSans-Semibold） | 仓库内 `.ttf` | MiSans 字体知识产权许可协议（免费商用） | 全部界面文字 | `assets/fonts/` |
| Noto Sans Thai（NotoSansThai-Regular） | 2.000 | SIL Open Font License 1.1 | 泰文回退字形（MiSans 不含泰文） | `assets/fonts/` |
| Noto Sans KR（NotoSansKR-Regular） | Google Noto（SubsetOTF） | SIL Open Font License 1.1 | 韩文回退字形（MiSans 不含谚文） | `assets/fonts/` |
| Nieobie Game Icon Pack | 新版 main 快照（2026-10-27 整批替换，2026-10-30 补 11 个） | CC0 1.0 | 界面图标 121 个 SVG | `assets/icons/` |
| GodotShaders「God rays」（pend00） | 页面 2021 版（2026-10-28 获取） | CC0 1.0 | 背景车窗光 shader | `resources/shaders/sunlight.gdshader`（只做 Godot 4 兼容性改动） |
| GUT | 9.6.0 | MIT（`addons/gut/LICENSE.md`） | 单元测试框架 | `addons/gut/`，**不随游戏分发** |

## 各条目的说明

### Godot Engine（MIT）

游戏引擎。按 MIT 许可，发布包中需要保留版权声明——引擎在导出的可执行文件里已包含该声明；
本项目另外在 `README.md` 与游戏内致谢页中标明。许可全文：<https://godotengine.org/license>。

### mc_game_framework（本项目自有）

- 本项目的架构核心（`RegistryManager` / `EventBus` / `I18NManager` / `UIManager` / Codec），
  由项目作者（`SyameimaruZheng`）自己编写，随本仓库一起分发——**不是第三方组件**，因此不存在
  「向别人取得授权」的问题，也不需要额外的许可文件。
- 之所以单独列在本文件：它长得像一个通用插件（`addons/` 下、有 `plugin.cfg`），列出来是为了
  避免以后有人误以为它需要合规确认。
- 如果将来把它单独发布到 Asset Library 或 GitHub 独立仓库，再由项目所有者决定用哪个许可
  （届时把许可文件放到 `addons/mc_game_framework/LICENSE.md` 并更新本文件即可）。

### 其他插件

- 项目使用的外部插件只有 Sound Manager（MIT）、Kenney Interface Sounds（CC0）、GUT（MIT，
  仅测试用）。三者都是允许商用与再分发的宽松许可，已在上面逐条记录，可直接随游戏使用。
- 音效素材：Kenney 两个包（Interface Sounds 与 Impact Sounds，都是 CC0），不是插件、
  不修改代码，只是音频文件；许可与署名方式见下面各自的段落。
- 新增任何插件前先确认它的许可允许商用与再分发，并把许可文件与本文件一起更新。

### Sound Manager（MIT）

- 音频池、总线回退（`AbstractAudioPlayerPool.get_possible_bus()`）、音乐淡入淡出。
- 许可文件：`addons/sound_manager/LICENSE.md`（Copyright (c) 2021-present Nathan Hoad）。
- 使用方式：作为 autoload `SoundManager`，本项目只调用它的公开方法（`play_ui_sound` / `play_music` 等），未修改其源码。

### Kenney Interface Sounds（CC0 1.0）

- 界面音效主体来自 Kenney 的 Interface Sounds 包（CC0，允许商用与再分发，不要求署名）。
- 2026-10 按「3–6 kHz 与 6 kHz 以上能量占比」从全库精选 16 个文件，替换首轮刺耳素材：
  CLICK `click_002`、TAB `switch_003`、OPEN `maximize_009`、CLOSE `minimize_008`、
  CONFIRM `select_004`、DENY `error_005`、COIN `drop_002`、BUY `glass_002`、SELL `drop_003`、
  UPGRADE/MILESTONE `confirmation_004`、CRAFT_DONE/RESEARCH_OK `confirmation_001`、
  LETTER `bong_001`、RESEARCH_FAIL `error_005`、ORDER_DONE `drop_004`。
- 2026-10-30 第七轮：来访铃 `VISIT` 复用 `bong_001`，副本放
  `assets/audio/sfx/visit_bell.wav`（pitch 0.94），让「门口有人」不再是敲门声。
  其余约 185 个文件仍留在插件目录里，但已没有代码引用。
- 本项目仍保留署名（致谢页 + 本文件），因为「不要求」不等于「不该给」。
- 许可文件：`addons/kenney_interface_sounds/LICENSE.txt`。

### Kenney Impact Sounds（CC0 1.0）

- 氛围层的两枚环境音来自 Kenney 的 Impact Sounds 包：敲门用 `impactWood_light_000.ogg`，
  杯碟轻碰用 `impactPlate_light_000.ogg`；只取了这两个文件，其余不入库。
- 落在 `assets/audio/sfx/knock.ogg` 与 `assets/audio/sfx/dish_clink.ogg`，由
  `scripts/systems/sfx.gd` 的 `KNOCK` / `DISH_CLINK` 意图引用。
- 许可文件：`assets/audio/sfx/Kenney_Impact_Sounds_LICENSE.txt`。
- 来源：<https://kenney.nl/assets/impact-sounds>

### Cozy Tunes（单座 EULA，**不是**开源许可）

- 背景音乐来自 Cozy Tunes（作者 pizzadoggy，<https://pizzadoggy.itch.io/>），许可原文
  `assets/audio/music/Cozy_Tunes_EULA.pdf`（Last updated: August 16, 2026）。
- 允许：用在个人与商业游戏里；可以编辑或修改。
- 禁止：转售、再分发、再许可、重新打包资产（含修改版）；分享资产或允许他人使用；
  放进别的资产包 / 模板 / 商城产品。
- 因此：**仓库必须保持私有**；音频文件只随本游戏使用，不得单独发给外部；
  游戏发行时随游戏打包属于「用在游戏里」，不属「再分发原始资产」。
- 已入库 14 首（文件名即曲目名，`scripts/systems/music.gd` 随机轮播）；
  `temp_assets/` 下的原始包不进仓库。

### MiSans（小米）

- 界面字体只保留 `MiSans-Semibold.ttf`（同字体的 `.otf` 是重复副本，已删，省 6.3MB 包体），按 MiSans 字体知识产权许可协议可免费商用。
- 该协议**禁止**把字体文件单独售卖或作为字体产品再发布；本项目只把它嵌进游戏与仓库源码，
  不单独分发字体文件。
- 发布时若需要更强的合规，可把字体许可全文附在发布页（本仓库不入库全文，因为协议可能更新）。
- 参考：<https://hyperos.mi.com/font/>

### Noto Sans Thai（SIL OFL 1.1）

- MiSans 不含泰文字形，泰语（th）界面需要回退字体；用 `resources/themes/paper_font.tres`
  （FontVariation）把 `NotoSansThai-Regular.ttf` 挂在 MiSans 之后，只补泰文字形。
- 来源：Google Noto Fonts（<https://github.com/googlefonts/noto-fonts>），Regular 2.000，OFL 1.1
  允许商用、嵌入与随软件再分发；本项目未修改字形。许可全文随字体在发布包中保留说明。

### Noto Sans KR（SIL OFL 1.1）

- MiSans 不含韩文谚文（测试中「한국어」显示为方块），韩语（ko）界面需要回退字体；
  `resources/themes/paper_font.tres` 把它作为第二个 fallback。
- 来源：Google Noto CJK（<https://github.com/notofonts/noto-cjk>）的 SubsetOTF/KR，
  NotoSansKR-Regular.otf，OFL 1.1，允许商用、嵌入与随软件再分发；未修改字形。

### Nieobie Game Icon Pack（CC0 1.0）

- 界面图标（箭头、开关、用户、食物、反馈等）来自 Nieobie 的 Game Icon Pack：
  <https://github.com/Nieobie/game-icon-pack>，itch 页 <https://nieobie.itch.io/free-icons>。
  README、GitHub 仓库元数据与包内 `LICENSE` 都写明 **CC0 1.0 Universal**：可商用、可再分发、
  不要求署名；本项目仍署名（致谢页 + 本文件）。
- 项目里保存的是从新版挑选并重命名的子集：`assets/icons/<分类>/<名字>.svg`
  （arrow 4 / device 2 / dish 6 / emoji 19 / feedback 20 / food 10 / material 5 / media 6 /
  misc 2 / ui 35 / user 12，snake_case），由 `scripts/ui/panel_kit.gd` 的 `ICON_ROOT` 引用；
  目录里没有随包的来源文件。
- 2026-10-30 为解决材料/菜品图标混用首字章的问题，从同一新版包补了 11 个：
  `5-food` 的 apple / carrot / meat-cooked / fish / bowl / rice / bread-02 / drink / tableware、
  `5-food` 的 bowl-02、`4-nature` 的 leaves，分别重命名为
  `material/{veg,fruit,meat,seafood,misc}.svg` 与
  `dish/{rice,soup_noodle,bakery,drink,salad,main}.svg`；归类只走
  `scripts/ui/item_icons.gd`（材料 5 族 / 菜品 6 族），没有逐条物品美术。
- 新版是 kebab-case、按 12 个分类目录组织（1-game … 12-misc），815 个图标
  （padding / no-padding 两套共 1630 个 SVG）。**2026-10-27 已整批替换**：110 个文件保持原路径、
  原文件名，内容换成新版 `svg/padding/` 下对应的图标——68 个按「下划线→连字符」直接对上，
  42 个走人工映射表（`cooked_meat` → `meat-cooked`、`water_cup` → `glass-of-water`、
  `smile_N` → `emoji-N`、`gamepad` → `controller`、`monitor` → `display`、`filter` → `funnel`、
  `puzzle` → `puzzle-01`、`cursor` → `cursor-default`）。换完重导入一次，`PanelKit` 的引用不用改。
- 替换时做了一处适配：新版 SVG 统一是 `width/height="24"` + 根 `fill="currentColor"`，写回时改成
  `fill="#ffffff"`——`PanelKit` 靠纯白图标 + `modulate` 染色，ThorVG 会把 `currentColor` 渲染成黑色。
  2026-10-27 整批替换的 110 个文件沿用旧版 `width/height="10"`；2026-10-30 新增的 11 个保留
  `24×24`，导入倍率分别是 8.0 与 4.0，最终都栅格化到约 80–96px 再按显示尺寸缩小。
- 导出包必须保留 SVG 源：运行时 `PanelKit.icon_texture()` 会从 `res://assets/icons/**/*.svg`
  重新栅格化，找不到才回退到导入纹理。`export_presets.cfg` 的 Web / Windows 两个预设都把
  `include_filter` 固定为 `*.svg`，避免发布版图标退回低清。
- 完整包解压在 `temp_assets/game-icon-pack-main/` 供对照；`temp_assets/` 被 `.gitignore` 忽略，**不进仓库**。

### GodotShaders「God rays」（CC0 1.0）

- 背景车窗光 shader 来自 GodotShaders 的公开条目：<https://godotshaders.com/shader/god-rays/>，
  作者页面为 <https://godotshaders.com/author/pend00/>；页面标注 `shader_license-cc0`，
  即 **CC0 1.0 Universal**（可商用、可修改、可再分发，不要求署名）。
- 仓库里的 `resources/shaders/sunlight.gdshader` 保留原作者的光形算法，只做了三处
  Godot 4 兼容性改动：`hint_color` → `source_color`；显式声明
  `uniform sampler2D screen_texture : hint_screen_texture`；采样调用从
  `texture(SCREEN_TEXTURE, SCREEN_UV)` 改为 `texture(screen_texture, SCREEN_UV)`。
- 参数由 `scripts/ui/sunlight_layer.gd` 暴露；调参工具在 `scenes/tools/sunlight_tuner.tscn`。
  按 CC0 不要求署名，但本项目仍在游戏内致谢页与本文件署名。

### GUT（MIT）

- 仅用于测试运行（`godot --headless --path . -s addons/gut/gut_cmdln.gd`），
  已在 `export_presets.cfg` 的 `exclude_filter` 中排除，不随游戏分发。

## 美术与音频资源现状

- **应用图标 `icon.png`**：用户自绘的贴纸插画（纸片、胶带、带盖咖啡杯、热气），
  原稿保存在 `docs/design/icon-source.png`（1798×1798）。发布用的是它裁边 3%、缩到 512×512、
  轻度锐化、量化到 192 色的版本（86KB）；不描边、不重绘，保留手绘墨线。
  这份稿子不是第三方素材，不涉及外部许可。
- `assets/sprites/`、`assets/textures/`、`assets/shaders/`：只有空目录占位，界面全部由代码绘制（色块、圆角面板、字体排版）。
- `assets/icons/`：121 个 SVG 图标（arrow 4 / device 2 / dish 6 / emoji 19 / feedback 20 /
  food 10 / material 5 / media 6 / misc 2 / ui 35 / user 12），来自 Nieobie Game Icon Pack
  （**CC0 1.0**，见上），内容以 2026-10-27 整批替换的新版为主、2026-10-30 补 11 个族图标，
  文件名沿用旧版；经 `scripts/ui/panel_kit.gd` 的 `ICON_ROOT` 引用。
  目录里没有随包的来源文件，本文件即来源登记。
- `assets/audio/music/`：背景音乐为 Cozy Tunes（pizzadoggy，单座许可）的 14 首（仓库里是重编码的
  ~128 kbps Vorbis，原始 340–455 kbps 文件不入库，见该目录 `README.md`），
  见 `scripts/systems/music.gd` 的随机轮播；许可原文与说明文件同目录。
  **仓库转公开前必须移除这批音频**（许可禁止再分发）。
- `assets/audio/sfx/`：界面音效全部来自 `addons/kenney_interface_sounds/`（16 个精选文件，CC0），
  隐藏池级增益 -4 dB 由 `scripts/systems/sfx.gd` 施加；氛围层的敲门与杯碟轻碰
  （`knock.ogg` / `dish_clink.ogg`）从 Kenney Impact Sounds 取，见 `scripts/systems/sfx.gd`。
  导入参数保持 `compress/mode=2`（QOA）、`edit/normalize=false`；**不加工音频文件**，
  柔化全部由 `default_bus_layout.tres` 的总线效果器完成：Master 挂 HardLimiter（ceiling -1.0）、
  UI 挂 Compressor（threshold -18 dB / ratio 3）+ EQ21（2.8–16 kHz 缓降）。
- `resources/shaders/sunlight.gdshader`：背景车窗光来自 GodotShaders「God rays」（pend00，CC0 1.0），
  见上；项目只做 Godot 4 兼容性改动并暴露参数。

## 发布前检查清单

- [x] `mc_game_framework` 为本项目自有插件，无需外部授权（见上）。
- [ ] 发布包内保留 Godot 与 Sound Manager 的版权声明（引擎内嵌 + 致谢页）。
- [ ] 致谢页可访问：设置 → 致谢与第三方许可（`idle_food:credits`）。
- [x] 界面图标来源已登记：Nieobie Game Icon Pack，CC0 1.0（2026-10-27 核实）。
- [x] 界面音效全为 Kenney CC0 素材（不要求署名），致谢页与 README 仍保留出处。
- [ ] 若新增背景音乐 / 图标 / 美术：先补本文件对应行，再提交资源。
- [ ] 游戏不联网、不采集任何数据（单机），因此不涉及隐私政策；若将来加入遥测需另写。
