extends GutTest
## D9：冰箱（信件解锁的设备）、冰只能从冰箱出、油料三档、茶、法压壶退场。

const FRIDGE := "game:facility/fridge"
const ICE := "game:item/ice"
const ICE_RECIPE := "game:recipe/ice"
const FRIDGE_LETTER := "game:letter/fridge_hum"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	GameState.reset()


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func _input_keys(recipe_key: String) -> Array[String]:
	var data := _data()
	var recipe := data.get_def(recipe_key) as RecipeDef
	assert_not_null(recipe, "%s 应存在" % recipe_key)
	if recipe == null:
		return [] as Array[String]
	return recipe.input_keys()


func test_fridge_starts_locked() -> void:
	assert_eq(GameState.get_facility_level(FRIDGE), 0, "冰箱开局不在厨房里")
	assert_false(GameState.is_discovered(FRIDGE), "还没到手的设备不算已知")
	assert_false(GameState.has_free_slot(FRIDGE), "0 级设备一格也开不出来")
	assert_false(GameState.start_craft(ICE_RECIPE), "冰箱没到，冰做不出来")


func test_ice_needs_the_fridge() -> void:
	var data := _data()
	var recipe := data.get_def(ICE_RECIPE) as RecipeDef
	assert_not_null(recipe, "冰的配方应存在")
	if recipe == null:
		return
	assert_eq(recipe.facility, FRIDGE, "冰只能由冰箱出")
	var ice := data.get_def(ICE) as ItemDef
	assert_not_null(ice, "冰应是一条物品")
	if ice == null:
		return
	assert_true(ice.is_material(), "冰是材料，不是食物")
	assert_eq(ice.material_kind, ItemDef.MaterialKind.INTERMEDIATE, "冰是中间品，不是采集来的")
	assert_eq(ice.merchant_price, 0, "冰不卖，只能自己做")
	assert_eq(ice.sell_price, 1, "冰能卖给商人")


func test_reading_the_letter_brings_the_fridge_in() -> void:
	var data := _data()
	var letter := data.get_def(FRIDGE_LETTER) as LetterDef
	assert_not_null(letter, "冰箱信应存在")
	if letter == null:
		return
	assert_eq(letter.order, 13, "信的序号是 13：冰箱在出发信（16）之前")
	assert_eq(letter.condition, LetterDef.Condition.CATALOG_COUNT, "按图鉴进度触发")
	assert_eq(letter.condition_value, 100, "冰箱信的门槛是 100")
	assert_eq(letter.rewards.size(), 1, "信里夹了一块冰")
	# 信按条件解锁；测试里直接把解锁名单摆好，省得先点亮三成图鉴。
	# 注意：`_unlocked_letters` 是 Array[String]，塞未类型化数组会被静默丢掉（§5.1）
	var unlocked: Array[String] = [FRIDGE_LETTER]
	GameState.set("_unlocked_letters", unlocked)
	assert_true(GameState.mark_letter_read(FRIDGE_LETTER), "解锁后应能读信")
	assert_eq(GameState.get_facility_level(FRIDGE), 1, "读完信冰箱进厨房，1 级")
	assert_true(GameState.is_discovered(FRIDGE), "冰箱进图鉴")
	assert_true(GameState.has_free_slot(FRIDGE), "有冰箱就能开工")
	assert_eq(GameState.get_amount(ICE), 4, "随信附的冰照收")
	assert_true(GameState.start_craft(ICE_RECIPE), "有冰箱之后冰就能做了")


func test_hand_pour_is_gone() -> void:
	# 用户 2026-10-27 拍板：手冲与滴滤是同一件事，只保留滴滤
	var data := _data()
	assert_false(data.has_def("game:item/hand_pour"), "手冲已从图鉴下架")
	assert_false(data.has_def("game:recipe/hand_pour"), "手冲的配方一起删了")
	assert_false(data.get_catalog_keys().has("game:item/hand_pour"))
	assert_not_null(data.get_def("game:item/pour_over"), "滴滤咖啡还在")
	var recipe := data.get_def("game:recipe/pour_over") as RecipeDef
	assert_not_null(recipe, "滴滤配方还在")
	if recipe == null:
		return
	assert_false(recipe.needs_facility(), "滴滤仍是手作，不占咖啡机")


func test_french_press_is_gone() -> void:
	var data := _data()
	assert_false(data.has_def("game:item/french_press"), "法压壶已从图鉴下架")
	assert_false(data.has_def("game:recipe/french_press"), "法压壶的配方一起删了")
	assert_false(data.get_catalog_keys().has("game:item/french_press"))


func test_tea_recipes_use_tea_leaf() -> void:
	for recipe_key in ["game:recipe/chai", "game:recipe/milk_tea", "game:recipe/tea_rice"]:
		var keys := _input_keys(recipe_key)
		assert_true(keys.has("game:item/tea_leaf"), "%s 应该用茶叶" % recipe_key)
		assert_false(keys.has("game:item/broth"), "%s 不该再用高汤" % recipe_key)
	# 第十一轮：chai 按文案补了香料；奶茶/茶饭仍不该用香料顶茶叶。
	assert_false(_input_keys("game:recipe/milk_tea").has("game:item/spice"), "奶茶不该用香料")
	assert_false(_input_keys("game:recipe/tea_rice").has("game:item/spice"), "茶饭不该用香料")


func test_olive_oil_belongs_to_the_mediterranean() -> void:
	var data := _data()
	var users := 0
	for def in data.get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if not recipe.input_keys().has("game:item/olive_oil"):
			continue
		users += 1
		var dish := data.get_def(recipe.output) as ItemDef
		assert_not_null(dish, "%s 的产出应是一条物品" % recipe.get_key())
		if dish != null:
			assert_eq(dish.theme, "game:theme/mediterranean", "%s 是地中海菜" % recipe.get_key())
	assert_eq(users, 7, "地中海里用油的有 7 条")


func test_oil_is_no_longer_the_only_oil() -> void:
	var data := _data()
	var oil := data.get_def("game:item/oil") as ItemDef
	var olive := data.get_def("game:item/olive_oil") as ItemDef
	assert_not_null(oil, "食用油还在")
	assert_not_null(olive, "橄榄油是新的一条")
	if oil == null or olive == null:
		return
	assert_ne(oil.localized(), olive.localized(), "两者显示名不能撞")
	assert_eq(olive.merchant_price, 5, "橄榄油商店买得到")


func test_ice_desserts_stay_in_base_and_cafe() -> void:
	var data := _data()
	var counted := {"base": 0, "cafe": 0}
	for slug in [
		"ice_cream_scoop", "shaved_ice", "popsicle", "smoothie", "ice_bar", "milk_pudding",
	]:
		var base := data.get_def("game:item/%s" % slug) as ItemDef
		assert_not_null(base, "%s 应存在" % slug)
		if base != null:
			assert_eq(base.theme, "game:theme/base", "%s 是家常台面上的" % slug)
			counted["base"] += 1
	for slug in ["vanilla_ice_cream", "chocolate_ice_cream", "fruit_ice_cream", "sundae"]:
		var cafe := data.get_def("game:item/%s" % slug) as ItemDef
		assert_not_null(cafe, "%s 应存在" % slug)
		if cafe != null:
			assert_eq(cafe.theme, "game:theme/cafe", "%s 属于咖啡馆" % slug)
			counted["cafe"] += 1
	assert_eq(int(counted["base"]), 6, "冰品不独立成主题：6 道留在家常")
	assert_eq(int(counted["cafe"]), 4, "4 道归咖啡馆")
