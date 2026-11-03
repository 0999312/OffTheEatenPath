extends GutTest
## 多产物：主产物 ×output_amount + 副产物；反查索引收副产物，但订单/「去做」只认主产物。

const ESPRESSO_RECIPE := "game:recipe/espresso"
const ESPRESSO := "game:item/espresso"
const WATER := "game:item/water"

var _recipe: RecipeDef
var _old_amount := 1
var _old_extras: Array[MaterialStack] = []


func before_each() -> void:
	GameState.reset()
	_recipe = GameState._def(ESPRESSO_RECIPE) as RecipeDef
	assert_not_null(_recipe, "测试前提：浓缩配方存在")
	if _recipe == null:
		return
	_old_amount = _recipe.output_amount
	_old_extras = _recipe.extra_outputs.duplicate()


func after_each() -> void:
	if _recipe != null:
		_recipe.output_amount = _old_amount
		_recipe.extra_outputs = _old_extras
	_invalidate_recipe_index()
	GameState.reset()


func _invalidate_recipe_index() -> void:
	# 反查索引按「配方数量」判断是否过期；测试临时改了资源，需要手动作废
	GameState._recipe_index_size = -1
	GameState._recipes_by_output.clear()
	GameState._recipes_by_input.clear()


func _install_water_extra(amount: int = 1) -> void:
	var extra := MaterialStack.new()
	extra.material = WATER
	extra.amount = amount
	var extras: Array[MaterialStack] = [extra]
	_recipe.extra_outputs = extras
	_invalidate_recipe_index()


func test_output_stacks_lists_primary_then_extras() -> void:
	_recipe.output_amount = 2
	_install_water_extra(3)
	var rows := _recipe.output_stacks()
	assert_eq(rows.size(), 2, "主产物 + 一份副产物")
	assert_eq(String(rows[0]["material"]), ESPRESSO)
	assert_eq(int(rows[0]["amount"]), 2, "主产物数量取 output_amount")
	assert_true(bool(rows[0]["primary"]))
	assert_eq(String(rows[1]["material"]), WATER)
	assert_eq(int(rows[1]["amount"]), 3)
	assert_false(bool(rows[1]["primary"]))


func test_complete_craft_multiplies_primary_and_adds_extras_per_batch() -> void:
	_recipe.output_amount = 2
	_install_water_extra(1)
	var espresso_before := GameState.get_amount(ESPRESSO)
	var water_before := GameState.get_amount(WATER)
	GameState._complete_craft(_recipe, "game:facility/coffee_machine", 2)
	assert_eq(GameState.get_amount(ESPRESSO), espresso_before + 4, "2 批 × 主产物 2")
	assert_eq(GameState.get_amount(WATER), water_before + 2, "副产物按批发放，不乘主产物数量")
	assert_eq(GameState.get_food_crafted_count(ESPRESSO), 4, "委托计数按主产物份数累计")


func test_extra_output_is_reverse_indexed_but_not_a_primary_recipe() -> void:
	_install_water_extra(1)
	assert_has(GameState.recipes_producing(WATER), ESPRESSO_RECIPE, "反查应能看见副产物来源")
	assert_eq(GameState.recipe_for_output(WATER), "", "订单/去做只认主产物，不认副产物")
	assert_eq(GameState.recipe_for_output(ESPRESSO), ESPRESSO_RECIPE, "主产物反查保持正常")
