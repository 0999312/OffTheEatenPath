extends GutTest
## 灶台：三列菜卡 + 折叠组懒加载 + 「只看可做」过滤。
##
## 左列 256 条配方不能一次全建：收起的组只留标题，展开时才补卡片。

const CRAFT := "idle_food:craft"
const TEST_SETTINGS_PATH := "user://__test_craft_settings.cfg"

## 测试期间把设置写到独立文件，别碰玩家的 settings.cfg（第八轮反馈 3）
var _original_settings_path: String = ""
## 本轮临时注入的配方键，after_each 里撤掉
var _temp_keys: Array[String] = []


func before_each() -> void:
	GameState.reset()
	_original_settings_path = SettingsStore.path
	SettingsStore.path = TEST_SETTINGS_PATH
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	_temp_keys.clear()


func after_each() -> void:
	UIManager.close_all()
	SettingsStore.path = _original_settings_path
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry != null:
		for key in _temp_keys:
			registry.unregister(ResourceLocation.from_string(key))
	_temp_keys.clear()
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	await wait_process_frames(1)


func _open() -> CraftPanel:
	UIManager.close_all()
	# 空手开局时「只看可做」一道都不过筛：唯一输入免费的是「水 → 冰」，而冰要冰箱，
	# 冰箱还没到手（这正是 P8 要修的那条）。给几颗生豆，让「首屏只建一组」有东西可量。
	GameState.add_item("game:item/coffee_bean", 3)
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string(CRAFT)) as CraftPanel
	await wait_process_frames(1)
	return panel


## 左列现在是一张张 RecipeCard（Q2 三列卡片墙）
func _cards(panel: CraftPanel) -> Array[RecipeCard]:
	var out: Array[RecipeCard] = []
	_collect_cards(panel.content, out)
	return out


func _collect_cards(node: Node, out: Array[RecipeCard]) -> void:
	for child in node.get_children():
		if child is RecipeCard:
			out.append(child as RecipeCard)
		_collect_cards(child, out)


func _card_for(panel: CraftPanel, recipe_key: String) -> RecipeCard:
	for card in _cards(panel):
		if card.recipe_key == recipe_key:
			return card
	return null


## 已经建过按钮的组（_group_filled 为真）
func _filled_groups(panel: CraftPanel) -> Array[String]:
	var ids: Array[String] = []
	for group_id in panel._group_filled.keys():
		if bool(panel._group_filled[group_id]):
			ids.append(String(group_id))
	return ids


func _closed_group(panel: CraftPanel) -> String:
	for group_id in panel._group_filled.keys():
		if not bool(panel._group_filled[group_id]):
			return String(group_id)
	return ""


func _listed_count(panel: CraftPanel) -> int:
	var total := 0
	for group_id in panel._group_members.keys():
		total += panel._members_of(String(group_id)).size()
	return total


## 组标题是 FoldableContainer.title（不是内部 Label），直接读属性
func _has_section_title(panel: CraftPanel, text: String) -> bool:
	for node in panel.content.find_children("*", "FoldableContainer", true, false):
		var section := node as FoldableContainer
		if section != null and section.title == text:
			return true
	return false


## 工具条末尾报「这一屏列了几条」（统一检索 §4）
func test_toolbar_reports_how_many_recipes_are_listed() -> void:
	var panel := await _open()
	var listed := _listed_count(panel)
	assert_gt(listed, 0, "开局至少有一组可看")
	var wanted := I18n.t("ui.filter.result_count", [listed])
	assert_not_null(_label_with(panel.toolbar, wanted), "工具条末尾要有「%s」" % wanted)


## 搜索按「显示名 + 描述」匹配，不只名字（统一检索 §5）
func test_search_matches_the_description_too() -> void:
	var panel := await _open()
	var target := _first_described_recipe(panel)
	assert_not_null(target, "应有带描述的配方")
	if target == null:
		return
	var description := target.localized(&"description")
	# 和 _passes_filters 一样先 strip_edges：取前六个字可能正好停在词尾空格上，
	# 不裁剪就会把 needle 变成「green 」，反而漏掉「greens」（CI 英文环境踩到过）。
	var needle := description.substr(0, mini(6, description.length())).strip_edges().to_lower()
	panel._bar._search.text = needle
	panel._on_filters_changed()
	await wait_process_frames(1)
	assert_eq(panel._keyword, needle, "关键词记下了")
	assert_true(panel._members_of(panel._group_of(target)).has(target),
			"描述里有「%s」的菜要能被搜到" % needle)
	for group_id in panel._group_members.keys():
		for recipe in panel._members_of(String(group_id)):
			assert_true(recipe.localized().to_lower().contains(needle)
					or recipe.localized(&"description").to_lower().contains(needle),
					"列出的每道菜都得在名字或描述里命中（%s，关键词 [%s]）" % [recipe.get_key(), needle])


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text:
			return button
	return null


