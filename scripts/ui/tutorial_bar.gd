class_name TutorialBar
extends Control
## 四步引导条：贴着房间下沿的一条纸，标题 + 一句说明 + 「去」+「跳过」。
##
## 只做呈现与事件接线；步骤表在 scripts/systems/tutorial.gd、进度与奖励在
## GameState / Tutorial。鼠标默认 IGNORE，只有两个按钮接收点击，
## 所以它盖在房间上方也不会挡住左右两列的入口卡。

signal target_requested(panel_id: String)
## 引导进度变了：由 main 决定什么时候落盘（不做每帧存档）
signal progress_changed

const TUTORIAL := preload("res://scripts/systems/tutorial.gd")
const THEME_PATH := "res://resources/themes/paper_theme.tres"
const EVENT_LETTER_READ := &"LetterReadEvent"
const EVENT_CRAFT := &"CraftCompletedEvent"
const EVENT_ORDER := &"OrderChangedEvent"
const EVENT_RESTORED := &"StateRestoredEvent"
const EVENT_LANGUAGE := &"LanguageChangedEvent"

## 由 main 注入：给定面板 ID，返回要脉冲的那张入口卡
var target_provider := Callable()

var _panel: PanelContainer
var _title: Label
var _body: Label
var _go: Button
var _skip: Button
var _step_index := -1
var _hint_target: Control
var _hint_original := Color.WHITE
var _pulse: Tween


func _ready() -> void:
	theme = load(THEME_PATH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.subscribe(EVENT_LETTER_READ, _on_letter_read)
	EventBus.subscribe(EVENT_CRAFT, _on_craft_completed)
	EventBus.subscribe(EVENT_ORDER, _on_order_changed)
	EventBus.subscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	_sync()
	_check_conditions()


func _exit_tree() -> void:
	_stop_pulse()
	EventBus.unsubscribe(EVENT_LETTER_READ, _on_letter_read)
	EventBus.unsubscribe(EVENT_CRAFT, _on_craft_completed)
	EventBus.unsubscribe(EVENT_ORDER, _on_order_changed)
	EventBus.unsubscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)


func _build() -> void:
	_panel = PanelKit.paper(PanelKit.CARD_HI, 10)
	_panel.name = "TutorialCard"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 150.0
	_panel.offset_right = -150.0
	_panel.offset_top = -104.0
	_panel.offset_bottom = -18.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var row := PanelKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var text := PanelKit.vbox(2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_title = PanelKit.label("", 17, PanelKit.INK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_title)
	_body = PanelKit.hint("", 560)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_body)

	_go = PanelKit.button(I18n.t("ui.tutorial.go"))
	_go.custom_minimum_size.x = 64.0
	_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_go.pressed.connect(_on_go_pressed)
	row.add_child(_go)

	_skip = PanelKit.button(I18n.t("ui.tutorial.skip"))
	_skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip.pressed.connect(_on_skip_pressed)
	row.add_child(_skip)


func _sync() -> void:
	var step := GameState.get_tutorial_step()
	if GameState.is_tutorial_done() or step >= TUTORIAL.step_count():
		_panel.visible = false
		_step_index = -1
		_stop_pulse()
		return
	var entry := TUTORIAL.step(step)
	if entry.is_empty():
		_panel.visible = false
		_stop_pulse()
		return
	# 第四步要用订单板，但订单板在第九封信前不存在：整条先收起，解锁后自动回来。
	if bool(entry.get("requires_orders", false)) and not GameState.is_orders_unlocked():
		_panel.visible = false
		_step_index = -1
		_stop_pulse()
		return
	_step_index = step
	_panel.visible = true
	_title.text = I18n.t(String(entry.get("title", "")))
	_body.text = I18n.t(String(entry.get("body", "")))
	_go.text = I18n.t("ui.tutorial.go")
	_skip.text = I18n.t("ui.tutorial.skip")
	_pulse_target(_resolve_target(entry))


## 当前步骤的目标面板；main 用它决定脉冲哪张卡，切语言/重建右栏后也可再调。
func refresh_target() -> void:
	var entry := TUTORIAL.step(GameState.get_tutorial_step())
	if entry.is_empty() or (bool(entry.get("requires_orders", false)) and not GameState.is_orders_unlocked()):
		_stop_pulse()
		return
	_pulse_target(_resolve_target(entry))


func _resolve_target(entry: Dictionary) -> Control:
	if entry.is_empty() or not target_provider.is_valid():
		return null
	return target_provider.call(String(entry.get("panel", ""))) as Control


func _pulse_target(target: Control) -> void:
	if target == _hint_target and _pulse != null and _pulse.is_valid():
		return
	_stop_pulse()
	if target == null or not is_instance_valid(target):
		return
	_hint_target = target
	_hint_original = target.modulate
	_pulse = create_tween().set_loops()
	_pulse.tween_property(target, "modulate:a", 0.55, 0.55) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(target, "modulate:a", 1.0, 0.55) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	if is_instance_valid(_hint_target):
		_hint_target.modulate = _hint_original
	_hint_target = null


func _on_go_pressed() -> void:
	var entry := TUTORIAL.step(GameState.get_tutorial_step())
	if entry.is_empty():
		return
	var panel_id := String(entry.get("panel", ""))
	Sfx.play(Sfx.Intent.CLICK)
	target_requested.emit(panel_id)


func _on_skip_pressed() -> void:
	Sfx.play(Sfx.Intent.CLICK)
	GameState.skip_tutorial()
	_sync()
	progress_changed.emit()


func _on_letter_read(_event: Event) -> void:
	_check_conditions()


func _on_craft_completed(_event: Event) -> void:
	_check_conditions()


func _on_order_changed(_event: Event) -> void:
	_check_conditions()


func _on_state_restored(_event: Event) -> void:
	_sync()
	_check_conditions()


func _on_language_changed(_event: Event) -> void:
	_sync()


## 每步都由状态直接判断：读信 / 读杂货商人的信 / 亲手做出一道菜 / 交单。
## 先 _sync 一次，让「第四步在订单解锁后自动出现」不必等下一次面板事件。
func _check_conditions() -> void:
	if GameState.is_tutorial_done():
		return
	_sync()
	match GameState.get_tutorial_step():
		0:
			if GameState.get_read_letter_count() >= 1:
				_complete_current()
		1:
			if GameState.has_crafted_any_food():
				_complete_current()
		2:
			if GameState.is_letter_read(GameState.MERCHANT_UNLOCK_LETTER):
				_complete_current()
		3:
			if GameState.is_orders_unlocked() and GameState.get_orders_completed() >= 1:
				_complete_current()


func _complete_current() -> void:
	if GameState.is_tutorial_done():
		return
	TUTORIAL.complete_current_step()
	Sfx.play(Sfx.Intent.CONFIRM)
	_sync()
	progress_changed.emit()
