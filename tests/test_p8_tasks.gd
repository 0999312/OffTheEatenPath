extends GutTest
## P8.2：信里的委托。读委托信 = 收下这件事，但物品/主题要亲手交付才算办妥；
## 订单与研究仍是达标的隐式交付。报酬只发一次。

## P10.11 起委托单独成信：window 只讲故事，第一件委托是它后面的 task_window_1
const WINDOW := "game:letter/window"
const TASK_POUR := "game:letter/task_window_1"
const TASK_EAST_ASIA := "game:letter/task_east_asia_arrive_1"
const TASK_TAG := "game:letter/task_east_asia_note_1"
const EAST_ASIA_NOTE := "game:letter/east_asia_note"
const POUR_OVER := "game:item/pour_over"
const EAST_ASIA := "game:theme/east_asia"
const EAST_ASIA_ARRIVE := "game:letter/east_asia_arrive"


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func before_each() -> void:
	GameState.reset()


## 直接把解锁名单摆好：Array[String]，塞未类型化数组会被静默丢掉
func _force_unlock(letter_key: String) -> void:
	var unlocked: Array[String] = [letter_key]
	GameState.set("_unlocked_letters", unlocked)


func _read(letter_key: String) -> void:
	_force_unlock(letter_key)
	GameState.mark_letter_read(letter_key)


## 伪造「做过哪几道菜」（主题计数看的是这个集合，同一道做几次只算一道）
func _set_food_set(keys: Array) -> void:
	var food: Dictionary = {}
	for key in keys:
		food[String(key)] = true
	GameState.set("_crafted_food", food)


## 手动跑一次复查：真实流程里由 advance() 每 tick 调，测试里不必等 tick
func _tick() -> void:
	GameState.set("_tasks_dirty", true)
	GameState._advance_tasks()


func _letter(key: String) -> LetterDef:
	return _data().get_def(key) as LetterDef


func _theme_dishes(theme_key: String, count: int) -> Array:
	var found: Array = []
	for def in _data().get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or recipe.needs_research():
			continue
		if not (recipe.output.begins_with("game:item/")):
			continue
		var item := _data().get_def(recipe.output) as ItemDef
		if item == null or not item.is_food():
			continue
		if GameState.item_theme_key(recipe.output) != theme_key:
			continue
		if found.has(recipe.output):
			continue
		found.append(recipe.output)
		if found.size() >= count:
			break
	return found


## 某个标签下不用研究就能做的不同菜品（内容守卫与测试预置共用）
func _tag_dishes(tag_key: String, count: int) -> Array:
	var found: Array = []
	for def in _data().get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or recipe.needs_research():
			continue
		if not (recipe.output.begins_with("game:item/")):
			continue
		var item := _data().get_def(recipe.output) as ItemDef
		if item == null or not item.is_food():
			continue
		if not item.tags.has(tag_key):
			continue
		if found.has(recipe.output):
			continue
		found.append(recipe.output)
		if found.size() >= count:
			break
	return found


func test_reading_a_story_letter_takes_on_nothing() -> void:
	_read(WINDOW)
	assert_true(GameState.is_letter_read(WINDOW), "信读过了")
	assert_false(GameState.is_task_accepted(WINDOW), "故事信没有委托，不该进待办")
	assert_eq(GameState.get_open_task_count(), 0, "待办数还是 0")
	assert_eq(GameState.get_task_letters().size(), 0, "待办页里空着")


func test_reading_a_task_letter_takes_it_on() -> void:
	assert_false(GameState.accept_task(TASK_POUR), "没读过的信接不了")
	_read(TASK_POUR)
	assert_true(GameState.is_task_accepted(TASK_POUR), "读委托信就自动收下")
	assert_eq(GameState.get_task_letters().size(), 1, "读完立刻进待办")
	assert_eq(GameState.get_open_task_count(), 1)
	assert_true(GameState.is_letter_read(TASK_POUR), "信仍留在信箱里")


func test_accepting_twice_is_a_no_op() -> void:
	_read(TASK_POUR)
	assert_false(GameState.accept_task(TASK_POUR), "已经随读信收下，不能再接一次")
	assert_eq(GameState.get_task_letters().size(), 1)


