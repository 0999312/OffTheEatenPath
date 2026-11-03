extends GutTest
## 采集点（v5.3）：一处产地管一类货，按标签收池、随机出货。
##
## 采集点参数都在 HarvestDef 里（`resources/game_data/harvest/`），
## 这里测的是 GameState 上的状态机：池子随等级长、成熟/冷却/满仓三态、升级扣费、存档往返。

const MAILBOX := "game:harvest/mailbox"
const FARM := "game:harvest/farm"
const SEA := "game:harvest/sea"
const TAG_PANTRY := "game:tag/pantry"
const TMP_DIR := "res://tests/tmp"
const TMP_SAVE := "res://tests/tmp/test_harvest.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GameState.reset()


func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))


## 测试里把一封信直接置为「已解锁并读过」：农田挂第一站到站信，正常流程要推进到那时
func _read_letter(letter_key: String) -> void:
	var unlocked: Array[String] = GameState.get_unlocked_letters()
	unlocked.append(letter_key)
	GameState.set("_unlocked_letters", unlocked)
	GameState.mark_letter_read(letter_key)


## 池子里每一样当前的数量
func _amounts(harvest_key: String) -> Dictionary:
	var amounts: Dictionary = {}
	var harvest := GameState.get_harvest_def(harvest_key)
	for item in GameState.harvest_pool(harvest):
		amounts[item.get_key()] = GameState.get_amount(item.get_key())
	return amounts


func _pool_keys(harvest_key: String) -> Array[String]:
	var keys: Array[String] = []
	var harvest := GameState.get_harvest_def(harvest_key)
	for item in GameState.harvest_pool(harvest):
		keys.append(item.get_key())
	keys.sort()
	return keys


func test_five_points_cover_five_kinds_of_material() -> void:
	var points := GameState.get_harvest_points()
	assert_eq(points.size(), 5, "信箱、农田、果园、海产、牧场五个产地")
	var tags: Array[String] = []
	for harvest in points:
		tags.append(harvest.tag)
	tags.sort()
	assert_eq(tags, ["game:tag/fruit", "game:tag/livestock", "game:tag/pantry", "game:tag/seafood", "game:tag/veg"] as Array[String],
		"五个产地各管一类材料")
	for harvest in points:
		assert_true(harvest.max_level() == 5, "%s 是五级升级线" % harvest.get_key())


func test_pool_holds_only_tagged_materials() -> void:
	var harvest := GameState.get_harvest_def(MAILBOX)
	var pool := GameState.harvest_pool(harvest)
	assert_gt(pool.size(), 0, "杂货池不该是空的")
	for item in pool:
		assert_true(item.is_material(), "%s 应是材料" % item.get_key())
		assert_true(item.tags.has(TAG_PANTRY), "%s 应挂着杂货标签" % item.get_key())


func test_pool_grows_with_level() -> void:
	# 农田挂第一站到站信（决策 2026-10-28 D6），升级前先读掉
	_read_letter("game:letter/east_asia_arrive")
	GameState.add_coins(10000, "test")
	GameState.add_item("game:item/potato", 500)
	var level_one := _pool_keys(FARM)
	for _index in 2:
		assert_true(GameState.upgrade_harvest(FARM), "农田升到 %d 级" % (GameState.get_harvest_level(FARM) + 1))
	var level_three := _pool_keys(FARM)
	assert_gt(level_three.size(), level_one.size(), "等级越高，池子里能出现的东西越多")
	for key in level_one:
		assert_true(level_three.has(key), "%s 不该因为升级被挤出去" % key)


func test_harvest_gives_one_member_of_the_pool() -> void:
	assert_true(GameState.is_harvest_ready(MAILBOX), "开局就是成熟的")
	var before := _amounts(MAILBOX)
	assert_true(GameState.harvest(MAILBOX), "点一下应采到东西")
	var gained := 0
	var current := _amounts(MAILBOX)
	for key in current:
		gained += int(current[key]) - int(before[key])
	assert_eq(gained, 1, "Lv1 每次 1 份，且落在池子里的某一样上")
	assert_false(GameState.is_harvest_ready(MAILBOX), "采完进入冷却")
	assert_almost_eq(GameState.get_harvest_cooldown_left(MAILBOX), 45.0, 0.001, "Lv1 冷却 45 秒")
	assert_false(GameState.harvest(MAILBOX), "冷却中采不了")


