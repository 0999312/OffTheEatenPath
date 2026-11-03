extends GutTest
## 研究组合（P3.6）：可见性、四档结论、试错代价、并行、存档与面板冒烟。
##
## 说明：NEAR_MISS / HEAT 需要「三样输入」或「高门槛」的配方，而当前内容里只有拿铁
## 需要研究。测试用 `DataRegistry.register_def()` 临时注入一条配方，`after_each` 里撤掉，
## 这样不用为了测试往 `resources/game_data/` 塞一条假内容。

const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
const LATTE := "game:recipe/latte"
const ESPRESSO_RECIPE := "game:recipe/espresso"
const ESPRESSO_FOOD := "game:item/espresso"
const AMERICANO_FOOD := "game:item/americano"
const MILK := "game:item/milk"
const SUGAR := "game:item/sugar"
const COFFEE_GROUND := "game:item/coffee_ground"
const DOUGH := "game:item/dough"

## 本测试临时注入的配方键（`after_each` 里撤掉）
var _temp_keys: Array[String] = []
## 收到的解锁事件
var _unlocked: Array[String] = []


func before_each() -> void:
	_unlocked.clear()
	_temp_keys.clear()
	GameState.reset()
	EventBus.subscribe(&"RecipeUnlockedEvent", _on_recipe_unlocked)


func after_each() -> void:
	EventBus.unsubscribe(&"RecipeUnlockedEvent", _on_recipe_unlocked)
	var registry := _registry()
	if registry != null:
		for key in _temp_keys:
			registry.unregister(ResourceLocation.from_string(key))
	_temp_keys.clear()


func _on_recipe_unlocked(event: Event) -> void:
	var unlocked := event as RecipeUnlockedEvent
	if unlocked != null:
		_unlocked.append(unlocked.recipe_key)


func _registry() -> DataRegistry:
	return RegistryManager.get_registry(DATA_REGISTRY_KEY) as DataRegistry


## 临时注入一条「需要研究」的配方：`inputs` 是每样 1 份，(键, 数量) 由调用者给全
func _inject_recipe(
	suffix: String,
	inputs: Array[String],
	pool: Array[String],
	min_level := 0,
	tag_inputs: Array[String] = [],
) -> RecipeDef:
	var recipe := RecipeDef.new()
	recipe.namespace_id = GameDef.DEFAULT_NAMESPACE
	recipe.id = "recipe/%s" % suffix
	recipe.display_name = "临时配方"
	recipe.description = "只存在于测试里。"
	recipe.output = inputs[0]
	recipe.duration_seconds = 3.0
	recipe.order = 900
	recipe.in_catalog = true
	recipe.research_pool.assign(pool)
	recipe.research_hint = "测试用的提示。"
	recipe.research_min_facility_level = min_level
	if min_level > 0:
		recipe.facility = "game:facility/coffee_machine"
	var stacks: Array[MaterialStack] = []
	for key in inputs:
		var stack := MaterialStack.new()
		stack.material = key
		stack.amount = 1
		stacks.append(stack)
	for tag in tag_inputs:
		var stack := MaterialStack.new()
		stack.by_tag = tag
		stack.amount = 1
		stacks.append(stack)
	recipe.inputs.assign(stacks)
	assert_true(_registry().register_def(recipe), "临时配方应能登记进注册表")
	_temp_keys.append(recipe.get_key())
	return recipe


func _stock(keys: Array[String]) -> void:
	for key in keys:
		GameState.add_item(key, 2.0)


# --- 1. 可见性 -------------------------------------------------------------


func test_research_recipe_is_hidden_until_unlocked() -> void:
	var visible: Array[String] = []
	for recipe in GameState.get_visible_recipes():
		visible.append(recipe.get_key())
	assert_false(visible.has(LATTE), "拿铁要先研究出来才出现在灶台")
	assert_true(visible.has(ESPRESSO_RECIPE), "浓缩不需要研究，照旧可见")
	assert_false(GameState.is_recipe_unlocked(LATTE))
	GameState.add_item(ESPRESSO_FOOD, 2.0)
	GameState.add_item(MILK, 2.0)
	assert_false(GameState.start_craft(LATTE), "没解锁的配方不能直接做")


# --- 2. 试对 ---------------------------------------------------------------


