extends GutTest
## P2 状态与循环：材料累积、制作、库存与消耗、铜币、设备、图鉴、信件。

const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
const AMERICANO := "game:recipe/americano"
const LATTE := "game:recipe/latte"
const ESPRESSO := "game:recipe/espresso"
const ESPRESSO_FOOD := "game:item/espresso"
const AMERICANO_FOOD := "game:item/americano"
const COFFEE_BEAN := "game:item/coffee_bean"
const COFFEE_GROUND := "game:item/coffee_ground"
const MILK := "game:item/milk"
const COFFEE_MACHINE := "game:facility/coffee_machine"
const MAILBOX := "game:harvest/mailbox"

var _received: Array[Event] = []


func before_each() -> void:
	_received.clear()
	assert_not_null(GameState, "GameState 应作为 autoload 存在")
	GameState.reset()
	# 这一组用例算的是制作与设备本身的钱；图鉴里程碑另有专门用例覆盖，
	# 先把档位顶满，免得「发现一条 +20 铜币」混进金额断言。
	GameState.set("_milestone_tier", GameState.get_milestone_targets().size())


func after_each() -> void:
	EventBus.unsubscribe(&"MaterialChangedEvent", _on_event)
	EventBus.unsubscribe(&"CraftCompletedEvent", _on_event)
	EventBus.unsubscribe(&"CoinChangedEvent", _on_event)


## 杂货池里所有材料的总量（涓流随机落到池子里的某一样上，只能看总量）
func _pantry_total() -> int:
	var total := 0
	for item in GameState.harvest_pool(GameState.get_harvest_def(MAILBOX)):
		total += GameState.get_amount(item.get_key())
	return total


func _on_event(event: Event) -> void:
	_received.append(event)


func _count_events(event_class: String) -> int:
	var count := 0
	for event in _received:
		if event.get_script().get_global_name() == event_class:
			count += 1
	return count


func _first_event(event_class: String) -> Event:
	for event in _received:
		if event.get_script().get_global_name() == event_class:
			return event
	return null


## 拿铁默认要「研究组合」试出来（见 docs/decisions/2026-10-24-research-combos.md）。
## 这里走玩家真正会走的那条路：备料 → 放上研究台 → 等 2 秒 → 解锁。
func _unlock_latte() -> void:
	# 备足：研究可能因概率多扣 1 份；拿铁要浓缩 1 + 奶 2，奶得多留一份
	GameState.add_item(ESPRESSO_FOOD, 3.0)
	GameState.add_item(MILK, 4.0)
	assert_true(GameState.start_research([ESPRESSO_FOOD, MILK]), "浓缩 + 牛奶应能放上研究台")
	GameState.advance(20.0)
	assert_true(GameState.is_recipe_unlocked(LATTE), "试对了就该解锁拿铁")


## 美式第六轮起在研究菜单里（需要研究解锁）。这一组用例算的是制作流程本身，
## 研究怎么试另有 test_research；这里直接把它解锁，等同于「已经研究出来」。
func _unlock_americano() -> void:
	var data := RegistryManager.get_registry(DATA_REGISTRY_KEY) as DataRegistry
	assert_not_null(data, "DataRegistry 未就绪")
	GameState._unlock_recipe(data.get_def(AMERICANO) as RecipeDef)
	assert_true(GameState.is_recipe_unlocked(AMERICANO), "美式应已解锁")


## P10.8 起咖啡机要等第一件委托办妥（第三封信）才进厨房，开局是 0 级。
## 这一组用例算的是制作与设备本身，先把咖啡机摆成 1 级，等同于「窗边之后」的世界。
func _bring_coffee_machine_in() -> void:
	GameState.set("_facility_levels", {COFFEE_MACHINE: 1})
	GameState.discover(COFFEE_MACHINE)


# --- 初始状态 -------------------------------------------------------------


func test_reset_state_is_empty() -> void:
	assert_eq(GameState.coins, 0, "开局没有铜币")
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0.0, "开局没有材料")
	# P10.8 起咖啡机等信才添置：开局是 0 级，既做不了浓缩也不占制作位。
	assert_eq(GameState.get_facility_level(COFFEE_MACHINE), 0, "咖啡机要等第三封信才进厨房")
	assert_eq(GameState.get_jobs().size(), 0, "开局没有进行中的任务")
	assert_false(GameState.offline_unlocked, "开局没有解锁离线")


