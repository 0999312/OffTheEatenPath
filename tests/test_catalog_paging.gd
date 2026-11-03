extends GutTest
## 图鉴分页：食物 288 条分 15 页（每页 20），翻页不丢筛选，
## 时钟刷新也不会把玩家丢回第 1 页。

const FOOD_TAB := 1
const EAST_ASIA := "game:theme/east_asia"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _open_food_page() -> CatalogPanel:
	UIManager.close_all()
	await wait_process_frames(1)
	var location := ResourceLocation.from_string("idle_food:catalog")
	var panel := UIManager.open_panel(location, {"tab": "food"}) as CatalogPanel
	await wait_process_frames(1)
	return panel


## 一条记录一个「查看」按钮，数它比数容器稳
func _row_count(panel: CatalogPanel) -> int:
	var view_text := I18n.t("ui.catalog.view")
	var count := 0
	for node in panel.content.find_children("*", "Button", true, false):
		if (node as Button).text == view_text:
			count += 1
	return count


func _footer_button(panel: CatalogPanel, text: String) -> Button:
	for node in panel.footer.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


func _page_count(panel: CatalogPanel) -> int:
	return maxi(1, ceili(float(panel._filtered_defs("food").size()) / float(CatalogPanel.PAGE_SIZE)))


func _expect_page_label(panel: CatalogPanel) -> void:
	var wanted := I18n.t("ui.catalog.page", [panel._page + 1, _page_count(panel)])
	var found := false
	for node in panel.footer.find_children("*", "Label", true, false):
		if (node as Label).text == wanted:
			found = true
			break
	assert_true(found, "页脚应显示「%s」" % wanted)


func test_food_page_splits_into_pages_of_twenty() -> void:
	var panel := await _open_food_page()
	assert_eq(panel._page, 0, "打开时停在第 1 页")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "第 1 页铺满 20 条")
	assert_eq(_page_count(panel), 15, "288 道分 15 页")
	_expect_page_label(panel)


func test_last_page_is_short() -> void:
	var panel := await _open_food_page()
	panel._page = 14
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_row_count(panel), 8, "末页只剩 288 - 14×20 = 8 条")
	_expect_page_label(panel)


func test_next_page_shows_the_next_batch() -> void:
	var panel := await _open_food_page()
	var first_names := _visible_names(panel)
	panel._on_page_step(1)
	await wait_process_frames(1)
	assert_eq(panel._page, 1, "翻到第 2 页")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "第 2 页也是 20 条")
	var second_names := _visible_names(panel)
	assert_eq(first_names.filter(func(name: String) -> bool: return second_names.has(name)).size(), 0,
		"两页条目不该重叠")
	_expect_page_label(panel)


## 页面上看得见的第一行名字，用来判断两页内容是否换了
func _visible_names(panel: CatalogPanel) -> Array[String]:
	var out: Array[String] = []
	var view_text := I18n.t("ui.catalog.view")
	for node in panel.content.find_children("*", "Button", true, false):
		if (node as Button).text == view_text:
			var row := (node as Button).get_parent()
			if row != null and row.get_child_count() > 0:
				out.append(String(row.get_child(0).name))
	return out


func test_buttons_disable_at_both_edges() -> void:
	var panel := await _open_food_page()
	var prev := _footer_button(panel, I18n.t("ui.catalog.prev"))
	var next_button := _footer_button(panel, I18n.t("ui.catalog.next"))
	assert_not_null(prev, "页脚应有「上一页」")
	assert_not_null(next_button, "页脚应有「下一页」")
	assert_true(prev.disabled, "第 1 页没有上一页")
	assert_false(next_button.disabled, "第 1 页可以往后翻")

	panel._page = 14
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	prev = _footer_button(panel, I18n.t("ui.catalog.prev"))
	next_button = _footer_button(panel, I18n.t("ui.catalog.next"))
	assert_false(prev.disabled, "末页可以往回翻")
	assert_true(next_button.disabled, "末页没有下一页")


func test_paging_keeps_the_active_filter() -> void:
	var panel := await _open_food_page()
	# 主题收在「筛选」浮层里（G 批）：走芯片的真实链路，而不是绕过 UI 改字段
	panel._bar.call("_on_menu_pressed", "theme", EAST_ASIA)
	await wait_process_frames(1)
	assert_eq(panel._filtered_defs("food").size(), 57, "东亚主题 57 道（春卷归东亚、烤茄子新增）")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "第 1 页 20 条")

	panel._on_page_step(1)
	await wait_process_frames(1)
	assert_eq(panel._theme_key, EAST_ASIA, "翻页不改筛选")
	assert_eq(_row_count(panel), 20, "第 2 页也铺满 20 条（57 道分三页）")


func test_changing_filter_returns_to_the_first_page() -> void:
	var panel := await _open_food_page()
	panel._on_page_step(1)
	await wait_process_frames(1)
	assert_eq(panel._page, 1, "先翻到第 2 页")

	panel._bar.call("_on_segment_pressed", "record", 2)
	await wait_process_frames(1)
	assert_eq(panel._page, 0, "改筛选应回到第 1 页")


## 时钟每 0.3 秒调一次 refresh()：页码进了结构指纹，重建后仍在同一页
func test_clock_refresh_keeps_the_current_page() -> void:
	var panel := await _open_food_page()
	panel._on_page_step(1)
	await wait_process_frames(1)
	assert_eq(panel._page, 1, "先翻到第 2 页")

	panel.refresh()
	await wait_process_frames(1)
	assert_eq(panel._page, 1, "刷新后仍在第 2 页")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "第 2 页内容还在")
	_expect_page_label(panel)
