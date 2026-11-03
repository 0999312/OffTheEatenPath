extends GutTest
## 订单需求权重与招牌菜加成：权重决定抽中概率、0 权重不上板、招牌菜酬劳加价、标记能进档。

const AMERICANO_FOOD := "game:item/americano"
const CAKE_FOOD := "game:item/cake"
const BOILED_EGG_FOOD := "game:item/boiled_egg"
const CAFE_THEME := "game:theme/cafe"
const BASE_THEME := "game:theme/base"


func before_each() -> void:
	GameState.reset()
	GameState.set_random_seed(20261025)


func after_each() -> void:
	GameState.set_random_seed(0)


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


## 美式第六轮起需要研究解锁；订单板只抽已解锁的菜，这里先把它放进池子。
func _unlock_americano() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	GameState._unlock_recipe(data.get_def("game:recipe/americano") as RecipeDef)
	# 美式的输入是浓缩；订单闸门会一路倒推，咖啡机没到手就不上板。
	# 这个用例只测招牌标记，先把咖啡机补到 1 级，让链路真的可达。
	GameState._facility_levels["game:facility/coffee_machine"] = 1


func test_every_dish_has_a_positive_weight() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	for def in data.get_defs_of_type("item"):
		var food := def as ItemDef
		if not food.is_food():
			continue
		assert_gt(food.order_weight, 0.0, "%s 应有正的订单权重" % food.get_key())


func test_heavier_weight_is_picked_more_often() -> void:
	# 美式 1.6 / 蛋糕 0.6：抽 400 次，美式该明显更多
	var dishes: Array[String] = [AMERICANO_FOOD, CAKE_FOOD]
	var americano := 0
	var cake := 0
	for i in 400:
		var key := String(GameState.call("_pick_order_dish", dishes))
		if key == AMERICANO_FOOD:
			americano += 1
		elif key == CAKE_FOOD:
			cake += 1
	assert_gt(americano, cake, "权重高的菜应更常被抽到（%d vs %d）" % [americano, cake])
	assert_gt(americano + cake, 300, "抽选不该大部分落空")


func test_zero_weight_dish_leaves_the_board() -> void:
	var data := _data()
	if data == null:
		fail_test("DataRegistry 未就绪")
		return
	var cake := data.get_def(CAKE_FOOD) as ItemDef
	var original := cake.order_weight
	cake.order_weight = 0.0
	var keys: Array[String] = []
	keys.assign(GameState.call("_order_dish_keys"))
	assert_false(keys.has(CAKE_FOOD), "权重 0 的菜不该出现在可选列表里")
	cake.order_weight = original


func test_signature_dish_pays_a_bonus() -> void:
	var food := _data().get_def(AMERICANO_FOOD) as ItemDef
	var plain := int(GameState.call("_order_reward_for", food, 2, false))
	# 加成按「便条上写了几道招牌菜」算：先写一道，再要求招牌单更值钱
	GameState.discover(AMERICANO_FOOD)
	GameState.set_signature_slot(0, AMERICANO_FOOD)
	var bonus := int(GameState.call("_order_reward_for", food, 2, true))
	assert_eq(plain, maxi(4, food.sell_price * 2 * GameState.ORDER_REWARD_MULTIPLIER),
			"普通单按基础价算")
	assert_eq(bonus, roundi(float(plain) * GameState.get_signature_bonus()),
			"招牌单按「写了几道」的加成算")
	assert_gt(bonus, plain, "招牌单应该更值钱")


func test_signature_slot_marks_fresh_orders() -> void:
	_unlock_americano()
	# 招牌位只收「已发现」的菜，先把美式塞进图鉴
	GameState.discover(AMERICANO_FOOD)
	GameState.set_signature_slot(0, AMERICANO_FOOD)
	assert_eq(GameState.get_signature_slots()[0], AMERICANO_FOOD, "招牌位应记住这道菜")
	# 直接追加委托：抽到招牌菜的单应带标记，且只有它带
	var saw_signature := false
	for i in 200:
		if not bool(GameState.call("_append_order")):
			break
		var order: Order = GameState.get_orders().back()
		if order.dish_key == AMERICANO_FOOD:
			saw_signature = saw_signature or order.is_signature
			assert_true(order.is_signature, "招牌菜的单应标出来")
		else:
			assert_false(order.is_signature, "没挂招牌的菜不该被标成招牌")
	assert_true(saw_signature, "200 次追加里应至少抽到一次招牌菜")


