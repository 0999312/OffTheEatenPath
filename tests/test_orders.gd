extends GutTest
## 订单板：开局补位、交付扣菜发酬劳、按时间补单、存档往返、成品食物收购价。

const ESPRESSO_FOOD := "game:item/espresso"
const AMERICANO_FOOD := "game:item/americano"
const COFFEE_BEAN := "game:item/coffee_bean"

var _order_events: int = 0


func before_each() -> void:
	_order_events = 0
	GameState.reset()
	EventBus.subscribe(&"OrderChangedEvent", _on_order_event)


func after_each() -> void:
	EventBus.unsubscribe(&"OrderChangedEvent", _on_order_event)


func _on_order_event(_event: Event) -> void:
	_order_events += 1


func test_reset_seeds_a_full_order_board() -> void:
	var orders := GameState.get_orders()
	assert_eq(orders.size(), GameState.ORDER_CAPACITY, "开局应补满订单板")
	for order in orders:
		assert_true(order.dish_key.begins_with("game:item/"), "委托应是成品菜")
		assert_true(order.quantity >= 1)
		assert_true(order.reward_coins >= 4, "酬劳至少 4 铜币")
		assert_false(order.bonus_material.is_empty(), "每单应带一点稀有材料")
		assert_true(order.bonus_material.begins_with("game:item/"))


func test_deliver_consumes_dish_and_pays_reward() -> void:
	var order := GameState.get_orders()[0]
	GameState.add_item(order.dish_key, order.quantity)
	GameState.add_coins(10, "测试本钱")
	var before_coins := GameState.coins
	var before_bonus := GameState.get_amount(order.bonus_material)

	assert_true(GameState.deliver_order(order.id), "菜够时应能交付")
	assert_eq(GameState.get_amount(order.dish_key), 0, "交付扣掉指定份数")
	assert_eq(GameState.coins, before_coins + order.reward_coins, "酬劳到账")
	assert_eq(GameState.get_amount(order.bonus_material), before_bonus + order.bonus_amount, "赠品到账")
	assert_eq(GameState.get_orders_completed(), 1)
	assert_eq(GameState.get_orders().size(), GameState.ORDER_CAPACITY - 1, "交付后腾出一个位置")
	assert_eq(_order_events, 1, "交付应广播 OrderChangedEvent")


func test_deliver_without_enough_dish_fails() -> void:
	var order := GameState.get_orders()[0]
	GameState.add_item(order.dish_key, order.quantity - 1)
	assert_false(GameState.deliver_order(order.id), "份数不够不能交付")
	assert_eq(GameState.get_orders().size(), GameState.ORDER_CAPACITY, "失败不动订单板")
	assert_false(GameState.deliver_order(-1), "不存在的单号应拒绝")


## 材料与食物同表之后，「这块肉不是一道菜」只能靠 kind 卡住。
## 只要漏掉那一刀，有配方、有收购价的中间材料（比如糖）就会被端上订单板。
func test_only_food_lands_on_the_order_board() -> void:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	assert_not_null(registry, "DataRegistry 未就绪")
	if registry == null:
		return
	var dishes: Array[String] = GameState._order_dish_keys()
	assert_gt(dishes.size(), 0, "应有可委托的菜")
	for key in dishes:
		var item := registry.get_def(key) as ItemDef
		assert_not_null(item, "%s 应能解析" % key)
		if item != null:
			assert_true(item.is_food(), "%s 是材料，不该进可委托列表" % key)
	var sugar := registry.get_def("game:item/sugar") as ItemDef
	assert_not_null(sugar, "糖应存在（有配方、有收购价的中间材料）")
	if sugar != null:
		assert_false(sugar.is_food())
		assert_false(dishes.has(sugar.get_key()), "材料不该出现在可委托列表里")


func test_empty_slot_refills_after_five_minutes() -> void:
	var orders := GameState.get_orders()
	for order in orders:
		GameState.add_item(order.dish_key, order.quantity)
		assert_true(GameState.deliver_order(order.id))
	assert_eq(GameState.get_orders().size(), 0)

	GameState.advance(GameState.ORDER_REFILL_SECONDS)
	assert_eq(GameState.get_orders().size(), 1, "五分钟后补一单")
	assert_eq(GameState.get_orders_refreshed(), 1, "按时间补的单要记数")
	assert_eq(_order_events, 4, "三次交付 + 一次补单")


func test_orders_survive_save_round_trip() -> void:
	var before := GameState.get_orders()
	var data := GameState.to_dict()
	assert_eq(int(data.get("version", 0)), GameState.SAVE_VERSION)

	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "应能读回")
	var after := GameState.get_orders()
	assert_eq(after.size(), before.size())
	for index in after.size():
		assert_eq(after[index].id, before[index].id)
		assert_eq(after[index].dish_key, before[index].dish_key)
		assert_eq(after[index].quantity, before[index].quantity)
		assert_eq(after[index].reward_coins, before[index].reward_coins)
		assert_eq(GameState.get_amount(after[index].bonus_material),
				GameState.get_amount(before[index].bonus_material))


