class_name MailPanel
extends GamePanel
## 信箱：分「未读 / 已读 / 待办」三页签；前两页按收到顺序排列，点开进入详情弹窗（整封一次看完）。
##
## 没寄到的信不再一封一行地占位置——那样「？？？」会刷满整页。
## 它们只是「还在路上」，用页脚一句话带过就够，不假装成可点的东西。
## 已收到的信也会越积越多，所以读过的那批收进第二个页签，
## 第一页永远只剩「还没拆的」。
##
## 待办页只放**收下过的**事：读委托信就自动收下（第五轮反馈 2026-10-29），
## 读过信但没进待办的旧档，再打开那封信时补上——这一页是玩家的承诺清单，
## 不是任务公告板。

const TAB_UNREAD := 0
const TAB_READ := 1
const TAB_TODO := 2

var _tab_index := TAB_UNREAD
## 当前页的几拨信，页签切换只换内容、不重扫数据
var _unread: Array[LetterDef] = []
var _read: Array[LetterDef] = []
var _todos: Array[LetterDef] = []
## 还在路上（未解锁）的信数，放页脚
var _pending := 0
## 本次会话第一次建页签：只有这时才做「未读空了自动翻到已读」
var _first_build := true


func _on_open(data: Dictionary = {}) -> void:
	# HUD 信箱卡带 {"tab": 2} 进来：直接落在待办页。
	# 先关掉「首次无未读自动翻已读」的兜底，否则它会把玩家刚点的那一页覆盖掉。
	if data.has("tab"):
		_tab_index = clampi(int(data["tab"]), 0, TAB_TODO)
		_first_build = false
	super._on_open(data)


func refresh() -> void:
	clear_content()
	PanelKit.clear(toolbar)
	PanelKit.clear(footer)
	set_title(I18n.t("ui.mail.title"))
	set_subtitle(I18n.t("ui.mail.subtitle"))

	var letters := defs_of("letter")
	letters.sort_custom(func(a: GameDef, b: GameDef) -> bool:
		return (a as LetterDef).order < (b as LetterDef).order
	)
	_unread.clear()
	_read.clear()
	_todos = GameState.get_task_letters()
	_pending = 0
	var unlocked := GameState.get_unlocked_letters()
	for def in letters:
		var letter := def as LetterDef
		if not unlocked.has(letter.get_key()):
			_pending += 1
			continue
		if GameState.is_letter_read(letter.get_key()):
			_read.append(letter)
		else:
			_unread.append(letter)

	# 第一次打开时如果一封未读都没有，直接落在已读页——别让人对着空页找信
	if _first_build and _unread.is_empty() and not _read.is_empty():
		_tab_index = TAB_READ
	_first_build = false

	_build_tabs()
	_fill_tab(_tab_index)


func _build_tabs() -> void:
	var bar := PanelKit.tab_bar([
		I18n.t("ui.mail.tab_unread", [_unread.size()]),
		I18n.t("ui.mail.tab_read", [_read.size()]),
		I18n.t("ui.mail.tab_todo", [GameState.get_open_task_count()]),
	])
	bar.current_tab = clampi(_tab_index, 0, bar.tab_count - 1)
	# 先设好 current_tab 再接信号：否则重建时会补发一次 tab_changed（切页音 + 白重画一遍）
	bar.tab_changed.connect(_on_tab_changed)
	toolbar.add_child(bar)


func _on_tab_changed(index: int) -> void:
	if index == _tab_index:
		return
	Sfx.play(Sfx.Intent.TAB)
	_fill_tab(index)
	flash_content()


## 只重画内容区：页签、标题、页脚都在滚动区外，切页时不该动
func _fill_tab(index: int) -> void:
	_tab_index = clampi(index, 0, TAB_TODO)
	clear_content()
	PanelKit.clear(footer)
	_scroll.scroll_vertical = 0
	var current: Array[LetterDef] = []
	match _tab_index:
		TAB_UNREAD: current = _unread
		TAB_READ: current = _read
		_: current = _todos
	if current.is_empty():
		content.add_child(PanelKit.hint(_empty_text()))
	elif _tab_index == TAB_TODO:
		for letter in current:
			content.add_child(_task_card(letter))
	else:
		for letter in current:
			content.add_child(_letter_card(letter))
	# 「还在路上」只在收信的那两页有意义：待办页说的是另一件事
	if _pending > 0 and _tab_index != TAB_TODO:
		footer.add_child(PanelKit.hint(I18n.t("ui.mail.pending", [_pending]), 660))
		var waiting := _waiting_hint()
		if not waiting.is_empty():
			footer.add_child(PanelKit.hint(waiting, 660))


