extends GutTest
## 第八轮反馈 R8.3：内容与数据。
##
## 覆盖：研磨机改名、面粉链、蛋糕改面糊、舒芙蕾研究、巧克力链（可可粉 / 布朗尼 /
## 两种曲奇 / 奥利奥）、吐司产出 2 片与三明治、棉花糖与 S'more，以及这些新内容
## 在图鉴里的收录与可达性。

const DishReachability = preload("res://scripts/systems/dish_reachability.gd")

const ITEM := "game:item/"
const RECIPE := "game:recipe/"

const NEW_ITEMS: Array[String] = [
	"wheat", "whole_wheat_flour", "cocoa_powder", "marshmallow",
	"whole_wheat_bread", "whole_wheat_cracker",
	"chocolate_chip_cookie", "chocolate_cookie", "oreo",
	"roasted_marshmallow", "smore",
]
const NEW_RECIPES: Array[String] = [
	"whole_wheat_flour", "flour_from_whole_wheat", "cocoa_powder",
	"whole_wheat_bread", "whole_wheat_cracker",
	"chocolate_chip_cookie", "chocolate_cookie", "oreo",
	"marshmallow", "roasted_marshmallow", "smore",
]
const SANDWICHES: Array[String] = [
	"sandwich", "pbj_sandwich", "blt", "club_sandwich",
	"egg_salad_sandwich", "grilled_cheese", "ham_cheese_sandwich", "tuna_sandwich",
]


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func _item(key: String) -> ItemDef:
	var data := _data()
	return (data.get_def(ITEM + key) as ItemDef) if data != null else null


func _recipe(key: String) -> RecipeDef:
	var data := _data()
	return (data.get_def(RECIPE + key) as RecipeDef) if data != null else null


func _has_input(recipe: RecipeDef, key: String) -> bool:
	for stack in recipe.inputs:
		if stack != null and not stack.material.is_empty() and stack.material == key:
			return true
	return false


# --- 存在性 ---------------------------------------------------------------


func test_new_items_exist() -> void:
	for key in NEW_ITEMS:
		assert_not_null(_item(key), "新物品 %s 应存在" % key)


func test_new_recipes_exist() -> void:
	for key in NEW_RECIPES:
		assert_not_null(_recipe(key), "新配方 %s 应存在" % key)


func test_new_content_is_in_catalog() -> void:
	var data := _data()
	var keys := data.get_catalog_keys()
	for key in NEW_ITEMS:
		assert_true(keys.has(ITEM + key), "%s 应进图鉴" % key)
	for key in NEW_RECIPES:
		assert_true(keys.has(RECIPE + key), "配方 %s 应进图鉴" % key)


# --- 研磨机改名 -----------------------------------------------------------


func test_grinder_is_renamed() -> void:
	assert_eq(I18n.t("data.facility.grinder.name"), "研磨机", "设施名应改成研磨机")
	assert_eq(I18n.t("ui.catalog.category_grinder"), "研磨机", "图鉴设备分类名应同步")
	assert_eq(I18n.t("data.recipe.grind_bean.desc").find("磨豆机"), -1, "旧文案里不该再出现磨豆机")


# --- 面粉链 ---------------------------------------------------------------


func test_wheat_is_merchant_only() -> void:
	var wheat := _item("wheat")
	assert_not_null(wheat)
	if wheat == null:
		return
	assert_eq(wheat.material_kind, ItemDef.MaterialKind.BASE, "小麦是基础材料")
	assert_gt(wheat.merchant_price, 0, "小麦由商人出售")
	assert_eq(wheat.tags, [] as Array[String], "小麦不挂采集标签，避免被采集点摇出来")


func test_whole_wheat_chain_is_reachable() -> void:
	var flour := _item("whole_wheat_flour")
	assert_eq(flour.material_kind, ItemDef.MaterialKind.INTERMEDIATE, "全麦面粉是中间材料")
	for key in ["whole_wheat_flour", "flour_from_whole_wheat", "whole_wheat_bread", "whole_wheat_cracker"]:
		var recipe := _recipe(key)
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe != null:
			var report: Dictionary = DishReachability.explain_recipe(GameState, RECIPE + key, true)
			assert_true(report.get("ok", false), "%s 在全内容口径下应可达：%s" % [key, report])


func test_flour_from_whole_wheat_outputs_two() -> void:
	var recipe := _recipe("flour_from_whole_wheat")
	assert_eq(recipe.output, ITEM + "flour")
	assert_eq(recipe.output_amount, 2, "全麦粉再磨应出两份精面粉")


# --- 蛋糕与舒芙蕾 ---------------------------------------------------------


func test_cakes_use_batter() -> void:
	for key in ["cake", "carrot_cake", "cheesecake", "muffin", "pancake"]:
		var recipe := _recipe(key)
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe == null:
			continue
		assert_true(_has_input(recipe, ITEM + "batter"), "%s 应改用面糊" % key)
		assert_false(_has_input(recipe, ITEM + "dough"), "%s 不应再用面团" % key)
		assert_false(_has_input(recipe, ITEM + "egg"), "%s 的蛋已由面糊带入" % key)


