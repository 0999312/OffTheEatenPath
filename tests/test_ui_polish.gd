extends GutTest
## 打磨（E 批）：主操作按钮与分隔线。这两件都是「形状说话」的部件 ——
## 颜色变了、形状没变，玩家仍然认得出「这是主操作」「这是一行」；反过来说，
## 形状一换，颜色调得再对也会读错。


## 订单卡曾经因为禁用的「交付」变成灰块、旁边的「拒」是墨边按钮，视觉重心整个落到次操作上
## （报告 P1-6）。主按钮禁用时只退颜色，圆角、描边、底边厚度都不动。
func test_primary_button_keeps_its_shape_when_disabled() -> void:
	var button := PanelKit.primary_button("做一份")
	assert_eq(button.focus_mode, Control.FOCUS_ALL, "主按钮也进焦点链")
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	var disabled := button.get_theme_stylebox("disabled") as StyleBoxFlat
	assert_not_null(normal, "有常态样式")
	assert_not_null(disabled, "有禁用样式")
	assert_eq(disabled.corner_radius_top_left, normal.corner_radius_top_left, "禁用不换形状")
	assert_eq(disabled.border_width_bottom, normal.border_width_bottom, "底边厚度不变")
	assert_gt(disabled.bg_color.get_luminance(), normal.bg_color.get_luminance(), "禁用是同一块颜色的浅一档，不是灰块")
	assert_eq(button.get_theme_color("font_color"), PanelKit.CARD_HI, "常态白字")
	assert_eq(button.get_theme_color("font_disabled_color"), PanelKit.INK_SOFT, "禁用字退到次墨")
	button.free()


## 分隔线在 1280 宽、纸片底上要看得见。0.28 的墨在渲染后几乎消失（报告 P1-5），
## 于是「列表项之间没有分隔」看起来像根本没画线。
func test_divider_is_visible_on_paper() -> void:
	var line := PanelKit.divider()
	assert_almost_eq(line.color.a, 0.36, 0.001, "分隔线不透明度")
	assert_gt(line.color.a, 0.3, "淡到 0.3 以下就等于没画")
	assert_lt(line.color.a, 0.5, "再深就变成表格线，压过纸片的层次")
	assert_eq(line.custom_minimum_size.y, 1.0, "一条纸厚的线")
	line.free()


## 「选中」曾经有三种语言：列表行是彩色底 + 左蓝条、筛选芯片是深蓝实底白字、页签是白底 + 顶蓝条。
## 统一成一条规则 —— 纸白底 + 强调色框 + 墨字，只靠加粗哪条边区分层级（报告 §5.8）。
func test_selection_style_is_shared_by_tabs_chips_and_rows() -> void:
	var chip := PanelKit.selection_box(8)
	assert_eq(chip.bg_color, PanelKit.CARD_HI, "选中是纸白，不是实底大色块")
	assert_eq(chip.border_color, PanelKit.ACCENT, "框用强调色")
	assert_eq(chip.border_width_left, 2, "芯片四边等宽")
	assert_eq(chip.border_width_right, 2, "芯片四边等宽")

	var row := PanelKit.selection_box(10, 6)
	assert_eq(row.border_width_left, 6, "列表行加粗左边")
	assert_eq(row.border_width_right, 2, "其余边仍是细框")

	# 行浮在纸白面板（CARD）上：这时再用纸白就贴成一片，只剩一圈 2px 蓝框
	# （用户 2026-10-27 截图：「选中后组件背景与背景板融为一体」）。
	# 所以选中面比所在的那层纸暗一档，仍然比纸白亮一档 —— 始终朝「离容器更远」的方向走。
	var on_paper := PanelKit.selection_box(10, 6, false, PanelKit.SELECT_FILL)
	assert_eq(on_paper.bg_color, PanelKit.SELECT_FILL, "行用压暗一档的选中面")
	assert_lt(on_paper.bg_color.get_luminance(), PanelKit.CARD.get_luminance(), "比面板底色暗，才不会融成一片")
	assert_gt(on_paper.bg_color.get_luminance(), PanelKit.ACCENT.get_luminance(), "也别暗到只剩框在说话")

	var tab := PanelKit.selection_box(3, 3, true)
	assert_eq(tab.border_width_top, 3, "页签加粗顶边")

	# 页签由主题承担，值要和工厂对齐；否则「统一」只是三处各写一遍
	var theme := load("res://resources/themes/paper_theme.tres") as Theme
	var theme_tab := theme.get_stylebox("tab_selected", "TabBar") as StyleBoxFlat
	assert_not_null(theme_tab, "主题里有页签选中样式")
	assert_gt(theme_tab.bg_color.get_luminance(), 0.9, "页签选中也是纸白")
	# .tres 里存六位小数、常量写三位，浮点比不等但颜色相同 —— 比 8-bit 值才对得上
	assert_gt(theme_tab.border_width_top, theme_tab.border_width_left, "页签靠顶边加粗表态")

	# 芯片落地：FilterBar 的选中态必须就是这一套
	var bar := FilterBar.new()
	add_child_autofree(bar)
	bar.add_segments("record", [{"value": 0, "key": "ui.catalog.filter_all"}, {"value": 1, "key": "ui.catalog.filter_found"}], 0)
	var chips: Array = (bar.get("_segment_chips") as Dictionary)["record"]
	var on := (chips[0] as Button).get_theme_stylebox("pressed") as StyleBoxFlat
	assert_eq(on.bg_color, PanelKit.CARD_HI, "芯片选中是纸白底")
	assert_eq(on.border_color, PanelKit.ACCENT, "芯片选中是强调色框")
	assert_eq((chips[0] as Button).get_theme_color("font_pressed_color"), PanelKit.INK, "选中字是墨色，不是白字")
	assert_eq(theme_tab.border_color.to_html(false), PanelKit.ACCENT.to_html(false), "页签选中也描强调色")