func _label_with(root: Node, text: String) -> Label:
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text == text:
			return label
	return null


func _first_described_recipe(panel: CraftPanel) -> RecipeDef:
	for recipe in panel._recipes:
		if not recipe.localized(&"description").strip_edges().is_empty():
			return recipe
	return null


func test_first_open_builds_only_the_selected_group() -> void:
	var panel := await _open()
	# 第六轮：可研配方要先在研究台解锁，开局可见的只有 base / cafe 直给与半成品
	assert_gt(panel._recipes.size(), 60, "开局应有几十道配方铺开首屏")
	var selected := panel.def_of(panel._selected) as RecipeDef
	assert_not_null(selected, "打开时就该选中一道菜")
	var filled := _filled_groups(panel)
	assert_eq(filled.size(), 1, "首屏只建选中那道菜所在的组")
	if selected != null:
		assert_eq(filled[0], panel._group_of(selected), "被建的是选中组")
	assert_lt(_cards(panel).size(), panel._recipes.size(), "收起的组不建卡")


func test_each_group_has_a_count_in_its_title() -> void:
	var panel := await _open()
	var group_id := String(panel._group_members.keys()[0])
	var members: Array[RecipeDef] = []
	members.assign(panel._group_members[group_id])
	var wanted := I18n.t("ui.craft.group_title", [I18n.t("ui.craft.group_" + group_id), members.size()])
	assert_true(_has_section_title(panel, wanted), "组标题应带条数（%s）" % wanted)


func test_expanding_a_group_builds_only_its_cards() -> void:
	var panel := await _open()
	var closed := _closed_group(panel)
	assert_ne(closed, "", "应该还有收起的组")
	var before := _cards(panel).size()
	var members := panel._members_of(closed).size()
	assert_gt(members, 0, "这个组里得有配方")

	panel._on_group_folding_changed(false, closed)
	await wait_process_frames(1)
	assert_eq(_cards(panel).size(), before + members, "展开一组只补这一组的卡片")
	assert_false(bool(panel._folded[closed]), "展开状态要记下来")

	panel._on_group_folding_changed(false, closed)
	await wait_process_frames(1)
	assert_eq(_cards(panel).size(), before + members, "同一组不会建第二遍")


func test_filter_defaults_to_all() -> void:
	var panel := await _open()
	assert_eq(panel._filter_mode, CraftPanel.Filter.ALL, "默认显示全部（缺料只灰化，规范⑥）")
	assert_eq(panel._bar.get_segment("filter"), CraftPanel.Filter.ALL, "工具条只有一个三档筛选，默认停在「全部」")


func test_craftable_filter_hides_recipes_you_cannot_make() -> void:
	var panel := await _open()
	# 默认「全部」，先量一遍全量
	var all := _listed_count(panel)
	assert_eq(all, panel._recipes.size(), "默认列出全部可见配方")

	var chip := _button_with_text(panel._bar, I18n.t("ui.craft.filter_craftable"))
	assert_not_null(chip, "工具条要有「可做」段选")
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	assert_eq(panel._filter_mode, CraftPanel.Filter.CRAFTABLE, "点「可做」后只筛可做")
	assert_eq(panel._bar.get_segment("filter"), CraftPanel.Filter.CRAFTABLE, "段选停在「可做」")
	var filtered := _listed_count(panel)
	assert_lt(filtered, all, "只看可做应把没材料的收起来")
	for group_id in panel._group_members.keys():
		for recipe in panel._members_of(String(group_id)):
			assert_true(panel._is_craftable_now(recipe),
					"%s 不该出现在只看可做的列表里" % recipe.get_key())


