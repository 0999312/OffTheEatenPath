extends GutTest
## R7.3 订单闸门：没到手的设备、没来源的材料、没研究的配方不该上订单板。

const WHITE_RICE := "game:item/white_rice"
const WHITE_RICE_RECIPE := "game:recipe/white_rice"
const STEAMER := "game:facility/steamer"
const EAST_ASIA_LETTER := "game:letter/east_asia_arrive"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	GameState.reset()


## 一阶段：主题已经到站（白饭配方可见），但蒸笼还没到手。
## 白饭不该被判成可下单，订单池里也不该出现它。
func test_steamer_dish_is_not_orderable_before_steamer() -> void:
	GameState._read_letters[EAST_ASIA_LETTER] = true
	assert_false(GameState.is_facility_ready(STEAMER), "新档蒸笼还没到手")
	assert_true(not GameState.get_visible_recipes().is_empty(), "至少还有别的配方可见")
	var report := GameState.explain_dish_reachability(WHITE_RICE)
	assert_eq(String(report.get("state", "")), "facility", "白饭应被诊断为缺设备")
	assert_false(GameState.is_orderable_now(WHITE_RICE_RECIPE), "蒸笼没到手，白饭不可下单")
	var dishes := GameState._order_dish_keys()
	assert_false(dishes.has(WHITE_RICE), "订单池不该出现白饭")
	assert_gte(dishes.size(), 1, "正常存档不该被闸门筛空")


## 一阶段连续刷 20 批订单：每一批都只能出现当前存档真能做的菜。
func test_twenty_order_batches_only_include_reachable_dishes() -> void:
	GameState._read_letters[EAST_ASIA_LETTER] = true
	for batch in 20:
		GameState._order_refresh_cooldown = 0.0
		if GameState.get_orders().is_empty():
			GameState._refill_orders()
		else:
			assert_true(GameState.refresh_orders(), "第 %d 批应能刷新" % (batch + 1))
		assert_gt(GameState.get_orders().size(), 0, "第 %d 批订单板不该为空" % (batch + 1))
		for order in GameState.get_orders():
			var recipe_key := GameState.recipe_for_output(order.dish_key)
			assert_ne(recipe_key, "", "订单菜 %s 应有配方" % order.dish_key)
			assert_true(GameState.is_orderable_now(recipe_key), "第 %d 批出现不可达菜：%s" % [batch + 1, order.dish_key])
			assert_ne(order.dish_key, WHITE_RICE, "蒸笼未到手时白饭不该上订单板")
