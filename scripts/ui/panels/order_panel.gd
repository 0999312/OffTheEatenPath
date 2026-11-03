class_name OrderPanel
extends GamePanel
## 订单板：顾客留下委托，交付指定菜品换铜币与一小份材料。
##
## 这是收集完内容之后的长期循环：材料 → 做菜 → 交付 → 铜币 / 设备。
## 委托会随时间自动补位（离线也算），所以每次回到游戏都有新单子可交。
## 页脚常驻三件事：现在的容量、花币扩容、「换一批」（免费但有冷却）。

## GamePanel 默认不订阅订单事件，这里补上
const ORDER_EVENTS: Array[StringName] = [&"OrderChangedEvent", &"StateRestoredEvent"]

var _refill_label: Label
var _capacity_label: Label
var _upgrade_button: Button
var _refresh_button: Button


func _on_open(data: Dictionary = {}) -> void:
	tick_interval = 1.0
	_build_footer()
	for event_type in ORDER_EVENTS:
		EventBus.subscribe(event_type, _on_data_changed)
	super._on_open(data)
	_refresh_refill()


func _on_close() -> void:
	for event_type in ORDER_EVENTS:
		EventBus.unsubscribe(event_type, _on_data_changed)
	super._on_close()


func _on_tick() -> void:
	_refresh_refill()


## 页脚两行：上面是常驻操作，下面是补位倒计时。
## 控件留在页脚里、只改文字与禁用状态，这样 tick 不会重建按钮（也不会打断点击）。
func _build_footer() -> void:
	PanelKit.clear(footer)
	var controls := PanelKit.hbox(10)
	controls.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_capacity_label = PanelKit.label("", 18, PanelKit.INK_SOFT)
	_capacity_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_child(_capacity_label)
	controls.add_child(PanelKit.spacer())

	_upgrade_button = PanelKit.button("", Sfx.Intent.NONE)
	_upgrade_button.custom_minimum_size.y = 38
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	controls.add_child(_upgrade_button)

	_refresh_button = PanelKit.button("", Sfx.Intent.NONE)
	_refresh_button.custom_minimum_size.y = 38
	_refresh_button.pressed.connect(_on_refresh_pressed)
	controls.add_child(_refresh_button)

	footer.add_child(controls)
	_refill_label = PanelKit.hint("", 640)
	footer.add_child(_refill_label)


## 推进世界速度也照走（advance 里递减冷却）
func _refresh_refill() -> void:
	if _refill_label == null:
		return
	var capacity := GameState.get_order_capacity()
	var orders := GameState.get_orders()
	_capacity_label.text = I18n.t("ui.order.capacity", [orders.size(), capacity])

	var cost := GameState.get_order_capacity_cost()
	if cost < 0:
		_upgrade_button.text = I18n.t("ui.order.upgrade_maxed")
		PanelKit.set_disabled(_upgrade_button, true)
	else:
		_upgrade_button.text = I18n.t("ui.order.upgrade", [PanelKit.coins_text(cost)])
		PanelKit.set_disabled(_upgrade_button, not GameState.can_upgrade_order_capacity())

	var cooldown := GameState.get_order_refresh_cooldown()
	PanelKit.set_disabled(_refresh_button, cooldown > 0.0 or orders.is_empty())
	if cooldown > 0.0:
		_refresh_button.text = I18n.t("ui.order.refresh_in", [int(ceil(cooldown))])
	else:
		_refresh_button.text = I18n.t("ui.order.refresh")

	if orders.size() >= capacity:
		_refill_label.text = I18n.t("ui.order.full")
	else:
		var wait := maxi(0, int(ceil(GameState.get_orders_refill_remaining())))
		_refill_label.text = I18n.t("ui.order.next_in", [maxi(1, int(ceil(float(wait) / 60.0)))])