func test_stock_task_waits_for_hand_in() -> void:
	_read(TASK_POUR)
	var letter := _letter(TASK_POUR)
	assert_eq(GameState.get_task_progress(letter), Vector2i(0, 1), "刚读信时手上没有")
	assert_false(GameState.can_deliver_task(TASK_POUR), "没东西不能交付")
	GameState.add_item(POUR_OVER, 1)
	assert_eq(GameState.get_task_progress(letter), Vector2i(1, 1), "凑齐就算进度满")
	assert_false(GameState.is_task_completed(TASK_POUR), "凑齐不等于交付")
	assert_true(GameState.can_deliver_task(TASK_POUR), "可以交付")
	assert_eq(GameState.get_open_task_count(), 1, "交付前仍占待办")
	assert_true(GameState.deliver_task(TASK_POUR), "交付应成功")
	assert_true(GameState.is_task_completed(TASK_POUR), "交付后办妥")
	assert_eq(GameState.get_amount(POUR_OVER), 0, "交付会扣掉物品")
	assert_eq(GameState.get_open_task_count(), 0, "办妥的不再占待办数")


func test_a_finished_task_pays_only_once() -> void:
	_read(TASK_POUR)
	var letter := _letter(TASK_POUR)
	var before := GameState.coins
	GameState.add_item(POUR_OVER, 1)
	assert_true(GameState.deliver_task(TASK_POUR), "第一次交付成功")
	assert_eq(GameState.coins, before + letter.task_reward_coins, "办妥就发报酬")
	assert_false(GameState.deliver_task(TASK_POUR), "不能重复交付")
	_tick()
	assert_eq(GameState.coins, before + letter.task_reward_coins, "报酬只发一次")


func test_theme_task_counts_distinct_dishes() -> void:
	_read(EAST_ASIA_ARRIVE)
	_read(TASK_EAST_ASIA)
	assert_true(GameState.is_task_accepted(TASK_EAST_ASIA), "读信就该收下主题委托")
	var letter := _letter(TASK_EAST_ASIA)
	var dishes := _theme_dishes(EAST_ASIA, 2)
	assert_eq(dishes.size(), 2, "东亚至少该有两道不用研究的菜")
	if dishes.size() < 2:
		return
	_set_food_set([])
	assert_eq(GameState.get_task_progress(letter), Vector2i(0, 2))
	_set_food_set([dishes[0]])
	assert_eq(GameState.get_task_progress(letter), Vector2i(1, 2))
	_set_food_set(dishes)
	assert_eq(GameState.get_task_progress(letter), Vector2i(2, 2), "两道不同的菜就算凑齐")
	_tick()
	assert_false(GameState.is_task_completed(TASK_EAST_ASIA), "主题委托要确认，不自动完成")
	assert_true(GameState.can_deliver_task(TASK_EAST_ASIA))
	assert_true(GameState.deliver_task(TASK_EAST_ASIA), "确认后办妥")
	assert_true(GameState.is_task_completed(TASK_EAST_ASIA))


func test_tag_task_counts_distinct_dishes_and_needs_no_hand_in_stock() -> void:
	_read(EAST_ASIA_NOTE)
	_read(TASK_TAG)
	var letter := _letter(TASK_TAG)
	assert_eq(letter.task_goal, LetterDef.TaskGoal.CRAFT_TAG)
	assert_true(GameState.is_task_accepted(TASK_TAG), "读信就该收下标签委托")
	_set_food_set([])
	assert_eq(GameState.get_task_progress(letter), Vector2i(0, 2))
	_set_food_set(["game:item/dal"])
	assert_eq(GameState.get_task_progress(letter), Vector2i(1, 2))
	_set_food_set(["game:item/dal", "game:item/gazpacho"])
	assert_eq(GameState.get_task_progress(letter), Vector2i(2, 2), "两道不同的汤就算凑齐")
	assert_true(GameState.can_deliver_task(TASK_TAG), "标签委托只确认，不扣菜")
	assert_true(GameState.deliver_task(TASK_TAG), "确认后办妥")
	assert_true(GameState.is_task_completed(TASK_TAG))


