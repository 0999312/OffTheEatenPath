class_name LetterDetailPanel
extends GamePanel
## 信件详情（POPUP 层）：整封一次显示；打开即视为「读过」，随信的东西这时收下。
##
## 带委托的信多出一块「信里夹着的这件事」：读信的同时就记进待办，不再另点一次
## 「接下这件事」（第四轮反馈 m02344；推翻 2026-10-28 §3 的「读完不等于答应」）。

## 正文宽度：和面板的卡片宽度对齐，太长会读串行
const TEXT_WIDTH := 660.0


func _on_open(data: Dictionary = {}) -> void:
	var key := String(data.get("letter", ""))
	var letter := def_of(key) as LetterDef
	if letter == null:
		push_warning("[LetterDetailPanel] 找不到信件：%s" % key)
		close_self()
		return
	set_title(letter.localized(&"title"))
	set_subtitle(I18n.t("ui.mail.order", [letter.order]))
	GameState.mark_letter_read(key)
	super._on_open(data)
	_build(letter)


func refresh() -> void:
	# 信件内容是静态的，打开后不再变；这里只需要保证外壳不空
	pass


func _build(letter: LetterDef) -> void:
	clear_content()
	var body := PanelKit.label(letter.localized(&"body"), 18)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = TEXT_WIDTH
	content.add_child(body)
	if not letter.localized(&"description").is_empty():
		content.add_child(PanelKit.hint(letter.localized(&"description"), TEXT_WIDTH))
	if not letter.handwriting.is_empty():
		var hand := PanelKit.label(I18n.t("ui.letter.handwriting_%s" % letter.handwriting), 14, PanelKit.INK_DIM)
		hand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hand.custom_minimum_size.x = TEXT_WIDTH
		content.add_child(hand)
	if letter.has_task():
		content.add_child(PanelKit.divider())
		_build_task(letter)
	var extras := _rewards_text(letter)
	if not extras.is_empty():
		content.add_child(PanelKit.divider())
		content.add_child(PanelKit.label(I18n.t("ui.letter.attached"), 17, PanelKit.INK_SOFT))
		content.add_child(PanelKit.hint(extras, TEXT_WIDTH))
	if letter.unlocks_offline:
		content.add_child(PanelKit.hint(I18n.t("ui.letter.offline_unlocked"), TEXT_WIDTH))


# --- 委托 -----------------------------------------------------------------


## 一块小纸片：标题、为什么、要做成什么样、现在的进度、报酬，最后是一个决定。
func _build_task(letter: LetterDef) -> void:
	var key := letter.get_key()
	content.add_child(PanelKit.label(I18n.t("ui.letter.task_heading"), 17, PanelKit.INK_SOFT))

	var panel := PanelKit.paper(PanelKit.CARD, 8)
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.content_margin_left = 16.0
	style.content_margin_top = 14.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	var box := PanelKit.vbox(8)
	panel.add_child(box)
	content.add_child(panel)

	box.add_child(PanelKit.label(letter.localized(&"task_title"), 20))
	if not letter.localized(&"task_body").is_empty():
		var task_body := PanelKit.label(letter.localized(&"task_body"), 17, PanelKit.INK_SOFT)
		task_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		task_body.custom_minimum_size.x = TEXT_WIDTH - 60.0
		box.add_child(task_body)

	var goal := PanelKit.hbox(12)
	goal.add_child(PanelKit.label(_task_goal_text(letter), 17))
	var progress := GameState.get_task_progress(letter)
	goal.add_child(PanelKit.label(
		I18n.t("ui.letter.task_progress", [progress.x, progress.y]), 17, PanelKit.ACCENT_DEEP))
	box.add_child(goal)
	if letter.task_goal == LetterDef.TaskGoal.CRAFT_FOOD:
		box.add_child(PanelKit.hint(I18n.t("ui.mail.task_hint", [_def_name(letter.task_ref)]), TEXT_WIDTH - 60.0))
	if not GameState.is_task_completed(key) and GameState.is_task_hand_in(letter):
		var need := GameState.get_task_delivery_need(letter)
		var have := GameState.get_amount(letter.task_ref)
		if need > 0 and have < need:
			box.add_child(PanelKit.hint(
				I18n.t("ui.letter.task_need_stock", [_def_name(letter.task_ref), need, have]), TEXT_WIDTH - 60.0))
		elif GameState.can_deliver_task(key):
			box.add_child(PanelKit.hint(I18n.t(
				"ui.letter.task_ready" if need > 0 else "ui.letter.task_ready_confirm"), TEXT_WIDTH - 60.0))

	var reward := _task_reward_text(letter)
	if not reward.is_empty():
		box.add_child(PanelKit.label(I18n.t("ui.letter.task_reward", [reward]), 16, PanelKit.INK_SOFT))

	box.add_child(_task_action(letter, key))


