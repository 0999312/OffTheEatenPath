class_name GameHud
extends Control
## 常驻 HUD：铜币 / 图鉴进度 / 未读信件 / 时钟（默认游戏时长，点击切现实时间），外加设置入口。
##
## 为什么不做成 UIPanel：HUD 不参与栈式导航，不该有背景遮罩、不该被 back() 关掉。
## 数据来自两条路：进树时向 GameState 拉一次快照，之后靠 EventBus 的增量事件刷新
## （push 增量 + pull 快照），这样 HUD 不需要每帧轮询。
##
## 全部控件在代码里搭：这一层只有一行纸牌，摆位随窗口宽度变，
## 用场景文件反而要多维护一份与代码同构的节点树。

## 面板入口被按下（面板 ID + 可选的打开参数）；由场景根节点决定怎么开
signal panel_requested(panel_id: String, data: Dictionary)

const THEME_PATH := "res://resources/themes/paper_theme.tres"
const EVENT_COIN := &"CoinChangedEvent"
const EVENT_CATALOG := &"CatalogDiscoveredEvent"
const EVENT_LETTER := &"LetterUnlockedEvent"
const EVENT_LETTER_READ := &"LetterReadEvent"
const EVENT_TASK_ACCEPTED := &"TaskAcceptedEvent"
const EVENT_TASK_DONE := &"TaskCompletedEvent"
const EVENT_RESTORED := &"StateRestoredEvent"

## 顶栏高度：卡片与设置按钮共用同一个基准（字号调大后由 54 提到 58）
const HUD_HEIGHT := 58.0
const EVENT_MATERIAL := &"MaterialChangedEvent"
const EVENT_ORDER := &"OrderChangedEvent"
const EVENT_LANGUAGE := &"LanguageChangedEvent"
const EVENT_CATALOG_SEEN := &"CatalogSeenEvent"

var _coins_label: Label
var _coin_caption: Label
var _catalog_label: Label
var _catalog_caption: Label
var _catalog_card: PanelContainer
var _catalog_dot: Panel
var _catalog_bar: ProgressBar
var _clock_label: Label
var _clock_card: PanelContainer
## 时钟默认显示本存档累计游戏时长；点击切现实时间。只记在本会话，重开回到默认值
var _show_playtime := true
var _mail_card: PanelContainer
var _mail_label: Label
## 已接未办完的待办数：大于 0 时 HUD 显示「待办 N」，点卡直达待办页
var _open_task_count := 0
var _orders_card: PanelContainer
var _orders_label: Label
var _clock_accumulator := 0.0
var _coin_card: PanelContainer
var _last_coins := -1
## 铜币变多时让整张卡轻轻跳一下；旧的还没播完就先收掉
var _coin_tween: Tween = null


func _ready() -> void:
	theme = load(THEME_PATH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.subscribe(EVENT_COIN, _on_coins_changed)
	EventBus.subscribe(EVENT_CATALOG, _on_catalog_changed)
	EventBus.subscribe(EVENT_LETTER, _on_letters_changed)
	EventBus.subscribe(EVENT_LETTER_READ, _on_letter_read)
	EventBus.subscribe(EVENT_TASK_ACCEPTED, _on_letter_read)
	EventBus.subscribe(EVENT_TASK_DONE, _on_letter_read)
	EventBus.subscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.subscribe(EVENT_ORDER, _on_orders_changed)
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.subscribe(EVENT_CATALOG_SEEN, _on_catalog_changed)
	refresh()


func _exit_tree() -> void:
	EventBus.unsubscribe(EVENT_COIN, _on_coins_changed)
	EventBus.unsubscribe(EVENT_CATALOG, _on_catalog_changed)
	EventBus.unsubscribe(EVENT_LETTER, _on_letters_changed)
	EventBus.unsubscribe(EVENT_LETTER_READ, _on_letter_read)
	EventBus.unsubscribe(EVENT_TASK_ACCEPTED, _on_letter_read)
	EventBus.unsubscribe(EVENT_TASK_DONE, _on_letter_read)
	EventBus.unsubscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.unsubscribe(EVENT_ORDER, _on_orders_changed)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.unsubscribe(EVENT_CATALOG_SEEN, _on_catalog_changed)


func _process(delta: float) -> void:
	_clock_accumulator += delta
	if _clock_accumulator < 1.0:
		return
	_clock_accumulator = 0.0
	_refresh_clock()


## 全部重新拉一遍快照
func refresh() -> void:
	_refresh_coins()
	_refresh_catalog()
	_refresh_clock()
	_refresh_mail()
	_refresh_orders()


# --- 搭界面 ---------------------------------------------------------------


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 26.0
	row.offset_top = 30.0
	row.offset_right = -26.0
	# 与设置按钮同高：整条 HUD 只有 HUD_HEIGHT，左半边的卡片也按这个基准压平
	row.offset_bottom = 30.0 + HUD_HEIGHT
	add_child(row)

	row.add_child(_build_coin_card())
	row.add_child(_build_catalog_card())
	row.add_child(_build_mail_card())
	row.add_child(_build_orders_card())
	row.add_child(PanelKit.spacer())
	row.add_child(_build_clock_card())
	row.add_child(_build_settings_button())


## 一张纸牌的统一外壳：白纸 + 墨线 + 贴纸厚度
func _card(content: Control) -> PanelContainer:
	var card := PanelContainer.new()
	var style := PanelKit.slab(PanelKit.CARD, PanelKit.INK, 5, 2)
	# HUD 卡片统一 HUD_HEIGHT 高，内容上下只留 2px（15px 小标题 + 24px 数值刚好 54px），
	# 避免被 slab 的默认 16px 内边距撑高，也让卡片与 58px 的设置按钮同高。
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size.y = HUD_HEIGHT
	var line := PanelKit.hbox(12)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)
	line.add_child(content)
	return card