## 空页的那句话：整本信都没寄到时说的是另一回事
func _empty_text() -> String:
	if _tab_index == TAB_TODO:
		return I18n.t("ui.mail.empty_todo")
	if defs_of("letter").is_empty():
		return I18n.t("ui.mail.empty")
	return I18n.t("ui.mail.empty_unread" if _tab_index == TAB_UNREAD else "ui.mail.empty_read")


## 下一封信在等什么。信件按 order 逐封放行，卡住时玩家最想知道的就是这一句。
func _waiting_hint() -> String:
	var next := GameState.get_next_locked_letter()
	if next == null:
		return ""
	return _waiting_text(next)


func _waiting_text(letter: LetterDef) -> String:
	var blocking := GameState.get_task_blocking_letter(letter)
	if blocking != null:
		return I18n.t("ui.mail.waiting_task_hand_in", [blocking.localized()])
	var have := GameState.get_catalog_discovered_count()
	if letter.catalog_min > 0 and have < letter.catalog_min:
		var short := letter.catalog_min - have
		if letter.condition == LetterDef.Condition.AFTER_LETTER:
			var previous := def_of(letter.condition_ref)
			var previous_name := previous.localized() if previous != null else I18n.t("ui.mail.waiting_letter")
			return I18n.t("ui.mail.waiting_letter_catalog", [previous_name, letter.catalog_min, short])
		return I18n.t("ui.mail.waiting_catalog_remaining", [letter.catalog_min, short])
	match letter.condition:
		LetterDef.Condition.CATALOG_COUNT:
			return I18n.t("ui.mail.waiting_catalog_remaining", [letter.condition_value, maxi(0, letter.condition_value - have)])
		LetterDef.Condition.FOOD_CRAFTED:
			var food := def_of(letter.condition_ref)
			if food != null:
				return I18n.t("ui.mail.waiting_craft", [food.localized()])
			return I18n.t("ui.mail.waiting_other")
		LetterDef.Condition.TASK_COMPLETED:
			return I18n.t("ui.mail.waiting_task")
		LetterDef.Condition.AFTER_LETTER:
			return I18n.t("ui.mail.waiting_letter")
	return I18n.t("ui.mail.waiting_other")


## 一封信做成一张信封样子的卡片：左边一枚贴纸，右边标题与「第几封 / 未读」
func _letter_card(letter: LetterDef) -> PanelContainer:
	var key := letter.get_key()
	var unread := not GameState.is_letter_read(key)

	var card := PanelKit.paper(PanelKit.CARD_HI if unread else PanelKit.CARD, 10)
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 16.0
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 14.0
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 16.0
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 14.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var row := PanelKit.hbox(14)
	card.add_child(row)

	var seal := ItemBadge.new()
	seal.configure("ui/bookmark.svg", letter.localized(&"title"), PanelKit.ACCENT_DEEP, 44.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seal)

	var text_box := PanelKit.vbox(3)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label := PanelKit.label(letter.localized(&"title"), 19)
	text_box.add_child(title_label)
	var meta := PanelKit.hbox(8)
	meta.add_child(PanelKit.label(I18n.t("ui.mail.order", [letter.order]), 15, PanelKit.INK_SOFT))
	if unread:
		meta.add_child(PanelKit.badge(I18n.t("ui.mail.unread"), PanelKit.ACCENT_DEEP, PanelKit.CARD_HI))
	text_box.add_child(meta)
	row.add_child(text_box)

	# 只有「未读」徽章一个标记：早先右边还有个圆点，两个记号说同一件事（报告 P2-10）

	card.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play(Sfx.Intent.LETTER)
			UIManager.open_panel(ResourceLocation.from_string(UIKeys.LETTER_DETAIL), {"letter": key})
	)
	return card

