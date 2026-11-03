class_name ShopCard
extends PanelContainer
## 商人卡片墙的一张卡：图标章 + 持有数 / 名称（悬停跑马灯）/ 单价 + 货架。
## 只负责显示与发点击信号，买卖经济逻辑仍在 MerchantPanel。

signal activated(item_key: String)

const CARD_SIZE := Vector2(151, 86)
const BADGE_SIZE := 28.0

var item_key := ""
var _marquee: MarqueeLabel
var _badge: ItemBadge
var _have_label: Label
var _price_label: Label
var _stock_label: Label
var _selected := false
var _sold_out := false
var _pending_item: ItemDef
var _pending_buy := true
var _pending_price := 0
var _pending_stock := 0
var _pending_capacity := 0
var _pending_owned := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	_refresh_style()
	if _pending_item != null:
		_apply_setup()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui_input)
	PanelKit.make_focusable(self, _activate)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var column := PanelKit.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var top := PanelKit.hbox(4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge = ItemBadge.new()
	_badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	top.add_child(_badge)
	top.add_child(PanelKit.spacer())
	_have_label = PanelKit.label("--", 14, PanelKit.INK_SOFT)
	_have_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_have_label)
	column.add_child(top)

	_marquee = MarqueeLabel.new()
	_marquee.custom_minimum_size.y = 21.0
	_marquee.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_marquee)

	var bottom := PanelKit.hbox(4)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_price_label = PanelKit.label("", 12, PanelKit.ACCENT_DEEP)
	_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_price_label)
	bottom.add_child(PanelKit.spacer())
	_stock_label = PanelKit.label("", 11, PanelKit.INK_SOFT)
	_stock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_stock_label)
	column.add_child(bottom)


func setup(item: ItemDef, buy_mode: bool, price: int, stock: int, capacity: int, owned: int) -> void:
	item_key = item.get_key()
	_pending_item = item
	_pending_buy = buy_mode
	_pending_price = price
	_pending_stock = stock
	_pending_capacity = capacity
	_pending_owned = owned
	if _marquee != null:
		_apply_setup()


func _apply_setup() -> void:
	if _pending_item == null:
		return
	var name_text := _pending_item.localized()
	_marquee.set_text(name_text, 17, PanelKit.INK)
	PanelKit.tooltip(self, name_text)
	var icon_path := ItemIcons.path_for(_pending_item)
	_badge.configure(icon_path, name_text, ItemIcons.accent_for(icon_path), BADGE_SIZE)
	_have_label.text = "--" if _pending_owned <= 0 else "×%d" % _pending_owned
	_price_label.text = I18n.t("ui.merchant.card_price", [_pending_price])
	if _pending_buy:
		_stock_label.text = I18n.t("ui.merchant.card_shelf", [_pending_stock, _pending_capacity])
		_sold_out = _pending_stock <= 0
	else:
		_stock_label.text = ""
		_sold_out = false
	_refresh_style()


## 图标归类统一走 ItemIcons；商人页没有配方分组，按物品键与标签退化判断。


func get_item_name() -> String:
	return _marquee.get_text() if _marquee != null else ""


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_refresh_style()


func _refresh_style() -> void:
	if not is_inside_tree():
		return
	var base := PanelKit.slab(PanelKit.CARD, PanelKit.INK, 8, 2)
	var active := PanelKit.selection_box(8, 6, false, PanelKit.SELECT_FILL)
	add_theme_stylebox_override("panel", active if _selected else base)
	modulate = Color(1, 1, 1, 1) if _selected or not _sold_out else Color(0.55, 0.55, 0.55, 1.0)


func _on_hover(value: bool) -> void:
	if _marquee != null:
		_marquee.set_hovered(value)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			release_focus()
			_activate()
			accept_event()


func _activate() -> void:
	activated.emit(item_key)
