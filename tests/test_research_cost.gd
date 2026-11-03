extends GutTest
## 经济 v2 第四步：研究台的试错代价。
##
## 规则（`docs/decisions/2026-10-25-economy-v2.md` §7）：每样材料先扣 1 份，
## 另有一半概率再扣 1 份；失败按固定份数烧掉（Lv1 两份、Lv2 与 Lv3 各一份），
## 其余退回；成功则放进去的都算学费，不退。

const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
const MILK := "game:item/milk"
const SUGAR := "game:item/sugar"
const COFFEE_GROUND := "game:item/coffee_ground"
const DOUGH := "game:item/dough"
const AMERICANO_FOOD := "game:item/americano"
const DESK := "game:facility/research_desk"

## 本测试临时注入的配方键（`after_each` 里撤掉）
var _temp_keys: Array[String] = []


func before_each() -> void:
	_temp_keys.clear()
	GameState.reset()
	# 固定种子：概率扣款才可复现（每个用例自己决定要不要开）
	GameState.set_research_seed(7)


func after_each() -> void:
	GameState.set_research_seed(0)
	var registry := _registry()
	if registry != null:
		for key in _temp_keys:
			registry.unregister(ResourceLocation.from_string(key))
	_temp_keys.clear()


func _registry() -> DataRegistry:
	return RegistryManager.get_registry(DATA_REGISTRY_KEY) as DataRegistry


## 借一条「需要研究」的配方，好让这两样材料进候选池
func _inject_recipe(suffix: String, pool: Array[String]) -> void:
	var recipe := RecipeDef.new()
	recipe.namespace_id = GameDef.DEFAULT_NAMESPACE
	recipe.id = "recipe/%s" % suffix
	recipe.display_name = "临时配方"
	recipe.description = "只存在于测试里。"
	recipe.output = AMERICANO_FOOD
	recipe.duration_seconds = 3.0
	recipe.order = 900
	recipe.research_pool.assign(pool)
	recipe.research_hint = "测试用的提示。"
	var stacks: Array[MaterialStack] = []
	for key in pool:
		var stack := MaterialStack.new()
		stack.material = key
		stack.amount = 1
		stacks.append(stack)
	recipe.inputs.assign(stacks)
	assert_true(_registry().register_def(recipe), "临时配方应能登记进注册表")
	_temp_keys.append(recipe.get_key())


func _bait() -> void:
	_inject_recipe("cost_bait", [COFFEE_GROUND, DOUGH, AMERICANO_FOOD, MILK])


# --- 1. 固定的那一份 -------------------------------------------------------


func test_each_pick_costs_one_for_sure() -> void:
	_bait()
	GameState.add_item(COFFEE_GROUND, 1.0)
	GameState.add_item(DOUGH, 1.0)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 0.0, 0.0001, "手头只有一份时一定扣掉")
	assert_almost_eq(GameState.get_amount(DOUGH), 0.0, 0.0001)


func test_extra_charge_never_takes_more_than_you_have() -> void:
	_bait()
	var rules := GameState.get_research_rules()
	var old := rules.charge_chance
	rules.charge_chance = 1.0
	GameState.add_item(COFFEE_GROUND, 1.0)
	GameState.add_item(DOUGH, 1.0)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 0.0, 0.0001, "只有一份就扣一份，不会扣成负数")
	rules.charge_chance = old


func test_certain_extra_charge_takes_two() -> void:
	_bait()
	var rules := GameState.get_research_rules()
	var old := rules.charge_chance
	rules.charge_chance = 1.0
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.add_item(DOUGH, 3.0)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 1.0, 0.0001, "概率必中就是扣两份")
	rules.charge_chance = old


# --- 2. 失败烧固定份数 -----------------------------------------------------


func test_failure_burns_two_and_returns_the_rest() -> void:
	_bait()
	var rules := GameState.get_research_rules()
	assert_eq(rules.get_burn_count(1), 2, "1 级烧两份")
	assert_eq(rules.get_burn_count(2), 1, "2 级烧一份")
	assert_eq(rules.get_burn_count(3), 1, "3 级烧一份")
	# 每样两份：共扣 4 份（概率可能再多），失败烧 2 份，其余退回
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.add_item(DOUGH, 3.0)
	var initial := GameState.get_amount(COFFEE_GROUND) + GameState.get_amount(DOUGH)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	GameState.advance(3.0)
	var after := GameState.get_amount(COFFEE_GROUND) + GameState.get_amount(DOUGH)
	assert_almost_eq(after, initial - 2.0, 0.0001, "只烧掉两份，剩下退回")
	var record := GameState.get_research_record(GameState.signature_of([COFFEE_GROUND, DOUGH]))
	assert_eq(record.get("burned", []).size(), 2, "烧毁清单正好两份")


func test_success_costs_the_materials() -> void:
	_bait()
	# 拿铁需要「浓缩 + 牛奶」，这里直接用真实配方试对
	GameState.add_item("game:item/espresso", 1.0)
	GameState.add_item(MILK, 1.0)
	assert_true(GameState.start_research(["game:item/espresso", MILK]))
	GameState.advance(20.0)
	assert_true(GameState.is_recipe_unlocked("game:recipe/latte"), "试对就解锁")
	assert_almost_eq(GameState.get_amount("game:item/espresso"), 0.0, 0.0001, "成了也算学费，不退")
	assert_almost_eq(GameState.get_amount(MILK), 0.0, 0.0001)


# --- 3. 取消要全退 ---------------------------------------------------------


func test_cancel_returns_what_was_charged() -> void:
	_bait()
	var rules := GameState.get_research_rules()
	var old := rules.charge_chance
	rules.charge_chance = 1.0
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.add_item(DOUGH, 3.0)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 1.0, 0.0001, "先扣两份")
	assert_true(GameState.cancel_research(GameState.get_research_jobs()[0].signature))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 3.0, 0.0001, "收回时按扣掉的份数退")
	assert_almost_eq(GameState.get_amount(DOUGH), 3.0, 0.0001)
	rules.charge_chance = old


# --- 4. 存档 ---------------------------------------------------------------


func test_save_keeps_charged_materials() -> void:
	_bait()
	var rules := GameState.get_research_rules()
	var old := rules.charge_chance
	rules.charge_chance = 1.0
	GameState.add_item(COFFEE_GROUND, 3.0)
	GameState.add_item(DOUGH, 3.0)
	assert_true(GameState.start_research([COFFEE_GROUND, DOUGH]))
	var signature := GameState.get_research_jobs()[0].signature
	var snapshot := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.restore_from_dict(snapshot), "存档应能读回")
	assert_eq(GameState.get_research_jobs().size(), 1, "研究任务还在")
	assert_true(GameState.cancel_research(signature))
	assert_almost_eq(GameState.get_amount(COFFEE_GROUND), 3.0, 0.0001, "读档后取消仍按原份数退")
	rules.charge_chance = old


func test_v8_save_is_rejected() -> void:
	var snapshot := GameState.to_dict()
	snapshot["version"] = 8
	GameState.reset()
	assert_false(GameState.restore_from_dict(snapshot), "v18 起不再读取 v8 存档")
