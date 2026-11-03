extends GutTest
## 图鉴筛选回归：搜索、主题、已记录/未记录三档只影响「这一页显示什么」，
## 不碰图鉴总数、已发现数与里程碑。
##
## 走 UIManager 的真实栈（和 test_ui_panels 一样），测的是玩家点开的那条链路。

const FOOD_TAB := 1
const LATTE := "game:item/latte"
const STEAMED_EGG := "game:item/steamed_egg"
const EAST_ASIA := "game:theme/east_asia"
const HOME := "game:theme/base"
const CAFE := "game:theme/cafe"
const STREET := "game:tag/street"
const SWEET := "game:tag/sweet"

# 断言的文案要跟当前语言走：CI 的 Linux runner 默认 en，写死中文在那边必然失败。
var _original_language := ""


func before_each() -> void:
	_original_language = I18NManager.get_current_language()
	GameState.reset()


func after_each() -> void:
	I18NManager.set_language(_original_language)
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
## 当前页签 + 当前筛选下的条目总数（不受分页影响）
func _matching(panel: CatalogPanel, type_id: String) -> int:
	return panel._filtered_defs(type_id).size()


func _row_count(panel: CatalogPanel) -> int:
	var view_text := I18n.t("ui.catalog.view")
	var count := 0
	for node in panel.content.find_children("*", "Button", true, false):
		if (node as Button).text == view_text:
			count += 1
	return count


func test_food_page_lists_the_first_page_of_dishes() -> void:
	var panel := await _open_food_page()
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "食物页首页只铺 20 条")
	assert_eq(_matching(panel, "food"), 288, "食物页总数仍是 288 道（含未发现）")


func test_theme_filter_keeps_only_that_theme() -> void:
	var panel := await _open_food_page()

	panel._theme_key = EAST_ASIA
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 57, "东亚主题应有 57 道（春卷归东亚、烤茄子新增）")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "57 道要翻三页，首页仍是 20 条")

	panel._theme_key = HOME
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 61, "家常主题应只剩 61 道")

	panel._theme_key = CAFE
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 39, "咖啡馆主题应只剩 39 道")


func test_search_narrows_the_list() -> void:
	var panel := await _open_food_page()
	GameState.discover(LATTE)

	# 关键词从当前语言取，别写死中文：CI 的 Linux runner 默认 en，写死会搜出 0 条
	panel._keyword = I18n.t("data.item.latte.name")
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	var hits := _row_count(panel)
	assert_gt(hits, 0, "搜名字能搜到拿铁自己")
	assert_lt(hits, 288, "搜索要把范围从整页缩下来")

	# 地区主题要到站才解锁：未到站的条目连名字都显示「？？？」，搜索也不该把它试出来。
	# 所以线索搜索拿一条「已经在场、但还没记录」的条目来测。
	var needle := ""
	for def in panel.defs_of("item"):
		var item := def as ItemDef
		if item == null or not item.is_food() or GameState.is_discovered(item.get_key()):
			continue
		if not GameState.is_theme_unlocked(item.theme):
			continue
		var hint := panel._hint_of(item)
		if not hint.is_empty():
			needle = hint
			break
	assert_ne(needle, "", "应有一条未记录、线索非空的条目")
	panel._keyword = needle
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_gt(_row_count(panel), 0, "未记录的条目也能靠线索搜到")
	assert_lt(_row_count(panel), 288, "线索搜索应把范围缩小")


func test_missing_filter_hides_discovered_entries() -> void:
	GameState.discover(LATTE)
	var panel := await _open_food_page()

	panel._filter = 2
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 287, "未记录应把已发现的那条筛掉")

	panel._filter = 1
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_row_count(panel), 1, "已记录应只剩那一条")


## 标签是第二层筛选，与主题正交：能叠着用，也能各自单独用
func test_tag_filter_is_independent_of_theme() -> void:
	var panel := await _open_food_page()

	panel._tag_key = STREET
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 68, "街边宵夜标签应只剩 68 道")

	# 东亚 + 街边 = 能拿着走的东亚菜；三明治是家常主题，不算在内
	panel._theme_key = EAST_ASIA
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 16, "东亚里带街边标签的应是 16 道（春卷归东亚）")
	assert_eq(_row_count(panel), 16, "16 条不足一页，整页铺完")


## 标签跨品类：甜品饮品同时覆盖咖啡与烘焙，这正是它和主题不同的地方
func test_sweet_tag_spans_drinks_and_desserts() -> void:
	var panel := await _open_food_page()

	panel._tag_key = SWEET
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)
	assert_eq(_matching(panel, "food"), 72, "甜品饮品标签应覆盖 72 道")
	assert_eq(_row_count(panel), CatalogPanel.PAGE_SIZE, "72 条分 4 页，首页 20 条")