func test_letters_unlock_in_order_on_reset() -> void:
	var letters := GameState.get_unlocked_letters()
	assert_eq(letters.size(), 1, "目前只有「窗边」这一封是 IMMEDIATE 条件")
	assert_eq(letters[0], "game:letter/window", "第一封应是窗边")
	assert_true(GameState.is_letter_read("game:letter/window") == false, "解锁不等于读过")
	assert_eq(GameState.get_unread_letter_count(), 1)


# --- 材料累积 -------------------------------------------------------------


func test_reading_letter_grants_its_gift_once() -> void:
	# 「窗边」这封信里夹着 5 颗咖啡生豆
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0.0, "读信之前没有这份礼物")
	assert_true(GameState.mark_letter_read("game:letter/window"))
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 5.0, 0.001, "读信时收下信里的东西")
	assert_true(GameState.mark_letter_read("game:letter/window"), "重复读返回 true")
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 5.0, 0.001, "礼物不重复发放")


func test_advance_does_not_grow_materials_at_level_one() -> void:
	# 经济 v2：开局没有任何自动产出，材料只从桌面采集点和商人来
	GameState.advance(600.0)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0, "1 级采集点没有涓流")
	assert_eq(GameState.get_amount(MILK), 0, "1 级采集点没有涓流")
	assert_eq(GameState.get_amount("game:item/water"), 0, "水是免费资源，不累积")
	# 中间材料不该自己长出来
	assert_eq(GameState.get_amount(COFFEE_GROUND), 0)


func test_offline_pays_materials_from_a_level_two_point() -> void:
	GameState.add_coins(100, "test")
	assert_true(GameState.upgrade_harvest(MAILBOX), "杂货信箱应能升到 2 级")
	# 第十轮起在线不再有涓流：材料由离线结算按「每级每小时 1 份」补
	GameState.advance(3600.0, true)
	# Lv2 离线一小时 2 份，落在杂货池里的某一样上（具体哪样是随机的）
	assert_eq(_pantry_total(), 2, "离线一小时，2 级采集点应入库两份")


func test_advance_ignores_non_positive_delta() -> void:
	GameState.advance(0.0)
	GameState.advance(-5.0)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0.0)


func test_offline_harvest_emits_material_changed() -> void:
	EventBus.subscribe(&"MaterialChangedEvent", _on_event)
	GameState.add_coins(100, "test")
	GameState.upgrade_harvest(MAILBOX)
	GameState.advance(3600.0, true)
	var count := _count_events("MaterialChangedEvent")
	assert_gt(count, 0, "离线入库也应广播 MaterialChangedEvent")
	# 离线可能给同一种材料连发两次（第 1 份 / 第 2 份），第一次事件的 "总量" 是 1，
	# 最终库存是 2；取最后一条同键事件才能与最终状态对齐。
	var event: MaterialChangedEvent = null
	for received in _received:
		if received is MaterialChangedEvent:
			event = received as MaterialChangedEvent
	assert_not_null(event)
	if event != null:
		assert_eq(event.amount, GameState.get_amount(event.key), "最后一条事件里的总量应与状态一致")


# --- 制作 -----------------------------------------------------------------


func test_short_recipe_completes_after_advance() -> void:
	_unlock_americano()
	# 经济 v2 落表后美式是 5 秒（原来 0 秒）；「0 秒立刻完成」的分支还留在 start_craft 里做防御
	GameState.add_item(ESPRESSO_FOOD, 1.0)
	assert_true(GameState.start_craft(AMERICANO), "美式现在要等 5 秒")
	assert_eq(GameState.get_jobs().size(), 1, "进队列")
	assert_eq(GameState.get_amount(ESPRESSO_FOOD), 0.0, "输入先扣")
	GameState.advance(5.0)
	assert_eq(GameState.get_amount(AMERICANO_FOOD), 1.0, "产出入库")
	assert_eq(GameState.get_jobs().size(), 0)


