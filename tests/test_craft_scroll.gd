extends GutTest
## 灶台外层滚动修复（试玩第三轮反馈 2）。
##
## 左列列表和右列详情各自滚；外层再套一层 ScrollContainer 时，滚轮会先被
## 外层吃掉，两列一起上下跑。这里锁住「外层不滚 + 两列撑满纸高」。

const CRAFT := "idle_food:craft"
const CATALOG := "idle_food:catalog"
const COFFEE_BEAN := "game:item/coffee_bean"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func test_craft_panel_has_no_outer_scroll() -> void:
	var panel := await _open_craft()
	assert_not_null(panel, "灶台应能打开")
	assert_false(panel.wants_outer_scroll(), "灶台应自己管滚动")
	assert_null(panel.get_outer_scroll(), "灶台不应再套外层滚动区")


func test_other_panels_keep_outer_scroll() -> void:
	var panel := UIManager.open_panel(ResourceLocation.from_string(CATALOG))
	await wait_process_frames(2)
	assert_not_null(panel, "书架应能打开")
	assert_true(panel.wants_outer_scroll(), "书架仍是整页滚动")
	assert_not_null(panel.get_outer_scroll(), "书架应保留外层滚动区")


func test_craft_columns_fill_the_paper() -> void:
	var panel := await _open_craft()
	var row := panel.content.get_child(0) as HBoxContainer
	assert_not_null(row, "灶台内容第一行应是两列")
	if row == null:
		return
	assert_ne(row.size_flags_vertical & Control.SIZE_EXPAND, 0, "两列应纵向撑满纸面")
	assert_not_null(panel._list_scroll, "左列应有自己的滚动区")
	assert_true(panel._list_scroll.size.y >= 320.0, "左列不应被压到最小高以下（实际 %.1f）" % panel._list_scroll.size.y)


func test_five_jobs_are_summarized_in_the_footer_inside_the_paper() -> void:
	# 第二轮规范②：进度条已经上卡，页脚只留总览，多条产线也不再长高。
	GameState._kitchen_level = 5
	var recipe_keys: Array[String] = [
		"game:recipe/roast_bean",
		"game:recipe/make_dough",
		"game:recipe/espresso",
		"game:recipe/croissant",
		"game:recipe/ice",
	]
	for key in recipe_keys:
		var job := CraftJob.new()
		job.recipe_key = key
		job.facility_key = ""
		job.batches = 1
		job.total_seconds = 30.0
		job.remaining_seconds = 17.3
		GameState._jobs.append(job)

	var panel := await _open_craft()
	assert_true(panel.footer.find_children("*", "ScrollContainer", true, false).is_empty(),
			"页脚只留总览，不再有第二套任务滚动条")
	var summary := I18n.t("ui.craft.lanes_in_use", [recipe_keys.size(), GameState.get_lane_count()])
	var has_summary := false
	for node in panel.footer.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text == summary:
			has_summary = true
			break
	assert_true(has_summary, "页脚要报「%s」" % summary)

	var footer_bottom := panel.footer.get_global_rect().end.y
	var card := panel.footer.get_parent().get_parent() as Control
	assert_not_null(card, "页脚应挂在面板卡片里")
	if card == null:
		return
	assert_lt(footer_bottom, card.get_global_rect().end.y - 8.0,
			"页脚不应越过卡片底边（footer %.1f / card %.1f）" % [footer_bottom, card.get_global_rect().end.y])


func _open_craft() -> CraftPanel:
	UIManager.close_all()
	GameState.add_item(COFFEE_BEAN, 3)
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string(CRAFT)) as CraftPanel
	await wait_process_frames(2)
	return panel
