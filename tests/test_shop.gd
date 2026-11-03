extends GutTest
## 商店货架（经济 v2 §4，D4）：常见料 20 份、稀料 10 份，买空拔一次**全局**冷却，
## 6 分钟后一次补满所有槽；买空不重置冷却、价格固定、离线照走冷却。

const BEAN := "game:item/coffee_bean"
const BUTTER := "game:item/butter"
const SUGAR := "game:item/sugar"
const MAILBOX := "game:harvest/mailbox"
const TMP_DIR := "res://tests/tmp"
const TMP_SAVE := "res://tests/tmp/test_shop.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GameState.reset()


func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))


func test_slots_start_full() -> void:
	assert_eq(GameState.get_shop_stock(BEAN), 20, "常见料开局 20 份")
	assert_eq(GameState.get_shop_stock(SUGAR), 20, "糖也是常见料")
	assert_eq(GameState.get_shop_stock(BUTTER), 10, "贵料开局 10 份")


## 容量按买价分档：买价 < 3 → 20，>= 3 → 10（不再有「四个槽共用一套参数」）
func test_capacity_follows_the_buy_price() -> void:
	assert_eq(GameState.get_shop_capacity(BEAN), 20)
	assert_eq(GameState.get_shop_capacity(SUGAR), 20)
	assert_eq(GameState.get_shop_capacity("game:item/flour"), 20)
	assert_eq(GameState.get_shop_capacity(BUTTER), 10)
	assert_eq(GameState.get_shop_capacity("game:item/egg"), 10)
	assert_eq(GameState.get_shop_capacity("game:item/milk"), 10)


func test_buying_takes_from_the_slot() -> void:
	GameState.add_coins(100, "测试")
	assert_true(GameState.buy_material(BEAN, 2), "槽里有货就能买")
	assert_eq(GameState.get_shop_stock(BEAN), 18, "买 2 份，槽里剩 18")
	assert_eq(GameState.get_amount(BEAN), 2, "买到手 2 份")


func test_cannot_buy_more_than_what_is_on_the_shelf() -> void:
	GameState.add_coins(1000, "测试")
	assert_false(GameState.buy_material(BEAN, 21), "槽里只有 20 份，买 21 份应被拒")
	assert_eq(GameState.get_amount(BEAN), 0, "拒绝时不该发货")


func test_emptying_the_slot_starts_a_restock() -> void:
	GameState.add_coins(1000, "测试")
	assert_true(GameState.buy_material(BEAN, 20), "一次搬空")
	assert_eq(GameState.get_shop_stock(BEAN), 0, "槽空了")
	assert_almost_eq(GameState.get_shop_refill_remaining(), GameState.SHOP_REFILL_SECONDS, 0.01,
			"空槽拨起全局补货表")
	assert_false(GameState.buy_material(BEAN, 1), "冷却期间买不到")


func test_restock_fills_the_slot_after_the_cooldown() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	GameState.advance(GameState.SHOP_REFILL_SECONDS * 0.5)
	assert_eq(GameState.get_shop_stock(BEAN), 0, "没到点还空着")
	GameState.advance(GameState.SHOP_REFILL_SECONDS * 0.5)
	assert_eq(GameState.get_shop_stock(BEAN), 20, "到点补满")
	assert_eq(GameState.get_shop_refill_remaining(), 0.0, "补满后不再冷却")


## 一次补满的是「所有槽」：只买了一半的贵料也跟着补到满，不是只补被买空的那一槽
func test_restock_fills_every_slot_at_once() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	GameState.buy_material(BUTTER, 3)
	assert_eq(GameState.get_shop_stock(BUTTER), 7)
	GameState.advance(GameState.SHOP_REFILL_SECONDS)
	assert_eq(GameState.get_shop_stock(BEAN), 20, "买空的槽补满")
	assert_eq(GameState.get_shop_stock(BUTTER), 10, "没买空的槽也补到满")
	assert_eq(GameState.get_amount(BUTTER), 3, "补的是货架，不替玩家买")


