extends GutTest
## 图鉴红点计数与铜板小费：本轮改了两处对外行为，各留一条回归。

const FOOD_KEY := "game:item/espresso"


func before_each() -> void:
	GameState.reset()


func test_catalog_new_count_starts_at_zero() -> void:
	# 开局摆在房间里的设备与世界条目不算「新发现」
	assert_eq(GameState.get_catalog_new_count(), 0, "开局不该亮图鉴红点")


func test_unseen_discovery_lights_dot_until_marked_seen() -> void:
	GameState._discovered[FOOD_KEY] = true
	assert_eq(GameState.get_catalog_new_count(), 1, "新发现一条应亮红点")
	GameState.mark_catalog_seen()
	assert_eq(GameState.get_catalog_new_count(), 0, "打开图鉴后红点收起")


func test_catalog_seen_survives_save_round_trip() -> void:
	GameState._discovered[FOOD_KEY] = true
	GameState.mark_catalog_seen()
	var data := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "存档应能读回")
	assert_eq(GameState.get_catalog_new_count(), 0, "已看数应随存档恢复")


func test_old_save_without_catalog_seen_reads_as_all_seen() -> void:
	GameState._discovered[FOOD_KEY] = true
	var data := GameState.to_dict()
	data.erase("catalog_seen")
	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "老档没有新字段也应能读")
	assert_eq(GameState.get_catalog_new_count(), 0, "老档读进来不该凭空亮红点")


func test_coin_fade_pays_one_coin() -> void:
	var layer := AmbientLayer.new()
	add_child_autofree(layer)
	var before := GameState.coins
	layer._on_trace_faded("coin")
	assert_eq(GameState.coins, before + 1, "铜板淡出时自动收下 1 枚")
	assert_eq(GameState.coins, before + 1, "同一枚只算一次")



func test_coin_clicked_does_not_double_pay() -> void:
	var layer := AmbientLayer.new()
	add_child_autofree(layer)
	var before := GameState.coins
	layer._coin_taken = true
	layer._on_trace_faded("coin")
	assert_eq(GameState.coins, before, "已经被点走的铜板不再结算")