func test_correct_combo_unlocks_recipe() -> void:
	_stock([ESPRESSO_FOOD, MILK])
	assert_true(GameState.start_research([ESPRESSO_FOOD, MILK]))
	assert_eq(GameState.get_research_jobs().size(), 1, "研究任务进了台面")
	GameState.advance(20.0)
	assert_eq(GameState.get_research_jobs().size(), 0, "拿铁 20 秒后结束")
	assert_true(GameState.is_recipe_unlocked(LATTE), "拿铁解锁")
	assert_eq(_unlocked.size(), 1, "发一次解锁事件")
	assert_eq(_unlocked[0], LATTE)
	var visible := GameState.get_visible_recipes()
	assert_true(visible.any(func(recipe: RecipeDef) -> bool: return recipe.get_key() == LATTE), "解锁后灶台可见")
	assert_true(GameState.is_discovered(LATTE), "解锁同时进图鉴")


## R18 反馈 1 回归：舒芙蕾与布丁都曾用「蛋 + 奶 + 糖」，签名只看种类，
## 先排到的布丁会抢走结论，舒芙蕾永远研究不出来。舒芙蕾加面粉后两套输入必须可区分。
func test_souffle_combo_is_distinct_after_flour_fix() -> void:
	var souffle := "game:recipe/souffle"
	var egg := "game:item/egg"
	var flour := "game:item/flour"
	_stock([egg, MILK, SUGAR, flour])
	var verdict := GameState.evaluate_research([egg, MILK, SUGAR, flour])
	assert_eq(String(verdict.get("recipe_key", "")), souffle, "蛋奶糖面粉应命中舒芙蕾")
	assert_true(GameState.start_research([egg, MILK, SUGAR, flour]))
	GameState.advance(50.0)
	assert_true(GameState.is_recipe_unlocked(souffle), "舒芙蕾应能真正研究出来")


## R18 反馈 1 回归：巧克力冰淇淋曾与可可奶昔共用「可可 + 冰 + 奶 + 糖」。
## 改成奶油后，两套四材料组合应分别命中各自配方。
func test_chocolate_ice_cream_and_cocoa_shake_are_distinct() -> void:
	var chocolate := "game:recipe/chocolate_ice_cream"
	var shake := "game:recipe/cocoa_shake"
	var cocoa := "game:item/cocoa"
	var ice := "game:item/ice"
	var cream := "game:item/cream"
	_stock([cocoa, ice, cream, MILK, SUGAR])
	_stock([cocoa, ice, cream, MILK, SUGAR])
	var chocolate_verdict := GameState.evaluate_research([cocoa, ice, cream, SUGAR])
	assert_eq(String(chocolate_verdict.get("recipe_key", "")), chocolate, "可可冰奶油糖应命中巧克力冰淇淋")
	assert_true(GameState.start_research([cocoa, ice, cream, SUGAR]))
	GameState.advance(45.0)
	assert_true(GameState.is_recipe_unlocked(chocolate), "巧克力冰淇淋应能研究出来")

	var shake_verdict := GameState.evaluate_research([cocoa, ice, MILK, SUGAR])
	assert_eq(String(shake_verdict.get("recipe_key", "")), shake, "可可冰奶糖应命中可可奶昔")
	assert_true(GameState.start_research([cocoa, ice, MILK, SUGAR]))
	GameState.advance(20.0)
	assert_true(GameState.is_recipe_unlocked(shake), "可可奶昔应仍能研究出来")


func test_tag_input_matches_any_member_of_tag() -> void:
	var veg_members := _registry().tag_member_keys("game:tag/veg")
	assert_gt(veg_members.size(), 0, "veg 标签要有成员")
	var veg := String(veg_members[0])
	_inject_recipe(
		"test_tag_hit",
		[MILK, SUGAR],
		[MILK, SUGAR, veg],
		0,
		["game:tag/veg"],
	)
	_stock([MILK, SUGAR, veg])
	assert_true(GameState.start_research([MILK, SUGAR, veg]), "具名 + 标签成员应能放上研究台")
	GameState.advance(10.0)
	assert_true(GameState.is_recipe_unlocked("game:recipe/test_tag_hit"), "by_tag 输入应能研究出来")


