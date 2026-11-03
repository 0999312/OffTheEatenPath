extends GutTest
## 检索条：搭得出来、状态读得回来、动一下就发 changed。
##
## 这里只测「控件契约」。哪些条目该留下、搜索能不能碰到未记录的名字，
## 是各面板自己的事（图鉴防剧透、商店持有量），由各自的测试守。

var _bar: FilterBar = null


func before_each() -> void:
	_bar = FilterBar.new()
	add_child_autofree(_bar)
	await wait_process_frames(1)


func test_reads_are_safe_before_anything_is_added() -> void:
	assert_eq(_bar.get_keyword(), "")
	assert_eq(_bar.get_segment("record"), 0)
	assert_eq(_bar.get_menu_value("theme"), "")
	assert_eq(_bar.get_group(), "")
	assert_eq(_bar.get_sort(), "")
	assert_eq(_bar.active_menu_count(), 0)


func test_search_keeps_its_text_and_reports_typing() -> void:
	watch_signals(_bar)
	var field := _bar.add_search("ui.catalog.search_placeholder", 150.0, "咖啡")
	assert_eq(_bar.get_keyword(), "咖啡", "初始值要带上（工具条重建后不能把玩家打的字弄丢）")
	# set_text() 是程序化赋值，引擎不会发 text_changed；手动补一发，模拟玩家敲了一个字
	field.text = "茶"
	field.text_changed.emit("茶")
	assert_eq(_bar.get_keyword(), "茶")
	assert_signal_emitted(_bar, "changed", "打字要通知面板重填列表")


func test_segments_switch_the_value_and_emit_changed() -> void:
	_bar.add_segments("record", [
		{"value": 0, "key": "ui.catalog.filter_all"},
		{"value": 1, "key": "ui.catalog.filter_found"},
	], 0)
	var chips: Array = (_bar.get("_segment_chips") as Dictionary)["record"]
	assert_eq(chips.size(), 2)
	assert_eq(_bar.get_segment("record"), 0)

	watch_signals(_bar)
	(chips[1] as Button).pressed.emit()
	assert_eq(_bar.get_segment("record"), 1)
	assert_signal_emitted(_bar, "changed")


func test_menu_group_counts_the_active_choices() -> void:
	_bar.add_menu_group("theme", "ui.catalog.filter_theme", [
		{"value": "", "label": "全部主题"},
		{"value": "game:theme/east_asia", "label": "东亚"},
	], "")
	assert_eq(_bar.active_menu_count(), 0, "默认没有生效的浮层维度")

	_bar.call("_on_menu_pressed", "theme", "game:theme/east_asia")
	assert_eq(_bar.get_menu_value("theme"), "game:theme/east_asia")
	assert_eq(_bar.active_menu_count(), 1)
	var button := _bar.get("_menu_button") as Button
	assert_not_null(button)
	assert_eq(button.text, I18n.t("ui.filter.more_count", [1]), "按钮要带上生效的组数")


func test_group_and_sort_return_the_selected_value() -> void:
	var group := _bar.add_group([
		{"value": "", "key": "ui.catalog.group_none"},
		{"value": "theme", "key": "ui.catalog.group_theme"},
	], "")
	var sort := _bar.add_sort([
		{"value": "default", "key": "ui.catalog.sort_default"},
		{"value": "name", "key": "ui.catalog.sort_name"},
	], "default")
	assert_eq(_bar.get_group(), "")
	assert_eq(_bar.get_sort(), "default")

	group.select(1)
	group.item_selected.emit(1)
	assert_eq(_bar.get_group(), "theme")

	sort.select(1)
	sort.item_selected.emit(1)
	assert_eq(_bar.get_sort(), "name")


## 结果数只在真筛过之后才显示：没筛时它和页脚总数重复，还白占宽度
func test_result_text_can_be_cleared() -> void:
	_bar.set_result_text("12 条")
	var label := _result_label()
	assert_not_null(label)
	assert_eq((label as Label).text, "12 条")

	_bar.set_result_text("")
	assert_eq((label as Label).text, "")


func _result_label() -> Label:
	for node in _bar.get_children():
		if node is Label:
			return node as Label
	return null