## 筛选是纯展示层：图鉴总数与已发现数都不能跟着动（里程碑按总数算）
func test_filter_never_touches_catalog_totals() -> void:
	var total := GameState.get_catalog_total()
	var discovered := GameState.get_catalog_discovered_count()
	var panel := await _open_food_page()

	panel._theme_key = EAST_ASIA
	panel._tag_key = STREET
	panel._filter = 2
	panel._keyword = "汤"
	panel._fill_page(FOOD_TAB)
	await wait_process_frames(1)

	assert_eq(GameState.get_catalog_total(), total, "筛选不该改图鉴总数")
	assert_eq(GameState.get_catalog_discovered_count(), discovered, "筛选不该改已发现数")


## 图鉴的「材料 / 食物」两个页签是**页面 id**，数据层已经只剩一种类型；
## 面板得自己把 kind 翻译成过滤条件，否则两页会长得一模一样。
func test_material_and_food_pages_split_the_same_item_table() -> void:
	var food_page := await _open_food_page()
	var food_rows := _matching(food_page, "food")
	assert_eq(food_rows, 288, "食物页只列食物")

	UIManager.close_all()
	await wait_process_frames(1)
	var location := ResourceLocation.from_string("idle_food:catalog")
	var material_page := UIManager.open_panel(location, {"tab": "material"}) as CatalogPanel
	await wait_process_frames(1)
	assert_not_null(material_page, "应能打开材料页")
	if material_page == null:
		return
	var material_rows := _matching(material_page, "material")
	assert_eq(material_rows, 70, "材料页只列材料（水不进图鉴）")
	assert_eq(food_rows + material_rows, 358, "两页加起来正好是物品条目数")


## 未收录的研究菜：列表 hint 要给出材料组合，而不是一句氛围话（用户 2026-10-29 报）。
func test_unfound_research_dish_lists_its_materials() -> void:
	var panel := await _open_food_page()
	var item := panel.def_of("game:item/americano")
	assert_not_null(item, "美式应在数据层")
	if item == null:
		return
	assert_false(GameState.is_discovered(item.get_key()), "新档里美式还没收录")
	var hint := panel._hint_of(item)
	var espresso := panel.def_of("game:item/espresso") as ItemDef
	var water := panel.def_of("game:item/water") as ItemDef
	assert_not_null(espresso, "浓缩咖啡应在数据层")
	assert_not_null(water, "水应在数据层")
	if espresso == null or water == null:
		return
	assert_string_contains(hint, espresso.localized(), "线索应点名浓缩")
	assert_string_contains(hint, water.localized(), "线索应点名免费的水")


## 已收录的菜回到自己的氛围线索，不再贴研究台提示。
func test_recorded_dish_keeps_its_own_hint() -> void:
	var panel := await _open_food_page()
	var item := panel.def_of("game:item/americano")
	assert_not_null(item, "美式应在数据层")
	if item == null:
		return
	GameState.discover(item.get_key())
	var hint := panel._hint_of(item)
	var own := item.localized(&"catalog_hint")
	assert_false(own.is_empty(), "美式应自带一句自己的线索")
	assert_eq(hint, own, "已收录的菜应回到它自己的线索，不再贴研究台提示")


## 图鉴顶部的区间提示要和「信」挂上钩，否则玩家不知道凑图鉴会来信。
func test_progress_hint_ties_catalog_to_letters() -> void:
	var panel := await _open_food_page()
	I18NManager.set_language("zh_CN")
	var zh := I18n.t("ui.catalog.progress_early")
	I18NManager.set_language("en")
	var en := I18n.t("ui.catalog.progress_early")
	assert_string_contains(zh, "信", "中文进度提示应说明和图鉴门槛信的关系")
	assert_string_contains(en, "letter", "英文进度提示应说明和图鉴门槛信的关系")
	I18NManager.set_language(_original_language)
	assert_eq(panel._progress_hint(), I18n.t("ui.catalog.progress_early"), "新档落在最低一档")

## 研究菜的列表线索永远是材料组合；氛围句退到旁白，不能顶替方向（用户 2026-10-29 报卡布奇诺只显示描述）。
func test_research_dish_hint_is_materials_not_flavor() -> void:
	var panel := await _open_food_page()
	var item := panel.def_of("game:item/cappuccino")
	assert_not_null(item, "卡布奇诺应在数据层")
	if item == null:
		return
	var hint := panel._hint_of(item)
	var espresso := panel.def_of("game:item/espresso") as ItemDef
	var milk := panel.def_of("game:item/milk") as ItemDef
	var sugar := panel.def_of("game:item/sugar") as ItemDef
	assert_not_null(espresso, "浓缩咖啡应在数据层")
	assert_not_null(milk, "牛奶应在数据层")
	assert_not_null(sugar, "糖应在数据层")
	if espresso == null or milk == null or sugar == null:
		return
	assert_string_contains(hint, espresso.localized(), "线索应点名浓缩")
	assert_string_contains(hint, milk.localized(), "线索应点名牛奶")
	assert_string_contains(hint, sugar.localized(), "线索应点名糖")
	var recipe := panel.def_of("game:recipe/cappuccino") as RecipeDef
	assert_not_null(recipe, "卡布奇诺配方应在数据层")
	if recipe == null:
		return
	var flavor := panel.research_flavor(recipe)
	assert_false(flavor.is_empty(), "氛围句应当还在")
	assert_false(hint.contains(flavor), "氛围句不能顶替材料线索")
	assert_eq(panel.research_flavor(recipe), flavor, "氛围句单独留在旁白里")


