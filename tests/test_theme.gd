extends GutTest
## 食物主题：ThemeDef 注册、进图鉴的边界、未写 theme 的默认归属。

const REGISTRY_KEY := DataRegistry.REGISTRY_NAME

var _data: DataRegistry


func before_each() -> void:
	var registry_manager := get_node_or_null("/root/RegistryManager")
	if registry_manager == null or not registry_manager.has_registry(REGISTRY_KEY):
		return
	_data = registry_manager.get_registry(REGISTRY_KEY) as DataRegistry


func test_eleven_themes_registered() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	assert_eq(_data.get_defs_of_type("theme").size(), 11, "应注册 11 条主题（家常 + 咖啡馆 + 东亚 + 八条地域主题）")
	assert_not_null(_data.get_def("game:theme/base"))
	assert_not_null(_data.get_def("game:theme/east_asia"))
	assert_not_null(_data.get_def("game:theme/cafe"))


func test_themes_are_not_catalog_entries() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	for key in _data.get_catalog_keys():
		assert_false(key.begins_with("game:theme/"), "主题 %s 不应进图鉴" % key)


func test_food_without_theme_defaults_to_base() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var cookie := _data.get_def("game:item/cookie") as ItemDef
	assert_not_null(cookie)
	assert_eq(cookie.theme, "game:theme/base", "未写 theme 的食物默认归家常")


func test_theme_names_are_localized() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("zh_CN")
	assert_eq((_data.get_def("game:theme/east_asia") as ThemeDef).localized(), "东亚餐食")
	I18NManager.set_language("en")
	assert_eq((_data.get_def("game:theme/east_asia") as ThemeDef).localized(), "East Asian Table")
	I18NManager.set_language("zh_CN")
	assert_eq((_data.get_def("game:theme/cafe") as ThemeDef).localized(), "咖啡馆")