func _build_coin_card() -> Control:
	var box := PanelKit.hbox(11)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var coin := CoinIcon.new()
	coin.name = "CoinMark"
	coin.custom_minimum_size = Vector2(36, 36)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.hole_color = PanelKit.CARD
	box.add_child(coin)

	var text_box := PanelKit.vbox(0)
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin_caption = PanelKit.label(I18n.t("ui.hud.coins"), 15, PanelKit.INK_SOFT)
	text_box.add_child(_coin_caption)
	_coins_label = PanelKit.label("0", 24, PanelKit.INK)
	_coins_label.name = "Coins"
	text_box.add_child(_coins_label)
	box.add_child(text_box)
	_coin_card = _card(box)
	_coin_card.resized.connect(func() -> void: _coin_card.pivot_offset = _coin_card.size * 0.5)
	return _coin_card


func _build_catalog_card() -> Control:
	var box := PanelKit.hbox(11)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var mark := PanelKit.icon("ui/book.svg", 24.0, PanelKit.INK)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)

	var text_box := PanelKit.vbox(2)
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var caption_row := PanelKit.hbox(4)
	_catalog_caption = PanelKit.caption(I18n.t("ui.hud.catalog"))
	_catalog_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption_row.add_child(_catalog_caption)
	_catalog_dot = _make_dot()
	caption_row.add_child(_catalog_dot)
	text_box.add_child(caption_row)
	_catalog_label = PanelKit.label("0 / 0", 19, PanelKit.INK)
	_catalog_label.name = "Catalog"
	text_box.add_child(_catalog_label)
	box.add_child(text_box)

	_catalog_bar = ProgressBar.new()
	_catalog_bar.custom_minimum_size = Vector2(132, 9)
	_catalog_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_catalog_bar.show_percentage = false
	_catalog_bar.max_value = 1.0
	_catalog_bar.step = 0.0
	# 轨道保持 9px 高，但 fill 不再被内描边吃掉 2px：底色和填充都画满 9px，
	# 描边改到轨道外侧 1px。这样进度条本身变厚，背景轨道的尺寸没变。
	var bar_bg := PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.PAPER_BACK, 5, 0)
	# slab 默认上下各 16px 的内容边距会把 ProgressBar 的最小高度撑到 32px
	bar_bg.content_margin_left = 0.0
	bar_bg.content_margin_right = 0.0
	bar_bg.content_margin_top = 0.0
	bar_bg.content_margin_bottom = 0.0
	_catalog_bar.add_theme_stylebox_override("background", bar_bg)
	var fill := PanelKit.slab(PanelKit.ACCENT, PanelKit.ACCENT, 5, 0)
	fill.content_margin_left = 0.0
	fill.content_margin_right = 0.0
	fill.content_margin_top = 0.0
	fill.content_margin_bottom = 0.0
	_catalog_bar.add_theme_stylebox_override("fill", fill)
	# 满进度时 fill 会盖住轨道；描边放在轨道外侧，任何进度都保留完整的框
	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -1.0
	frame.offset_top = -1.0
	frame.offset_right = 1.0
	frame.offset_bottom = 1.0
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = PanelKit.INK
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", frame_style)
	_catalog_bar.add_child(frame)
	box.add_child(_catalog_bar)
	_catalog_card = _card(box)
	PanelKit.tooltip(_catalog_card, I18n.t("ui.hud.catalog_tooltip"))
	_wire_card(_catalog_card, _open_catalog_newest)
	return _catalog_card