## 接任务前就把主题菜做满：累计口径应直接显示完成，允许确认。
func test_theme_task_counts_dishes_made_before_accepting() -> void:
	_read(EAST_ASIA_ARRIVE)
	var dishes := _theme_dishes(EAST_ASIA, 2)
	assert_eq(dishes.size(), 2, "东亚至少该有两道不用研究的菜")
	if dishes.size() < 2:
		return
	_set_food_set(dishes)
	_read(TASK_EAST_ASIA)
	var letter := _letter(TASK_EAST_ASIA)
	assert_true(GameState.is_task_accepted(TASK_EAST_ASIA))
	assert_eq(GameState.get_task_progress(letter), Vector2i(2, 2), "接之前做过的两道菜要算数")
	assert_true(GameState.can_deliver_task(TASK_EAST_ASIA), "接任务时已达标就能确认")
	# 旧档可能留着接任务时的 baseline；累计目标应忽略它。
	var baselines := (GameState.get("_task_baseline") as Dictionary).duplicate()
	baselines[TASK_EAST_ASIA] = 99
	GameState.set("_task_baseline", baselines)
	assert_eq(GameState.get_task_progress(letter), Vector2i(2, 2), "旧 baseline 不再扣减累计值")


func test_tag_task_counts_dishes_made_before_accepting() -> void:
	_read(EAST_ASIA_NOTE)
	var dishes := _tag_dishes("game:tag/soup", 2)
	assert_eq(dishes.size(), 2, "汤标签至少该有两道不用研究的菜")
	if dishes.size() < 2:
		return
	_set_food_set(dishes)
	_read(TASK_TAG)
	var letter := _letter(TASK_TAG)
	assert_eq(GameState.get_task_progress(letter), Vector2i(2, 2), "接之前做过的汤要算数")
	assert_true(GameState.can_deliver_task(TASK_TAG), "标签任务接取时已达标")


func test_theme_and_tag_tasks_have_enough_distinct_dishes() -> void:
	for def in _data().get_defs_of_type("letter"):
		var letter := def as LetterDef
		if letter == null or not letter.has_task():
			continue
		var available := 0
		match letter.task_goal:
			LetterDef.TaskGoal.CRAFT_THEME:
				available = _theme_dishes(letter.task_ref, 999).size()
			LetterDef.TaskGoal.CRAFT_TAG:
				available = _tag_dishes(letter.task_ref, 999).size()
			_:
				continue
		assert_gte(available, letter.task_target(),
			"%s 的目标菜数不应超过该主题/标签可做的不同菜数" % letter.get_key())


func test_explicit_task_must_be_delivered_before_the_next_letter() -> void:
	var task_key := "game:letter/vegetable_patch"
	var next_key := "game:letter/rice_sack"
	# 真实流程里前面的信都已读过；这里把 29 之前全部标成已解锁，避免刷新在第一封就停下。
	var unlocked: Array[String] = []
	for def in _data().get_defs_of_type("letter"):
		var letter := def as LetterDef
		if letter != null and letter.order <= 29:
			unlocked.append(letter.get_key())
	GameState.set("_unlocked_letters", unlocked)
	GameState.mark_letter_read(task_key)
	assert_true(GameState.is_letter_read(task_key))
	assert_false(GameState._unlocked_letters.has(next_key), "物品委托未交付，下一封不应出现")
	GameState.add_item("game:item/leafy", 3)
	assert_true(GameState.deliver_task(task_key))
	assert_true(GameState._unlocked_letters.has(next_key), "交付后下一封才放行")


func test_task_state_survives_a_reload() -> void:
	_read(TASK_POUR)
	var saved := GameState.to_dict()
	GameState.reset()
	assert_eq(GameState.get_open_task_count(), 0, "存档清掉之后待办也空了")
	assert_true(GameState.restore_from_dict(saved))
	assert_true(GameState.is_task_accepted(TASK_POUR), "读回来还认得这件委托")
	assert_eq(GameState.get_open_task_count(), 1)


