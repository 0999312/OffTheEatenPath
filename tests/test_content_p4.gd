extends GutTest
## P4 内容层与配套机制：图鉴总量、九道食物、十封信、设备升级口径、图鉴里程碑、商人收购。

const MATERIAL := "game:item/"
const FOOD := "game:item/"
const RECIPE := "game:recipe/"

## 图鉴当前批次（R16.2：加酸奶）：765 条 = 食物 288 / 材料 70 / 配方 318 / 设备 8 / 信件 69 / 世界 12。
## 数字集中在这里，下一批内容进来后只改这一处。
const EXPECTED_CATALOG := 765
const EXPECTED_BY_TYPE := {
	"item": 358,
	"recipe": 318,
	"facility": 8,
	"letter": 69,
	"world": 12,
}
## 物品同表之后按 kind 再分一次：图鉴里的材料 70 条（水不进图鉴）、食物 288 条
const EXPECTED_ITEM_BY_KIND := {
	"material": 70,
	"food": 288,
}

## 用来凑发现数的键（材料优先，不够再补食物）
const DISCOVERABLE: Array[String] = [
	"game:item/americano",
	"game:item/apple_crumble",
	"game:item/apple_pie",
	"game:item/arancini",
	"game:item/asado",
	"game:item/avocado_toast",
	"game:item/baba_ganoush",
	"game:item/bagel",
	"game:item/bagel_sandwich",
	"game:item/baklava",
	"game:item/banana_rice",
	"game:item/banh_mi",
	"game:item/beef_bourguignon",
	"game:item/beef_wellington",
	"game:item/bibimbap",
	"game:item/biryani",
	"game:item/blt",
	"game:item/boerewors",
	"game:item/boiled_egg",
	"game:item/braised_egg",
	"game:item/brownie",
	"game:item/buffalo_wings",
	"game:item/bun",
	"game:item/burrito",
	"game:item/butter_rice",
	"game:item/butter_toast",
	"game:item/caesar_salad",
	"game:item/cake",
	"game:item/candied_fruit",
	"game:item/cappuccino",
	"game:item/caprese",
	"game:item/caramel_macchiato",
	"game:item/carrot_cake",
	"game:item/ceviche",
	"game:item/chai",
	"game:item/cheese_stick",
	"game:item/cheese_toast",
	"game:item/cheeseburger",
	"game:item/cheesecake",
	"game:item/chicken_curry",
	"game:item/chicken_wrap",
	"game:item/cinnamon_roll",
	"game:item/clear_noodle_soup",
	"game:item/club_sandwich",
	"game:item/coconut_dessert",
	"game:item/cold_brew",
	"game:item/con_panna",
	"game:item/cookie",
	"game:item/corn_soup",
	"game:item/couscous",
	"game:item/cream_puff",
	"game:item/creamed_spinach",
	"game:item/creamy_mushroom_chicken",
	"game:item/creme_brulee",
	"game:item/croissant",
	"game:item/curry_puff",
	"game:item/curry_rice",
	"game:item/dal",
	"game:item/dumpling",
	"game:item/egg_drop_soup",
	"game:item/egg_pancake",
	"game:item/egg_roll",
	"game:item/egg_salad",
	"game:item/egg_salad_sandwich",
	"game:item/egg_tart",
	"game:item/egg_toast",
	"game:item/espresso",
	"game:item/falafel",
	"game:item/farinata",
	"game:item/feijoada",
	"game:item/fish_and_chips",
	"game:item/flat_white",
	"game:item/focaccia",
	"game:item/french_omelette",
	"game:item/french_onion_soup",
	"game:item/french_toast",
	"game:item/fresh_milk",
	"game:item/fried_chicken",
	"game:item/fried_dough",
	"game:item/fried_egg",
	"game:item/fried_noodles",
	"game:item/fried_rice",
	"game:item/fries",
	"game:item/fruit_salad",
	"game:item/fufu",
	"game:item/garlic_toast",
	"game:item/gazpacho",
	"game:item/greek_salad",
	"game:item/green_curry",
	"game:item/green_papaya_salad",
	"game:item/grilled_cheese",
	"game:item/groundnut_stew",
	"game:item/ham_cheese_sandwich",
	"game:item/hamburger",
	"game:item/hash_brown",
	"game:item/hash_browns",
	"game:item/hot_cocoa",
	"game:item/hot_dog",
	"game:item/hummus",
	"game:item/iced_americano",
	"game:item/iced_latte",
	"game:item/injera",
	"game:item/jam_toast",
	"game:item/jollof",
	"game:item/juice",
	"game:item/kebab",
	"game:item/kebab_wrap",
	"game:item/khao_soi",
	"game:item/kimchi_soup",
	"game:item/lasagna",
	"game:item/latte",
	"game:item/lemonade",
	"game:item/mac_cheese",
	"game:item/macaron",
	"game:item/macchiato",
	"game:item/mango_lassi",
	"game:item/mango_sticky_rice",
	"game:item/mapo_tofu",
	"game:item/mashed_potato",
	"game:item/meat_sauce_rice",
	"game:item/meat_soup",
	"game:item/milk_tea",
	"game:item/milkshake",
	"game:item/mint_tea",
	"game:item/mocha",
	"game:item/mooncake",
	"game:item/muffin",
	"game:item/mushroom_risotto",
	"game:item/mushroom_soup",
	"game:item/naan",
	"game:item/nachos",
	"game:item/nasi_goreng",
	"game:item/nasi_lemak",
	"game:item/noodle_soup",
	"game:item/onigiri",
	"game:item/onion_rings",
	"game:item/onion_soup",
	"game:item/onion_tart",
	"game:item/oyakodon",
	"game:item/pad_thai",
	"game:item/paella",
	"game:item/palak_paneer",
	"game:item/pancake",
	"game:item/pasta_tomato",
	"game:item/persian_stew",
	"game:item/peruvian_chicken",
	"game:item/pho",
	"game:item/pilaf",
	"game:item/pita",
	"game:item/pizza",
	"game:item/poached_egg",
	"game:item/popcorn",
	"game:item/potato_salad",
	"game:item/pour_over",
	"game:item/poutine",
	"game:item/pudding",
	"game:item/raita",
	"game:item/ramen",
	"game:item/ravioli",
	"game:item/red_curry",
	"game:item/ribs",
	"game:item/rice_cake",
	"game:item/roast_chicken",
	"game:item/roasted_corn",
	"game:item/roasted_vegetables",
	"game:item/rose_dessert",
	"game:item/samosa",
	"game:item/sandwich",
	"game:item/satay",
	"game:item/sausage_sauerkraut",
	"game:item/scallion_noodle",
	"game:item/scone",
	"game:item/scrambled_egg",
	"game:item/seafood_pancake",
	"game:item/sesame_bun",
	"game:item/shawarma",
	"game:item/shepherd_pie",
	"game:item/shumai",
	"game:item/soda",
	"game:item/souffle",
	"game:item/soy_rice",
	"game:item/sparkling_water",
	"game:item/spring_roll",
	"game:item/steak",
	"game:item/steamed_egg",
	"game:item/stew",
	"game:item/sushi",
	"game:item/taco",
	"game:item/tagine",
	"game:item/tamale",
	"game:item/tamarind_sauce",
	"game:item/tandoori_chicken",
	"game:item/tangyuan",
	"game:item/tea_egg",
	"game:item/tea_rice",
	"game:item/tempura",
	"game:item/thali",
	"game:item/tiramisu",
	"game:item/toast",
	"game:item/toast_slice",
	"game:item/tom_yum",
	"game:item/tomato_soup",
	"game:item/tostada",
	"game:item/tres_leches",
	"game:item/tuna_sandwich",
	"game:item/turkish_coffee",
	"game:item/turmeric_rice",
	"game:item/twice_cooked_pork",
	"game:item/vegetable_salad",
	"game:item/vegetable_soup",
	"game:item/vienna_coffee",
	"game:item/waffle",
	"game:item/cocoa_shake",
	"game:item/white_rice",
	"game:item/wonton",
	"game:item/yogurt_soup",
	"game:item/yorkshire_pudding",
	"game:item/zongzi",
]