## 未记录必然可做：这一档不会把「图鉴没记过但做不了」的菜混进来
func test_unrecorded_filter_excludes_discovered_and_uncraftable() -> void:
	var panel := await _open()
	var chip := _button_with_text(panel._bar, I18n.t("ui.craft.filter_uncrafted"))
	assert_not_null(chip, "工具条要有「未记录」段选")
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	assert_eq(panel._filter_mode, CraftPanel.Filter.UNRECORDED, "点「未记录」后只筛空白")
	assert_eq(panel._bar.get_segment("filter"), CraftPanel.Filter.UNRECORDED, "段选停在「未记录」")

	var roast := panel.def_of("game:recipe/roast_bean") as RecipeDef
	assert_not_null(roast, "咖啡豆烘焙应是开局配方")
	if roast == null:
		return
	assert_true(panel._members_of(panel._group_of(roast)).has(roast),
			"有豆、有平底锅、还没烘过 → 应列在「未记录」里")
	for group_id in panel._group_members.keys():
		for recipe in panel._members_of(String(group_id)):
			assert_true(panel._is_craftable_now(recipe),
					"%s 未记录但做不了，不该出现在这一档" % recipe.get_key())
			var output := panel.def_of(recipe.output) as ItemDef
			assert_not_null(output, "配方应有成品定义")
			if output != null:
				assert_false(GameState.is_discovered(output.get_key()),
						"%s 已经记录过，不该再算空白" % output.get_key())

	# 做出/点亮之后，它从「未记录」里消失
	GameState.discover("game:item/roasted_bean")
	panel._on_filters_changed()
	await wait_process_frames(1)
	assert_false(panel._members_of(panel._group_of(roast)).has(roast),
			"点亮图鉴后，它不再算「能做但没记录」")


## 灶台标签筛选：只列非食材标签，单选，与主题/关键词叠加。
func test_tag_filter_matches_output_tags() -> void:
	var panel := await _open()
	var options := panel._tag_options()
	assert_gt(options.size(), 1, "工具条应至少有一个标签选项")
	for option in options:
		var key := String(option.get("value", ""))
		if key.is_empty():
			continue
		var tag := panel.def_of(key) as TagDef
		assert_not_null(tag, "标签选项应指向 TagDef：%s" % key)
		if tag != null:
			assert_false(tag.is_ingredient(), "食材标签不该出现在筛菜条里：%s" % key)

	var tag_key := "game:tag/soup"
	var tag_def := panel.def_of(tag_key) as TagDef
	assert_not_null(tag_def, "汤标签应存在")
	if tag_def == null:
		return
	var chip := _button_with_text(panel._bar, tag_def.localized())
	assert_not_null(chip, "工具条要有「%s」标签芯片" % tag_def.localized())
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	assert_eq(panel._tag_key, tag_key, "选中的标签要记下来")
	var listed := 0
	for group_id in panel._group_members.keys():
		for recipe in panel._members_of(String(group_id)):
			listed += 1
			assert_true(GameState.has_tag(recipe.output, tag_key),
				"%s 不带汤标签，不该出现在筛后列表里" % recipe.get_key())
	assert_gt(listed, 0, "汤标签下应至少有一道可见菜")

	# 与主题叠加：直接设主题字段，验证纯函数取交集（不依赖具体某道菜存在）。
	panel._theme_key = "game:theme/east_asia"
	for recipe in panel._recipes:
		if not GameState.has_tag(recipe.output, tag_key):
			continue
		var is_east := GameState.recipe_theme_key(recipe.get_key()) == panel._theme_key
		assert_eq(panel._passes_filters(recipe), is_east,
			"标签 + 主题应取交集：%s" % recipe.get_key())
	panel._theme_key = ""

	var all_chip := _button_with_text(panel._bar, I18n.t("ui.craft.tag_all"))
	assert_not_null(all_chip, "工具条要有「所有标签」芯片")
	if all_chip != null:
		all_chip.pressed.emit()
		await wait_process_frames(1)
		assert_eq(panel._tag_key, "", "清空标签回到全部")