## 数据守卫：33 件委托的引用、报酬、标题都得对得上，写错一个字就永远办不成
func test_every_task_is_wired_correctly() -> void:
	var data := _data()
	var letters := 0
	var goal_counts := {}
	for def in data.get_defs_of_type("letter"):
		var letter := def as LetterDef
		if letter == null or not letter.has_task():
			continue
		letters += 1
		goal_counts[letter.task_goal] = int(goal_counts.get(letter.task_goal, 0)) + 1
		assert_true(letter.task_title.begins_with("data."),
			"%s 的委托标题应当是翻译键" % letter.get_key())
		assert_true(letter.task_body.begins_with("data."),
			"%s 的委托正文应当是翻译键" % letter.get_key())
		assert_gt(letter.task_reward_coins, 0, "%s 的委托没写报酬" % letter.get_key())
		match letter.task_goal:
			LetterDef.TaskGoal.CRAFT_FOOD, LetterDef.TaskGoal.COLLECT:
				var item := data.get_def(letter.task_ref) as ItemDef
				assert_not_null(item, "%s 的 task_ref 指向不存在的条目：%s"
					% [letter.get_key(), letter.task_ref])
				if item != null and letter.task_goal == LetterDef.TaskGoal.CRAFT_FOOD:
					assert_true(item.is_food(), "%s 要求的不是一道菜" % letter.get_key())
			LetterDef.TaskGoal.CRAFT_TAG:
				var tag := data.get_def(letter.task_ref) as TagDef
				assert_not_null(tag, "%s 的 task_ref 指向不存在的标签：%s"
					% [letter.get_key(), letter.task_ref])
			LetterDef.TaskGoal.CRAFT_THEME:
				var theme := data.get_def(letter.task_ref) as ThemeDef
				assert_not_null(theme, "%s 的 task_ref 指向不存在的主题：%s"
					% [letter.get_key(), letter.task_ref])
				if theme != null:
					# P10.11 起主题仍由到站信解锁，委托信只负责「去做两道」
					assert_false(theme.unlock_letter.is_empty(),
						"%s 的委托主题应当由一封到站信解锁" % letter.get_key())
					assert_not_null(data.get_def(theme.unlock_letter),
						"%s 的主题解锁信不存在：%s" % [letter.get_key(), theme.unlock_letter])
			LetterDef.TaskGoal.CATALOG_COUNT:
				assert_gt(letter.task_amount, 0)
			LetterDef.TaskGoal.DELIVER_ORDER:
				assert_true(letter.task_ref.is_empty(),
					"%s 交订单不需要具体条目，task_ref 应当留空" % letter.get_key())
			LetterDef.TaskGoal.RESEARCH_RECIPE:
				var recipe := data.get_def(letter.task_ref) as RecipeDef
				assert_not_null(recipe, "%s 的 task_ref 指向不存在的配方：%s"
					% [letter.get_key(), letter.task_ref])
				if recipe != null:
					assert_true(recipe.needs_research(),
						"%s 要求研究的配方本身不用研究" % letter.get_key())
			_:
				fail_test("%s 的 task_goal 不是已知类型" % letter.get_key())
	# 批次 3：中东/西式两张旧「家常菜」单子改成具体菜，任务总数仍为 33
	var shawarma_task := data.get_def("game:letter/task_middle_east_note_1") as LetterDef
	assert_not_null(shawarma_task, "牧羊人的单子应当存在")
	if shawarma_task != null:
		assert_eq(shawarma_task.task_goal, LetterDef.TaskGoal.CRAFT_FOOD)
		assert_eq(shawarma_task.task_ref, "game:item/shawarma")
		assert_eq(shawarma_task.task_amount, 1)
	var kebab_task := data.get_def("game:letter/task_western_note_1") as LetterDef
	assert_not_null(kebab_task, "官员的餐牌应当存在")
	if kebab_task != null:
		assert_eq(kebab_task.task_goal, LetterDef.TaskGoal.CRAFT_FOOD)
		assert_eq(kebab_task.task_ref, "game:item/kebab")
		assert_eq(kebab_task.task_amount, 1)
	assert_eq(int(goal_counts.get(LetterDef.TaskGoal.CRAFT_FOOD, 0)), 8, "CRAFT_FOOD 应为 8 件")
	assert_eq(int(goal_counts.get(LetterDef.TaskGoal.CRAFT_TAG, 0)), 5, "CRAFT_TAG 应为 5 件")
	assert_eq(letters, 33, "第九轮：序章与东亚 7 件 + 站间过渡 10 件 + 八站各 2 件")