## 未读信件：平时不占位置，有信才出现
func _build_mail_card() -> Control:
	var box := PanelKit.hbox(9)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(PanelKit.icon("ui/bookmark.svg", 20.0, PanelKit.ACCENT))
	_mail_label = PanelKit.label(I18n.plural("ui.hud.mail_new", 0), 17, PanelKit.INK)
	_mail_label.name = "Mail"
	_mail_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_mail_label)

	_mail_card = _card(box)
	PanelKit.tooltip(_mail_card, I18n.t("ui.hud.mail_tooltip"))
	_wire_card(_mail_card, _open_mail)
	_mail_card.visible = false
	return _mail_card


## 订单板入口：第九封信（离店）之后才出现，显示当前可交的委托数
func _build_orders_card() -> Control:
	var box := PanelKit.hbox(9)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(PanelKit.icon("ui/clip.svg", 20.0, PanelKit.ACCENT))
	_orders_label = PanelKit.label(I18n.t("ui.hud.orders", [0]), 17, PanelKit.INK)
	_orders_label.name = "Orders"
	_orders_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_orders_label)

	var card := _card(box)
	PanelKit.tooltip(card, I18n.t("ui.hud.orders_tooltip"))
	_orders_card = card
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_orders_card_input)
	# 键盘也要能进订单板：Tab 到这张卡、回车
	PanelKit.make_focusable(card, _open_orders)
	# 订单还没开放时整张卡不存在：不给一个点了只弹「未开放」的入口。
	card.visible = GameState.is_orders_unlocked()
	return card


## 订单入口卡：引导的最后一步要把「去交第一单」的目标脉冲到这上面。
func get_orders_card() -> Control:
	return _orders_card


func _on_orders_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 先松焦点再开面板：面板打开时会记下「关掉后把焦点还给谁」，还回来的时候
		# 订单卡顶着一圈强调色描边，看起来像一直 hover 着（用户 2026-10-27 报）。
		if _orders_card != null and is_instance_valid(_orders_card):
			_orders_card.release_focus()
		_open_orders()


func _open_orders() -> void:
	Sfx.play(Sfx.Intent.CLICK)
	panel_requested.emit(UIKeys.ORDERS, {})


## 给 HUD 卡接上鼠标与键盘：鼠标左键、Tab 聚焦后回车都能触发。
## 鼠标那一半不能交给 PanelKit.make_focusable——它只在鼠标按下时松焦点，不触发动作。
func _wire_card(card: PanelContainer, action: Callable) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			card.release_focus()
			action.call()
	)
	PanelKit.make_focusable(card, action)


## 图鉴卡：打开最近发现的那一条（面板负责切页签并滚到它）
func _open_catalog_newest() -> void:
	Sfx.play(Sfx.Intent.CLICK)
	panel_requested.emit(UIKeys.CATALOG, {"focus": "newest"})


## 信箱卡：有待办时直达待办页，否则照旧落在未读页
func _open_mail() -> void:
	Sfx.play(Sfx.Intent.CLICK)
	if _open_task_count > 0:
		panel_requested.emit(UIKeys.MAIL, {"tab": 2})
	else:
		panel_requested.emit(UIKeys.MAIL, {})


func _build_clock_card() -> Control:
	var box := PanelKit.hbox(9)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := PanelKit.icon("media/time.svg", 20.0, PanelKit.INK_SOFT)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)
	_clock_label = PanelKit.label("0:00:00", 20, PanelKit.INK_SOFT)
	_clock_label.name = "Clock"
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 两种模式字数不同（H:MM:SS / HH:MM），给一个下限免得整张卡左右跳
	_clock_label.custom_minimum_size.x = 78.0
	box.add_child(_clock_label)
	var card := _card(box)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clock_card = card
	_wire_card(card, _toggle_clock_mode)
	_refresh_clock()
	return card


func _build_settings_button() -> Control:
	# 不给提示：齿轮图标 + 位置已经把「设置」说完，再多一个只写着「设置」的气泡是纯冗余。
	var button := PanelKit.icon_button("ui/settings.svg", HUD_HEIGHT, 30.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void:
		Sfx.play(Sfx.Intent.CLICK)
		panel_requested.emit(UIKeys.SETTINGS, {})
	)
	return button


# --- 刷新 -----------------------------------------------------------------


func _refresh_coins() -> void:
	var value := GameState.coins
	_coins_label.text = PanelKit.big_number_text(value)
	# 首次/读档后的刷新只记基线，不播：玩家没看见「从多少变成多少」
	if _last_coins >= 0 and value > _last_coins:
		_bump_coins()
	_last_coins = value


