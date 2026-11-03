class_name HarvestLayer
extends Control
## 桌面下沿的几块采集点：一处产地管一类货（货箱、农田、果园、海产），解锁条件各不相同。
##
## 为什么放在屏幕底部横带而不是桌面上：桌面中间是「进行中的活儿」（制作/研究进度条），
## 桌面上半部和两列已经给了设备入口；底部这条带子空着，放采集点既不遮桌面，
## 也符合「料理台前沿摆着几样原料」的空间感。
##
## 三态与铜板一致（点击 → 拿东西 → 进冷却）：
## - 成熟：亮着，点一下给 1–3 份，进冷却；
## - 冷却：压暗、显示剩余秒数，点不动；
## - 满仓：再压一档、写「仓满」，提示玩家先消耗，点不动。
##
## 这一层只管展示与点击，数值与状态都在 GameState（`harvest()` / `get_harvest_cooldown_left()`）。
## 仓库入口不在这条横带上：桌脚的「看看仓库」贴纸负责开面板（第四轮反馈）。

const EVENT_MATERIAL := &"MaterialChangedEvent"
const EVENT_FACILITY := &"FacilityUpgradedEvent"
const EVENT_RESTORED := &"StateRestoredEvent"
const EVENT_LANGUAGE := &"LanguageChangedEvent"
const EVENT_LETTER := &"LetterReadEvent"

## 状态文本刷新间隔（冷却按秒走，不必每帧重排）
const TICK := 0.2
## 冷却转就绪时轻轻鼓一下：告诉玩家「这里又能点了」，不用盯着数字
const READY_PULSE_SCALE := 1.035
## 采集成功时卡片先被按扁一点，再弹回来
const COLLECT_PRESS_SCALE := 0.94
## 底部横带高度：卡片 64 + 上留白
const BAND_HEIGHT := 92.0
const CARD_SIZE := Vector2(192.0, 76.0)
const CARD_GAP := 16

var _row: HBoxContainer
## 材料键 → {"root": PanelContainer, "state": Label, "chips": Array[Control]}
var _cards: Dictionary = {}
var _tick_left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -BAND_HEIGHT
	offset_bottom = -12.0
	EventBus.subscribe(EVENT_MATERIAL, _on_state_changed)
	EventBus.subscribe(EVENT_FACILITY, _on_state_changed)
	EventBus.subscribe(EVENT_RESTORED, _on_language_changed)
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.subscribe(EVENT_LETTER, _on_letter_read)
	_rebuild()


func _exit_tree() -> void:
	EventBus.unsubscribe(EVENT_MATERIAL, _on_state_changed)
	EventBus.unsubscribe(EVENT_FACILITY, _on_state_changed)
	EventBus.unsubscribe(EVENT_RESTORED, _on_language_changed)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.unsubscribe(EVENT_LETTER, _on_letter_read)


func _process(delta: float) -> void:
	_tick_left += delta
	if _tick_left < TICK:
		return
	_tick_left = 0.0
	_refresh_states()


# --- 搭结构 ---------------------------------------------------------------


func _on_language_changed(_event: Variant = null) -> void:
	_rebuild()


func _on_state_changed(_event: Variant = null) -> void:
	_refresh_states()


## 读完信可能多出一块产地（农田挂第一站到站信）：卡片要重排，不能只刷状态。
func _on_letter_read(_event: Variant = null) -> void:
	_rebuild()


## 采集点本身不变时只重建一次；解锁（鸡蛋随烤箱 2 级）与换语言时重建
func _rebuild() -> void:
	PanelKit.clear(self)
	_cards.clear()
	_row = PanelKit.hbox(CARD_GAP)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for harvest in GameState.get_harvest_points():
		if not GameState.is_harvest_unlocked(harvest):
			continue
		_row.add_child(_card(harvest))
	_refresh_states()