func test_food_can_be_sold_for_coins() -> void:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	var espresso := registry.get_def(ESPRESSO_FOOD) as ItemDef
	assert_not_null(espresso)
	GameState.add_item(ESPRESSO_FOOD, 3)
	var before := GameState.coins
	assert_true(GameState.sell_item(ESPRESSO_FOOD, 2), "成品食物应能卖给商人")
	assert_eq(GameState.get_amount(ESPRESSO_FOOD), 1)
	assert_eq(GameState.coins, before + 2 * espresso.sell_price, "按每份收购价结算")
	assert_false(GameState.sell_item(ESPRESSO_FOOD, 5), "手上不够时拒绝")
	assert_false(GameState.sell_item(AMERICANO_FOOD, 1), "没有库存时拒绝")


func test_every_food_has_a_sell_price() -> void:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	assert_not_null(registry)
	if registry == null:
		return
	for def in registry.get_defs_of_type("item"):
		var food := def as ItemDef
		if not food.is_food():
			continue
		assert_gt(food.sell_price, 0, "%s 应有收购价" % food.get_key())


func test_stock_stays_integer_with_fraction_carry() -> void:
	GameState.add_item_float(COFFEE_BEAN, 0.6)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0, "不足一份不显示")
	GameState.add_item_float(COFFEE_BEAN, 0.6)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 1, "攒满一份才入账")
	GameState.add_item(COFFEE_BEAN, 2)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 3)


func test_offline_tips_are_capped_by_the_material_ceiling() -> void:
	GameState.offline_unlocked = true
	# 第九轮：离线总时长按材料上限 8 小时封顶，小费仍是每 5 分钟 1 份。
	# 里程碑档位先推满，避免把里程碑铜币算进预期。
	GameState._milestone_tier = GameState.MILESTONE_PCTS.size()
	var summary := GameState.apply_offline(48.0 * 3600.0)
	assert_eq(summary.coins_gained, 96, "8 小时 × 每 5 分钟 1 份，48 小时也只发到这里")
	assert_eq(GameState.coins, 96)


func test_v2_float_stock_save_is_rejected() -> void:
	var data := GameState.to_dict()
	data["version"] = 2
	data["stock"] = {COFFEE_BEAN: 3.7}
	GameState.reset()
	assert_false(GameState.restore_from_dict(data), "v18 起不再读取 v2 存档")


func test_big_numbers_use_wan_and_yi() -> void:
	# 大数单位随语言切换（中文「万/亿」、英文 k/M/B），断言前固定到中文
	I18NManager.set_language("zh_CN")
	assert_eq(PanelKit.big_number_text(9999), "9999")
	assert_eq(PanelKit.big_number_text(10000), "1万")
	assert_eq(PanelKit.big_number_text(15000), "1.5万")
	assert_eq(PanelKit.big_number_text(100000000), "1亿")
	assert_eq(PanelKit.big_number_text(123456789), "1.23亿")
	assert_eq(PanelKit.coins_text(25000), "2.5万 铜币")


func test_big_numbers_use_k_and_m_in_english() -> void:
	I18NManager.set_language("en")
	assert_eq(PanelKit.big_number_text(999), "999")
	assert_eq(PanelKit.big_number_text(1500), "1.5k")
	assert_eq(PanelKit.big_number_text(2500000), "2.5M")
	assert_eq(PanelKit.coins_text(25000), "25k coins")
	I18NManager.set_language("zh_CN")


## 订单板扩容：前两张各 80 / 200 铜币，扩张后立刻补满新格位。
func test_order_capacity_can_be_upgraded_with_coins() -> void:
	assert_eq(GameState.get_order_capacity(), GameState.ORDER_CAPACITY, "开局三格")
	assert_eq(GameState.get_order_capacity_cost(), 80, "第一次扩容 80 铜币")
	GameState.add_coins(79, "测试本钱")
	assert_false(GameState.upgrade_order_capacity(), "钱不够不能扩")
	assert_eq(GameState.get_order_capacity(), GameState.ORDER_CAPACITY)
	GameState.add_coins(1, "测试本钱")
	assert_true(GameState.upgrade_order_capacity(), "钱够就能扩")
	assert_eq(GameState.coins, 0, "扩容扣掉 80")
	assert_eq(GameState.get_order_capacity(), 4)
	assert_eq(GameState.get_orders().size(), 4, "新格位立刻补一单")