func test_cooldown_recovers_with_world_time() -> void:
	GameState.harvest(MAILBOX)
	GameState.advance(20.0)
	assert_almost_eq(GameState.get_harvest_cooldown_left(MAILBOX), 25.0, 0.001, "冷却按世界时间走")
	GameState.advance(25.0)
	assert_true(GameState.is_harvest_ready(MAILBOX), "到了就重新成熟")
	assert_true(GameState.harvest(MAILBOX), "成熟后又能采")


func test_full_point_is_not_harvestable() -> void:
	var cap := GameState.get_harvest_cap(MAILBOX)
	assert_eq(cap, GameState.get_warehouse_cap_common(), "单样上限归仓库管：1 级常见料 20")
	# 满仓按「池子里每一样都到上限」算：只堆满一样还不算满
	var pool := GameState.harvest_pool(GameState.get_harvest_def(MAILBOX))
	GameState.add_item(pool[0].get_key(), cap)
	if pool.size() > 1:
		assert_false(GameState.is_harvest_full(MAILBOX), "还有别的空着就不算满")
	for item in pool:
		GameState.add_item(item.get_key(), cap)
	assert_true(GameState.is_harvest_full(MAILBOX), "全到上限才算满仓")
	assert_false(GameState.harvest(MAILBOX), "满仓时点不动")


func test_upgrade_costs_coins_and_any_material_of_the_tag() -> void:
	GameState.add_coins(1000, "test")
	assert_true(GameState.upgrade_harvest(MAILBOX), "升到 2 级不要材料")
	assert_eq(GameState.get_harvest_level(MAILBOX), 2)
	assert_eq(GameState.coins, 960, "扣 40 币")
	assert_almost_eq(GameState.get_harvest_cooldown_left(MAILBOX), 0.0, 0.001, "升级不重置冷却")
	# 3 级要 120 币 + 3 份「任意杂货」：给两样不一样的，看它先扣哪样
	GameState.add_item("game:item/salt", 1)
	GameState.add_item("game:item/sugar", 2)
	assert_true(GameState.upgrade_harvest(MAILBOX), "升到 3 级")
	assert_eq(GameState.coins, 840, "扣 120 币")
	assert_eq(GameState.get_amount("game:item/salt"), 0, "先扣持有量最少的")
	assert_eq(GameState.get_amount("game:item/sugar"), 0, "两样合计 3 份就够了")


func test_upgrade_refused_without_enough_coins_or_material() -> void:
	assert_false(GameState.upgrade_harvest(MAILBOX), "没钱不能升")
	GameState.add_coins(1000, "test")
	GameState.add_item("game:item/salt", 1)
	assert_true(GameState.upgrade_harvest(MAILBOX), "2 级不看材料")
	assert_false(GameState.upgrade_harvest(MAILBOX), "3 级要 3 份，只有 1 份不够")
	assert_eq(GameState.get_harvest_level(MAILBOX), 2, "失败的升级不扣级")
	# 标签之外的料不算数
	GameState.add_item("game:item/pork", 10)
	assert_false(GameState.upgrade_harvest(MAILBOX), "猪肉不在杂货标签下，不能拿来交")


func test_level_five_is_the_cap() -> void:
	GameState.add_coins(10000, "test")
	GameState.add_item("game:item/salt", 500)
	for i in 4:
		assert_true(GameState.upgrade_harvest(MAILBOX), "第 %d 次升级应成功" % (i + 2))
	assert_eq(GameState.get_harvest_level(MAILBOX), 5, "封顶 5 级")
	assert_false(GameState.upgrade_harvest(MAILBOX), "满级后升不动")
	assert_eq(GameState.get_harvest_cap(MAILBOX), GameState.get_warehouse_cap_common(), "产地升级只管冷却与产量，容量仍归仓库")
	assert_almost_eq(GameState.get_harvest_cooldown_left(MAILBOX), 0.0, 0.001)


func test_unlock_follows_the_facility_level() -> void:
	var sea := GameState.get_harvest_def(SEA)
	assert_not_null(sea, "海产有定义")
	assert_false(GameState.is_harvest_unlocked(sea), "灶台 1 级时海产还不该出现")
	assert_false(GameState.harvest(SEA), "锁着的采集点采不到东西")
	var farm := GameState.get_harvest_def(FARM)
	assert_false(GameState.is_harvest_unlocked(farm), "农田要等第一站到站信")
	assert_false(GameState.harvest(FARM), "没到站之前农田点不动")
	_read_letter("game:letter/east_asia_arrive")
	assert_true(GameState.is_harvest_unlocked(farm), "读完第一站信农田才出现")
	assert_true(GameState.harvest(FARM), "解锁之后农田能采")