func before_each() -> void:
	GameState.reset()


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


# --- 图鉴总量 -------------------------------------------------------------


func test_catalog_total_matches_the_content_sheet() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var counts := {}
	var item_kinds := {}
	for key in data.get_catalog_keys():
		var def := data.get_def(key)
		var type_id := def.get_type_id()
		counts[type_id] = int(counts.get(type_id, 0)) + 1
		if def is ItemDef:
			var kind_name := "food" if (def as ItemDef).is_food() else "material"
			item_kinds[kind_name] = int(item_kinds.get(kind_name, 0)) + 1
	var expected_total := 0
	for type_id in EXPECTED_BY_TYPE:
		expected_total += int(EXPECTED_BY_TYPE[type_id])
	assert_eq(EXPECTED_CATALOG, expected_total, "期望值自洽")
	assert_eq(data.get_catalog_keys().size(), EXPECTED_CATALOG, "图鉴应收录 %d 条" % EXPECTED_CATALOG)
	for type_id in EXPECTED_BY_TYPE:
		assert_eq(int(counts.get(type_id, 0)), int(EXPECTED_BY_TYPE[type_id]), "%s 应为 %d 条" % [type_id, int(EXPECTED_BY_TYPE[type_id])])
	for kind_name in EXPECTED_ITEM_BY_KIND:
		assert_eq(int(item_kinds.get(kind_name, 0)), int(EXPECTED_ITEM_BY_KIND[kind_name]),
				"图鉴里的物品按 kind 分：%s 应为 %d 条" % [kind_name, int(EXPECTED_ITEM_BY_KIND[kind_name])])


