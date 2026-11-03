extends GutTest
## 仓库：三页签（材料/成品/产地）、只列手上有货的、卖 1 / 卖光两段式、
## 容量按仓库等级、产地升级收在这一页、空态与检索。
##
## 面板一律走 UIManager 打开——测的是「玩家真的从桌沿点开」那条链路，
## 与 test_merchant_panel.gd 同一套做法。

const WAREHOUSE := "idle_food:warehouse"
const MILK := "game:item/milk"
const TOAST := "game:item/toast"
const WATER := "game:item/water"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _open(tab: String = "") -> WarehousePanel:
	UIManager.close_all()
	await wait_process_frames(1)
	var data := {}
	if not tab.is_empty():
		data["tab"] = tab
	var panel := UIManager.open_panel(ResourceLocation.from_string(WAREHOUSE), data) as WarehousePanel
	await wait_process_frames(1)
	return panel


## 递归收一段子树里所有 Label 的文字（行内层级会变，不写死下标）
func _texts_of(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label:
		texts.append((node as Label).text)
	for child in node.get_children():
		texts.append_array(_texts_of(child))
	return texts


func _button_starting_with(root: Node, prefix: String) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child as Button
		var found := _button_starting_with(child, prefix)
		if found != null:
			return found
	return null


func test_empty_pantry_tells_you_where_to_start() -> void:
	var panel := await _open()
	assert_eq(panel._tab, 0, "默认停在材料页")
	assert_eq(panel.content.get_child_count(), 3, "空仓仍有容量行 + 分隔 + 一句空态")
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.empty_material")))

	panel._on_tab_changed(1)
	await wait_process_frames(1)
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.empty_food")), "成品页有自己的一句")

func test_harvest_tab_shows_capacity_and_upgrades_the_warehouse() -> void:
	GameState.add_coins(1000, "test")
	var panel := await _open("harvest")
	assert_eq(panel._tab, 2, "open 时可以点名产地页")
	assert_null(panel._bar, "产地页不摆检索条")
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.capacity_title")), "容量抬头在")
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.capacity_line", [20, 10, 10])), "1 级三档上限")
	assert_eq(GameState.get_warehouse_level(), 1)

	var upgrade := _button_starting_with(panel.content, I18n.t("ui.warehouse.upgrade", [2, PanelKit.coins_text(80)]))
	assert_not_null(upgrade, "仓库升级按钮在")
	if upgrade == null:
		return
	upgrade.pressed.emit()
	await wait_process_frames(2)
	assert_eq(GameState.get_warehouse_level(), 2, "点一下就升到 2 级")
	assert_eq(GameState.get_warehouse_cap_common(), 40, "常见料 20 → 40（每级 +1 倍）")
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.capacity_line", [40, 20, 20])), "容量行跟着换")


func test_harvest_page_upgrades_a_source() -> void:
	GameState.add_coins(1000, "test")
	var panel := await _open("harvest")
	var levels_before := {}
	for harvest in GameState.get_harvest_points():
		levels_before[harvest.get_key()] = GameState.get_harvest_level(harvest.get_key())
	var upgrade := _button_starting_with(panel.content, I18n.t("ui.warehouse.harvest_upgrade", [2, PanelKit.coins_text(40)]))
	assert_not_null(upgrade, "产地升级按钮在")
	if upgrade == null:
		return
	upgrade.pressed.emit()
	await wait_process_frames(2)
	var raised := 0
	for harvest in GameState.get_harvest_points():
		if GameState.get_harvest_level(harvest.get_key()) > int(levels_before[harvest.get_key()]):
			raised += 1
	assert_eq(raised, 1, "只升被点的那一条产地")


func test_catalog_no_longer_carries_a_per_material_upgrade_button() -> void:
	GameState.add_item(MILK, 1)
	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string("idle_food:catalog"), {"tab": "material"}) as CatalogPanel
	await wait_process_frames(1)
	assert_not_null(panel, "书架应能打开")
	if panel == null:
		return
	assert_null(_button_starting_with(panel.content, "↑"), "材料行不再各挂一个升级按钮")



func test_tabs_split_materials_from_food() -> void:
	GameState.add_item(MILK, 3)
	GameState.add_item(TOAST, 1)
	var panel := await _open("material")
	var materials := panel._tab_items()
	assert_eq(materials.size(), 1, "材料页只列材料")
	if materials.size() == 1:
		assert_eq(materials[0].get_key(), MILK)
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.owned", [PanelKit.big_number_text(3)])), "存量照实写")

	panel._on_tab_changed(1)
	await wait_process_frames(1)
	var foods := panel._tab_items()
	assert_eq(foods.size(), 1, "成品页只列做好的菜")
	if foods.size() == 1:
		assert_eq(foods[0].get_key(), TOAST)


func test_selling_one_moves_it_out_and_pays() -> void:
	GameState.add_item(TOAST, 2)
	var panel := await _open("food")
	var def := panel.def_of(TOAST) as ItemDef
	assert_not_null(def)
	var before := GameState.coins
	var button := _button_starting_with(panel.content, I18n.t("ui.warehouse.sell_button", [1, def.sell_price]))
	assert_not_null(button, "有收购价的成品应摆出「卖 1」")
	if button != null:
		button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(GameState.get_amount(TOAST), 1, "卖 1 份只扣 1 份")
	assert_eq(GameState.coins, before + def.sell_price, "钱按收购价进账")