func _on_upgrade_pressed() -> void:
	if GameState.upgrade_order_capacity():
		Sfx.play(Sfx.Intent.UPGRADE)
		show_message(I18n.t("ui.order.upgraded", [GameState.get_order_capacity()]), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.order.upgrade_denied"), PanelKit.DANGER_DEEP)
	refresh()


func _on_refresh_pressed() -> void:
	if GameState.refresh_orders():
		Sfx.play(Sfx.Intent.CONFIRM)
		show_message(I18n.t("ui.order.refreshed"), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.order.refresh_wait"), PanelKit.DANGER_DEEP)
	refresh()


func refresh() -> void:
	clear_content()
	set_title(I18n.t("ui.order.title"))
	var boosts := GameState.get_signature_theme_boosts()
	if boosts.is_empty():
		set_subtitle(I18n.t("ui.order.subtitle"))
	else:
		var themes: Array = boosts.keys()
		themes.sort()
		var parts: Array[String] = []
		for theme in themes:
			var theme_def := def_of(String(theme))
			var theme_name := theme_def.localized() if theme_def != null else String(theme)
			parts.append("%s ×%s" % [theme_name, String.num(float(boosts[theme]), 1)])
		set_subtitle(I18n.t("ui.order.subtitle_boost", [I18n.t("ui.order.subtitle"), " · ".join(parts)]))
	var orders := GameState.get_orders()
	if orders.is_empty():
		content.add_child(PanelKit.hint(I18n.t("ui.order.empty"), 640))
		_refresh_refill()
		return
	for order in orders:
		content.add_child(_order_card(order))
	_refresh_refill()


func _order_card(order: Order) -> PanelContainer:
	var food := def_of(order.dish_key) as ItemDef
	var dish_name := food.localized() if food != null else order.dish_key
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10, 2))
	var row := PanelKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var icon := PanelKit.icon("food/ham.svg", 34.0, PanelKit.ACCENT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text_box := PanelKit.vbox(5)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := PanelKit.hbox(10)
	head.add_child(PanelKit.label(dish_name, 21))
	head.add_child(PanelKit.label("× %d" % order.quantity, 19, PanelKit.INK_SOFT))
	if order.is_signature:
		head.add_child(PanelKit.badge(I18n.t("ui.order.signature"), PanelKit.ACCENT_DEEP, PanelKit.CARD_HI))
	if order.signature_theme_boost > 1.0 and not order.signature_theme_key.is_empty():
		var theme_def := def_of(order.signature_theme_key)
		var theme_name := theme_def.localized() if theme_def != null else order.signature_theme_key
		head.add_child(PanelKit.badge(
			I18n.t("ui.order.signature_theme", [theme_name, String.num(order.signature_theme_boost, 1)]),
			PanelKit.ACCENT, PanelKit.CARD_HI))
	text_box.add_child(head)

	var reward := PanelKit.hbox(10)
	reward.add_child(PanelKit.label(I18n.t("ui.order.reward", [PanelKit.big_number_text(order.reward_coins)]), 17, PanelKit.ACCENT_DEEP))
	if not order.bonus_material.is_empty() and order.bonus_amount > 0:
		var bonus_def := def_of(order.bonus_material)
		var bonus_name := bonus_def.localized() if bonus_def != null else order.bonus_material
		reward.add_child(PanelKit.label(I18n.t("ui.order.bonus", [bonus_name, order.bonus_amount]), 17, PanelKit.INK_SOFT))
	text_box.add_child(reward)

	var have := GameState.get_amount(order.dish_key)
	text_box.add_child(PanelKit.hint(I18n.t("ui.order.have", [have, order.quantity])))
	row.add_child(text_box)

	# 拒单在左、交付在右：不想做的单子推掉就好，不花钱，等补位
	var decline := PanelKit.button(I18n.t("ui.order.decline"), Sfx.Intent.NONE)
	decline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	decline.pressed.connect(func() -> void:
		if GameState.decline_order(order.id):
			Sfx.play(Sfx.Intent.CLOSE)
			show_message(I18n.t("ui.order.declined"), PanelKit.INK_SOFT)
			refresh()
	)
	row.add_child(decline)

	# 「去做」只连到已经看得见的配方：没解锁的菜送进灶台也只会看到一片空白。
	# 灶台叠在订单板上面（NORMAL 栈支持），返回时这张单子还在（第七轮反馈 24）。
	var maker_key := GameState.recipe_for_output(order.dish_key)
	if not maker_key.is_empty():
		var go_craft := PanelKit.button(I18n.t("ui.order.go_craft"), Sfx.Intent.NONE)
		go_craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go_craft.pressed.connect(func() -> void:
			Sfx.play(Sfx.Intent.CLICK)
			UIManager.open_panel(ResourceLocation.from_string(UIKeys.CRAFT), {"recipe": maker_key})
		)
		row.add_child(go_craft)

	# 交付是这张卡的主操作：禁用时也保留实底形状，重心才不会落到左边的「拒」上（P1-6）
	var deliver := PanelKit.primary_button(I18n.t("ui.order.deliver"), Sfx.Intent.NONE, 40.0)
	PanelKit.set_disabled(deliver, have < order.quantity)
	deliver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deliver.pressed.connect(func() -> void:
		if GameState.deliver_order(order.id):
			Sfx.play(Sfx.Intent.ORDER_DONE)
			show_message(I18n.t("ui.order.delivered", [dish_name, order.quantity]), PanelKit.INK_SOFT)
		else:
			Sfx.play(Sfx.Intent.DENY)
			show_message(I18n.t("ui.order.not_enough"), PanelKit.DANGER_DEEP)
		refresh()
	)
	row.add_child(deliver)
	return card