func test_content_validates_cleanly() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var issues := data.validate()
	assert_eq(issues, [] as Array[String], "内容校验不应有问题：%s" % str(issues))


func test_every_food_has_a_recipe() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var produced := {}
	for def in data.get_defs_of_type("recipe"):
		produced[(def as RecipeDef).output] = true
	for def in data.get_defs_of_type("item"):
		var item := def as ItemDef
		if not item.is_food():
			continue
		assert_true(produced.has(item.get_key()), "%s 没有对应的配方" % item.get_key())


# --- 鸡蛋与设备 -----------------------------------------------------------


func test_egg_is_a_base_material_in_the_catalog() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var egg := data.get_def(MATERIAL + "egg") as ItemDef
	assert_not_null(egg, "鸡蛋应存在")
	if egg == null:
		return
	assert_eq(egg.material_kind, ItemDef.MaterialKind.BASE)
	assert_eq(egg.merchant_price, 4, "经济 v2：鸡蛋从商人买 4 铜币")
	assert_eq(egg.sell_price, 2, "卖回给商人 2 铜币（收购价 = 售价 ×0.5 的反面）")
	assert_true(egg.in_catalog, "鸡蛋要进图鉴")


func test_egg_comes_from_the_mailbox() -> void:
	var mailbox := GameState.get_harvest_for_material(MATERIAL + "egg")
	assert_not_null(mailbox, "鸡蛋应有来路")
	if mailbox == null:
		return
	assert_eq(mailbox.tag, "game:tag/pantry", "鸡蛋归杂货那一类")
	var keys: Array[String] = []
	for item in GameState.harvest_pool(mailbox):
		keys.append(item.get_key())
	assert_true(keys.has(MATERIAL + "egg"), "Lv1 的杂货池里就该有鸡蛋")
	assert_false(keys.has(MATERIAL + "nuts"), "坚果是 tier 5，开局摇不到")


func test_facility_upgrades_use_their_own_outputs() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var grinder := data.get_def("game:facility/grinder") as FacilityDef
	var oven := data.get_def("game:facility/oven") as FacilityDef
	assert_not_null(grinder, "磨豆机应存在")
	assert_not_null(oven, "烤箱应存在")
	if grinder == null or oven == null:
		return
	var grinder_two := grinder.get_upgrade(2)
	assert_not_null(grinder_two, "磨豆机应有 2 级升级")
	if grinder_two != null:
		assert_eq(grinder_two.materials[0].material, MATERIAL + "roasted_bean", "磨豆机 2 级要烘焙豆而不是咖啡粉")
		assert_eq(grinder_two.materials[0].amount, 10)
	var oven_three := oven.get_upgrade(3)
	assert_not_null(oven_three, "烤箱应有 3 级升级")
	if oven_three != null:
		assert_eq(oven_three.materials[0].material, MATERIAL + "flour", "烤箱 3 级要面粉")
		assert_eq(oven_three.materials[0].amount, 25)


