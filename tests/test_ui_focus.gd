extends GutTest
## 键盘可用性（用户 2026-10-27 拍板：「键盘和手柄是鼠标的替补」，所以凡是能点的都要能 Tab 到）。
##
## 之前 `PanelKit` 的三个按钮工厂都写死 `FOCUS_NONE`，主题里的焦点环根本没人用得上；
## 房间入口卡、HUD 订单卡、底部采集卡是自绘 PanelContainer，压根不参与焦点链。


func test_buttons_are_focusable_by_default() -> void:
	var plain := PanelKit.button("x")
	var sticker := PanelKit.sticker("x")
	var icon_button := PanelKit.icon_button("ui/settings.svg")
	assert_eq(plain.focus_mode, Control.FOCUS_ALL, "普通按钮能被 Tab 到")
	assert_eq(sticker.focus_mode, Control.FOCUS_ALL, "贴纸按钮能被 Tab 到")
	assert_eq(icon_button.focus_mode, Control.FOCUS_ALL, "图标按钮能被 Tab 到")
	plain.free()
	sticker.free()
	icon_button.free()


## 反馈 20：鼠标右键 = 返回，和 Esc 走同一条退路。
func test_right_click_is_bound_to_back() -> void:
	assert_true(InputMap.has_action("ui_back"), "应新增 ui_back 动作")
	var has_right := false
	for event in InputMap.action_get_events("ui_back"):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.button_index == MOUSE_BUTTON_RIGHT:
			has_right = true
			break
	assert_true(has_right, "ui_back 应绑鼠标右键")


func test_hotspot_card_takes_focus() -> void:
	var card := HotspotCard.new()
	assert_eq(card.focus_mode, Control.FOCUS_ALL, "房间入口卡能被 Tab 到")
	card.free()


func test_make_focusable_swaps_border_on_focus() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD, PanelKit.INK, 5, 2))
	PanelKit.make_focusable(card, func() -> void: pass)
	assert_eq(card.focus_mode, Control.FOCUS_ALL, "卡片接上焦点链")
	var rest := card.get_theme_stylebox("panel") as StyleBoxFlat
	card.focus_entered.emit()
	var focused := card.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(focused.border_color, PanelKit.ACCENT, "焦点时描边换成强调色")
	assert_gt(focused.border_width_left, rest.border_width_left, "焦点时描边加粗一档")
	card.focus_exited.emit()
	var back := card.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(back.border_color, PanelKit.INK, "失焦还原成墨边")
	card.free()


## Godot 不会因为 disabled 就跳过按钮：Tab 仍会停在灰掉的按钮上，焦点环套着灰字，
## 看起来像界面坏了（B 批实测：设备面板 Tab 停在缺料的升级钮）。
func test_disabled_buttons_leave_the_focus_chain() -> void:
	var button := PanelKit.button("x")
	PanelKit.set_disabled(button, true)
	assert_true(button.disabled, "确实禁用了")
	assert_eq(button.focus_mode, Control.FOCUS_NONE, "禁用后退出了焦点链")
	PanelKit.set_disabled(button, false)
	assert_false(button.disabled, "又能点了")
	assert_eq(button.focus_mode, Control.FOCUS_ALL, "恢复焦点")
	button.free()


## 折叠标题与图标按钮曾经把 focus 样式清成 StyleBoxEmpty：键盘停在上面时，界面上
## 一点变化都没有。焦点环是这两类控件唯一的「我在这里」提示。
func test_fold_and_icon_focus_rings_are_drawn() -> void:
	var section := PanelKit.fold_section("通用")
	var fold_focus := section.get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(fold_focus, "分组标题要有焦点样式")
	if fold_focus != null:
		assert_gt(fold_focus.border_width_left, 0, "至少画一圈描边")
		assert_eq(fold_focus.bg_color.a, 0.0, "只描边不铺底，别把标题栏那张纸片盖平")
	section.free()
	var button := PanelKit.icon_button("ui/settings.svg")
	var ring := button.get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(ring, "图标按钮要有焦点环")
	if ring != null:
		assert_gt(ring.border_width_left, 0, "焦点环画在描边上")
	button.free()
