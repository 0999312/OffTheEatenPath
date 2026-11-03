extends GutTest
## P3 状态层扩展：存档往返、离线结算、商人购买。

const COFFEE_BEAN := "game:item/coffee_bean"
const COFFEE_GROUND := "game:item/coffee_ground"
const MAILBOX := "game:harvest/mailbox"
const AMERICANO := "game:recipe/americano"
const AMERICANO_FOOD := "game:item/americano"
const TMP_DIR := "res://tests/tmp"
const TMP_SAVE := "res://tests/tmp/test_save.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GameState.reset()
	# 存档用例比较的是「存取是否一致」，先把图鉴里程碑顶满，免得过程中跨档 +20 干扰金额
	GameState.set("_milestone_tier", GameState.get_milestone_targets().size())


func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))


# --- 存档 -----------------------------------------------------------------


func test_save_round_trip_restores_state() -> void:
	GameState.add_coins(120, "测试")
	GameState.add_item(COFFEE_BEAN, 7)
	# 下面读「窗边」会再收下信里的 5 颗咖啡生豆，所以库存最终是 12
	GameState.add_item(AMERICANO_FOOD, 2)
	GameState.add_item(COFFEE_GROUND, 3)
	# 咖啡机 P10.8 起要等信才进厨房；这里只测存档，直接把它摆成 1 级
	GameState.set("_facility_levels", {"game:facility/coffee_machine": 1})
	GameState.start_craft("game:recipe/espresso")
	GameState.mark_letter_read("game:letter/window")
	var saved := GameState.to_dict()

	GameState.reset()
	assert_eq(GameState.coins, 0, "reset 后应清空")

	assert_true(GameState.restore_from_dict(saved), "同版本应能恢复")
	assert_eq(GameState.coins, 120)
	assert_eq(GameState.get_amount(COFFEE_BEAN), 12, "读信礼物也应随存档恢复")
	assert_eq(GameState.get_amount(AMERICANO_FOOD), 2)
	assert_true(GameState.is_discovered(AMERICANO_FOOD), "图鉴状态应恢复")
	assert_true(GameState.is_letter_read("game:letter/window"), "已读状态应恢复")
	assert_eq(GameState.get_jobs().size(), 1, "进行中的制作任务应原样恢复")


func test_restore_rejects_wrong_version() -> void:
	var data := GameState.to_dict()
	data["version"] = 99
	assert_false(GameState.restore_from_dict(data), "版本不符应拒绝恢复")


## v10 起物品键统一成 item/，还带着 food/、material/ 路径的旧档一律拒绝。
## 前缀在这里拼出来，免得以后又做一次全量替换时把这份「不兼容名单」顺手改掉。
func test_restore_rejects_pre_v10_keys() -> void:
	var data := GameState.to_dict()
	data["version"] = GameState.SAVE_VERSION
	var legacy := "%s:%s" % [GameDef.DEFAULT_NAMESPACE, "food/espresso"]
	data["stock"] = {legacy: 3}
	assert_false(GameState.restore_from_dict(data), "库存里带旧键应拒绝恢复")

	data["stock"] = {}
	data["discovered"] = [legacy]
	assert_false(GameState.restore_from_dict(data), "图鉴里的旧键同样要拒绝")

	data["discovered"] = []
	assert_true(GameState.restore_from_dict(data), "清掉旧键之后应能恢复")


func test_save_game_writes_and_reads_file() -> void:
	var saver := SaveGame.new(TMP_SAVE)
	assert_false(saver.exists(), "开始时没有存档")
	assert_eq(saver.load_state(), {}, "没有存档时读到空字典")

	GameState.add_coins(40, "测试")
	GameState.add_item(COFFEE_BEAN, 3.0)
	assert_eq(saver.save_state(GameState.to_dict()), OK, "写盘应成功")
	assert_true(saver.exists())

	var loaded := saver.load_state()
	assert_false(loaded.is_empty(), "读回不应为空")
	GameState.reset()
	assert_true(GameState.restore_from_dict(loaded), "读回的存档应能恢复")
	assert_eq(GameState.coins, 40)
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 3.0, 0.0001)


func test_save_game_ignores_corrupted_file() -> void:
	var file := FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string("{ 这不是 JSON")
		file.close()
	var saver := SaveGame.new(TMP_SAVE)
	assert_eq(saver.load_state(), {}, "损坏的存档按空处理，不崩")


