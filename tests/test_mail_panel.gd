extends GutTest
## 信箱页与信件详情弹窗是两层：详情在 POPUP，信箱在 NORMAL，关掉详情时信箱不会
## 收到 _on_resume。第五轮反馈「读完信，未读卡还留在信箱里」就是这里漏了刷新。
## 这里锁住「读完 / 收下委托后，背后那页当场重排」。

const MAIL := "idle_food:mail"
const DETAIL := "idle_food:letter_detail"
const WINDOW := "game:letter/window"
const TASK_WINDOW := "game:letter/task_window_1"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _open_mail() -> MailPanel:
	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string(MAIL)) as MailPanel
	await wait_process_frames(2)
	return panel


func _read(letter_key: String) -> void:
	var location := ResourceLocation.from_string(DETAIL)
	var panel := UIManager.open_panel(location, {"letter": letter_key})
	await wait_process_frames(1)
	assert_not_null(panel, "信件详情应能打开：%s" % letter_key)
	UIManager.close_panel(location)
	# 面板刷新有 250ms 合并节流（GamePanel.MIN_REFRESH_GAP_MS），等它落地
	await get_tree().create_timer(0.4).timeout


func _keys(letters: Array[LetterDef]) -> Array[String]:
	var keys: Array[String] = []
	for letter in letters:
		keys.append(letter.get_key())
	return keys


func test_reading_a_letter_moves_it_out_of_unread_behind_the_popup() -> void:
	var mail := await _open_mail()
	assert_true(_keys(mail._unread).has(WINDOW), "开局第一封应是未读")

	await _read(WINDOW)

	assert_false(_keys(mail._unread).has(WINDOW), "读完不该还挂在未读页")
	assert_true(_keys(mail._read).has(WINDOW), "读完应出现在已读页")
	assert_eq(_keys(mail._todos).size(), 0, "这封没有委托，待办仍是空的")


func test_reading_a_task_letter_puts_it_in_the_todo_tab() -> void:
	var mail := await _open_mail()
	await _read(WINDOW)
	assert_true(_keys(mail._unread).has(TASK_WINDOW), "读完第一封后，第一件委托应寄到")

	await _read(TASK_WINDOW)

	assert_true(GameState.is_task_accepted(TASK_WINDOW), "读委托信就收下")
	assert_eq(GameState.get_open_task_count(), 1, "待办计数应立刻加一")
	assert_false(_keys(mail._unread).has(TASK_WINDOW), "委托信不该留在未读页")
	assert_true(_keys(mail._read).has(TASK_WINDOW), "它仍留在已读页，信不搬走")
	assert_true(_keys(mail._todos).has(TASK_WINDOW), "待办页应出现这张任务卡")


## 页脚要说清下一封信在等什么：卡住时玩家最想知道的就是这一句（用户 2026-10-29 报）。
func test_footer_names_what_the_next_letter_waits_for() -> void:
	var mail := await _open_mail()
	assert_ne(mail._waiting_hint(), "", "新档的页脚应说明下一封信在等什么")

	var catalog := LetterDef.new()
	catalog.condition = LetterDef.Condition.CATALOG_COUNT
	catalog.condition_value = 90
	assert_string_contains(mail._waiting_text(catalog), "90", "图鉴门槛要说清凑到几条")

	var crafted := LetterDef.new()
	crafted.condition = LetterDef.Condition.FOOD_CRAFTED
	crafted.condition_ref = "game:item/cookie"
	var cookie := mail.def_of("game:item/cookie") as ItemDef
	assert_not_null(cookie, "曲奇应在数据层")
	if cookie != null:
		assert_string_contains(mail._waiting_text(crafted), cookie.localized(), "做出某样的门槛要点名")

	var task := LetterDef.new()
	task.condition = LetterDef.Condition.TASK_COMPLETED
	task.condition_ref = "game:letter/task_window_1"
	assert_eq(mail._waiting_text(task), I18n.t("ui.mail.waiting_task"), "任务门槛要提示办完")


## 到站信的门禁同时要说“读完上一封”和“图鉴还差几条”，不能只说等一封信。
func test_arrival_footer_names_previous_letter_and_catalog_gap() -> void:
	var mail := await _open_mail()
	var have := GameState.get_catalog_discovered_count()
	var arrival := LetterDef.new()
	arrival.condition = LetterDef.Condition.AFTER_LETTER
	arrival.condition_ref = "game:letter/beyond_paper"
	arrival.catalog_min = have + 3
	var text := mail._waiting_text(arrival)
	assert_string_contains(text, str(arrival.catalog_min), "要说清图鉴门槛")
	assert_string_contains(text, "3", "要说清还差几条")
	var previous := mail.def_of("game:letter/beyond_paper")
	if previous != null:
		assert_string_contains(text, previous.localized(), "要点名读完哪一封")


## 上一封的显式委托没交付时，页脚要点名那封信，而不是笼统说“等一封信”。
func test_footer_names_the_task_holding_the_next_letter() -> void:
	var mail := await _open_mail()
	await _read(WINDOW)
	await _read(TASK_WINDOW)
	var blocking := mail.def_of(TASK_WINDOW) as LetterDef
	assert_not_null(blocking, "委托信应在数据层")
	if blocking == null:
		return
	var next := LetterDef.new()
	next.order = 3
	next.condition = LetterDef.Condition.AFTER_LETTER
	next.condition_ref = TASK_WINDOW
	var text := mail._waiting_text(next)
	assert_string_contains(text, blocking.localized(), "要点名还没交付的委托")
	assert_string_contains(text, "办妥", "要说明先交付才放行")
	assert_false(text.contains("还差 0"), "不该只显示图鉴差额")


## 待办卡的交付按钮要真的扣物品并完成任务，而不只是换文案。
func test_todo_card_hand_in_button_delivers_the_item() -> void:
	var mail := await _open_mail()
	await _read(WINDOW)
	await _read(TASK_WINDOW)
	GameState.add_item("game:item/pour_over", 1)
	var letter := mail.def_of(TASK_WINDOW) as LetterDef
	assert_not_null(letter, "委托信应在数据层")
	if letter == null:
		return
	var card := mail._task_card(letter)
	var action: Button = null
	for node in card.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and not button.disabled:
			action = button
			break
	assert_not_null(action, "可交付时待办卡应有按钮")
	if action == null:
		card.free()
		return
	action.pressed.emit()
	assert_true(GameState.is_task_completed(TASK_WINDOW), "点交付应完成任务")
	assert_eq(GameState.get_amount("game:item/pour_over"), 0, "交付应扣掉成品")
	card.free()
