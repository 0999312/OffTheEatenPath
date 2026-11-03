extends GutTest
## R7.3 菜品树体检：白饭数据、全量可达、第一条咖啡待办只给一种做法。

const COFFEE_TASK_LETTER := "game:letter/task_window_1"
const COFFEE_GROUND := "game:item/coffee_ground"
const POUR_OVER_RECIPE := "game:recipe/pour_over"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	GameState.reset()


## Q5：白饭 = 蒸笼 + 米 ×1 + 水 ×1（水是 FREE，不进图鉴）。
func test_white_rice_recipe_uses_one_rice_and_one_water() -> void:
	var recipe := GameState._def("game:recipe/white_rice") as RecipeDef
	assert_not_null(recipe, "白饭配方应存在")
	assert_eq(recipe.facility, "game:facility/steamer", "白饭用蒸笼")
	assert_eq(recipe.duration_seconds, 25.0, "白饭耗时保持 25 秒")
	assert_eq(recipe.group, "simple", "白饭仍在简单菜组")
	assert_eq(recipe.inputs.size(), 2, "白饭恰好两样输入")
	var rice := recipe.inputs[0] as MaterialStack
	var water := recipe.inputs[1] as MaterialStack
	assert_eq(rice.material, "game:item/rice", "第一样是米")
	assert_eq(rice.amount, 1, "米只要 1 份")
	assert_eq(water.material, "game:item/water", "第二样是水")
	assert_eq(water.amount, 1, "水只要 1 份")


## 全设备 / 全采集 / 全研究口径：288 道菜必须全部可达，且不能有研发互引环。
func test_full_tree_reaches_all_288_dishes_without_cycles() -> void:
	var keys := GameState.get_all_dish_keys()
	assert_eq(keys.size(), 288, "图鉴里的菜应有 288 道")
	var blocked: Array[String] = []
	var cyclic: Array[String] = []
	for dish_key in keys:
		var report := GameState.explain_dish_reachability(String(dish_key), true)
		if not bool(report.get("orderable", false)):
			blocked.append(String(dish_key))
		if String(report.get("kind", "")) == "cycle":
			cyclic.append(String(dish_key))
	assert_eq(blocked.size(), 0, "FULL 口径不该有缺口：%s" % ", ".join(blocked))
	assert_eq(cyclic.size(), 0, "FULL 口径不该有研发互引环：%s" % ", ".join(cyclic))


## 咖啡教学：第一杯待办到达时，饮品组里真正能做的只有「手冲」。
## 此时咖啡机还没到手，espresso / flat_white / macchiato 做不了；
## latte 等研究配方在解锁前不可见，不能混进「可做」。
func test_first_coffee_task_only_offers_pour_over() -> void:
	GameState._read_letters["game:letter/window"] = true
	GameState._read_letters[COFFEE_TASK_LETTER] = true
	assert_true(GameState.accept_task(COFFEE_TASK_LETTER), "读完信可以接下待办")
	GameState.add_item(COFFEE_GROUND, 2)
	assert_eq(GameState.get_active_task_recipe_keys(), [POUR_OVER_RECIPE],
			"灶台应标出手冲是当前委托目标")
	var craftable: Array[String] = []
	for recipe in GameState.get_visible_recipes():
		if recipe.group != "drink":
			continue
		if GameState.can_consume(recipe.inputs, 1) and GameState.is_facility_ready(recipe.facility):
			craftable.append(recipe.get_key())
	assert_eq(craftable, [POUR_OVER_RECIPE], "饮品组可做只应有手冲一条：%s" % ", ".join(craftable))