## 铜币增加时整张卡弹一下：数字本身不动，不干扰阅读
func _bump_coins() -> void:
	if _coin_card == null or not is_inside_tree():
		return
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	_coin_card.pivot_offset = _coin_card.size * 0.5
	_coin_tween = create_tween()
	_coin_tween.tween_property(_coin_card, "scale", Vector2(1.08, 1.08), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_coin_tween.tween_property(_coin_card, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_catalog() -> void:
	var found := GameState.get_catalog_discovered_count()
	var total := maxi(GameState.get_catalog_total(), 1)
	_catalog_label.text = "%d / %d" % [found, GameState.get_catalog_total()]
	_catalog_bar.value = clampf(float(found) / float(total), 0.0, 1.0)
	_catalog_dot.visible = GameState.get_catalog_new_count() > 0


## 一个 8px 的圆点：图鉴有新发现没看过时亮在标题旁边
func _make_dot() -> Panel:
	var dot := Panel.new()
	dot.name = "NewDot"
	dot.custom_minimum_size = Vector2(8.0, 8.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.82, 0.27, 0.20)
	style.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", style)
	return dot


## 时钟卡点击切换「本局时长 / 现实时间」；默认时长，重开游戏也回到时长
func _toggle_clock_mode() -> void:
	Sfx.play(Sfx.Intent.CLICK)
	_show_playtime = not _show_playtime
	_refresh_clock()


func _refresh_clock() -> void:
	if _show_playtime:
		var total := GameState.get_play_seconds()
		var hours := int(total / 3600)
		var minutes := int((total % 3600) / 60)
		_clock_label.text = "%d:%02d:%02d" % [hours, minutes, total % 60]
		PanelKit.tooltip(_clock_card, I18n.t("ui.hud.clock_playtime_tooltip"))
	else:
		var now := Time.get_time_dict_from_system()
		_clock_label.text = "%02d:%02d" % [now["hour"], now["minute"]]
		PanelKit.tooltip(_clock_card, I18n.t("ui.hud.clock_realtime_tooltip"))


## 未读信 + 已接未办完的委托：两件事都发生在信箱里，共用一张卡。
## 读委托信会自动收下（第四轮反馈），所以读完但没办完的委托仍占着这张卡。
func _refresh_mail() -> void:
	var unread := GameState.get_unread_letter_count()
	var open := GameState.get_open_task_count()
	_open_task_count = open
	_mail_card.visible = unread > 0 or open > 0
	if not _mail_card.visible:
		return
	# 待办优先：它是「得去干活」的强提示，未读信只是「有东西可看」。
	# 两件事都发生时才并列显示（保留原有的合并文案）。
	if open > 0 and unread > 0:
		_mail_label.text = I18n.t("ui.hud.mail_task", [unread, open])
	elif open > 0:
		_mail_label.text = I18n.plural("ui.hud.task_open", open)
	else:
		_mail_label.text = I18n.plural("ui.hud.mail_new", unread)


func _refresh_orders() -> void:
	if _orders_card == null:
		return
	_orders_card.visible = GameState.is_orders_unlocked()
	if not _orders_card.visible:
		return
	_orders_label.text = I18n.t("ui.hud.orders", [GameState.get_orders().size()])


func _on_coins_changed(_event: Event) -> void:
	_refresh_coins()


func _on_catalog_changed(_event: Event) -> void:
	_refresh_catalog()


func _on_letters_changed(_event: Event) -> void:
	_refresh_mail()
	_refresh_catalog()


func _on_letter_read(_event: Event) -> void:
	_refresh_mail()
	_refresh_orders()


func _on_orders_changed(_event: Event) -> void:
	_refresh_orders()


## 读档后整体重拉：铜币 / 图鉴 / 未读数都可能与进树时的快照不同
func _on_state_restored(_event: Event) -> void:
	refresh()


## 切语言后把常驻文案换成新语言；数字类文案要重走一次格式化
func _on_language_changed(_event: Event) -> void:
	_coin_caption.text = I18n.t("ui.hud.coins")
	_catalog_caption.text = I18n.t("ui.hud.catalog")
	PanelKit.tooltip(_orders_card, I18n.t("ui.hud.orders_tooltip"))
	PanelKit.tooltip(_catalog_card, I18n.t("ui.hud.catalog_tooltip"))
	PanelKit.tooltip(_mail_card, I18n.t("ui.hud.mail_tooltip"))
	# 时钟的 tooltip 与数字都随语言/模式重算
	_refresh_clock()
	# 铜币走 big_number_text，中文用「万/亿」、英文用 k/M/B —— 单位跟着语言变，
	# 必须重算；否则切到英文后还挂着「123.5万」（2026-10-27 巡检发现）。
	_refresh_coins()
	_refresh_mail()
	_refresh_orders()