func test_souffle_needs_research() -> void:
	var recipe := _recipe("souffle")
	assert_not_null(recipe)
	assert_true(recipe.needs_research(), "舒芙蕾应需要研究")
	assert_true(recipe.research_pool.has(ITEM + "egg"), "研究池应能试出蛋")
	assert_true(recipe.research_pool.has(ITEM + "flour"), "研究池应能试出面粉")
	assert_eq(recipe.research_pool.size(), 4, "舒芙蕾研究池为蛋 / 奶 / 糖 / 面粉")


# --- 巧克力 ---------------------------------------------------------------


func test_brownie_uses_dark_chocolate() -> void:
	var recipe := _recipe("brownie")
	assert_not_null(recipe)
	assert_true(_has_input(recipe, ITEM + "dark_chocolate"), "布朗尼应使用黑巧克力")
	assert_false(_has_input(recipe, ITEM + "cocoa"), "布朗尼不应直接放可可")


func test_chocolate_tag_covers_chocolate_kinds() -> void:
	var tag := _data().get_def("game:tag/chocolate") as TagDef
	assert_not_null(tag, "巧克力标签应存在")
	assert_true(tag.is_ingredient(), "巧克力标签要能被配方按标签要料")
	var members := _data().tag_member_keys("game:tag/chocolate")
	assert_eq(members.size(), 2, "黑巧 / 牛奶巧克力都算")
	for key in ["dark_chocolate", "milk_chocolate"]:
		assert_true(members.has(ITEM + key), "%s 应挂巧克力标签" % key)
	assert_false(members.has(ITEM + "lava_cake"), "熔岩蛋糕是成品，不占巧克力原料标签")
	assert_false(members.has(ITEM + "white_chocolate"), "白巧克力已退场")


func test_chocolate_cookies_use_tag_input() -> void:
	for key in ["chocolate_chip_cookie", "chocolate_cookie"]:
		var recipe := _recipe(key)
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe == null:
			continue
		var tagged := false
		for stack in recipe.inputs:
			if stack != null and stack.by_tag == "game:tag/chocolate":
				tagged = true
		assert_true(tagged, "%s 应接受任意一种巧克力" % key)
	assert_true(_has_input(_recipe("chocolate_cookie"), ITEM + "cocoa_powder"),
			"巧克力曲奇要额外加可可粉")


func test_oreo_uses_two_chocolate_cookies() -> void:
	var recipe := _recipe("oreo")
	assert_not_null(recipe)
	var first := recipe.inputs[0] if recipe.inputs.size() > 0 else null
	assert_not_null(first, "奥利奥要有输入")
	if first != null:
		assert_eq(first.material, ITEM + "chocolate_cookie", "奥利奥用巧克力曲奇")
		assert_eq(first.amount, 2, "要两片")
	assert_true(_has_input(recipe, ITEM + "cream"), "奥利奥要奶油")
	assert_true(_has_input(recipe, ITEM + "sugar"), "奥利奥要糖")


func test_cocoa_powder_comes_from_cocoa() -> void:
	var recipe := _recipe("cocoa_powder")
	assert_not_null(recipe)
	assert_eq(recipe.output, ITEM + "cocoa_powder")
	assert_true(_has_input(recipe, ITEM + "cocoa"), "可可粉由可可磨成")


# --- 吐司与三明治 ---------------------------------------------------------


func test_toast_outputs_two_slices() -> void:
	assert_eq(_recipe("toast").output_amount, 2, "一份面包至少切两片吐司")


func test_sandwiches_use_two_toasts() -> void:
	for key in SANDWICHES:
		var recipe := _recipe(key)
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe == null or recipe.inputs.is_empty():
			continue
		var first := recipe.inputs[0]
		assert_eq(first.material, ITEM + "toast", "%s 应改用吐司" % key)
		assert_eq(first.amount, 2, "%s 要用两片吐司" % key)


# --- 棉花糖与 S'more ------------------------------------------------------


func test_marshmallow_chain() -> void:
	var marshmallow := _recipe("marshmallow")
	assert_not_null(marshmallow)
	assert_eq(marshmallow.output_amount, 2, "熬一次出两颗棉花糖")
	assert_true(_has_input(marshmallow, ITEM + "sugar"), "棉花糖要糖")
	assert_true(_has_input(marshmallow, ITEM + "syrup"), "棉花糖要糖浆")

	var roasted := _recipe("roasted_marshmallow")
	assert_not_null(roasted)
	assert_true(_has_input(roasted, ITEM + "marshmallow"), "烤棉花糖由棉花糖烤成")

	var smore := _recipe("smore")
	assert_not_null(smore)
	assert_true(_has_input(smore, ITEM + "whole_wheat_cracker"), "S'more 用全麦饼干")
	assert_true(_has_input(smore, ITEM + "dark_chocolate"), "S'more 用黑巧克力")
	assert_true(_has_input(smore, ITEM + "roasted_marshmallow"), "S'more 用烤棉花糖")


func test_smore_is_reachable_in_full_content() -> void:
	var report: Dictionary = DishReachability.explain_recipe(GameState, RECIPE + "smore", true)
	assert_true(report.get("ok", false), "S'more 全内容口径应可达：%s" % report)
