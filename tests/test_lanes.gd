extends GutTest
## 产线（厨房扩建）与批处理（经济 v2 §5 / §9）。
##
## 产线 = 「一座店同时开几炉」，由厨房等级决定；槽位 = 「同一台设备能开几炉」，
## 由设备等级决定。两者相乘才是玩家真正能并行多少，所以两个限制都要测。

const BEAN := "game:item/coffee_bean"
const ROAST := "game:recipe/roast_bean"
const GRIND := "game:recipe/grind_bean"
const ESPRESSO := "game:recipe/espresso"
## 3 种材料的中间品：旧实现 8/3 会把上限压回 2，用来守「份数不看材料种类」
const SAUSAGE := "game:recipe/sausage"
const TMP_DIR := "res://tests/tmp"
const TMP_SAVE := "res://tests/tmp/test_lanes.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GameState.reset()


func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))


func test_kitchen_starts_with_one_line() -> void:
	assert_eq(GameState.get_kitchen_level(), 1, "开局厨房 Lv1")
	assert_eq(GameState.get_lane_count(), 1, "开局只有一条产线")


func test_second_job_is_blocked_until_the_kitchen_grows() -> void:
	GameState.add_item(BEAN, 10)
	assert_true(GameState.start_craft(ROAST), "第一炉能开")
	assert_false(GameState.start_craft(GRIND), "产线只有一条，第二炉开不了")


func test_expanding_the_kitchen_allows_parallel_jobs() -> void:
	GameState.add_coins(500, "测试")
	assert_true(GameState.upgrade_kitchen(), "有钱就能扩厨房")
	assert_eq(GameState.get_lane_count(), 2, "扩完两条产线")
	GameState.add_item(BEAN, 10)
	GameState.add_item("game:item/roasted_bean", 5)
	assert_true(GameState.start_craft(ROAST), "第一炉")
	assert_true(GameState.start_craft(GRIND), "第二炉能并行了")


func test_kitchen_upgrade_needs_coins_and_stops_at_max() -> void:
	assert_false(GameState.upgrade_kitchen(), "没钱不能扩")
	GameState.add_coins(5000, "测试")
	for i in range(GameState.KITCHEN_MAX_LEVEL - 1):
		assert_true(GameState.upgrade_kitchen(), "第 %d 次扩建" % (i + 1))
	assert_eq(GameState.get_kitchen_level(), GameState.KITCHEN_MAX_LEVEL, "到顶了")
	assert_eq(GameState.get_kitchen_upgrade_cost(), -1, "满级没有下一级花费")
	assert_false(GameState.upgrade_kitchen(), "满级后不能再扩")


func test_facility_slots_still_apply_within_a_line_each() -> void:
	GameState.add_coins(5000, "测试")
	GameState.upgrade_kitchen()
	GameState.add_item(BEAN, 10)
	assert_true(GameState.start_craft(ROAST), "咖啡机线：第一炉")
	assert_false(GameState.start_craft(ROAST), "同一台设备 Lv1 只有一个槽位")


func test_food_recipes_never_batch() -> void:
	assert_eq(GameState.max_batches(ESPRESSO), 1, "成品不做批处理")


func test_intermediate_batches_follow_facility_level() -> void:
	# 烤豆归平底锅（开局 1 级 → 2 份）；手作配方没有设备，同样按 Lv1 算。磨豆归磨豆机：Lv1 → 2 份，Lv2 → 3 份
	assert_eq(GameState.max_batches(ROAST), 2, "手作配方按 Lv1 算，一次 2 份")
	assert_eq(GameState.max_batches(GRIND), 2, "磨豆机 Lv1 一次 2 份")
	GameState.add_coins(1000, "测试")
	GameState.add_item("game:item/roasted_bean", 10)
	assert_true(GameState.upgrade_facility("game:facility/grinder"), "磨豆机要 30 币 + 10 份熟豆")
	assert_eq(GameState.max_batches(GRIND), 3, "磨豆机 Lv2 一次 3 份")
	assert_eq(GameState.max_batches(SAUSAGE), 3, "3 种材料的中间品同样是 3 份（旧实现 8/3 会掉回 2）")
	assert_eq(GameState.BATCH_MAX, 5, "批处理上限 = 设备最高 Lv4 + 1")


func test_batching_consumes_and_yields_in_multiples() -> void:
	# 烤豆一份要 1 颗生豆，两批就是 2 颗
	GameState.add_item(BEAN, 6)
	var before := GameState.get_amount(BEAN)
	assert_true(GameState.start_craft(ROAST, 2), "两批一起做")
	assert_eq(GameState.get_amount(BEAN), before - 2, "原料按份数扣（每份 1 颗）")
	var job: CraftJob = GameState.get_jobs()[0]
	assert_eq(job.batches, 2, "任务记住份数")
	var recipe := GameState.get_jobs()[0]
	# 耗时 = 单份 × 份数 × 0.65
	var recipe_def := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME).get_def(ROAST) as RecipeDef
	var single: float = recipe_def.duration_seconds
	assert_almost_eq(job.total_seconds, single * 2.0 * GameState.BATCH_TIME_FACTOR, 0.01,
			"批量省时间：N 份只要 N×0.65 倍")
	GameState.advance(job.total_seconds + 0.1)
	assert_eq(GameState.get_amount("game:item/roasted_bean"), 2, "一次出 2 份成品")
	assert_eq(recipe.batches, 2, "任务还在（引用没被清）")


func test_batching_requires_materials_for_every_batch() -> void:
	# 1 颗只够一份
	GameState.add_item(BEAN, 1)
	assert_false(GameState.start_craft(ROAST, 2), "只够一份时不能按两份下单")
	assert_eq(GameState.get_jobs().size(), 0, "被拒时不该留下任务")


func test_batches_are_clamped_to_the_limit() -> void:
	GameState.add_item(BEAN, 20)
	assert_true(GameState.start_craft(ROAST, 99), "超量下单按上限收")
	assert_eq(GameState.get_jobs()[0].batches, GameState.max_batches(ROAST), "被夹到上限")


func test_kitchen_and_batches_survive_a_save() -> void:
	GameState.add_coins(5000, "测试")
	GameState.upgrade_kitchen()
	GameState.add_item(BEAN, 4)
	GameState.start_craft(ROAST, 2)
	var saver := SaveGame.new(TMP_SAVE)
	assert_eq(saver.save_state(GameState.to_dict()), OK, "存档应成功")
	GameState.reset()
	assert_true(GameState.restore_from_dict(saver.load_state()), "读档应成功")
	assert_eq(GameState.get_kitchen_level(), 2, "厨房等级保留")
	assert_eq(GameState.get_jobs().size(), 1, "进行中的任务保留")
	assert_eq(GameState.get_jobs()[0].batches, 2, "批量的份数保留")


## 离线回来：批处理任务照样一次出满份数（不该退化成一份）
func test_offline_completes_every_batch() -> void:
	GameState.add_item(BEAN, 4)
	GameState.start_craft(ROAST, 2)
	GameState.advance(600.0)
	assert_eq(GameState.get_jobs().size(), 0, "任务已结束")
	assert_eq(GameState.get_amount("game:item/roasted_bean"), 2, "离线也出满 2 份")