## 浓缩是唯一开放批量制作的成品：Lv1 只能 1 份，Lv2 可一次 2 份。
## 批量与槽位独立（D2 B）：Lv2 仍可开 2 个 job，每个 job 最多 2 份。
func test_espresso_batches_follow_coffee_machine_level() -> void:
	_bring_coffee_machine_in()
	GameState.add_item(COFFEE_GROUND, 8.0)
	assert_eq(GameState.max_batches(ESPRESSO), 1, "Lv1 咖啡机只能 1 份")
	assert_true(GameState.start_craft(ESPRESSO, 2), "提交 2 份应被夹到 1 份")
	var first := GameState.get_jobs()[0]
	assert_eq(first.batches, 1, "Lv1 实际只做 1 份")
	assert_almost_eq(first.total_seconds, 20.0 * 0.65, 0.0001, "单份也走批量折扣")
	GameState.advance(first.total_seconds)
	assert_eq(GameState.get_amount(ESPRESSO_FOOD), 1.0)

	var levels := (GameState.get("_facility_levels") as Dictionary).duplicate()
	levels[COFFEE_MACHINE] = 2
	GameState.set("_facility_levels", levels)
	assert_eq(GameState.max_batches(ESPRESSO), 2, "Lv2 可一次 2 份")
	var before_ground := GameState.get_amount(COFFEE_GROUND)
	assert_true(GameState.start_craft(ESPRESSO, 2))
	var second := GameState.get_jobs()[0]
	assert_eq(second.batches, 2, "Lv2 一次 2 份")
	assert_almost_eq(second.total_seconds, 20.0 * 2.0 * 0.65 * 0.8, 0.0001, "时间按份数×折扣×设备速度")
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), before_ground - 2.0, 0.0001, "材料按份数扣")
	GameState.advance(second.total_seconds)
	assert_eq(GameState.get_amount(ESPRESSO_FOOD), 3.0, "先前 1 份 + 这次 2 份")
	assert_eq(GameState.max_batches(AMERICANO), 1, "其他成品菜不做批量")


## R18 反馈 2：成品食物仍要发同一个事件，并标 is_food=true / first_time 状态；
## 这样 GameBridge 才能在同一个入口里决定「响 + 弹 toast」。
func test_food_completion_emits_craft_completed_as_food() -> void:
	EventBus.subscribe(&"CraftCompletedEvent", _on_event)
	_unlock_americano()
	GameState.add_item(ESPRESSO_FOOD, 1.0)
	assert_true(GameState.start_craft(AMERICANO))
	GameState.advance(5.0)
	assert_eq(_count_events("CraftCompletedEvent"), 1, "成品完成应发一次事件")
	var event := _first_event("CraftCompletedEvent") as CraftCompletedEvent
	assert_not_null(event)
	if event != null:
		assert_eq(event.output_key, AMERICANO_FOOD)
		assert_true(event.is_food, "成品食物应标 is_food")
		assert_true(event.first_time, "第一次做美式应标 first_time")


## R18 反馈 2：半成品（奶油）做完也要发 CraftCompletedEvent，让 GameBridge 响完成音；
## 事件带 is_food=false，toast 与首次制作仍只属于成品食物。
func test_intermediate_completion_emits_craft_completed() -> void:
	EventBus.subscribe(&"CraftCompletedEvent", _on_event)
	GameState.add_item(MILK, 2.0)
	assert_true(GameState.start_craft("game:recipe/cream"), "奶油配方应能开做")
	GameState.advance(15.0)
	assert_eq(GameState.get_amount("game:item/cream"), 1.0, "奶油应入库")
	assert_eq(_count_events("CraftCompletedEvent"), 1, "半成品完成也应发一次事件")
	var event := _first_event("CraftCompletedEvent") as CraftCompletedEvent
	assert_not_null(event)
	if event != null:
		assert_eq(event.output_key, "game:item/cream")
		assert_false(event.is_food, "奶油不是成品食物")
		assert_false(event.first_time, "半成品没有首次制作奖励")


func test_first_food_gives_coins_once() -> void:
	_unlock_americano()
	GameState.add_item(ESPRESSO_FOOD, 2.0)
	assert_true(GameState.start_craft(AMERICANO))
	GameState.advance(5.0)
	assert_eq(GameState.coins, 5, "首次做出美式 +5 铜币")
	assert_true(GameState.start_craft(AMERICANO))
	GameState.advance(5.0)
	assert_eq(GameState.coins, 5, "再做一份不再给铜币")


func test_craft_fails_without_inputs() -> void:
	_unlock_americano()
	assert_false(GameState.start_craft(AMERICANO), "没有浓缩做不了美式")
	assert_eq(GameState.get_amount(AMERICANO_FOOD), 0.0)