func test_tag_input_rejects_non_member() -> void:
	var veg_members := _registry().tag_member_keys("game:tag/veg")
	if veg_members.is_empty():
		fail_test("veg 标签没有成员")
		return
	var veg := String(veg_members[0])
	_inject_recipe(
		"test_tag_miss",
		[MILK, SUGAR],
		[MILK, SUGAR, veg],
		0,
		["game:tag/veg"],
	)
	var verdict := GameState.evaluate_research([MILK, SUGAR, DOUGH])
	assert_eq(int(verdict.get("outcome", -1)), GameState.ResearchOutcome.MISMATCH, "非标签成员不能顶替 by_tag 输入")


# --- 3. 差一味 -------------------------------------------------------------


func test_near_miss_kind_of_answer() -> void:
	_inject_recipe(
		"test_three_way",
		[AMERICANO_FOOD, MILK, SUGAR],
		[AMERICANO_FOOD, MILK, SUGAR, ESPRESSO_FOOD],
	)
	_stock([AMERICANO_FOOD, MILK])
	assert_true(GameState.start_research([AMERICANO_FOOD, MILK]), "两样可以放上去")
	var job := GameState.get_research_jobs()[0]
	assert_eq(job.outcome, GameState.ResearchOutcome.NEAR_MISS, "三样配方只放两样 = 差一味")
	assert_false(GameState.is_recipe_unlocked("game:recipe/test_three_way"), "差一味不解锁")
	GameState.advance(3.0)
	assert_false(GameState.is_recipe_unlocked("game:recipe/test_three_way"))
	var record := GameState.get_research_record(GameState.signature_of([AMERICANO_FOOD, MILK]))
	assert_eq(int(record.get("outcome", -1)), GameState.ResearchOutcome.NEAR_MISS, "结论记下来了")


func test_failed_research_burns_materials_by_level() -> void:
	# 候选池只认「有待解锁配方」的那些材料，所以先注入一条来借它的池子；
	# 用不自增的中间材料，免得「基础材料随时间累积」把消耗盖住
	_inject_recipe(
		"test_burn",
		[AMERICANO_FOOD, MILK, SUGAR],
		[COFFEE_GROUND, DOUGH, AMERICANO_FOOD, MILK],
	)
	_stock([COFFEE_GROUND, DOUGH])
	var before := GameState.get_amount(COFFEE_GROUND)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]), "完全不对也能试")
	var paid: Dictionary = GameState.get_research_jobs()[0].charged
	assert_almost_eq(
		GameState.get_amount(COFFEE_GROUND),
		before - float(paid.get(COFFEE_GROUND, 1)),
		0.0001,
		"开始时就按份扣掉了")
	GameState.advance(2.0)
	# 1 级研究台烧两份：四份里去掉两份，另外两份退回
	assert_almost_eq(
		GameState.get_amount(COFFEE_GROUND) + GameState.get_amount(DOUGH),
		4.0 - 2.0,
		0.0001,
		"只烧掉固定两份")
	var signature := GameState.signature_of([COFFEE_GROUND, DOUGH])
	var record := GameState.get_research_record(signature)
	assert_eq(int(record.get("burned", []).size()), 2, "两样都记在烧毁清单里")


# --- 4. 火候不对 -----------------------------------------------------------


func test_heat_means_facility_level_too_low() -> void:
	_inject_recipe("test_heat", [ESPRESSO_FOOD, SUGAR], [ESPRESSO_FOOD, SUGAR], 2)
	_stock([ESPRESSO_FOOD, SUGAR])
	assert_true(GameState.start_research([ESPRESSO_FOOD, SUGAR]))
	var job := GameState.get_research_jobs()[0]
	assert_eq(job.outcome, GameState.ResearchOutcome.HEAT, "种类份数都对、设备不够 = 火候不对")
	GameState.advance(3.0)
	assert_false(GameState.is_recipe_unlocked("game:recipe/test_heat"), "火候不对不解锁")
	var text := GameState.describe_research(job.signature)
	assert_string_contains(text, "火候不对", "结论要能说清楚")