func test_save_game_preserves_unreadable_old_file() -> void:
	var saver := SaveGame.new(TMP_SAVE)
	GameState.add_coins(7, "测试")
	assert_eq(saver.save_state(GameState.to_dict()), OK, "先写一份档")
	var kept := saver.preserve("v17")
	assert_ne(kept, "", "主档存在时应另存成功")
	assert_true(FileAccess.file_exists(kept), "副本要真的落盘")
	var kept_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(kept))
	assert_true(kept_data is Dictionary, "副本仍是合法 JSON")
	assert_eq(int((kept_data as Dictionary).get("version", 0)), GameState.SAVE_VERSION, "副本保留版本号")
	assert_eq(saver.load_state().get("version", 0), GameState.SAVE_VERSION, "主档不受影响")
	var second := saver.preserve("v17")
	assert_ne(second, kept, "同名副本已存在时顺延序号，不覆盖上一份")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kept))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second))


# --- 离线 -----------------------------------------------------------------


func test_offline_summary_reports_gains() -> void:
	GameState.offline_unlocked = true
	# 第九轮：离线按等级每小时 1 份，1 级也有产出；升到 2 级验证份数翻倍
	GameState.add_coins(100, "test")
	assert_true(GameState.upgrade_harvest(MAILBOX), "采集点应能升到 2 级")
	var summary := GameState.apply_offline(3600.0)
	assert_almost_eq(summary.elapsed_seconds, 3600.0, 0.001)
	assert_true(summary.offline_unlocked, "已解锁时摘要标记为已解锁")
	assert_true(summary.has_gains(), "一小时应产出基础材料")
	# 采集点按标签随机出货，所以只看「进的都是杂货、总量对得上」
	var pool: Array[String] = []
	for item in GameState.harvest_pool(GameState.get_harvest_def(MAILBOX)):
		pool.append(item.get_key())
	var total := 0
	for gain in summary.gains:
		var key := String(gain["key"])
		assert_true(pool.has(key), "%s 应在杂货池里" % key)
		total += int(gain["delta"])
	assert_almost_eq(float(total), 2.0, 0.5, "2 级采集点离线每小时 2 份")
	assert_true(summary.is_meaningful(), "一小时且有产出应弹结算")


func test_offline_summary_is_silent_before_unlock() -> void:
	GameState.add_coins(100, "测试")
	assert_true(GameState.upgrade_harvest(MAILBOX), "采集点应先升级")
	GameState.set("_facility_levels", {"game:facility/coffee_machine": 1})
	GameState.add_item(COFFEE_GROUND, 1)
	assert_true(GameState.start_craft("game:recipe/espresso"), "制作应能开始")
	var before_stock := GameState._stock.duplicate()
	var coins_before := GameState.coins
	var summary := GameState.apply_offline(7200.0)
	assert_false(summary.offline_unlocked, "没解锁离线")
	assert_false(summary.is_meaningful(), "未解锁时不该弹结算面板")
	assert_eq(summary.gains.size(), 0, "未解锁时离线不产材料")
	assert_eq(GameState.coins, coins_before, "未解锁时离线不发小费")
	assert_eq(GameState.get_jobs().size(), 1, "未解锁时离线不做完制作")
	for key in before_stock:
		assert_eq(GameState.get_amount(String(key)), int(before_stock[key]), "%s 不该变多" % key)


func test_offline_summary_ignores_short_away() -> void:
	GameState.offline_unlocked = true
	var summary := GameState.apply_offline(5.0)
	assert_false(summary.is_meaningful(), "离开不到一分钟不该打扰")


func test_offline_text_is_chinese() -> void:
	var summary := OfflineSummary.new()
	summary.elapsed_seconds = 3.0 * 3600.0 + 12.0 * 60.0
	assert_eq(summary.elapsed_text(), "3 小时 12 分")
	summary.elapsed_seconds = 90.0
	assert_eq(summary.elapsed_text(), "1 分")


func _find_gain(summary: OfflineSummary, key: String) -> Variant:
	for gain in summary.gains:
		if String(gain["key"]) == key:
			return gain
	return null


# --- 商人 -----------------------------------------------------------------


func test_buy_material_spends_coins_and_adds_stock() -> void:
	var price := 0
	var def := (RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry).get_def(COFFEE_BEAN) as ItemDef
	assert_not_null(def)
	if def != null:
		price = def.merchant_price
	GameState.add_coins(price * 3, "测试")
	assert_true(GameState.buy_material(COFFEE_BEAN, 3), "钱够应能买")
	assert_eq(GameState.coins, 0, "买完应该正好花光")
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 3.0, 0.0001)


func test_buy_material_rejects_without_coins() -> void:
	assert_false(GameState.buy_material(COFFEE_BEAN, 1), "没钱不能买")
	assert_eq(GameState.get_amount(COFFEE_BEAN), 0.0)


func test_free_water_cannot_be_bought() -> void:
	GameState.add_coins(1000, "测试")
	assert_false(GameState.buy_material("game:item/water", 1), "水是免费的，不该出现在货架上")


func test_unknown_material_cannot_be_bought() -> void:
	GameState.add_coins(1000, "测试")
	assert_false(GameState.buy_material("game:item/nope", 1))