func test_feeding_the_inputs_brings_the_recipe_back() -> void:
	var panel := await _open()
	var target := _first_unfed_recipe(panel)
	assert_not_null(target, "应能找到一条当下做不了的配方")

	var chip := _button_with_text(panel._bar, I18n.t("ui.craft.filter_craftable"))
	assert_not_null(chip, "工具条要有「可做」段选")
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	if target != null:
		assert_false(panel._members_of(panel._group_of(target)).has(target),
				"材料不够时它不该在列表里")

	for stack in target.inputs:
		if stack.by_tag.is_empty() and not stack.material.is_empty():
			GameState.add_item(stack.material, stack.amount)
	await wait_process_frames(1)
	panel._on_filters_changed()
	await wait_process_frames(1)
	if target != null:
		assert_true(panel._members_of(panel._group_of(target)).has(target),
				"补上材料后它应回到列表里")


## 一条「要的设备还没到手」的配方（开局咖啡机 / 蒸笼都是 0 级）
func _locked_recipe(panel: CraftPanel) -> RecipeDef:
	for recipe in panel._recipes:
		if recipe.needs_facility() and not GameState.is_facility_ready(recipe.facility):
			return recipe
	return null


## 设备没到手的菜仍留在墙上，卡面写「需要 X」，点得进详情（规范⑥）
func test_locked_facility_recipe_stays_with_a_reason() -> void:
	var panel := await _open()
	var locked := _locked_recipe(panel)
	assert_not_null(locked, "开局应有设备还没到手的配方")
	if locked == null:
		return
	panel._on_group_folding_changed(false, panel._group_of(locked))
	await wait_process_frames(1)

	var facility := panel.def_of(locked.facility) as FacilityDef
	assert_not_null(facility, "配方要能查到设备定义")
	if facility == null:
		return
	var reason := I18n.t("ui.craft.card_need_facility", [facility.localized()])
	var card := _card_for(panel, locked.get_key())
	assert_not_null(card, "设备没到手的菜仍应出现在墙上")
	if card != null:
		assert_eq(card._need_label.text, reason, "卡片要标「%s」" % reason)
		assert_eq(card.mouse_filter, Control.MOUSE_FILTER_STOP, "缺设备的卡还能点进详情")
		card._activate()
		await wait_process_frames(1)
		assert_eq(panel._selected, locked.get_key(), "点卡进详情，不是死路")


## 设备到手（0 级 → 1 级）后，那条菜不再算「还没到手」，列表要跟着重建
func test_unlocking_the_facility_clears_the_mark() -> void:
	var panel := await _open()
	var locked := _locked_recipe(panel)
	assert_not_null(locked, "开局应有设备还没到手的配方")
	if locked == null:
		return
	var before := panel._locked_facility_count()
	var levels := (GameState.get("_facility_levels") as Dictionary).duplicate()
	levels[locked.facility] = 1
	GameState.set("_facility_levels", levels)
	panel.refresh()
	await wait_process_frames(1)
	assert_null(panel._missing_facility(locked), "设备到手后这条不再算「还没到手」")
	assert_lt(panel._locked_facility_count(), before, "被这一台设备挡住的菜都该解除标记")


## 挑一条「输入全是指名材料」且当下做不了的配方，测试里好喂饱它
func _first_unfed_recipe(panel: CraftPanel) -> RecipeDef:
	for recipe in panel._recipes:
		if GameState.can_consume(recipe.inputs, 1):
			continue
		# 设备没到手的菜喂了料也做不了，别把它算进来
		if not GameState.is_facility_ready(recipe.facility):
			continue
		var plain := true
		for stack in recipe.inputs:
			if not stack.by_tag.is_empty() or stack.material.is_empty():
				plain = false
				break
		if plain:
			return recipe
	return null


# --- 第八轮反馈 2：下游提示 ------------------------------------------------


## 没有下游（滴滤咖啡）时整段「它可以做…」不出现，别留一句空话
func test_used_in_section_is_omitted_without_downstream() -> void:
	var panel := await _open()
	var recipe := panel.def_of("game:recipe/pour_over") as RecipeDef
	assert_not_null(recipe, "滴滤咖啡配方应存在")
	assert_true(GameState.recipes_using(recipe.output).is_empty(), "滴滤咖啡当前没有下游")
	assert_null(panel._used_in_section(recipe), "没有下游时整段不应出现")