func test_heat_before_upgrade_replays_without_charge() -> void:
	_inject_recipe("test_heat_replay", [ESPRESSO_FOOD, SUGAR], [ESPRESSO_FOOD, SUGAR], 2)
	_stock([ESPRESSO_FOOD, SUGAR])
	assert_true(GameState.start_research([ESPRESSO_FOOD, SUGAR]))
	var signature := GameState.signature_of([ESPRESSO_FOOD, SUGAR])
	GameState.advance(3.0)
	assert_false(GameState.is_research_retryable(signature), "设备没升级前不能重试")
	var before := GameState.get_amount(ESPRESSO_FOOD)
	assert_true(GameState.start_research([ESPRESSO_FOOD, SUGAR]), "重试仍回放旧结论")
	assert_eq(GameState.get_research_jobs().size(), 0, "不建新任务")
	assert_almost_eq(GameState.get_amount(ESPRESSO_FOOD), before, 0.0001, "回放不扣材料")


func test_heat_can_be_retried_after_facility_upgrade() -> void:
	_inject_recipe("test_heat_retry", [ESPRESSO_FOOD, SUGAR], [ESPRESSO_FOOD, SUGAR], 2)
	_stock([ESPRESSO_FOOD, SUGAR])
	assert_true(GameState.start_research([ESPRESSO_FOOD, SUGAR]))
	var signature := GameState.signature_of([ESPRESSO_FOOD, SUGAR])
	GameState.advance(3.0)
	assert_false(GameState.is_recipe_unlocked("game:recipe/test_heat_retry"))
	assert_string_contains(GameState.describe_research(signature), "火候不对")

	var levels := (GameState.get("_facility_levels") as Dictionary).duplicate()
	levels["game:facility/coffee_machine"] = 2
	GameState.set("_facility_levels", levels)
	assert_true(GameState.is_research_retryable(signature), "升级到门槛后应可重试")
	assert_string_contains(GameState.describe_research(signature), "火候够了")

	_stock([ESPRESSO_FOOD, SUGAR])
	var before := GameState.get_amount(ESPRESSO_FOOD)
	assert_true(GameState.start_research([ESPRESSO_FOOD, SUGAR]), "火候够了应开新研究")
	assert_eq(GameState.get_research_jobs().size(), 1, "重试进台面")
	assert_lt(GameState.get_amount(ESPRESSO_FOOD), before, "重试要重新扣料")
	assert_false(GameState.start_research([ESPRESSO_FOOD, SUGAR]), "同组合进行中不能重复提交")
	GameState.advance(3.0)
	assert_true(GameState.is_recipe_unlocked("game:recipe/test_heat_retry"), "这次应成功")
	var record := GameState.get_research_record(signature)
	assert_eq(int(record.get("outcome", -1)), GameState.ResearchOutcome.NONE, "成功记录覆盖旧 HEAT")
	assert_eq(GameState.get_research_history().size(), 2, "历史追加一条成功记录")


# --- 5. 完全不对 -----------------------------------------------------------


func test_mismatch_uses_default_seconds() -> void:
	_stock([COFFEE_GROUND, SUGAR])
	assert_true(GameState.start_research([COFFEE_GROUND, SUGAR]))
	var job := GameState.get_research_jobs()[0]
	assert_eq(job.outcome, GameState.ResearchOutcome.MISMATCH)
	assert_almost_eq(job.total_seconds, 2.0, 0.0001, "完全不对用默认 2 秒")
	GameState.advance(2.0)
	assert_eq(GameState.get_research_jobs().size(), 0)


# --- 6. 试过的组合不再收费 -------------------------------------------------


func test_repeat_research_costs_nothing() -> void:
	_inject_recipe(
		"test_repeat",
		[AMERICANO_FOOD, MILK, SUGAR],
		[COFFEE_GROUND, DOUGH, AMERICANO_FOOD, MILK],
	)
	_stock([COFFEE_GROUND, DOUGH])
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	GameState.advance(2.0)
	var signature := GameState.signature_of([COFFEE_GROUND, DOUGH])
	assert_eq(GameState.get_research_record_count(), 1, "记下一条")
	var before := GameState.get_amount(COFFEE_GROUND)
	GameState.add_item(COFFEE_GROUND, 3.0)
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), before + 3.0, 0.0001, "手里 + 新加 3")
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]), "重试直接回放结论")
	assert_eq(GameState.get_research_jobs().size(), 0, "不会开新任务")
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), before + 3.0, 0.0001, "不扣材料")
	assert_eq(GameState.get_research_record_count(), 1, "记录不会重复")
	assert_eq(GameState.get_last_research_signature(), signature)


