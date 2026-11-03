extends GutTest
## 食物标签：TagDef 注册、进图鉴的边界、多标签叠加、翻译。
##
## 标签与主题是两个维度：主题单选（这道菜从哪来），标签可叠加（它在什么场合出现）。

const REGISTRY_KEY := DataRegistry.REGISTRY_NAME

var _data: DataRegistry


func before_each() -> void:
	var registry_manager := get_node_or_null("/root/RegistryManager")
	if registry_manager == null or not registry_manager.has_registry(REGISTRY_KEY):
		return
	_data = registry_manager.get_registry(REGISTRY_KEY) as DataRegistry


func test_sixteen_tags_registered() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	assert_eq(_data.get_defs_of_type("tag").size(), 16, "应注册 16 条标签（9 条场合标签 + 7 条食材标签）")
	for key in ["game:tag/home", "game:tag/festival", "game:tag/sweet", "game:tag/street"]:
		assert_not_null(_data.get_def(key), "%s 应已注册" % key)


func test_tags_are_not_catalog_entries() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	for key in _data.get_catalog_keys():
		assert_false(key.begins_with("game:tag/"), "标签 %s 不应进图鉴" % key)


## 一道菜可以同时属于多个场合：炖菜既家常、又适合过节
func test_one_food_can_carry_several_tags() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var stew := _data.get_def("game:item/stew") as ItemDef
	assert_not_null(stew)
	assert_true(stew.tags.has("game:tag/home"), "炖菜应带家常标签")
	assert_true(stew.tags.has("game:tag/festival"), "炖菜应带节庆标签")
	var bun := _data.get_def("game:item/bun") as ItemDef
	assert_true(bun.tags.has("game:tag/street"), "包子应带街边标签")


## 汤羹标签要覆盖基础汤，不能只靠茶泡饭或酸橘汁腌鱼凑数
func test_soup_tag_covers_soups_and_excludes_non_soups() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	for key in [
		"game:item/tomato_soup", "game:item/egg_drop_soup", "game:item/corn_soup",
		"game:item/clear_noodle_soup", "game:item/meat_soup", "game:item/mushroom_soup",
		"game:item/noodle_soup", "game:item/vegetable_soup",
	]:
		var soup := _data.get_def(key) as ItemDef
		assert_not_null(soup, "%s 应已注册" % key)
		if soup != null:
			assert_true(soup.tags.has("game:tag/soup"), "%s 应带汤羹标签" % key)
	for key in ["game:item/tea_rice", "game:item/ceviche"]:
		var not_soup := _data.get_def(key) as ItemDef
		assert_not_null(not_soup, "%s 应已注册" % key)
		if not_soup != null:
			assert_false(not_soup.tags.has("game:tag/soup"), "%s 不该被算作汤羹" % key)


## 主题与标签互不替代：拿铁只有甜品饮品标签，主题归咖啡馆
func test_theme_and_tags_are_separate_dimensions() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var latte := _data.get_def("game:item/latte") as ItemDef
	assert_eq(latte.theme, "game:theme/cafe", "拿铁的主题归咖啡馆")
	assert_true(latte.tags.has("game:tag/sweet"), "拿铁应带甜品饮品标签")
	assert_false(latte.tags.has("game:tag/home"), "拿铁不该被当成家常菜")


func test_tag_names_are_localized() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("zh_CN")
	assert_eq((_data.get_def("game:tag/street") as TagDef).localized(), "街边·宵夜")
	I18NManager.set_language("en")
	assert_eq((_data.get_def("game:tag/street") as TagDef).localized(), "Street & Late Night")
	I18NManager.set_language("zh_CN")


## 食材标签（scope = ingredient）：材料细分之后，「随便一种肉 / 菜 / 水果 / 海鲜」用标签表达，
## 这样配方不必为每道菜写死具体材料，玩家手上有什么都能凑。
func test_ingredient_tags_cover_the_split_materials() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var expected := {
		"game:tag/meat": ["game:item/beef", "game:item/chicken", "game:item/pork"],
		"game:tag/veg": [
			"game:item/bean", "game:item/cabbage", "game:item/cassava", "game:item/chili",
			"game:item/corn", "game:item/eggplant", "game:item/leafy", "game:item/mushroom",
			"game:item/onion", "game:item/potato",
			"game:item/root", "game:item/scallion", "game:item/soy", "game:item/tomato",
		],
		"game:tag/fruit": ["game:item/apple", "game:item/banana", "game:item/lemon", "game:item/tropical"],
		"game:tag/seafood": ["game:item/fish", "game:item/shrimp"],
		"game:tag/pantry": [
			"game:item/butter", "game:item/cheese", "game:item/cocoa", "game:item/coconut_milk",
			"game:item/coffee_bean", "game:item/egg", "game:item/flour", "game:item/milk",
			"game:item/nuts", "game:item/oil", "game:item/olive_oil", "game:item/rice",
			"game:item/salt", "game:item/spice", "game:item/sugar", "game:item/tea_leaf",
			"game:item/vanilla",
		],
		"game:tag/livestock": [
			"game:item/beef", "game:item/butter", "game:item/cheese", "game:item/chicken",
			"game:item/egg", "game:item/milk", "game:item/pork",
		],
	}
	var tag_registry := DataRegistry.tag_registry()
	assert_not_null(tag_registry, "标签注册表应已登记")
	if tag_registry == null:
		return
	for key: String in expected:
		var tag := _data.get_def(key) as TagDef
		assert_not_null(tag, "%s 应已注册" % key)
		if tag == null:
			continue
		assert_true(tag.is_ingredient(), "%s 应是食材标签（scope = ingredient）" % key)
		var members: Array[String] = []
		for entry in tag_registry.get_all_entries_of_tag(ResourceLocation.from_string(key)):
			var item := _data.get_def((entry as ResourceLocation).to_string()) as ItemDef
			# 成品菜也会带食材标签（图鉴筛选要用），这里只核对材料清单
			if item == null or not item.is_material():
				continue
			members.append(item.get_key())
		members.sort()
		assert_eq(members, expected[key], "%s 的成员应正好是这几样" % key)


## 场合标签不进图鉴筛选条，食材标签也不进 —— 两套标签只在自己那一侧出现
func test_party_tags_are_not_ingredient_tags() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	for key in ["game:tag/home", "game:tag/festival", "game:tag/sweet", "game:tag/street"]:
		var tag := _data.get_def(key) as TagDef
		assert_not_null(tag)
		if tag != null:
			assert_false(tag.is_ingredient(), "%s 是场合标签" % key)