func test_order_capacity_stops_at_five() -> void:
	GameState.add_coins(1000, "测试本钱")
	assert_true(GameState.upgrade_order_capacity())
	assert_eq(GameState.get_order_capacity_cost(), 200, "第二次 200 铜币")
	assert_true(GameState.upgrade_order_capacity())
	assert_eq(GameState.get_order_capacity(), GameState.ORDER_CAPACITY_MAX)
	assert_eq(GameState.get_order_capacity_cost(), -1, "满级没有下一个价位")
	assert_false(GameState.can_upgrade_order_capacity())
	assert_false(GameState.upgrade_order_capacity(), "满级再扩应拒绝")
	assert_eq(GameState.get_orders().size(), GameState.ORDER_CAPACITY_MAX)


## 拒单免费：腾出的位置按正常补位倒计时慢慢补，不立刻换上新的。
func test_decline_is_free_and_frees_the_slot() -> void:
	var order := GameState.get_orders()[0]
	var before_coins := GameState.coins
	assert_true(GameState.decline_order(order.id), "应能拒单")
	assert_eq(GameState.coins, before_coins, "拒单不花钱")
	assert_eq(GameState.get_orders().size(), GameState.ORDER_CAPACITY - 1)
	var still_there := false
	for remaining in GameState.get_orders():
		if remaining.id == order.id:
			still_there = true
	assert_false(still_there, "被拒的单不在了")
	assert_gt(GameState.get_orders_refill_remaining(), 0.0, "空位进入补位倒计时")
	assert_eq(_order_events, 1, "拒单应广播 OrderChangedEvent")
	assert_false(GameState.decline_order(order.id), "同一单不能拒两次")


## 「换一批」免费，但要走完 300 秒冷却才能再换。
func test_refresh_is_free_but_has_a_cooldown() -> void:
	var before_ids: Array[int] = []
	for order in GameState.get_orders():
		before_ids.append(order.id)
	var before_coins := GameState.coins
	assert_true(GameState.refresh_orders(), "开局可以换一批")
	assert_eq(GameState.coins, before_coins, "换一批不花钱")
	assert_eq(GameState.get_orders().size(), GameState.ORDER_CAPACITY, "换完还是满板")
	for order in GameState.get_orders():
		assert_false(before_ids.has(order.id), "每张都是新单")
	assert_eq(GameState.get_order_refresh_cooldown(), GameState.ORDER_REFRESH_COOLDOWN_SECONDS)
	assert_false(GameState.refresh_orders(), "冷却期内不能再换")

	GameState.advance(GameState.ORDER_REFRESH_COOLDOWN_SECONDS - 1.0)
	assert_false(GameState.refresh_orders(), "差一秒还不行")
	GameState.advance(1.0)
	assert_true(GameState.refresh_orders(), "冷却走完可以再换")


## 招牌加成按「写了几个槽」叠加：1.25 / 1.35 / 1.45。
func test_signature_bonus_grows_with_each_dish() -> void:
	assert_almost_eq(GameState.get_signature_bonus(), 1.0, 0.0001, "没写招牌时没有加成")
	GameState.discover("game:item/espresso")
	GameState.discover("game:item/latte")
	GameState.discover("game:item/cake")
	GameState.set_signature_slot(0, "game:item/espresso")
	assert_almost_eq(GameState.get_signature_bonus(), 1.25, 0.0001, "一道招牌 ×1.25")
	GameState.set_signature_slot(1, "game:item/latte")
	assert_almost_eq(GameState.get_signature_bonus(), 1.35, 0.0001, "两道招牌 ×1.35")
	GameState.set_signature_slot(2, "game:item/cake")
	assert_almost_eq(GameState.get_signature_bonus(), 1.45, 0.0001, "三道招牌 ×1.45")

	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	var espresso := registry.get_def("game:item/espresso") as ItemDef
	assert_not_null(espresso)
	if espresso == null:
		return
	assert_eq(GameState._order_reward_for(espresso, 1, true),
			roundi(float(espresso.sell_price * GameState.ORDER_REWARD_MULTIPLIER) * 1.45),
			"招牌酬劳按当前槽数加成")
	assert_eq(GameState._order_reward_for(espresso, 1, false),
			espresso.sell_price * GameState.ORDER_REWARD_MULTIPLIER, "非招牌不加成")


func test_order_capacity_survives_save_round_trip() -> void:
	GameState.add_coins(80, "测试本钱")
	assert_true(GameState.upgrade_order_capacity())
	var data := GameState.to_dict()
	assert_eq(int(data.get("order_capacity", 0)), 4)

	GameState.reset()
	assert_eq(GameState.get_order_capacity(), GameState.ORDER_CAPACITY, "reset 回到三格")
	assert_true(GameState.restore_from_dict(data))
	assert_eq(GameState.get_order_capacity(), 4, "容量随存档恢复")
	assert_eq(GameState.get_orders().size(), 4, "读档后订单板仍是满的")