func test_sell_all_takes_two_presses() -> void:
	GameState.add_item(TOAST, 2)
	var panel := await _open("food")
	var def := panel.def_of(TOAST) as ItemDef
	var before := GameState.coins
	var all_button := _button_starting_with(panel.content, I18n.t("ui.warehouse.sell_all", [2]))
	assert_not_null(all_button, "整摞卖出要先有个按钮")
	if all_button == null:
		return
	all_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(GameState.get_amount(TOAST), 2, "第一下只是武装，不真卖")
	assert_eq(GameState.coins, before, "第一下不动钱")
	assert_eq(panel._armed_all, TOAST, "这一行进入待确认")

	# 武装后那一行按钮换了字，重新按它
	var confirm_button := _button_starting_with(panel.content, I18n.t("ui.warehouse.sell_all_armed", [2 * def.sell_price]))
	assert_not_null(confirm_button, "按钮应改成确认文案")
	if confirm_button != null:
		confirm_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(GameState.get_amount(TOAST), 0, "第二下才整摞卖掉")
	assert_eq(GameState.coins, before + 2 * def.sell_price)


func test_material_the_merchant_will_not_buy_says_so() -> void:
	GameState.add_item(WATER, 1)
	var panel := await _open("material")
	var def := panel.def_of(WATER) as ItemDef
	assert_eq(def.sell_price, 0, "测试依赖：水这类中间料没有收购价")
	assert_true(_texts_of(panel.content).has(I18n.t("ui.warehouse.no_buyer")))
	assert_null(_button_starting_with(panel.content, I18n.t("ui.warehouse.sell_button", [1, 0])), "不收的东西不该有卖按钮")


func test_search_narrows_and_reports_the_count() -> void:
	GameState.add_item(MILK, 1)
	GameState.add_item(TOAST, 1)
	var panel := await _open("food")
	var toast := panel.def_of(TOAST) as ItemDef
	panel._bar._search.text = toast.localized().left(1)
	panel._on_filters_changed()
	await wait_process_frames(1)
	assert_eq(panel._tab_items().size(), 1, "按名字筛只剩一道")
	assert_eq(panel._bar.get_keyword(), toast.localized().left(1))

	panel._bar._search.text = "zzz_not_a_dish"
	panel._on_filters_changed()
	await wait_process_frames(1)
	assert_true(_texts_of(panel.content).has(I18n.t("ui.filter.empty")), "筛空说的是「换个词」，不是「仓库空」")


## 状态段「能卖的」只留收购价 > 0 的条目（统一检索 §3）
func test_status_filter_keeps_only_sellable() -> void:
	GameState.add_item(MILK, 1)
	GameState.add_item(WATER, 1)
	var panel := await _open("material")
	var chip := _button_with_text(panel._bar, I18n.t("ui.warehouse.filter_sellable"))
	assert_not_null(chip, "材料页要有「能卖的」状态芯片")
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	assert_eq(panel._status_filter, 1, "状态记下了")
	assert_true(panel._has_filters(), "状态也是筛选条件")
	var items := panel._tab_items()
	assert_eq(items.size(), 1, "水没有收购价，应被挡掉")
	if items.size() == 1:
		assert_eq(items[0].get_key(), MILK)


## 材料页的标签浮层按 tag 收窄（材料看食材标签）
func test_tag_menu_narrows_materials() -> void:
	GameState.add_item(MILK, 1)
	GameState.add_item(WATER, 1)
	var panel := await _open("material")
	panel._bar._on_menu_pressed("tag", "game:tag/pantry")
	await wait_process_frames(1)
	assert_eq(panel._tag_key, "game:tag/pantry")
	var items := panel._tab_items()
	assert_eq(items.size(), 1, "只剩奶制品")
	if items.size() == 1:
		assert_eq(items[0].get_key(), MILK)


## 成品页的主题浮层认「没写 theme = base」这条回退
func test_theme_menu_treats_unset_theme_as_base() -> void:
	GameState.add_item(TOAST, 1)
	var panel := await _open("food")
	panel._bar._on_menu_pressed("theme", ItemDef.DEFAULT_THEME)
	await wait_process_frames(1)
	assert_eq(panel._theme_key, ItemDef.DEFAULT_THEME)
	assert_eq(panel._tab_items().size(), 1, "吐司没写 theme，归 base 后仍应留下")


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text:
			return button
	return null


## 换页签换分组维度，但搜索词留在框里（与商人同一套规矩）
func test_switching_tab_keeps_the_keyword_and_resets_sort() -> void:
	GameState.add_item(MILK, 1)
	var panel := await _open("material")
	panel._bar._search.text = (panel.def_of(MILK) as ItemDef).localized().left(1)
	panel._on_filters_changed()
	panel._sort_key = "name"
	panel._group_key = "source"
	panel._on_tab_changed(1)
	await wait_process_frames(1)
	assert_eq(panel._sort_key, "owned", "排序回到该页默认")
	assert_eq(panel._group_key, "", "分组清空，选项整排换掉")
	assert_eq(panel._bar.get_keyword(), (panel.def_of(MILK) as ItemDef).localized().left(1), "搜索词不该被悄悄清掉")