## 全局一份表：第二样买空不把倒计时推回 6 分钟
func test_another_empty_shelf_does_not_reset_the_timer() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	GameState.advance(60.0)
	assert_almost_eq(GameState.get_shop_refill_remaining(), GameState.SHOP_REFILL_SECONDS - 60.0, 0.01)
	GameState.buy_material(BUTTER, 10)
	assert_eq(GameState.get_shop_stock(BUTTER), 0, "第二样也搬空了")
	assert_almost_eq(GameState.get_shop_refill_remaining(), GameState.SHOP_REFILL_SECONDS - 60.0, 0.01,
			"已经在走的表不重置")


## 离线回来（一次推进几小时）不该重复补货，也不该卡在半路
func test_long_offline_restock_is_idempotent() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	GameState.advance(3600.0 * 8.0)
	assert_eq(GameState.get_shop_stock(BEAN), 20, "离线回来是满架")
	assert_eq(GameState.get_shop_refill_remaining(), 0.0, "冷却已清掉")


func test_price_does_not_climb_with_purchases() -> void:
	GameState.add_coins(1000, "测试")
	var before := GameState.coins
	assert_true(GameState.buy_material(BEAN, 1))
	var first := before - GameState.coins
	before = GameState.coins
	assert_true(GameState.buy_material(BEAN, 1))
	assert_eq(before - GameState.coins, first, "第二份与第一份同价")


func test_stock_and_cooldown_survive_a_save() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	GameState.advance(60.0)
	var saver := SaveGame.new(TMP_SAVE)
	assert_eq(saver.save_state(GameState.to_dict()), OK, "存档应成功")
	GameState.reset()
	assert_true(GameState.restore_from_dict(saver.load_state()), "读档应成功")
	assert_eq(GameState.get_shop_stock(BEAN), 0, "空槽状态保留")
	assert_almost_eq(GameState.get_shop_refill_remaining(), GameState.SHOP_REFILL_SECONDS - 60.0, 0.01,
			"全局补货倒计时保留")


## v6 老档没有货架字段：读档后应当满架，而不是「什么都买不到」
func test_old_v6_save_is_rejected() -> void:
	var data := GameState.to_dict()
	data["version"] = 6
	assert_false(GameState.restore_from_dict(data), "v18 起不再读取 v6 存档")


## 老档的补货是「每个 key 一个倒计时」，迁移成全局一份时取还在走的最长那条
func test_old_per_key_refill_migrates_to_the_longest_wait() -> void:
	var data := GameState.to_dict()
	data["shop_stock"] = {BEAN: 0, BUTTER: 3}
	data["shop_refill"] = {BEAN: 120.0, BUTTER: 30.0}
	data.erase("shop_refill_remaining")
	assert_true(GameState.restore_from_dict(data), "带老补货字段的档应能读")
	assert_eq(GameState.get_shop_stock(BEAN), 0)
	assert_eq(GameState.get_shop_stock(BUTTER), 3)
	assert_almost_eq(GameState.get_shop_refill_remaining(), 120.0, 0.01, "取最长的那条")


## §3：上限只挡自动累积，配方产出与商人买入可以顶破它
func test_upper_cap_only_stops_passive_accrual() -> void:
	# 上限挂在仓库设施等级上，这里借咖啡豆的 1 级容量来测
	var cap := GameState.get_material_cap(BEAN)
	GameState.add_item(BEAN, cap + 20)
	assert_gt(GameState.get_amount(BEAN), cap, "先把库存推到上限之上")
	GameState.advance(600.0)
	assert_eq(GameState.get_amount(BEAN), cap + 20, "涓流在上限之上不会再涨，也不会被削")

	GameState.add_coins(1000, "测试")
	var before := GameState.get_amount(BEAN)
	assert_true(GameState.buy_material(BEAN, 1), "买入不设上限")
	assert_eq(GameState.get_amount(BEAN), before + 1, "买到的材料照常入库")
