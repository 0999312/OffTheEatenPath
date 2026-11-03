extends GutTest
## 便条是招牌菜的唯一入口（决策 2026-10-28 D8）：点它选档、选菜，「不设」清空。
## 设置页里那三个下拉已删除，这组用例守住「状态只有一个入口、一条通路」。

const FOOD_KEY := "game:item/espresso"
const LATTE_KEY := "game:item/latte"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	GameState.reset()


func _layer() -> AmbientLayer:
	var layer := AmbientLayer.new()
	add_child_autofree(layer)
	return layer


func test_sign_is_clickable_while_the_layer_stays_transparent() -> void:
	var layer := _layer()
	await wait_process_frames(1)
	assert_eq(layer.mouse_filter, Control.MOUSE_FILTER_IGNORE, "整层仍不该挡桌面点击")
	assert_not_null(layer._sign, "便条应存在")
	if layer._sign == null:
		return
	assert_eq(layer._sign.mouse_filter, Control.MOUSE_FILTER_STOP, "便条要接住点击")
	assert_eq(layer._sign.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND,
			"鼠标移到便条上应变成手型")


func test_slot_menu_lists_unset_and_every_slot() -> void:
	var layer := _layer()
	await wait_process_frames(1)
	layer._open_slot_menu()
	assert_eq(layer._slot_menu.item_count, GameState.SIGNATURE_SLOTS + 1, "「不设」+ 三档")
	assert_eq(layer._slot_menu.get_item_text(0), I18n.t("ui.ambient.sign_clear"))
	assert_eq(layer._slot_menu.get_item_text(1), I18n.t("ui.ambient.sign_slot", [1]))


func test_picking_a_dish_writes_the_slot_and_the_sign() -> void:
	var layer := _layer()
	await wait_process_frames(1)
	GameState.discover(FOOD_KEY)
	await wait_process_frames(1)
	var candidates := GameState.get_signature_candidates()
	assert_false(candidates.is_empty(), "发现咖啡后应至少有一道候选菜")
	if candidates.is_empty():
		return
	layer._on_slot_menu_id(2)
	assert_eq(layer._food_menu.item_count, candidates.size() + 1, "「自动」+ 全部候选")
	layer._on_food_menu_id(1)
	assert_eq(GameState.get_signature_slots()[1], candidates[0].get_key(), "第 2 档写进所选菜")
	await wait_process_frames(1)
	assert_true(layer.get_signature_names().has(candidates[0].localized()),
			"便条要显示刚选的菜")


func test_unset_clears_every_slot() -> void:
	var layer := _layer()
	await wait_process_frames(1)
	GameState.discover(FOOD_KEY)
	GameState.discover(LATTE_KEY)
	GameState.set_signature_slot(0, FOOD_KEY)
	GameState.set_signature_slot(1, LATTE_KEY)
	layer._on_slot_menu_id(0)
	var slots := GameState.get_signature_slots()
	assert_eq(slots.size(), 3, "三档都应保留")
	for slot in slots.size():
		assert_eq(slots[slot], "", "「不设」应清空第 %d 档" % (slot + 1))