## 下游是未解锁的研究配方：只给「？？？」，点击跳图鉴定位
func test_used_in_section_shows_locked_research_downstream() -> void:
	var panel := await _open()
	var recipe := panel.def_of("game:recipe/pour_over") as RecipeDef
	_inject_hidden_downstream(recipe.output)
	var section := panel._used_in_section(recipe)
	assert_not_null(section, "有需要研究的下游时应出现折叠区")
	if section == null:
		return
	section.folded = false
	await wait_process_frames(1)
	var unknown := _button_with_text(section, I18n.t("ui.craft.used_in_unknown"))
	assert_not_null(unknown, "未解锁的下游不报名字，只给「？？？」")
	assert_not_null(_label_with(section, I18n.t("ui.craft.used_in_research")),
			"旁边要提示「需要研究」")
	if unknown != null:
		unknown.pressed.emit()
		await wait_process_frames(2)
		assert_true(UIManager.is_panel_open(ResourceLocation.from_string(UIKeys.CATALOG)),
				"点隐藏条目应打开图鉴（recipe 页由 key 定位）")


## 图鉴按条目键打开：直接翻到配方页，并把它设为定位目标
func test_catalog_opens_recipe_page_for_key() -> void:
	var location := ResourceLocation.from_string(UIKeys.CATALOG)
	var panel := UIManager.open_panel(location, {"key": "game:recipe/souffle"}) as CatalogPanel
	assert_not_null(panel, "应能打开图鉴")
	if panel == null:
		return
	await wait_process_frames(2)
	assert_eq(panel._tab_index, 2, "配方应落在 recipe 页（材料/食物/配方 → 下标 2）")


# --- 第八轮反馈 3：灶台记忆 ------------------------------------------------


func test_selected_recipe_is_written_and_restored() -> void:
	var first := await _open()
	assert_gt(first._recipes.size(), 1, "至少有两道可见配方才谈得上记忆")
	var wanted := String(first._recipes[1].get_key())
	first._select_recipe(wanted)
	assert_eq(SettingsStore.get_craft_recipe(), wanted, "选中应立刻写下")
	UIManager.close_all()
	await wait_process_frames(1)
	var again := await _open()
	assert_eq(again._selected, wanted, "重开灶台应回到上次停留的菜")


func test_filter_mode_is_restored() -> void:
	SettingsStore.set_craft_filter(CraftPanel.Filter.UNRECORDED)
	var panel := await _open()
	assert_eq(panel._filter_mode, CraftPanel.Filter.UNRECORDED, "重开时「未记录」应沿用上次")
	assert_eq(panel._bar.get_segment("filter"), CraftPanel.Filter.UNRECORDED,
			"工具条也应显示在「未记录」段")
	assert_eq(SettingsStore.get_craft_filter(), CraftPanel.Filter.UNRECORDED,
			"三档模式应原样写回设置")


## 老设置只有布尔键：true 迁成「可做」，不因为换档位把玩家的视图丢掉
func test_legacy_only_craftable_setting_migrates() -> void:
	SettingsStore.set_value(SettingsStore.SECTION_CRAFT, SettingsStore.LEGACY_KEY_ONLY_CRAFTABLE, true)
	var panel := await _open()
	assert_eq(panel._filter_mode, CraftPanel.Filter.CRAFTABLE, "旧 true 应迁成「可做」")
	assert_eq(panel._bar.get_segment("filter"), CraftPanel.Filter.CRAFTABLE,
			"工具条也应落在「可做」段")


## 临时加一条「需要研究」的下游配方，让 output 多一个未解锁用途
func _inject_hidden_downstream(output_key: String) -> void:
	var recipe := RecipeDef.new()
	recipe.namespace_id = GameDef.DEFAULT_NAMESPACE
	recipe.id = "recipe/test_used_in"
	recipe.display_name = "测试下游"
	recipe.description = "只存在于测试里。"
	recipe.output = output_key
	recipe.duration_seconds = 3.0
	recipe.order = 900
	recipe.in_catalog = true
	recipe.research_pool.assign([output_key])
	recipe.research_hint = "测试用的提示。"
	var stack := MaterialStack.new()
	stack.material = output_key
	stack.amount = 1
	var stacks: Array[MaterialStack] = [stack]
	recipe.inputs.assign(stacks)
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	assert_true(registry.register_def(recipe), "临时下游配方应能登记")
	_temp_keys.append(recipe.get_key())