func test_timed_recipe_runs_through_advance() -> void:
	_unlock_latte()
	var left := GameState.get_amount(ESPRESSO_FOOD)
	assert_true(left >= 1.0, "研究成了要付学费，但还留得下做一杯")
	assert_true(GameState.get_amount(MILK) >= 1.0, "牛奶同样留下了至少一份")
	assert_true(GameState.start_craft(LATTE), "拿铁 20 秒应进入队列")
	assert_eq(GameState.get_jobs().size(), 1)
	assert_almost_eq(GameState.get_amount(ESPRESSO_FOOD), left - 1.0, 0.0001, "开始制作即扣材料")
	assert_eq(GameState.get_amount("game:item/latte"), 0.0, "还没做好")
	GameState.advance(20.0)
	assert_eq(GameState.get_jobs().size(), 0, "20 秒后完成")
	assert_eq(GameState.get_amount("game:item/latte"), 1.0, "产出入库")


func test_facility_limits_parallel_jobs() -> void:
	_bring_coffee_machine_in()
	GameState.add_item(COFFEE_GROUND, 2.0)
	assert_true(GameState.start_craft(ESPRESSO), "咖啡机 1 级可开第 1 个")
	assert_false(GameState.start_craft(ESPRESSO), "咖啡机 1 级只有一个位，第 2 个应被拒")
	assert_eq(GameState.get_jobs().size(), 1)
	assert_eq(GameState.get_amount(COFFEE_GROUND), 1.0, "被拒的任务不扣材料")


func test_hand_made_recipes_use_single_slot() -> void:
	_unlock_latte()
	GameState.add_item(ESPRESSO_FOOD, 2.0)
	GameState.add_item(MILK, 4.0)
	assert_true(GameState.start_craft(LATTE))
	assert_false(GameState.start_craft(LATTE), "手作只有一双手")
	GameState.advance(20.0)
	assert_true(GameState.start_craft(LATTE), "做完后手又空出来了")


# --- 图鉴 -----------------------------------------------------------------


func test_food_discovery_emits_event() -> void:
	_unlock_americano()
	assert_false(GameState.is_discovered(AMERICANO_FOOD))
	GameState.add_item(ESPRESSO_FOOD, 1.0)
	assert_true(GameState.is_discovered(ESPRESSO_FOOD), "食物一入库就进图鉴")
	assert_false(GameState.is_discovered(AMERICANO_FOOD))
	GameState.start_craft(AMERICANO)
	GameState.advance(5.0)
	assert_true(GameState.is_discovered(AMERICANO_FOOD))
	assert_false(GameState.is_discovered("game:facility/coffee_machine"), "咖啡机还没送到，不算已知")
	assert_true(GameState.is_discovered("game:facility/oven"), "桌上的设备一开始就在房间里，属于已知")
	assert_true(GameState.is_discovered("game:world/room"), "车厢一开始就是已知的")
	assert_true(GameState.is_discovered("game:world/nearby"), "门口那一小片一开始就是已知的")
	assert_false(GameState.is_discovered("game:world/cafe"), "车身写的是什么，要出发那封信才揭开")


func test_free_water_never_needs_stock() -> void:
	_bring_coffee_machine_in()
	GameState.add_item(COFFEE_GROUND, 1.0)
	assert_eq(GameState.get_amount("game:item/water"), 0.0)
	assert_true(GameState.start_craft(ESPRESSO), "水免费，不需要库存也能萃取")


# --- 设备 -----------------------------------------------------------------


func test_facility_upgrade_spends_and_speeds_up() -> void:
	_bring_coffee_machine_in()
	GameState.add_coins(200, "测试")
	GameState.add_item(COFFEE_GROUND, 10.0)  # 2 级升级要 10 份咖啡粉
	var before := GameState.get_speed_factor(COFFEE_MACHINE)
	assert_almost_eq(before, 1.0, 0.0001, "1 级是基准速度")
	assert_true(GameState.upgrade_facility(COFFEE_MACHINE), "铜币与材料充足应能升级")
	assert_eq(GameState.get_facility_level(COFFEE_MACHINE), 2)
	assert_eq(GameState.coins, 140, "2 级升级 60 铜币")
	assert_almost_eq(GameState.get_speed_factor(COFFEE_MACHINE), 0.8, 0.0001)
	assert_lt(GameState.get_speed_factor(COFFEE_MACHINE), before, "升级后更快")


