extends GutTest
## 「更多筛选」浮层的高度：主题与标签是开集（内容会涨，Mod 还会再添），
## 所以浮层高度只跟屏幕走；组区自己滚，不许把浮层撑出屏幕。

const ANCHOR := Rect2(0.0, 40.0, 80.0, 36.0)


func _make_bar(groups: int, per_group: int) -> FilterBar:
	var bar := FilterBar.new()
	bar.custom_minimum_size = Vector2(900.0, 36.0)
	bar.size = Vector2(900.0, 36.0)
	add_child_autofree(bar)
	var options: Array = []
	for i in per_group:
		options.append({"label": "主题 %d" % i, "value": "t%d" % i})
	for g in groups:
		bar.add_menu_group("group_%d" % g, "ui.filter.all", options)
	return bar


func test_many_groups_scroll_instead_of_stretching_the_popup() -> void:
	# 40 组 × 12 个芯片 ≈ 1560px，比任何窗口都高（headless 下 viewport 是 1280 见方）
	var bar := _make_bar(40, 12)
	await wait_process_frames(2)
	var wanted := bar._menu_groups_box.get_combined_minimum_size().y
	var rect: Rect2i = bar.call("_menu_geometry", ANCHOR)
	assert_gt(wanted, bar._menu_scroll.custom_minimum_size.y + 1.0,
			"组区比显示区高，说明是滚动而不是把浮层拉长")
	assert_lte(rect.end.y, int(bar.get_viewport_rect().size.y),
			"浮层底边不许出去")


func test_popup_turns_upward_when_anchored_at_screen_bottom() -> void:
	var bar := _make_bar(12, 10)
	await wait_process_frames(2)
	var view_height := bar.get_viewport_rect().size.y
	var anchored := Rect2(0.0, view_height - 40.0, 80.0, 36.0)
	var rect: Rect2i = bar.call("_menu_geometry", anchored)
	assert_lte(rect.end.y, int(view_height) - 8, "贴着底边打开时，浮层要往上抬")
	assert_gte(rect.position.y, 8, "抬也要留点边距，不能顶到天花板外")


func test_a_short_menu_keeps_its_natural_height() -> void:
	var bar := _make_bar(1, 3)
	await wait_process_frames(2)
	# 首次打开时 HFlowContainer 还没按宽度换行，必须等 popup 真正显示后再量内容高。
	bar.call("_open_menu")
	await wait_process_frames(2)
	var wanted := bar._menu_groups_box.get_combined_minimum_size().y
	assert_almost_eq(bar._menu_scroll.custom_minimum_size.y, wanted, 0.5,
			"组少时按内容高，不强行拉满")
	bar._menu_popup.hide()


func test_first_open_shows_all_wrapped_tag_rows() -> void:
	var bar := _make_bar(1, 9)
	await wait_process_frames(2)
	bar.call("_open_menu")
	await wait_process_frames(2)
	var wanted := bar._menu_groups_box.get_combined_minimum_size().y
	assert_gt(wanted, 64.0, "九个标签应当换行，不能只按一行量高")
	# 只许高不许矮。九枚标签正好卡在换行边界，不同平台的字体度量与滚动条宽度会把
	# 实际行数推来推去（CI 上就量到过 2 行），所以这里要求「自算不低于实际」，
	# 而不是精确相等 —— 多留一行是空白，少留一行就是裁字。
	assert_gte(bar._menu_scroll.custom_minimum_size.y, wanted - 0.5,
			"第一次打开就要把换行后的标签全部算进去，宁可多留也不能裁")
	bar._menu_popup.hide()


func test_popup_height_is_capped_by_host_panel() -> void:
	var bar := FakePanelBar.new()
	bar.host_rect = Rect2(200.0, 36.0, 880.0, 648.0)
	bar.custom_minimum_size = Vector2(900.0, 36.0)
	bar.size = Vector2(900.0, 36.0)
	add_child_autofree(bar)
	var options: Array = []
	for i in 10:
		options.append({"label": "标签 %d" % i, "value": "t%d" % i})
	for g in 12:
		bar.add_menu_group("group_%d" % g, "ui.filter.all", options)
	await wait_process_frames(2)
	bar.call("_open_menu")
	await wait_process_frames(2)
	var popup: PopupPanel = bar._menu_popup
	assert_gt(popup.size.y, 500, "标签多时浮层要接近面板高度，而不是只留一条缝")
	assert_lt(popup.size.y, 648, "浮层仍应比宿主面板矮一点")
	assert_lte(popup.position.y + popup.size.y, 684, "浮层底边不能漏出面板")
	popup.hide()


class FakePanelBar extends FilterBar:
	var host_rect := Rect2()

	func _host_panel_rect() -> Rect2:
		return host_rect