# --- 7. 并行位 -------------------------------------------------------------


func test_research_slots_follow_desk_level() -> void:
	_stock([COFFEE_GROUND, SUGAR, MILK, ESPRESSO_FOOD])
	assert_true(GameState.start_research([COFFEE_GROUND, SUGAR]))
	var before := GameState.get_amount(MILK)
	assert_false(GameState.start_research([MILK, ESPRESSO_FOOD]), "1 级只有一组的位置")
	assert_eq(GameState.get_amount(MILK), before, "被拒的那次不扣材料")
	GameState.advance(3.0)
	assert_true(GameState.start_research([MILK, ESPRESSO_FOOD]), "腾出位置后可以再试")


func test_desk_level_raises_burn_rate_softly() -> void:
	var rules := GameState.get_research_rules()
	assert_not_null(rules, "研究规则资源要能读到")
	assert_almost_eq(rules.get_burn_rate(1), 1.0, 0.0001, "1 级全烧")
	assert_almost_eq(rules.get_burn_rate(2), 0.7, 0.0001, "2 级烧 70%")
	assert_almost_eq(rules.get_burn_rate(3), 0.4, 0.0001, "3 级烧 40%")


# --- 8. 存档 ---------------------------------------------------------------


func test_save_round_trip_keeps_research() -> void:
	_stock([ESPRESSO_FOOD, MILK])
	assert_true(GameState.start_research([ESPRESSO_FOOD, MILK]))
	GameState.advance(20.0)
	assert_true(GameState.is_recipe_unlocked(LATTE), "先试出拿铁")
	# 拿铁解锁后候选池就空了，注入一条新的待解锁配方，才挂得上第二个任务
	_inject_recipe(
		"test_pending",
		[COFFEE_GROUND, "game:item/dough"],
		[COFFEE_GROUND, "game:item/dough"],
	)
	_stock([COFFEE_GROUND, "game:item/dough"])
	assert_true(GameState.start_research([COFFEE_GROUND, "game:item/dough"]), "再挂一个没做完的")
	var data := GameState.to_dict()
	assert_eq(int(data.get("version", 0)), GameState.SAVE_VERSION, "存档版本应随 SAVE_VERSION 走（v4 加招牌菜）")

	GameState.reset()
	assert_false(GameState.is_recipe_unlocked(LATTE))
	assert_true(GameState.restore_from_dict(data), "读得回来")
	assert_true(GameState.is_recipe_unlocked(LATTE), "解锁状态保留")
	assert_eq(GameState.get_research_record_count(), 1, "试法记录保留")
	assert_eq(GameState.get_research_jobs().size(), 1, "进行中的研究保留")
	assert_eq(GameState.get_research_jobs()[0].signature, GameState.signature_of([COFFEE_GROUND, "game:item/dough"]))


func test_v1_save_is_rejected() -> void:
	var data := GameState.to_dict()
	data["version"] = 1
	assert_false(GameState.restore_from_dict(data), "v18 起不再读取 v1 存档")


# --- 8.5 本轮回归：标签线索 / gazpacho 死锁 ---------------------------------


func test_research_clue_spells_out_tag_materials() -> void:
	# 第十一轮反馈 1：研究线索必须把 by_tag 输入也念出来，不能只列具名材料。
	var panel := GamePanel.new()
	var recipe := _registry().get_def("game:recipe/noodle_soup") as RecipeDef
	assert_not_null(recipe, "汤面配方应存在")
	if recipe == null:
		panel.free()
		return
	var clue := panel.research_clue(recipe)
	assert_string_contains(clue, "清汤面", "具名输入仍要出现")
	assert_string_contains(clue, "任意蔬菜", "标签输入要写成「任意蔬菜」")
	panel.free()