func test_facility_upgrade_blocked_without_coins() -> void:
	_bring_coffee_machine_in()
	GameState.add_item(COFFEE_GROUND, 20.0)
	assert_false(GameState.upgrade_facility(COFFEE_MACHINE), "没钱不能升级")
	assert_eq(GameState.get_facility_level(COFFEE_MACHINE), 1)


func test_facility_upgrade_stops_at_max_level() -> void:
	_bring_coffee_machine_in()
	GameState.add_coins(1000, "测试")
	GameState.add_item(COFFEE_GROUND, 40.0)  # 10 + 25
	assert_true(GameState.upgrade_facility(COFFEE_MACHINE))
	assert_true(GameState.upgrade_facility(COFFEE_MACHINE))
	assert_eq(GameState.get_facility_level(COFFEE_MACHINE), 3, "封顶 3 级")
	assert_false(GameState.upgrade_facility(COFFEE_MACHINE), "3 级后不能再升")


# --- 信件 -----------------------------------------------------------------


func test_reading_letter_marks_it_read() -> void:
	assert_true(GameState.mark_letter_read("game:letter/window"))
	assert_true(GameState.is_letter_read("game:letter/window"))
	# 读掉第一封会让第二封「牛奶商人」解锁，于是又有了 1 封未读
	assert_eq(GameState.get_unread_letter_count(), 1)
	assert_eq(GameState.get_unlocked_letters().size(), 2)
	assert_true(GameState.is_letter_read("game:letter/window"))
	assert_false(GameState.mark_letter_read("game:letter/does_not_exist"), "没解锁的信不能标已读")


# --- 可玩性打磨：连续做与调试解锁 ------------------------------------------


func test_repeat_recipe_queues_another_after_completion() -> void:
	_bring_coffee_machine_in()
	# 用咖啡粉而不是咖啡生豆：生豆会随时间自己长，测不出「材料真的被吃掉」
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.set_repeat_recipe(ESPRESSO)
	assert_eq(GameState.get_repeat_recipe(), ESPRESSO, "应记住连续做的配方")
	assert_true(GameState.start_craft(ESPRESSO), "材料够应能开始")
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 2.0, 0.001)

	# 单份实际耗时 20 × 0.65 = 13 秒；一次结算会把续做的也一路算下去
	GameState.advance(13.5)  # 第一份做完，第二份开上
	assert_eq(GameState.get_jobs().size(), 1, "做完一份应自动续上下一份")
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 1.0, 0.001)

	GameState.advance(13.5)  # 第二份做完，第三份开上，咖啡粉正好用光
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 0.0, 0.001)
	assert_eq(GameState.get_jobs().size(), 1, "最后一份还在做")
	GameState.advance(13.5)  # 第三份做完，材料不够，应安静停下
	assert_eq(GameState.get_jobs().size(), 0, "材料不够时连续做应安静停下")


func test_repeat_recipe_can_be_cancelled() -> void:
	_bring_coffee_machine_in()
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.set_repeat_recipe(ESPRESSO)
	GameState.set_repeat_recipe("")
	assert_eq(GameState.get_repeat_recipe(), "", "传空字符串应取消")
	assert_true(GameState.start_craft(ESPRESSO))
	GameState.advance(20.5)
	assert_eq(GameState.get_jobs().size(), 0, "取消后不再续做")
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 2.0, 0.001)


func test_short_recipe_is_repeated_once_done() -> void:
	_unlock_americano()
	GameState.add_item(ESPRESSO_FOOD, 3.0)
	GameState.set_repeat_recipe(AMERICANO)
	assert_true(GameState.start_craft(AMERICANO))
	GameState.advance(5.0)
	assert_eq(GameState.get_amount(AMERICANO_FOOD), 1.0, "第一份做好")
	assert_eq(GameState.get_jobs().size(), 1, "续做马上又开了一份")
	assert_eq(GameState.get_amount(ESPRESSO_FOOD), 1.0, "只多消耗一份")
	GameState.set_repeat_recipe("")


func test_debug_unlock_offline_only_in_debug_build() -> void:
	assert_false(GameState.offline_unlocked, "初始应锁定")
	GameState.debug_unlock_offline()
	assert_true(GameState.offline_unlocked, "调试构建应能解开离线产出")