## 招牌菜系：同一菜系手填 1/2/3 道，订单权重依次 ×1.5 / ×1.8 / ×2.0；
## 没有手填的菜系不出现，自动补位永远不会写进槽位，所以也不会计入。
func test_signature_theme_boost_counts_only_manual_slots() -> void:
	assert_true(GameState.get_signature_theme_boosts().is_empty(), "默认三格自动，不该有菜系加成")
	GameState.discover(AMERICANO_FOOD)
	GameState.discover(CAKE_FOOD)
	GameState.discover("game:item/latte")
	GameState.set_signature_slot(0, AMERICANO_FOOD)
	assert_almost_eq(GameState.get_signature_theme_boost(CAFE_THEME), 1.5, 0.0001, "一道招牌 ×1.5")
	GameState.set_signature_slot(1, CAKE_FOOD)
	assert_almost_eq(GameState.get_signature_theme_boost(CAFE_THEME), 1.8, 0.0001, "两道同菜系 ×1.8")
	GameState.set_signature_slot(2, "game:item/latte")
	assert_almost_eq(GameState.get_signature_theme_boost(CAFE_THEME), 2.0, 0.0001, "三道同菜系 ×2.0")
	assert_almost_eq(GameState.get_signature_theme_boost(BASE_THEME), 1.0, 0.0001, "没手填的菜系不加成")


## 菜系加成只放大被抽中的概率，不改订单酬劳：咖啡招牌把美式的 1.6 权重抬到 2.4，
## 对比无主题的水煮蛋 1.5，抽 800 次应明显更多。
func test_signature_theme_boost_changes_pick_rate() -> void:
	var dishes: Array[String] = [AMERICANO_FOOD, BOILED_EGG_FOOD]
	GameState.discover(AMERICANO_FOOD)
	GameState.set_signature_slot(0, AMERICANO_FOOD)
	# 先抽一次把「下一单保底」用掉，后续才是按权重抽。
	GameState.call("_pick_order_dish", dishes)
	var americano := 0
	var egg := 0
	for i in 800:
		var key := String(GameState.call("_pick_order_dish", dishes))
		if key == AMERICANO_FOOD:
			americano += 1
		elif key == BOILED_EGG_FOOD:
			egg += 1
	assert_gt(americano, egg, "有菜系加成的美式应比无主题水煮蛋更常被抽到（%d vs %d）" % [americano, egg])


## 设置招牌后，订单板有空位就立即补一单该菜系；这单不要求正好是那道菜，只要求同菜系。
func test_setting_signature_guarantees_one_themed_order() -> void:
	GameState._orders.clear()
	GameState.discover(AMERICANO_FOOD)
	GameState.set_signature_slot(0, AMERICANO_FOOD)
	var orders := GameState.get_orders()
	assert_eq(orders.size(), 1, "有空位时设置招牌应立即补一单")
	if not orders.is_empty():
		assert_eq(orders[0].signature_theme_key, CAFE_THEME, "补的单应来自招牌菜系")
		assert_almost_eq(orders[0].signature_theme_boost, 1.5, 0.0001, "订单应记录菜系倍率")


func test_order_theme_fields_survive_roundtrip() -> void:
	var order := Order.new()
	order.id = 9
	order.dish_key = CAKE_FOOD
	order.quantity = 1
	order.reward_coins = 80
	order.signature_theme_key = CAFE_THEME
	order.signature_theme_boost = 1.8
	var restored := Order.from_dict(order.to_dict())
	assert_eq(restored.signature_theme_key, CAFE_THEME, "菜系键应能进档")
	assert_almost_eq(restored.signature_theme_boost, 1.8, 0.0001, "菜系倍率应能进档")
	var old := Order.from_dict({"id": 1, "dish": CAKE_FOOD})
	assert_eq(old.signature_theme_key, "", "旧档没有菜系字段 = 空")
	assert_almost_eq(old.signature_theme_boost, 1.0, 0.0001, "旧档没有菜系倍率 = 1.0")


func test_order_flag_survives_save_roundtrip() -> void:
	var order := Order.new()
	order.id = 7
	order.dish_key = AMERICANO_FOOD
	order.quantity = 2
	order.reward_coins = 25
	order.bonus_material = "game:item/sugar"
	order.bonus_amount = 3
	order.is_signature = true
	var restored := Order.from_dict(order.to_dict())
	assert_true(restored.is_signature, "招牌标记应能进档")
	assert_eq(restored.reward_coins, 25)
	var plain := Order.new()
	assert_false(Order.from_dict(plain.to_dict()).is_signature, "普通单默认不是招牌")