func test_gazpacho_can_be_researched_after_stack_merge() -> void:
	# 第十一轮 H4/H5：两个番茄 stack 合并成 amount=2 后，研究台应能用两种材料试出来。
	var recipe := _registry().get_def("game:recipe/gazpacho") as RecipeDef
	assert_not_null(recipe, "西班牙冷汤配方应存在")
	if recipe == null:
		return
	assert_eq(recipe.inputs.size(), 2, "合并后应只剩番茄与橄榄油两种输入")
	# 西班牙冷汤是地中海主题，研究台只列已到站主题的配方。
	GameState._read_letters["game:letter/mediterranean_arrive"] = true
	GameState.add_item("game:item/tomato", 2.0)
	GameState.add_item("game:item/olive_oil", 1.0)
	assert_true(GameState.start_research(["game:item/tomato", "game:item/olive_oil"]),
		"番茄 + 橄榄油应能放上研究台")
	GameState.advance(60.0)
	assert_true(GameState.is_recipe_unlocked("game:recipe/gazpacho"),
		"研究结束后应解锁西班牙冷汤")


# --- 9. 面板冒烟 -----------------------------------------------------------


func test_research_panel_smoke() -> void:
	assert_false(GameState.get_research_candidates().is_empty(), "拿铁在等着被想出来，候选池不该空")
	var location := ResourceLocation.from_string(UIKeys.RESEARCH)
	assert_not_null(location)
	var panel := UIManager.open_panel(location)
	assert_not_null(panel, "研究台面板能打开")
	assert_true(panel is ResearchPanel, "打开的确实是研究台")
	var research_panel := panel as ResearchPanel
	var labels := research_panel.content.get_children()
	assert_gt(labels.size(), 0, "面板里要有内容（台面行 + 候选 + 按钮）")
	UIManager.close_panel(location)
	await wait_process_frames(1)
	assert_false(UIManager.is_panel_open(location), "关得掉")



# --- 10. 候选页过滤 --------------------------------------------------------


## 候选有十几样、每张牌都比名字长，横着一排必然顶到卡片外面（用户原话「材料变成了出界的单行」）。
## 现在默认只摆手上有货的，铺全集得自己开开关。

func test_candidate_page_defaults_to_what_you_own() -> void:
	GameState.add_item(MILK, 2)
	GameState.add_item(SUGAR, 2)
	var panel := await _open_candidate_page()
	assert_false(panel._show_all_candidates, "默认不铺全集")
	var flow := _candidate_flow(panel)
	assert_not_null(flow, "候选要用会换行的容器")
	if flow != null:
		# 水这类免费材料不攒库存但一直算「手上有」，所以期望值是拥有 + 常备
		var expected := 0
		for key in GameState.get_research_candidates():
			var def := GameState.call("_def", key) as ItemDef
			if GameState.get_amount(key) > 0 or (def != null and def.is_free()):
				expected += 1
		assert_eq(flow.get_child_count(), expected, "只摆手上有货的与常备免费材料")
	await _close_research()


func test_candidate_page_falls_back_to_everything_when_empty_handed() -> void:
	var panel := await _open_candidate_page()
	var flow := _candidate_flow(panel)
	assert_not_null(flow)
	if flow != null:
		assert_eq(flow.get_child_count(), GameState.get_research_candidates().size(),
				"手上一无所有时退回全集——空表比「不好用」更像坏了")
	await _close_research()


func test_show_all_candidates_toggle_fills_the_flow() -> void:
	GameState.add_item(MILK, 2)
	var panel := await _open_candidate_page()
	panel._show_all_candidates = true
	panel._structure_signature = ""
	panel.refresh()
	await wait_process_frames(1)
	var flow := _candidate_flow(panel)
	assert_not_null(flow)
	if flow != null:
		assert_eq(flow.get_child_count(), GameState.get_research_candidates().size(),
				"打开开关铺全集")
	await _close_research()


func _open_candidate_page() -> ResearchPanel:
	var location := ResourceLocation.from_string(UIKeys.RESEARCH)
	var panel := UIManager.open_panel(location) as ResearchPanel
	panel._tab_index = ResearchPanel.TAB_CANDIDATES
	panel._tab_chosen = true
	panel._structure_signature = ""
	panel.refresh()
	await wait_process_frames(1)
	return panel


func _candidate_flow(panel: ResearchPanel) -> HFlowContainer:
	var found := panel.content.find_children("*", "HFlowContainer", true, false)
	return found[0] as HFlowContainer if not found.is_empty() else null


func _close_research() -> void:
	UIManager.close_panel(ResourceLocation.from_string(UIKeys.RESEARCH))
	await wait_process_frames(1)