# --- 信件 -----------------------------------------------------------------


func test_all_letters_are_ordered_and_chained() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var letters: Array[LetterDef] = []
	for def in data.get_defs_of_type("letter"):
		letters.append(def as LetterDef)
	letters.sort_custom(func(a: LetterDef, b: LetterDef) -> bool: return a.order < b.order)
	assert_eq(letters.size(), 69, "应有 69 封信：序章 16 + 东亚 5 + 其余八站各 5 + 站间过渡 7 + 收尾 1")
	var orders := {}
	for i in letters.size():
		assert_eq(letters[i].order, i + 1, "信件 order 应连续递增")
		orders[letters[i].get_key()] = letters[i].order
	for letter in letters:
		if letter.condition == LetterDef.Condition.AFTER_LETTER:
			assert_true(orders.has(letter.condition_ref), "%s 的 AFTER_LETTER 指向不存在的信" % letter.get_key())
			if orders.has(letter.condition_ref):
				assert_lt(int(orders[letter.condition_ref]), letter.order, "%s 应指向更早的一封" % letter.get_key())


func test_leaving_letter_unlocks_offline() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var letter := data.get_def("game:letter/before_leaving") as LetterDef
	assert_not_null(letter, "出发信应存在")
	if letter == null:
		return
	assert_true(letter.unlocks_offline, "离线结算绑在出发信上")
	assert_eq(letter.condition, LetterDef.Condition.CATALOG_COUNT, "出发信按图鉴进度触发")
	# 第九轮（v4）：出发信挪到 16、门槛 110——冰箱信（13／100）先来，
	# 离线解锁放在真正离站的那一封上；东亚到站信 17／120 紧跟其后。
	assert_eq(letter.condition_value, 110, "出发信的门槛是 110")


func test_butter_warmth_waits_for_the_upgrade_letter() -> void:
	# 第九轮：出发信挪到 16，黄油信（order 9）改挂第八封「教你怎么升级」之后，
	# 让「先升级、再出发」的顺序在叙事上接得上。
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var leave := data.get_def("game:letter/before_leaving") as LetterDef
	var butter := data.get_def("game:letter/butter_warmth") as LetterDef
	assert_not_null(leave, "出发信应存在")
	assert_not_null(butter, "黄油信应存在")
	if leave == null or butter == null:
		return
	assert_eq(butter.order, 9, "黄油信是 order 9")
	assert_eq(butter.condition, LetterDef.Condition.AFTER_LETTER, "黄油信按前一封触发")
	assert_eq(butter.condition_ref, "game:letter/teach_upgrade", "黄油信要等「教你怎么升级」读过")
	assert_lt(butter.order, leave.order, "黄油信排在出发信之前")


# --- 图鉴里程碑 -----------------------------------------------------------


func test_milestone_targets_follow_the_catalog_size() -> void:
	var total := GameState.get_catalog_total()
	var expected: Array[int] = []
	for pct in GameState.MILESTONE_PCTS:
		expected.append(int(ceil(float(total) * pct)))
	assert_eq(GameState.get_milestone_targets(), expected, "%d 条的 25/50/75/100%%" % total)


## 按 DISCOVERABLE 顺序补齐已发现数到 target_count（不够就停）
func _discover_until(target_count: int) -> void:
	for key in DISCOVERABLE:
		if GameState.get_catalog_discovered_count() >= target_count:
			return
		GameState.discover(key)


