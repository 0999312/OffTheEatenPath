extends GutTest
## 存档版本 v18：R14 起委托语义与任务种类换过，v17 及更早直接拒绝。

const ESPRESSO := "game:item/espresso"
const CAKE := "game:item/cake"


func before_each() -> void:
	GameState.reset()


func test_v18_round_trip_keeps_new_fields() -> void:
	GameState.discover(ESPRESSO)
	GameState.advance_tutorial()
	var data := GameState.to_dict()
	assert_eq(int(data.get("version", 0)), 18, "存档版本应升到 18")
	assert_false(data.has("task_credit"), "v18 不再写旧档冻结字段")
	assert_true(GameState.restore_from_dict(data), "v18 应能读回")
	assert_eq(GameState.get_newest_discovered_key(), ESPRESSO, "最新发现应保留")
	assert_eq(GameState.get_discovery_index(ESPRESSO), GameState._discovery_order.size() - 1)
	assert_eq(GameState.get_tutorial_step(), 1, "引导进度应随存档")
	assert_false(GameState.is_tutorial_done(), "还没走完的引导不该被标成完成")


## 游戏时长只算在线推进，并随存档往返；离线结算不能把它灌成几小时
func test_play_seconds_counts_online_time_and_survives_save() -> void:
	GameState.advance(65.0)
	GameState.advance(3600.0, true)
	assert_eq(GameState.get_play_seconds(), 65, "离线一小时不进入本局时长")
	var data := GameState.to_dict()
	assert_eq(float(data.get("play_seconds", -1.0)), 65.0, "存档应带累计时长")
	GameState.reset()
	assert_eq(GameState.get_play_seconds(), 0, "新档从零开始")
	assert_true(GameState.restore_from_dict(data), "v18 应能读回时长")
	assert_eq(GameState.get_play_seconds(), 65, "读档应恢复累计时长")


func test_v17_save_is_rejected() -> void:
	var data := GameState.to_dict()
	data["version"] = 17
	assert_false(GameState.restore_from_dict(data), "v17 及更早的存档不再兼容")


func test_fresh_save_starts_tutorial_from_zero() -> void:
	assert_eq(GameState.get_tutorial_step(), 0, "新档从第一步开始")
	assert_false(GameState.is_tutorial_done(), "新档要显示引导")
	assert_eq(GameState._discovery_order.size(), GameState.get_discovered_keys().size(),
			"开局已知的设备与世界也要有先后")


func test_skip_tutorial_is_persisted() -> void:
	GameState.skip_tutorial()
	assert_eq(GameState.get_tutorial_step(), 4, "跳过等于直接走到最后一步")
	assert_true(GameState.is_tutorial_done(), "跳过即完成")
	var data := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "应能读回")
	assert_true(GameState.is_tutorial_done(), "重开游戏不该再出现引导")


func test_catalog_new_keys_snapshot_before_mark_seen() -> void:
	GameState.discover(ESPRESSO)
	GameState.discover(CAKE)
	var fresh := GameState.get_new_catalog_keys()
	assert_eq(fresh.size(), 2, "两条新发现都该进红点名单")
	assert_eq(fresh[0], CAKE, "最近发现的排在最前")
	GameState.mark_catalog_seen()
	assert_eq(GameState.get_catalog_new_count(), 0, "打开图鉴后红点收起")
	assert_eq(GameState.get_new_catalog_keys().size(), 0, "已看过的条目不再标红")
	assert_eq(fresh.size(), 2, "打开前抓的快照仍可用于本轮行红点")
