extends GutTest
## R7.4 四步引导：步骤表、奖励只发一次、订单未解锁时第四步收起、新档有信可读。

const TUTORIAL := preload("res://scripts/systems/tutorial.gd")


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	GameState.reset()


func test_steps_table_has_four_steps_and_first_upgrade_reward() -> void:
	assert_eq(TUTORIAL.step_count(), 4, "引导四步：信 → 菜 → 商人信 → 交单")
	assert_eq(String(TUTORIAL.STEPS[0]["panel"]), UIKeys.MAIL, "第一步去信箱")
	assert_eq(String(TUTORIAL.STEPS[1]["panel"]), UIKeys.CRAFT, "第二步去灶台做第一道菜")
	assert_eq(String(TUTORIAL.STEPS[2]["panel"]), UIKeys.MAIL, "第三步回信箱读牛奶商人的信")
	assert_eq(String(TUTORIAL.STEPS[3]["panel"]), UIKeys.ORDERS, "第四步去订单板交单")
	assert_true(bool(TUTORIAL.STEPS[3].get("requires_orders", false)), "订单未解锁时第四步先收起")
	assert_eq(TUTORIAL.total_reward_coins(), 72, "磨豆机 2 级 60 铜 × 1.2 = 72")
	for entry in TUTORIAL.STEPS:
		var item_key := String(entry.get("item", ""))
		assert_not_null(GameState._def(item_key), "奖励材料 %s 必须存在" % item_key)
		assert_eq(int(entry.get("coins", 0)), 18, "四步均分 72 铜")


func test_four_steps_advance_and_reward_only_once() -> void:
	var coins_before := GameState.coins
	assert_eq(GameState.get_tutorial_step(), 0)
	assert_false(GameState.is_tutorial_done())
	for index in 4:
		assert_eq(GameState.get_tutorial_step(), index, "第 %d 步应轮到它" % index)
		TUTORIAL.complete_current_step()
	assert_eq(GameState.get_tutorial_step(), 4, "四步走完")
	assert_true(GameState.is_tutorial_done(), "走完即 done")
	assert_eq(GameState.coins, coins_before + TUTORIAL.total_reward_coins(), "奖励总额只发一次")
	assert_eq(GameState.get_amount("game:item/rice"), 2, "第一步给米")
	assert_eq(GameState.get_amount("game:item/coffee_bean"), 2, "第二步给咖啡豆")
	assert_eq(GameState.get_amount("game:item/flour"), 2, "第三步给面粉")
	assert_eq(GameState.get_amount("game:item/milk"), 2, "第四步给牛奶")
	# 再调一次不能再发一遍
	var coins_after := GameState.coins
	TUTORIAL.complete_current_step()
	assert_eq(GameState.coins, coins_after, "done 之后不该重复发奖励")


func test_bar_ignores_mouse_except_buttons() -> void:
	var bar := TutorialBar.new()
	add_child_autofree(bar)
	await wait_process_frames(1)
	var card := bar.get_node_or_null("TutorialCard") as Control
	assert_not_null(card, "引导条应有纸片")
	if card == null:
		return
	assert_true(card.visible, "新档要显示第一步")
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "整条不挡房间")
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "纸片不挡点击")
	for node in card.find_children("*", "Button", true, false):
		assert_eq((node as Button).mouse_filter, Control.MOUSE_FILTER_STOP, "按钮要能点")


func test_final_step_hides_until_orders_unlock() -> void:
	for index in 3:
		TUTORIAL.complete_current_step()
	assert_eq(GameState.get_tutorial_step(), 3, "三步做完，停在交单这一步")
	assert_false(GameState.is_tutorial_done(), "第四步还没完成，不能算走完")
	var bar := TutorialBar.new()
	add_child_autofree(bar)
	await wait_process_frames(1)
	var card := bar.get_node_or_null("TutorialCard") as Control
	assert_not_null(card)
	if card == null:
		return
	assert_false(card.visible, "订单板没解锁时不显示一个去不到的第四步")
	GameState._read_letters[GameState.ORDERS_UNLOCK_LETTER] = true
	bar._sync()
	assert_true(card.visible, "第九封信读完后第四步自动回来")


func test_bar_hides_when_tutorial_done() -> void:
	GameState.skip_tutorial()
	var bar := TutorialBar.new()
	add_child_autofree(bar)
	await wait_process_frames(1)
	var card := bar.get_node_or_null("TutorialCard") as Control
	assert_not_null(card)
	if card != null:
		assert_false(card.visible, "跳过/旧档不再出现引导条")


func test_new_save_starts_with_a_letter_to_read() -> void:
	assert_eq(GameState.get_read_letter_count(), 0, "新档还没读过信")
	assert_gte(GameState.get_unread_letter_count(), 1, "第一步得有一封信可读")
	assert_false(GameState.is_tutorial_done(), "新档要显示引导")