func test_save_round_trip_keeps_harvest_state() -> void:
	GameState.add_coins(1000, "test")
	GameState.upgrade_harvest(MAILBOX)
	GameState.harvest(MAILBOX)
	var saver := SaveGame.new(TMP_SAVE)
	assert_eq(saver.save_state(GameState.to_dict()), OK, "写盘应成功")
	GameState.reset()
	var loaded := saver.load_state()
	assert_true(GameState.restore_from_dict(loaded), "读档应成功")
	assert_eq(GameState.get_harvest_level(MAILBOX), 2, "采集点等级要存下来")
	assert_gt(GameState.get_harvest_cooldown_left(MAILBOX), 0.0, "冷却剩余也要存下来")


func test_old_save_before_v18_is_rejected() -> void:
	var data := GameState.to_dict()
	data["version"] = 5
	assert_false(GameState.restore_from_dict(data), "v18 起不再读取 v17 及更早的存档")


func test_material_keys_in_old_saves_are_ignored() -> void:
	var data := GameState.to_dict()
	# 采集点改按标签收池之前，等级是按材料键存的；这些键现在对不上了，直接丢掉
	data["harvest_levels"] = {"game:item/coffee_bean": 5}
	data["harvest_cooldowns"] = {"game:item/coffee_bean": 30.0}
	assert_true(GameState.restore_from_dict(data), "这种档也该读得进来")
	assert_eq(GameState.get_harvest_level(MAILBOX), 1, "材料键不再当成采集点键")
	assert_almost_eq(GameState.get_harvest_cooldown_left(MAILBOX), 0.0, 0.001, "冷却也不认材料键")


func test_offline_pays_the_passive_yield() -> void:
	GameState.offline_unlocked = true
	GameState.harvest(MAILBOX)
	var before := _amounts(MAILBOX)
	GameState.apply_offline(3600.0)
	# 第九轮：离线改成按采集点等级发被动收成（1 级每小时 1 份），
	# 但不会替玩家手采；冷却照走，回来时采集点是成熟的。
	var after := _amounts(MAILBOX)
	var gained := 0
	for key in after:
		gained += int(after[key]) - int(before.get(key, 0))
	assert_eq(gained, 1, "1 级采集点离线每小时 1 份")
	assert_true(GameState.is_harvest_ready(MAILBOX), "离线回来采集点是成熟的")


## 第十轮反馈 4：在线取消涓流——材料只在玩家点采集点时到手，
## 站十分钟不该自己长东西（离线收货走 apply_offline，不在此列）。
func test_online_advance_no_longer_trickles_materials() -> void:
	GameState.add_coins(1000, "test")
	GameState.add_item("game:item/salt", 10)
	assert_true(GameState.upgrade_harvest(MAILBOX), "升到 2 级")
	var before := _amounts(MAILBOX)
	GameState.advance(600.0)
	var after := _amounts(MAILBOX)
	var gained := 0
	for key in after:
		gained += int(after[key]) - int(before[key])
	assert_eq(gained, 0, "在线十分钟不该自己长材料")

## 界面现在按品种报「采到了什么」（用户反馈「采集只写了数量，没有种类」）
func test_harvest_with_result_reports_what_you_got() -> void:
	var expected := GameState.harvest_yield(MAILBOX)
	var gained := GameState.harvest_with_result(MAILBOX)
	assert_false(gained.is_empty(), "成熟了就该采到东西")
	var total := 0
	for key in gained:
		var item_key := String(key)
		total += int(gained[key])
		assert_gt(int(gained[key]), 0, "份数为正：%s" % item_key)
		assert_true(_pool_keys(MAILBOX).has(item_key), "采到的必须是池子里有的：%s" % item_key)
	assert_eq(total, expected, "一份不少、也不多给")


func test_harvest_keeps_the_bool_interface() -> void:
	assert_true(GameState.harvest(MAILBOX), "老接口仍返回 true")
	assert_false(GameState.harvest(MAILBOX), "冷却中返回 false")
	assert_true(GameState.harvest_with_result(MAILBOX).is_empty(), "采不到时明细是空的")