## 打开信的时候 GameState 已经把它记进待办了；这里只给交付/确认，隐式委托仍只报状态。
func _task_action(letter: LetterDef, key: String) -> Control:
	if GameState.is_task_completed(key):
		var finished := PanelKit.button(I18n.t("ui.letter.task_done"), Sfx.Intent.NONE)
		finished.disabled = true
		return finished
	if not GameState.is_task_hand_in(letter):
		var waiting := PanelKit.button(I18n.t("ui.letter.task_accepted"), Sfx.Intent.NONE)
		waiting.disabled = true
		return waiting
	var confirm := letter.task_goal == LetterDef.TaskGoal.CRAFT_THEME \
			or letter.task_goal == LetterDef.TaskGoal.CATALOG_COUNT \
			or letter.task_goal == LetterDef.TaskGoal.CRAFT_TAG
	var action := PanelKit.button(I18n.t(
		"ui.letter.task_confirm" if confirm else "ui.letter.task_hand_in"), Sfx.Intent.CONFIRM)
	action.disabled = not GameState.can_deliver_task(key)
	if not action.disabled:
		action.pressed.connect(func() -> void:
			if GameState.deliver_task(key):
				_build(letter)
		)
	return action


## 目标那一句：按类型拼，名字一律走数据里的显示名
func _task_goal_text(letter: LetterDef) -> String:
	var amount := letter.task_target()
	match letter.task_goal:
		LetterDef.TaskGoal.CRAFT_FOOD:
			return I18n.t("ui.letter.task_craft", [_def_name(letter.task_ref), amount])
		LetterDef.TaskGoal.CRAFT_THEME:
			return I18n.t("ui.letter.task_craft_theme", [_def_name(letter.task_ref), amount])
		LetterDef.TaskGoal.CRAFT_TAG:
			return I18n.t("ui.letter.task_craft_tag", [_def_name(letter.task_ref), amount])
		LetterDef.TaskGoal.COLLECT:
			return I18n.t("ui.letter.task_collect", [_def_name(letter.task_ref), amount])
		LetterDef.TaskGoal.CATALOG_COUNT:
			return I18n.t("ui.letter.task_catalog", [amount])
		LetterDef.TaskGoal.DELIVER_ORDER:
			return I18n.t("ui.letter.task_deliver", [amount])
		LetterDef.TaskGoal.RESEARCH_RECIPE:
			return I18n.t("ui.letter.task_research", [_def_name(letter.task_ref)])
	return ""


func _def_name(key: String) -> String:
	var def := def_of(key)
	if def == null:
		return key
	return def.localized(&"display_name")


func _task_reward_text(letter: LetterDef) -> String:
	var parts: Array[String] = []
	if letter.task_reward_coins > 0:
		parts.append(PanelKit.coins_text(letter.task_reward_coins))
	for stack in letter.task_rewards:
		if stack == null:
			continue
		parts.append("%s × %d" % [stack_name(stack), stack.amount])
	return I18n.list_sep().join(parts)


func _rewards_text(letter: LetterDef) -> String:
	var parts: Array[String] = []
	if letter.reward_coins > 0:
		parts.append(PanelKit.coins_text(letter.reward_coins))
	for stack in letter.rewards:
		if stack == null:
			continue
		parts.append("%s × %d" % [stack_name(stack), stack.amount])
	return I18n.list_sep().join(parts)