func _card(harvest: HarvestDef) -> Control:
	# 卡片属于采集点本身（一处产地），不再借用某样材料的名字
	var key := harvest.get_key()
	var name_text := harvest.localized()
	if name_text.is_empty():
		name_text = key
	var icon_path := ItemIcons.tag_path(harvest.tag)

	var card := PanelKit.paper(PanelKit.CARD_HI, 8)
	card.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 8, 2, true))
	card.custom_minimum_size = CARD_SIZE
	# 所有动效都以基准角为原点：连点不会把中间态当成新的 0 度
	card.set_meta(&"_base_rotation", 0.0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(key))
	# 键盘也要能采：Tab 到这张卡、回车
	PanelKit.make_focusable(card, func() -> void: _collect(key))

	var row := PanelKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seal := ItemBadge.new()
	seal.configure(icon_path, name_text, ItemIcons.accent_for(icon_path), 40.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seal)

	var column := PanelKit.vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := PanelKit.label(name_text, 15, PanelKit.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state_label := PanelKit.caption("", PanelKit.INK_SOFT)
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	column.add_child(state_label)
	row.add_child(column)
	card.add_child(row)

	card.resized.connect(func() -> void: card.pivot_offset = card.size * 0.5)
	# last_state 用来识别「冷却 → 就绪」这一下状态迁移；空字符串表示还没算过
	_cards[key] = {"root": card, "state": state_label, "last_state": &""}
	return card



# --- 状态 -----------------------------------------------------------------


func _refresh_states() -> void:
	# 面板盖着桌面时整条带子收起来：它是「桌上的东西」，被纸盖住就不该露在纸外面
	var covered := UIManager.get_top_panel() != null
	if visible == covered:
		visible = not covered
	for key in _cards:
		var card: Dictionary = _cards[key]
		var root := card["root"] as Control
		var state := card["state"] as Label
		var last_state: StringName = card.get("last_state", &"")
		var now_state := &""
		if GameState.is_harvest_full(key):
			now_state = &"full"
			root.modulate = Color(1.0, 1.0, 1.0, 0.45)
			root.mouse_default_cursor_shape = Control.CURSOR_ARROW
			state.text = I18n.t("ui.harvest.full")
			state.add_theme_color_override("font_color", PanelKit.DANGER_DEEP)
		else:
			var left := GameState.get_harvest_cooldown_left(key)
			if left <= 0.0:
				now_state = &"ready"
				root.modulate = Color(1.0, 1.0, 1.0, 1.0)
				root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				state.text = I18n.t("ui.harvest.ready")
				state.add_theme_color_override("font_color", PanelKit.ACCENT_DEEP)
			else:
				now_state = &"cooling"
				root.modulate = Color(1.0, 1.0, 1.0, 0.7)
				root.mouse_default_cursor_shape = Control.CURSOR_ARROW
				state.text = I18n.t("ui.harvest.cooling", [ceili(left)])
				state.add_theme_color_override("font_color", PanelKit.INK_SOFT)
		# 只在「冷却 → 就绪」这一下鼓一下；首次构建（last_state 为空）和满仓恢复都不播
		if last_state == &"cooling" and now_state == &"ready" and visible:
			_pulse_ready(root)
		card["last_state"] = now_state


func _on_card_input(event: InputEvent, key: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_collect(key)


## 采一次：鼠标点与键盘回车走同一条路。
func _collect(key: String) -> void:
	var gained := GameState.harvest_with_result(key)
	if not gained.is_empty():
		Sfx.play(Sfx.Intent.COIN)
		_bounce_collect(key)
		_burst_collect(key)
		_pop(key, _gained_text(gained))
	else:
		Sfx.play(Sfx.Intent.DENY)
		_shake_denied(key)
	_refresh_states()


## 成功：卡片先被按扁一点再弹回来，像从桌上把东西按下去又松开
func _bounce_collect(key: String) -> void:
	if not _cards.has(key):
		return
	var root := _cards[key]["root"] as Control
	var tween := _card_tween(root)
	root.pivot_offset = root.size * 0.5
	root.scale = Vector2(COLLECT_PRESS_SCALE, COLLECT_PRESS_SCALE)
	tween.tween_property(root, "scale", Vector2.ONE, 0.34) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 成功：卡片上沿溅一小撮材料色的碎屑，再扩一圈同色涟漪。
## 放在上沿而不是正中：不盖住卡片里的状态字，也和往上飘的「糖 ×1」连成一条。
func _burst_collect(key: String) -> void:
	if not _cards.has(key):
		return
	var root := _cards[key]["root"] as Control
	var center := root.global_position + Vector2(root.size.x * 0.5, 2.0) - global_position
	var tint := PanelKit.tint_of(_name_of(key), 0.55, 0.92)
	VfxKit.sparkle(self, center, tint, 18, 58.0)
	VfxKit.ring(self, center, tint, 30.0, 0.42)


## 点不动时轻轻摇一下头：不弹窗、不报错，动作本身就是反馈
func _shake_denied(key: String) -> void:
	if not _cards.has(key):
		return
	var root := _cards[key]["root"] as Control
	var base := float(root.get_meta(&"_base_rotation", 0.0))
	var tween := _card_tween(root)
	root.pivot_offset = root.size * 0.5
	root.rotation = base
	tween.tween_property(root, "rotation", base + 0.018, 0.045)
	tween.tween_property(root, "rotation", base - 0.012, 0.075)
	tween.tween_property(root, "rotation", base, 0.10)
	_settle_rotation(root, base)


## 连点后兜底：停手 1.5s 若还偏着就缓缓回正。只认最后一次抖动（token 防串台）。
func _settle_rotation(root: Control, base: float) -> void:
	var seq := int(root.get_meta(&"_settle_seq", 0)) + 1
	root.set_meta(&"_settle_seq", seq)
	get_tree().create_timer(1.5).timeout.connect(_on_settle_rotation.bind(root, base, seq))


func _on_settle_rotation(root: Control, base: float, seq: int) -> void:
	if not is_instance_valid(root):
		return
	if int(root.get_meta(&"_settle_seq", -1)) != seq:
		return
	if absf(root.rotation - base) < 0.001:
		return
	var settle := _card_tween(root)
	settle.tween_property(root, "rotation", base, 0.18)


## 冷却转好：轻轻鼓一下。用同一个 tween 槽，不会和采集回弹叠在一起。
func _pulse_ready(root: Control) -> void:
	var tween := _card_tween(root)
	root.pivot_offset = root.size * 0.5
	tween.tween_property(root, "scale", Vector2(READY_PULSE_SCALE, READY_PULSE_SCALE), 0.10) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 一张卡同一时刻只留一个动作 tween，旧的不杀会和新的一起抢 scale
func _card_tween(root: Control) -> Tween:
	var tween: Tween = null
	if root.has_meta(&"_collect_tween"):
		tween = root.get_meta(&"_collect_tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	# kill 会把属性停在中间值：新链开始前先回到基准，否则连点会累加角度
	root.rotation = float(root.get_meta(&"_base_rotation", 0.0))
	root.scale = Vector2.ONE
	tween = root.create_tween()
	root.set_meta(&"_collect_tween", tween)
	return tween


## 这一下摇到了什么：按名字排，一行一样，「洋葱 ×2」比「+2」有用得多。
## 排序是为了同一批采集每次都长一个样，不会因为字典顺序看起来在跳。
func _gained_text(gained: Dictionary) -> String:
	var keys := gained.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return _name_of(a) < _name_of(b))
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s ×%d" % [_name_of(key), int(gained[key])])
	return "\n".join(parts)


func _name_of(key: Variant) -> String:
	var def := _def_of(String(key))
	return def.localized() if def != null else String(key)


## 拿到手时在卡片上方飘一行明细，像桌上多了一份
func _pop(key: String, text: String) -> void:
	if not _cards.has(key):
		return
	var root := _cards[key]["root"] as Control
	var label := PanelKit.label(text, 18, PanelKit.ACCENT_DEEP)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.9, 0.9)
	var start := root.global_position + Vector2(root.size.x * 0.5, -6.0)
	label.global_position = start
	# 现在是一行一样，停久一点才读得完；先轻轻弹出来，再慢慢往上飘
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "global_position", start - Vector2(0.0, 30.0), 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)


func _def_of(key: String) -> GameDef:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return null
	return registry.get_def(key)