## 线索是现翻的：换语言后同一份数据要给出该语言的材料名。
## 这条同时替 CI 兜底——那边初始语言是 en，靠它把英文分支也跑一遍。
func test_catalog_hints_follow_active_language() -> void:
	var panel := await _open_food_page()
	var item := panel.def_of("game:item/cappuccino")
	assert_not_null(item, "卡布奇诺应在数据层")
	var espresso := panel.def_of("game:item/espresso") as ItemDef
	assert_not_null(espresso, "浓缩咖啡应在数据层")
	if item == null or espresso == null:
		return
	I18NManager.set_language("en")
	var en := panel._hint_of(item)
	var en_name := espresso.localized()
	I18NManager.set_language("zh_CN")
	var zh := panel._hint_of(item)
	var zh_name := espresso.localized()
	assert_string_contains(en, en_name, "英文线索里应是英文材料名")
	assert_string_contains(zh, zh_name, "中文线索里应是中文材料名")
	assert_ne(en, zh, "换语言后线索也要跟着换")
	assert_ne(en_name, zh_name, "两种语言的材料名不该相同")


## 还没遇见的材料要给来历：能造写配方、能买写价钱（用户 2026-10-29 报「??? 里填描述」）。
func test_unfound_material_lists_its_source() -> void:
	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string("idle_food:catalog"), {"tab": "material"}) as CatalogPanel
	await wait_process_frames(1)
	assert_not_null(panel, "应能打开材料页")
	if panel == null:
		return
	var dough := panel.def_of("game:item/batter") as ItemDef
	assert_not_null(dough, "面团应在数据层")
	if dough != null:
		assert_false(GameState.is_discovered(dough.get_key()), "新档里面团还没收录")
		var made := panel._hint_of(dough)
		var flour := panel.def_of("game:item/flour") as ItemDef
		var water := panel.def_of("game:item/water") as ItemDef
		assert_not_null(flour, "面粉应在数据层")
		assert_not_null(water, "水应在数据层")
		if flour != null:
			assert_string_contains(made, flour.localized(), "半成品要写出用料")
		if water != null:
			assert_string_contains(made, water.localized(), "半成品要写出用料")
	var apple := panel.def_of("game:item/apple") as ItemDef
	assert_not_null(apple, "苹果应在数据层")
	if apple == null:
		return
	assert_false(GameState.is_discovered(apple.get_key()), "新档里苹果还没收录")
	var buy := I18n.t("ui.catalog.hint_material_buy", [str(apple.merchant_price)])
	assert_string_contains(panel.material_hint(apple, true), buy, "能买的材料要写商店")
	GameState.discover(apple.get_key())
	assert_false(panel._hint_of(apple).contains(buy), "收录过的材料回到它自己的描述")


## 第七轮反馈 17：来源不能只显示第一条，「能买」不能盖掉「能采」。
func test_material_hint_merges_buy_and_harvest() -> void:
	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string("idle_food:catalog"), {"tab": "material"}) as CatalogPanel
	await wait_process_frames(1)
	assert_not_null(panel, "应能打开材料页")
	if panel == null:
		return
	var apple := panel.def_of("game:item/apple") as ItemDef
	assert_not_null(apple, "苹果应在数据层")
	if apple == null:
		return
	var orchard := GameState.get_harvest_for_material(apple.get_key())
	assert_not_null(orchard, "苹果应能对应到一个采集点")
	if orchard == null:
		return

	var buy := I18n.t("ui.catalog.hint_material_buy", [str(apple.merchant_price)])
	var gather_key := "ui.catalog.hint_material_harvest"
	var gather_args: Array = [orchard.localized()]
	if not GameState.is_harvest_unlocked(orchard):
		gather_key = "ui.catalog.hint_material_harvest_unopened"
	elif apple.harvest_tier > GameState.get_harvest_level(orchard.get_key()):
		gather_key = "ui.catalog.hint_material_harvest_locked"
		gather_args = [orchard.localized(), str(apple.harvest_tier), str(GameState.get_harvest_level(orchard.get_key()))]
	var gather := I18n.t(gather_key, gather_args)

	var both := panel.material_hint(apple, true)
	assert_string_contains(both, buy, "有售价就要写商店")
	assert_string_contains(both, gather, "同时有采集点也要写产地")

	# 只有采集点：临时把售价拿掉，提示里不该再出现购买句
	var price := apple.merchant_price
	apple.merchant_price = 0
	var only_gather := panel.material_hint(apple, true)
	apple.merchant_price = price
	assert_string_contains(only_gather, gather, "只有采集点时仍要写产地")
	assert_false(only_gather.contains(I18n.t("ui.catalog.hint_material_buy", ["0"])),
			"没有售价就不该写购买句")
