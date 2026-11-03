extends GutTest
## 分组必须是排序的一级关键字（第二轮问题 ①，用户 2026-10-27）。
##
## 抬头由 `_build_page()` 在「换堆」时插一条，所以同堆条目一旦被别的堆隔开，
## 同一抬头就会反复出现 —— 屏幕上看着就是「根本没分组」，其实数据根本没排在一起。
## 这里守的是数据顺序：每一堆必须连成一段，段数等于堆数。
##
## 另外两条同轮报的 QoL 也一并守住：CheckButton 悬停按下的底框与字色、
## 卡片点过之后不留键盘焦点环。


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _open(panel_id: String, data: Dictionary = {}) -> UIPanel:
	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string(panel_id), data) as UIPanel
	await wait_process_frames(1)
	return panel


## 相邻相同的标签合成一段：分组合法时，段数等于不同标签的个数
func _runs(labels: Array) -> Array:
	var runs: Array = []
	for label in labels:
		var text := String(label)
		if runs.is_empty() or runs[runs.size() - 1] != text:
			runs.append(text)
	return runs


func _assert_contiguous(labels: Array, scene: String) -> void:
	assert_gt(labels.size(), 0, "%s：有可列的条目" % scene)
	var runs := _runs(labels)
	var unique: Array = []
	for label in labels:
		if not unique.has(label):
			unique.append(label)
	assert_gt(unique.size(), 1, "%s：至少两堆才谈得上分组（现状 %s）" % [scene, unique])
	assert_eq(runs.size(), unique.size(), "%s：每堆只该连成一段，现状 %s" % [scene, runs])


func test_catalog_food_groups_by_theme_are_contiguous() -> void:
	var panel := await _open(UIKeys.CATALOG, {"tab": "food"}) as CatalogPanel
	panel.set("_group_key", "theme")
	var labels: Array = []
	for def in panel._filtered_defs("food"):
		labels.append(panel._group_label_of(def, "food"))
	_assert_contiguous(labels, "图鉴·食物·按主题")


func test_catalog_material_groups_by_source_are_contiguous() -> void:
	var panel := await _open(UIKeys.CATALOG, {"tab": "material"}) as CatalogPanel
	panel.set("_group_key", "source")
	var labels: Array = []
	for def in panel._filtered_defs("material"):
		labels.append(panel._group_label_of(def, "material"))
	_assert_contiguous(labels, "图鉴·材料·按采集点")


func test_merchant_buy_groups_by_source_are_contiguous() -> void:
	var panel := await _open(UIKeys.MERCHANT) as MerchantPanel
	panel.set("_group_key", "source")
	var labels: Array = []
	for item in panel._tab_defs():
		labels.append(panel._group_label_of(item))
	_assert_contiguous(labels, "商店·买·按采集点")


## 「其他」是兜底堆，必须排最后：夹在正经分组中间会被读成又一个正经分类
func test_other_group_sorts_last() -> void:
	var panel := await _open(UIKeys.MERCHANT) as MerchantPanel
	panel.set("_group_key", "source")
	var labels: Array = []
	for item in panel._tab_defs():
		labels.append(panel._group_label_of(item))
	var runs := _runs(labels)
	var other := I18n.t("ui.filter.other")
	if not runs.has(other):
		pass_test("这一页没有归「其他」的货")
		return
	assert_eq(runs[runs.size() - 1], other, "「其他」必须排在最后")


## 悬停 + 按下是玩家最常制造的状态：按住不放时底框整个消失、字变白，
## 就等于「按下去东西没了」（用户 2026-10-27 截图报）。
func test_hover_pressed_state_keeps_its_frame_and_ink() -> void:
	var theme := load("res://resources/themes/paper_theme.tres") as Theme
	assert_true(theme.has_stylebox("hover_pressed", "CheckButton"), "开关要有悬停按下底色")
	assert_false(theme.get_stylebox("hover_pressed", "CheckButton") is StyleBoxEmpty, "不能是空样式")
	# .tres 存六位小数、常量写三位，浮点比不等；比 8-bit 值才是「颜色相同」
	assert_eq(theme.get_color("font_hover_pressed_color", "CheckButton").to_html(false), PanelKit.INK.to_html(false), "开关悬停按下时字是墨色")
	# 同一档颜色在普通按钮与下拉框上也缺过（主题从未定义，引擎默认白）
	assert_eq(theme.get_color("font_hover_pressed_color", "Button").to_html(false), PanelKit.INK.to_html(false), "普通按钮同理")
	assert_eq(theme.get_color("font_hover_pressed_color", "OptionButton").to_html(false), PanelKit.INK.to_html(false), "下拉框同理")


## 订单卡 / 采集卡点一下就开面板，关掉时基类会把焦点还给刚才那张卡 ——
## 键盘焦点环（3px 强调色描边）于是常亮，看起来像 hover 卡住了（用户 2026-10-27 报）。
func test_mouse_click_on_a_card_leaves_no_focus_ring() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10, 2, false))
	add_child_autofree(card)
	var fired: Array = [0]
	PanelKit.make_focusable(card, func() -> void: fired[0] += 1)
	card.grab_focus()
	assert_true(card.has_focus(), "卡片先拿到焦点")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card.emit_signal("gui_input", click)
	assert_false(card.has_focus(), "鼠标点过之后不该留着焦点环")
	assert_eq(fired[0], 0, "鼠标点击不走 make_focusable 的激活通道")