func test_crossing_a_milestone_pays_once() -> void:
	var start_coins := GameState.coins
	var start_count := GameState.get_catalog_discovered_count()
	var targets := GameState.get_milestone_targets()
	# 咖啡机、蒸笼、冰箱都要等信才进厨房（P10.8），开局已知是 5 件设备（含仓库）
	# 世界条目 P16 收束：开局只有车厢与门口 2 条，其余要等信才揭开
	assert_eq(start_count, 8, "开局已知：5 件设备 + 2 条世界 + 第一封信")
	assert_eq(GameState.get_milestone_tier(), 0)

	_discover_until(targets[0] - 1)
	assert_eq(GameState.get_milestone_tier(), 0, "还差一条")
	assert_eq(GameState.get_catalog_discovered_count(), targets[0] - 1)

	_discover_until(targets[0])
	assert_eq(GameState.get_milestone_tier(), 1, "到第一档阈值应跨过")
	assert_eq(GameState.coins - start_coins, 60, "第一档给 60 铜币")

	var discovered := GameState.get_catalog_discovered_count()
	GameState.discover(DISCOVERABLE[discovered - start_count])
	assert_eq(GameState.get_milestone_tier(), 1, "同档之内不重复发")
	assert_eq(GameState.coins - start_coins, 60)


func test_milestone_tier_survives_a_save_round_trip_without_paying_twice() -> void:
	_discover_until(GameState.get_milestone_targets()[0])
	assert_eq(GameState.get_milestone_tier(), 1)
	var coins_before := GameState.coins
	var saved := GameState.to_dict()
	assert_eq(int(saved.get("milestone_tier", -1)), 1, "档位要进存档")

	GameState.reset()
	assert_eq(GameState.get_milestone_tier(), 0)
	assert_true(GameState.restore_from_dict(saved), "存档应能恢复")
	assert_eq(GameState.get_milestone_tier(), 1, "恢复后档位应还原")
	assert_eq(GameState.coins, coins_before, "读档不该重发里程碑铜币")


func test_old_save_without_milestone_field_aligns_silently() -> void:
	_discover_until(GameState.get_milestone_targets()[0])
	var saved := GameState.to_dict()
	saved.erase("milestone_tier")
	var coins_before := GameState.coins
	GameState.reset()
	assert_true(GameState.restore_from_dict(saved), "缺字段的老档也应能恢复")
	assert_eq(GameState.get_milestone_tier(), 1, "按当前进度补算档位")
	assert_eq(GameState.coins, coins_before, "补算不补发铜币")


# --- 商人收购 -------------------------------------------------------------


func test_selling_a_material_pays_its_sell_price() -> void:
	GameState.add_item(MATERIAL + "coffee_bean", 5.0)
	var coins_before := GameState.coins
	assert_true(GameState.sell_material(MATERIAL + "coffee_bean", 2), "应当能卖出")
	assert_eq(GameState.coins - coins_before, 2, "咖啡生豆收购价 1 × 2")
	assert_almost_eq(GameState.get_amount(MATERIAL + "coffee_bean"), 3.0, 0.0001)


func test_selling_more_than_owned_is_refused() -> void:
	GameState.add_item(MATERIAL + "butter", 1.0)
	var coins_before := GameState.coins
	assert_false(GameState.sell_material(MATERIAL + "butter", 2), "手上不够不该成交")
	assert_eq(GameState.coins, coins_before)
	assert_almost_eq(GameState.get_amount(MATERIAL + "butter"), 1.0, 0.0001)


func test_materials_without_a_sell_price_are_not_bought() -> void:
	GameState.add_item(MATERIAL + "water", 3.0)
	assert_false(GameState.sell_material(MATERIAL + "water", 1), "免费材料的收购价是 0，卖不掉")


# --- 研究接入 -------------------------------------------------------------


func test_new_advanced_foods_need_research_but_basics_do_not() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var gated := ["game:recipe/cappuccino", "game:recipe/pudding", "game:recipe/croissant"]
	for key in gated:
		var recipe := data.get_def(key) as RecipeDef
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe != null:
			assert_true(recipe.needs_research(), "%s 应当需要研究" % key)
	var open_recipes := ["game:recipe/pour_over", "game:recipe/cookie", "game:recipe/cake"]
	for key in open_recipes:
		var recipe := data.get_def(key) as RecipeDef
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe != null:
			assert_false(recipe.needs_research(), "%s 一开始就该看得见" % key)