## 一件应下的事：左边一道竖条标状态，右边做什么、做到哪了、办成给什么。
## 办妥的不消失——回看是这一页存在的第二个理由。
func _task_card(letter: LetterDef) -> PanelContainer:
	var key := letter.get_key()
	var done := GameState.is_task_completed(key)
	var progress := GameState.get_task_progress(letter)
	var thing := def_of(letter.task_ref)
	var thing_name := thing.localized() if thing != null else letter.task_ref

	var card := PanelKit.paper(PanelKit.CARD if done else PanelKit.CARD_HI, 10)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	style.content_margin_left = 14.0
	style.content_margin_top = 14.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var row := PanelKit.hbox(14)
	card.add_child(row)

	# 竖条：不用字符记号，省得字体缺字。颜色本身就是状态
	var edge := ColorRect.new()
	edge.color = PanelKit.INK_DIM if done else PanelKit.ACCENT
	edge.custom_minimum_size = Vector2(4, 0)
	edge.size_flags_vertical = Control.SIZE_FILL
	row.add_child(edge)

	var box := PanelKit.vbox(4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(PanelKit.label(letter.localized(&"task_title"), 19,
		PanelKit.INK_DIM if done else PanelKit.INK))
	box.add_child(PanelKit.label(
		I18n.t("ui.mail.task_from", [letter.localized(&"title")]), 15, PanelKit.INK_SOFT))
	if letter.task_goal == LetterDef.TaskGoal.CRAFT_FOOD:
		var target := def_of(letter.task_ref)
		var target_name := target.localized() if target != null else letter.task_ref
		box.add_child(PanelKit.hint(I18n.t("ui.mail.task_hint", [target_name]), 420))

	var line := PanelKit.hbox(10)
	var bar := PanelKit.progress_bar(8.0)
	bar.custom_minimum_size.x = 160.0
	bar.value = 1.0 if done else clampf(float(progress.x) / float(progress.y), 0.0, 1.0)
	line.add_child(bar)
	line.add_child(PanelKit.label(
		I18n.t("ui.letter.task_progress", [progress.x, progress.y]), 15, PanelKit.INK_SOFT))
	box.add_child(line)
	if not done and GameState.is_task_hand_in(letter):
		var need := GameState.get_task_delivery_need(letter)
		var have := GameState.get_amount(letter.task_ref)
		if need > 0 and have < need:
			box.add_child(PanelKit.hint(
				I18n.t("ui.letter.task_need_stock", [thing_name, need, have]), 420))
		elif GameState.can_deliver_task(key):
			box.add_child(PanelKit.hint(I18n.t(
				"ui.letter.task_ready" if need > 0 else "ui.letter.task_ready_confirm"), 420))
	row.add_child(box)

	var tail := PanelKit.vbox(4)
	tail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if letter.task_reward_coins > 0:
		var coins := PanelKit.label(PanelKit.coins_text(letter.task_reward_coins), 16, PanelKit.COIN)
		coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tail.add_child(coins)
	if done:
		var badge := PanelKit.badge(I18n.t("ui.mail.task_done"), PanelKit.CARD, PanelKit.INK_SOFT)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		tail.add_child(badge)
	elif GameState.can_deliver_task(key):
		var action := PanelKit.button(I18n.t(
			"ui.letter.task_confirm" if letter.task_goal == LetterDef.TaskGoal.CRAFT_THEME \
					or letter.task_goal == LetterDef.TaskGoal.CATALOG_COUNT \
					or letter.task_goal == LetterDef.TaskGoal.CRAFT_TAG \
					else "ui.letter.task_hand_in"), Sfx.Intent.CONFIRM)
		action.pressed.connect(func() -> void:
			if GameState.deliver_task(key):
				refresh()
		)
		tail.add_child(action)
	row.add_child(tail)

	card.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play(Sfx.Intent.LETTER)
			UIManager.open_panel(ResourceLocation.from_string(UIKeys.LETTER_DETAIL), {"letter": key})
	)
	return card
