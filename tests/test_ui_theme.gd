extends GutTest
## 界面主题：焦点环与悬停提示的对比度（用户试玩反馈「焦点颜色和 ToolTip 颜色对比
## 不足，导致其文字和背景等显示不明显」）。
##
## 纸色桌面整体偏浅，焦点只靠悬停色区分时，键盘 Tab 过去几乎看不出来；ToolTip
## 没写主题项时落回引擎默认的深色底——在纸面上像贴了一块黑布。

const THEME_PATH := "res://resources/themes/paper_theme.tres"

var _theme: Theme


func before_each() -> void:
	_theme = load(THEME_PATH) as Theme


func test_focus_has_its_own_ring() -> void:
	assert_not_null(_theme, "纸色主题能加载")
	var focus := _theme.get_stylebox("focus", "Button")
	var hover := _theme.get_stylebox("hover", "Button")
	assert_not_null(focus, "Button 有 focus 样式")
	assert_ne(focus, hover, "焦点样式不能直接复用悬停样式——键盘切过时看不出来")
	var flat := focus as StyleBoxFlat
	assert_not_null(flat, "焦点环是画出来的描边")
	if flat != null:
		assert_gte(flat.border_width_left, 3, "描边够粗才扫得到")
		assert_ne(flat.border_color, flat.bg_color, "描边颜色要跟底色分开")


## 焦点态只用样式提示（白底 + 蓝边），字色必须和常态一致。主题漏了
## font_focus_color 时引擎会回落到默认主题的浅色，看起来像禁用态（B 批实测：
## 键盘回车打开面板后，第一个按钮明明是可点的，字却是灰的）。
func test_focus_does_not_fade_button_text() -> void:
	for type in [&"Button", &"CheckButton", &"OptionButton"]:
		assert_true(_theme.has_color(&"font_focus_color", type), "%s 要有自己的焦点字色" % type)
		assert_eq(_theme.get_color(&"font_focus_color", type), _theme.get_color(&"font_color", type),
				"%s 焦点时字色不能变淡" % type)


## Toast 曾经是「300 最小宽 + 双层内边距」，一行 12 个字撑出 332×89 的白块，
## 文字只占 20% 面积（用户：背景太大但文字太小）。专用变体把内边距收到 20/12，
## 卡片改由内容撑开，短提示约 276×49。
func test_toast_card_is_tight_around_its_text() -> void:
	assert_eq(_theme.get_type_variation_base(&"ToastCard"), &"PanelContainer",
		"ToastCard 是 PanelContainer 的变体，面板卡片样式不受影响")
	var card := _theme.get_stylebox("panel", "ToastCard") as StyleBoxFlat
	assert_not_null(card, "Toast 有专用样式")
	if card != null:
		var pad_x := card.get_content_margin(SIDE_LEFT) + card.get_content_margin(SIDE_RIGHT)
		var pad_y := card.get_content_margin(SIDE_TOP) + card.get_content_margin(SIDE_BOTTOM)
		assert_lte(pad_x, 44.0, "横向内边距不超过 44px——再宽就回到「大背景小文字」")
		assert_lte(pad_y, 28.0, "纵向内边距不超过 28px——一行字不该占 89px 高")
		assert_gt(card.bg_color.get_luminance(), 0.85, "Toast 底色仍是浅色纸面")
		assert_gt(card.border_width_left, 0, "没有描边时会和背后卡片糊在一起")
	var base := _theme.get_stylebox("panel", "PanelContainer")
	assert_ne(card, base, "不要改 PanelContainer 的通用样式——那会影响所有面板卡片")


## 表单控件（勾选、下拉、输入框、进度条、滑杆把手）以前没有主题项，全靠各面板
## 逐个 add_theme_*_override 手工描一遍，字号码不准、下拉弹层还是系统灰菜单。
## 这组断言盯住「主题里有这五件」——删掉就会在这里红。
func test_form_controls_have_theme_entries() -> void:
	var input := _theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat
	assert_not_null(input, "LineEdit 有输入框样式")
	if input != null:
		assert_gt(input.border_width_left, 0, "输入框要有描边，否则在浅底上看不出可输入区域")
		assert_gt(input.get_content_margin(SIDE_LEFT), 8.0, "文字不能贴着边框")
	assert_not_null(_theme.get_stylebox("focus", "LineEdit"), "输入框聚焦要换样式")
	assert_lt(_theme.get_color("font_placeholder_color", "LineEdit").get_luminance(), 0.6,
		"占位符别用最淡的墨——之前读起来像没写字")
	assert_gte(_theme.get_font_size("font_size", "LineEdit"), 16, "输入框字号不小于 16")

	var menu := _theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	assert_not_null(menu, "下拉弹层有纸片底——不写就是系统灰菜单")
	if menu != null:
		assert_gt(menu.bg_color.get_luminance(), 0.85, "弹层底色跟卡片一致")
		assert_gt(menu.border_width_left, 0, "弹层要有描边")
	var hover := _theme.get_stylebox("hover", "PopupMenu") as StyleBoxFlat
	assert_not_null(hover, "下拉悬停项有自己的底色")
	if hover != null:
		assert_lt(hover.bg_color.get_luminance(), 0.45,
			"悬停/选中项底色够深，白字才压得住（原来的强调蓝只有 3.9:1）")
	assert_gte(_theme.get_color("font_hover_color", "PopupMenu").get_luminance(), 0.8,
		"悬停项的文字要亮")

	var track := _theme.get_stylebox("background", "ProgressBar") as StyleBoxFlat
	var fill := _theme.get_stylebox("fill", "ProgressBar") as StyleBoxFlat
	assert_not_null(track, "进度条有轨道样式")
	assert_not_null(fill, "进度条有填充样式")
	if track != null and fill != null:
		assert_lt(fill.bg_color.get_luminance(), track.bg_color.get_luminance(),
			"填充要比轨道深，才看得出走了多远")

	assert_not_null(_theme.get_icon("grabber", "HSlider"), "滑杆要有个看得见的把手")
	assert_gte(_theme.get_font_size("font_size", "CheckButton"), 16, "勾选文字不小到看不清")