func test_pudding_requires_a_hot_enough_oven() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var recipe := data.get_def("game:recipe/pudding") as RecipeDef
	assert_not_null(recipe, "布丁配方应存在")
	if recipe == null:
		return
	assert_eq(recipe.facility, "game:facility/oven")
	assert_eq(recipe.research_min_facility_level, 2, "布丁要烤箱到 2 级才算「火候到了」")


# --- 世界条目 -------------------------------------------------------------


func test_the_cafe_is_revealed_by_the_leaving_letter() -> void:
	GameState.reset()
	assert_false(GameState.is_discovered("game:world/cafe"), "出发前不知道车身写着什么")
	assert_eq(GameState.get_catalog_discovered_count(), 8, "开局只认得车厢与门口")
	GameState._unlocked_letters.append("game:letter/before_leaving")
	GameState.mark_letter_read("game:letter/before_leaving")
	assert_true(GameState.is_discovered("game:world/cafe"), "出发信揭开「原来是咖啡馆」")


func test_arrival_letters_reveal_their_region() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var pairs := {
		"game:letter/east_asia_arrive": "game:world/east_asia",
		"game:letter/fast_food_arrive": "game:world/fast_food",
	}
	for letter_key in pairs:
		GameState.reset()
		var letter := data.get_def(letter_key) as LetterDef
		assert_not_null(letter, "%s 应存在" % letter_key)
		if letter == null:
			continue
		assert_false(GameState.is_discovered(pairs[letter_key]), "到站前不该认得 %s" % pairs[letter_key])
		GameState._unlocked_letters.append(letter_key)
		GameState.mark_letter_read(letter_key)
		assert_true(GameState.is_discovered(pairs[letter_key]), "%s 应揭开 %s" % [letter_key, pairs[letter_key]])

# --- 第十二轮：茄子 / 木薯与菜系归位 ----------------------------------------


## Q15/Q16：茄子、木薯是独立基础材料，各带两道需研究的新菜；咖喱角归东南亚、春卷归东亚。
func test_r12_eggplant_and_cassava_are_wired_into_dishes() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	for key in ["game:item/eggplant", "game:item/cassava"]:
		var item := data.get_def(key) as ItemDef
		assert_not_null(item, "%s 应存在" % key)
		if item != null:
			assert_true(item.is_material(), "%s 应是材料" % key)
			assert_true(item.tags.has("game:tag/veg"), "%s 应带蔬菜标签" % key)
	assert_eq((data.get_def("game:item/eggplant") as ItemDef).harvest_tier, 2, "茄子农田 Lv2 起可见")
	assert_eq((data.get_def("game:item/cassava") as ItemDef).harvest_tier, 3, "木薯农田 Lv3 起可见")

	var expected := {
		"game:recipe/roasted_eggplant": ["game:item/eggplant", "game:item/oil", "game:item/spice", "game:item/soy_sauce"],
		"game:recipe/eggplant_parmesan": ["game:item/eggplant", "game:item/tomato", "game:item/cheese", "game:item/oil"],
		"game:recipe/cassava_fries": ["game:item/cassava", "game:item/oil", "game:item/salt"],
		"game:recipe/cassava_cake": ["game:item/cassava", "game:item/coconut_milk", "game:item/sugar"],
	}
	for key: String in expected:
		var recipe := data.get_def(key) as RecipeDef
		assert_not_null(recipe, "%s 应存在" % key)
		if recipe == null:
			continue
		assert_true(recipe.needs_research(), "%s 应需要研究" % key)
		var inputs: Array[String] = []
		for stack in recipe.inputs:
			if stack.material != "":
				inputs.append(stack.material)
		assert_eq(inputs, expected[key], "%s 的输入顺序应与设计一致" % key)

	assert_eq((data.get_def("game:item/curry_puff") as ItemDef).theme, "game:theme/southeast_asia", "咖喱角归东南亚")
	assert_eq((data.get_def("game:item/spring_roll") as ItemDef).theme, "game:theme/east_asia", "春卷归东亚")