func test_tooltip_is_ink_on_paper() -> void:
	var panel := _theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	assert_not_null(panel, "ToolTip 有纸色底——不写就落回引擎默认的深色")
	if panel != null:
		assert_gt(panel.bg_color.get_luminance(), 0.85, "ToolTip 底色是浅色纸面")
		assert_lt(panel.border_color.get_luminance(), 0.4, "边框与文字是深墨")
		assert_gt(panel.border_width_left, 0, "没有描边时浅底会跟卡片糊在一起")
	var ink := _theme.get_color("font_color", "TooltipLabel")
	assert_lt(ink.get_luminance(), 0.4, "ToolTip 文字是深墨")
	assert_gte(_theme.get_font_size("font_size", "TooltipLabel"), 16, "字号不比正文小太多")

## ToolTip 从前只能靠引擎 `Control.tooltip_text`：宽度没上限、贴边不避让、键盘焦点
## 不触发。F 批把提示换成自绘浮层（scripts/ui/tooltip_layer.gd），卡片用专属变体——
## 引擎自带的内边距 12/9 对一行字偏大（「设置」两字撑出 56×40 的框）。
func test_tooltip_card_variant_is_tighter_than_engine_tooltip() -> void:
	assert_eq(_theme.get_type_variation_base(&"TooltipCard"), &"PanelContainer",
		"TooltipCard 是 PanelContainer 的变体，只影响自绘提示")
	var card := _theme.get_stylebox("panel", "TooltipCard") as StyleBoxFlat
	var engine := _theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	assert_not_null(card, "自绘提示有专用样式")
	assert_not_null(engine, "引擎提示的样式还在——回落路径要用")
	if card != null and engine != null:
		var card_pad := card.get_content_margin(SIDE_LEFT) + card.get_content_margin(SIDE_RIGHT)
		var engine_pad := engine.get_content_margin(SIDE_LEFT) + engine.get_content_margin(SIDE_RIGHT)
		assert_lt(card_pad, engine_pad, "自绘提示的横向内边距要比引擎版紧，短文案才不会显得空")
		assert_gt(card.border_width_left, 0, "没有描边时浅底会跟卡片糊在一起")
		assert_gt(card.bg_color.get_luminance(), 0.85, "自绘提示也是纸面色")
	assert_ne(card, _theme.get_stylebox("panel", "PanelContainer"),
		"不要改 PanelContainer 的通用样式——那会影响所有面板卡片")


## 文字色在纸片底上必须过 WCAG AA（4.5:1）。淡墨 INK_DIM 不在此列——它只留给
## 禁用态与装饰；正文、说明、状态字都用次墨及更深的一档。
func test_text_tones_clear_aa_on_paper() -> void:
	var papers := {"card": PanelKit.CARD, "card_hi": PanelKit.CARD_HI}
	var tones := {
		"ink": PanelKit.INK,
		"ink_soft": PanelKit.INK_SOFT,
		"accent_deep": PanelKit.ACCENT_DEEP,
		"danger_deep": PanelKit.DANGER_DEEP,
	}
	for paper_name in papers:
		for tone_name in tones:
			var ratio := _contrast(tones[tone_name], papers[paper_name])
			assert_gt(ratio, 4.5, "%s on %s 应过 AA，实测 %.2f:1" % [tone_name, paper_name, ratio])


## 强调色本体只给图标与边框用：白字压上去只有 3.7:1，不够当文字底。
func test_accent_alone_is_not_a_text_background() -> void:
	assert_lt(_contrast(PanelKit.CARD_HI, PanelKit.ACCENT), 4.5, "ACCENT 作白字底本就不达标（所以才要 ACCENT_DEEP）")
	assert_gt(_contrast(PanelKit.CARD_HI, PanelKit.ACCENT_DEEP), 4.5, "ACCENT_DEEP 压白字要过 AA")


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	return 0.2126 * _channel(color.r) + 0.7152 * _channel(color.g) + 0.0722 * _channel(color.b)


func _channel(value: float) -> float:
	return value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)
