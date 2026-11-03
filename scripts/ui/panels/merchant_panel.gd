class_name MerchantPanel
extends GamePanel
## 商人：拿铜币换基础材料，也收做好的菜。货架上的东西与价格全部来自 ItemDef，不在这里写死。
##
## 两页签：「买」列能进货的材料，「卖」页收成品菜与中间材料（第四轮反馈：
## 中间材料也能卖，收购价按输入成本略高一点）。
## 「卖」页默认只看手里有货的——两百多道菜平铺出来，九成是「你没有」。
## 第七轮改为三列卡片墙（Q3）：原先每页 20 行、页脚翻页的写法已删；
## 卡片按组惰性补，打开时先铺一屏，后续分帧补完。

const TABS: Array[Dictionary] = [
	{"id": "buy", "key": "ui.merchant.tab_buy"},
	{"id": "sell", "key": "ui.merchant.tab_sell"},
]

var _tab: int = 0
## 「卖」页状态段：关着只列手上有的，切到「全部」连「记下了但手上没有」的也列出来。
## 两道门里只有这一道被它放宽——**没记下的菜一律不出现**，那是剧透不是筛选
## （用户 2026-10-27 拍板）。
var _show_all_owned := false
## 检索状态。买页与卖页的内容维度不同（产地 / 主题），换页签时分组与排序会
## 各自回到该页的默认值，但搜索词留着——框里的字还在，被悄悄清空更让人困惑。
var _keyword: String = ""
## "" 不分组；买页 "source" 按采集点，卖页默认 "kind"（中间材料 / 成品菜），也可 "theme"
var _group_key: String = ""
## 排序键。空串是初始态，重置函数会按页签填默认值
var _sort_key: String = ""
## 检索条：搜索 + 分组 + 排序。换页签要重建，所以不放在工具条函数里写死
var _bar: FilterBar = null
## 重建页签栏时补发的 tab_changed 不算玩家操作，别覆盖记录
var _restoring_tab := false
## 空架行上的补货倒计时：全局一份，所有空架行显示同一个数字。按 tick 就地改文字，不重建行
## 页脚的全局补货倒计时。货架全满时为 null（没有东西在等）
var _refill_footer: Label = null
## 卡片墙的待建队列。打开/刷新时只同步铺第一批，剩下的分帧补，避免 294 张卡卡住一帧
var _pending_cards: Array[Dictionary] = []
var _build_seq := 0
## 交易弹窗同一时间只留一个
var _trade_popup: PopupPanel = null
## 商人升级弹窗也同一时间只留一个
var _upgrade_popup: PopupPanel = null


func _on_init() -> void:
	# 补货倒计时按秒走，只改那一行字；补满了才整页重绘一次（按钮要从灰变亮）
	tick_interval = 0.5


func _on_open(data: Dictionary = {}) -> void:
	if data.has("tab"):
		var wanted := String(data["tab"])
		for index in TABS.size():
			if String(TABS[index]["id"]) == wanted:
				_tab = index
				break
	# 排序默认值跟着页签走，得在 super 重建工具条之前定下来
	_reset_filters_for_tab()
	super._on_open(data)


func refresh() -> void:
	set_title(I18n.t("ui.merchant.title"))
	set_subtitle(I18n.t("ui.merchant.subtitle"))
	_build_toolbar()
	_fill_page()


## 页签钉在工具条上；「有货 / 全部」状态段只在「卖」页出现，买货本来就是在买没有的东西
func _build_toolbar() -> void:
	# 工具条整层清掉时 _bar 会跟着被释放：先松手，免得后面拿到死引用
	_bar = null
	PanelKit.clear(toolbar)
	var row := PanelKit.hbox(12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(row)

	var tab_bar := TabBar.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restoring_tab = true
	tab_bar.tab_changed.connect(_on_tab_changed)
	row.add_child(tab_bar)
	for tab in TABS:
		tab_bar.add_tab(I18n.t(String(tab["key"])))
	tab_bar.current_tab = _tab
	_restoring_tab = false

	# 「商人 Lv.n」常驻在页签右侧：商人自己也能升级（第 9 轮反馈 1），
	# 入口不藏进二级菜单，点开就是这一级与下一级的数字。
	var level_button := _make_level_button()
	if level_button != null:
		row.add_child(level_button)

	_build_filter_bar()


## 商人等级入口。没开张时面板本来就打不开，这里再判一次只是为了测试直接调 refresh。
func _make_level_button() -> Button:
	if not GameState.is_merchant_unlocked():
		return null
	var button := PanelKit.button(
			I18n.t("ui.merchant.level_button", [GameState.get_merchant_level()]), Sfx.Intent.NONE)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_open_upgrade_popup)
	return button


## 升级弹窗：现状 + 下一级多什么 + 花什么。数值全部读 MerchantDef，
## 弹窗里不重写一份档位表（反馈 1 的收益必须和 GameState 真正用的一致）。
func _open_upgrade_popup() -> void:
	_close_upgrade_popup()
	var merchant := GameState.get_merchant_def()
	if merchant == null:
		return
	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup.add_child(margin)
	var box := PanelKit.vbox(7)
	box.custom_minimum_size.x = 320
	margin.add_child(box)

	var level := GameState.get_merchant_level()
	box.add_child(PanelKit.label(I18n.t("ui.merchant.level_title"), 20))
	box.add_child(PanelKit.label(
			I18n.t("ui.merchant.level_current", [level, merchant.max_level]), 16, PanelKit.INK_SOFT))
	box.add_child(PanelKit.hint(I18n.t("ui.merchant.level_slots", [
			merchant.capacity_normal_at(level), merchant.capacity_scarce_at(level)]), 320.0))
	box.add_child(PanelKit.hint(I18n.t("ui.merchant.level_refill",
			[PanelKit.duration_text(GameState.get_shop_refill_seconds())]), 320.0))
	box.add_child(PanelKit.hint(I18n.t("ui.merchant.level_hint"), 320.0))
	box.add_child(PanelKit.divider())

	var upgrade := GameState.get_merchant_upgrade()
	if upgrade == null:
		box.add_child(PanelKit.label(I18n.t("ui.merchant.level_max"), 17, PanelKit.INK_SOFT))
	else:
		var next := upgrade.target_level
		box.add_child(PanelKit.label(I18n.t("ui.merchant.level_next", [next]), 18))
		box.add_child(PanelKit.hint(I18n.t("ui.merchant.level_next_gain", [
				merchant.capacity_normal_at(next), merchant.capacity_scarce_at(next),
				PanelKit.duration_text(merchant.refill_seconds_at(next))]), 320.0))
		var cost: Array[String] = [PanelKit.coins_text(upgrade.coin_cost)]
		for stack in upgrade.materials:
			if stack == null:
				continue
			cost.append("%s × %d" % [stack_name(stack), stack.amount])
		box.add_child(PanelKit.hint(I18n.t("ui.merchant.level_cost", [I18n.list_sep().join(cost)]), 320.0))
		var upgrade_button := PanelKit.button(
				I18n.t("ui.merchant.level_up_button", [next]), Sfx.Intent.NONE)
		PanelKit.set_disabled(upgrade_button, not GameState.can_upgrade_merchant())
		upgrade_button.pressed.connect(func() -> void:
			popup.hide()
			if GameState.upgrade_merchant():
				show_message(I18n.t("ui.merchant.level_done",
						[GameState.get_merchant_level()]), PanelKit.INK_SOFT)
			else:
				Sfx.play(Sfx.Intent.DENY)
				show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
			refresh()
		)
		box.add_child(upgrade_button)

	var cancel := PanelKit.button(I18n.t("ui.merchant.trade_cancel"), Sfx.Intent.CLICK)
	cancel.pressed.connect(popup.hide)
	box.add_child(cancel)
	add_child(popup)
	_upgrade_popup = popup
	popup.popup_hide.connect(_on_upgrade_popup_hidden.bind(popup))
	popup.popup_centered.call_deferred()


func _on_upgrade_popup_hidden(popup: PopupPanel) -> void:
	if _upgrade_popup == popup:
		_upgrade_popup = null
	popup.queue_free()


func _close_upgrade_popup() -> void:
	var popup := _upgrade_popup
	_upgrade_popup = null
	if popup != null and is_instance_valid(popup):
		popup.hide()


## 第二层工具条：搜索 + 分组 + 排序。买页三十几样、卖页两百多道，
## 没有检索只能从头翻到尾（第一轮第 9 条：商店缺搜索与过滤）。
func _build_filter_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		toolbar.remove_child(_bar)
		_bar.queue_free()
	_bar = FilterBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_bar)
	_bar.add_search("ui.merchant.search_placeholder", 150.0, _keyword)
	# 状态维度进 FilterBar，和书架 / 灶台同一套座位顺序（统一检索 §4）：
	# 搜索 → 状态 → 分组 → 排序。卖页关心「手上有货」；买页没有这个维度。
	if _tab == 1:
		_bar.add_segments("owned", [
			{"value": 0, "key": "ui.merchant.filter_owned"},
			{"value": 1, "key": "ui.merchant.filter_all"},
		], 1 if _show_all_owned else 0)
	_bar.add_group(_group_options(), _group_key)
	_bar.add_sort(_sort_options(), _sort_key)
	_bar.changed.connect(_on_filters_changed)
	_bar.set_result_text("")


## 搜到一半改筛选不该丢光标，所以这里只重填列表，不重建工具条
func _on_filters_changed() -> void:
	_keyword = _bar.get_keyword()
	_show_all_owned = _tab == 1 and _bar.get_segment("owned") == 1
	_group_key = _bar.get_group()
	_sort_key = _bar.get_sort()
	_fill_page()


## 换页签时重置：分组维度换了（产地 / 类型），排序默认值也换了
func _reset_filters_for_tab() -> void:
	_group_key = "" if _tab == 0 else "kind"
	_sort_key = _default_sort()


## 买页按产地分堆，卖页先按「中间材料 / 成品菜」分堆，也可以换成主题
func _group_options() -> Array:
	var options: Array = [{"value": "", "key": "ui.merchant.group_none"}]
	if _tab == 0:
		options.append({"value": "source", "key": "ui.merchant.group_source"})
		options.append({"value": "category", "key": "ui.merchant.group_category"})
	else:
		options.append({"value": "kind", "key": "ui.merchant.group_kind"})
		options.append({"value": "theme", "key": "ui.merchant.group_theme"})
	return options


func _sort_options() -> Array:
	return [
		{"value": "price_up", "key": "ui.merchant.sort_price_up"},
		{"value": "price_down", "key": "ui.merchant.sort_price_down"},
		{"value": "name", "key": "ui.merchant.sort_name"},
		{"value": "owned", "key": "ui.merchant.sort_owned"},
	]


## 买东西先看便宜的，卖东西先看贵的——买卖两边关心的方向正好相反
func _default_sort() -> String:
	return "price_up" if _tab == 0 else "price_down"


## 结果数只在「真的筛过」时出现：没筛的时候它跟页脚那行总数一模一样，白占宽度
func _result_text(total: int) -> String:
	if total <= 0 or not _has_filters():
		return ""
	return I18n.t("ui.filter.result_count", [total])


## 分组和排序只是换个排列，不算「筛」——结果数只在真的少掉东西时才有意义
func _has_filters() -> bool:
	return not _keyword.strip_edges().is_empty() or (_tab == 1 and _show_all_owned)


## 换页签 / 改开关：只换内容与页脚，页签栏自己不动
func _on_tab_changed(index: int) -> void:
	if _restoring_tab:
		return
	_tab = index
	Sfx.play(Sfx.Intent.TAB)
	# 换页签 = 换维度：买按产地分、卖按主题分，检索条的选项整排跟着换
	_reset_filters_for_tab()
	_build_filter_bar()
	_fill_page()
	flash_content()


## 三列卡片墙。组抬头保留；卡片先铺一屏，剩下的交给 _drain_cards 分帧补，
## 打开时不用为 294 张卡付一帧的建树成本（Q3 / 反馈 10）。
func _fill_page() -> void:
	clear_content()
	PanelKit.clear(footer)
	_refill_footer = null
	_build_seq += 1
	_pending_cards.clear()
	_close_trade_popup()
	var defs := _tab_defs()
	# 结果数是「筛选有多窄」的即时反馈；页脚那句「共 N 样」说的是这一类一共多少
	if _bar != null and is_instance_valid(_bar):
		_bar.set_result_text(_result_text(defs.size()))
	if defs.is_empty():
		# 搜空了和本来就没有，是两件不同的事：前者要人「换个词」，后者要人「去做菜」
		var empty_text := I18n.t("ui.filter.empty") if _has_filters() else _empty_text()
		content.add_child(PanelKit.hint(empty_text))
		return

	var last_group := ""
	var grid: GridContainer = null
	for def in defs:
		var group_label := _group_label_of(def)
		if not group_label.is_empty() and group_label != last_group:
			grid = _make_card_grid()
			content.add_child(PanelKit.group_header(group_label))
			content.add_child(grid)
			last_group = group_label
		elif grid == null:
			grid = _make_card_grid()
			content.add_child(grid)
		_pending_cards.append({"grid": grid, "item": def})

	_build_footer(defs.size())
	_drain_cards(_build_seq, 24)
	if not _pending_cards.is_empty():
		call_deferred("_drain_cards", _build_seq)


func _make_card_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


## budget 是本次最多建几张；默认值给分帧用，打开时不传就按 24 张先铺一屏。
func _drain_cards(seq: int, budget: int = 36) -> void:
	if seq != _build_seq:
		return
	var made := 0
	while made < budget and not _pending_cards.is_empty():
		var spec: Dictionary = _pending_cards.pop_front()
		_add_shop_card(spec.get("grid") as GridContainer, spec.get("item") as ItemDef)
		made += 1
	if not _pending_cards.is_empty():
		call_deferred("_drain_cards", seq)


## 测试与「立即补完」用；正常打开走分帧。
func _flush_pending_cards() -> void:
	while not _pending_cards.is_empty():
		var spec: Dictionary = _pending_cards.pop_front()
		_add_shop_card(spec.get("grid") as GridContainer, spec.get("item") as ItemDef)


func _add_shop_card(grid: GridContainer, item: ItemDef) -> void:
	if grid == null or not is_instance_valid(grid) or item == null:
		return
	var key := item.get_key()
	var card := ShopCard.new()
	card.setup(
			item,
			_tab == 0,
			_price_of(item),
			GameState.get_shop_stock(key),
			GameState.get_shop_capacity(key),
			GameState.get_amount(key))
	card.activated.connect(_on_card_activated.bind(card))
	grid.add_child(card)


func _build_footer(total: int) -> void:
	footer.add_child(PanelKit.divider())
	var bar := PanelKit.hbox(10)
	bar.add_child(PanelKit.hint_inline(I18n.t("ui.merchant.count", [total])))
	# 补货是全局一份计时：页脚说一句比每行各说一句更接近真相
	var remaining := GameState.get_shop_refill_remaining()
	if remaining > 0.0:
		_refill_footer = PanelKit.hint_inline(
				I18n.t("ui.merchant.refill_all", [PanelKit.duration_text(remaining)]))
		bar.add_child(_refill_footer)
	bar.add_child(PanelKit.spacer())
	bar.add_child(PanelKit.hint_inline(I18n.t("ui.merchant.card_hint")))
	footer.add_child(bar)


## 倒计时就地改文字；到点就整页重绘一次（货架数、按钮的亮/灰都要跟着变）
func _on_tick() -> void:
	var remaining := GameState.get_shop_refill_remaining()
	if remaining <= 0.0:
		# 手机能挂着面板跨过补货点：到点了整页重绘，把 0 秒和空架一起换掉
		if _refill_footer != null:
			request_refresh()
		return
	var text := I18n.t("ui.merchant.refill_all", [PanelKit.duration_text(remaining)])
	if _refill_footer != null and is_instance_valid(_refill_footer):
		_refill_footer.text = text


## 卖页有两种空法：手上有货但没打开开关 / 一道都没记下。
## 后者就算打开「显示全部」也还是空的，再让人去点开关就是骗人。
func _empty_text() -> String:
	if _tab != 1:
		return I18n.t("ui.merchant.empty")
	if not _has_known_sellable():
		return I18n.t("ui.merchant.empty_sell")
	if not _show_all_owned:
		return I18n.t("ui.merchant.empty_owned")
	return I18n.t("ui.merchant.empty_sell")


## 卖页聊不聊得下去，看的是「记下来过、有人收的东西」有多少——不是手上有没有货
func _has_known_sellable() -> bool:
	for def in defs_of("item"):
		var item := def as ItemDef
		if item == null or not _is_sellable(item):
			continue
		if item.in_catalog and GameState.is_discovered(item.get_key()):
			return true
	return false


## 当前页签该列的货：先看这道能不能卖，再过检索条，最后排序。
## 分页与页脚共用这一份，避免两处算出不同结果。
func _tab_defs() -> Array[ItemDef]:
	var items: Array[ItemDef] = []
	for def in defs_of("item"):
		var item := def as ItemDef
		if item == null:
			continue
		if _tab == 0:
			if not _is_for_sale(item):
				continue
		else:
			if not _is_sellable(item):
				continue
			# 防剧透：没记下来的菜连名字都不该出现。「显示全部」只放宽「手上有货」
			# 这一道门，不放宽「见过」这一道——玩家不可能卖掉一道没见过的菜
			# （用户 2026-10-27 拍板）。
			if not item.in_catalog or not GameState.is_discovered(item.get_key()):
				continue
			if not _show_all_owned and GameState.get_amount(item.get_key()) <= 0:
				continue
		if not _matches_keyword(item):
			continue
		items.append(item)
	items.sort_custom(_sort_less)
	return items


## 关键词只比名字与描述。商店没有图鉴那种「线索」机制：货架上的东西本来
## 就是摆出来给你看的，能按名字搜到就够了。
func _matches_keyword(item: ItemDef) -> bool:
	var needle := _keyword.strip_edges().to_lower()
	if needle.is_empty():
		return true
	if item.localized().to_lower().contains(needle):
		return true
	return item.localized(&"description").to_lower().contains(needle)


## 买的时候按进货价，卖的时候按收购价——同一套排序在这两页含义不同
func _price_of(item: ItemDef) -> int:
	return item.merchant_price if _tab == 0 else item.sell_price


## 排序。名字用译文比，否则切英文后顺序会跳。
## 价格相同时回落到数据里的 order，保证同一份数据每次排出来一样。
## 分组是排序的一级关键字：抬头只在换堆时插一次，同堆条目必须先排到一起（同图鉴，
## 用户 2026-10-27 报「同一采集点的材料没被分到一起」）。
## 「卖」页还要在前面多一档成品菜 → 中间材料（反馈 3）：这一档不能交给译文比，
## 中文逐字节比较时「中间材料」小于「成品菜」，半成品会整堆压在成品前面。
func _sort_less(a: ItemDef, b: ItemDef) -> bool:
	if _tab == 1 and (_group_key.is_empty() or _group_key == "kind"):
		var rank_a := _kind_rank(a)
		var rank_b := _kind_rank(b)
		if rank_a != rank_b:
			return rank_a < rank_b
	if not _group_key.is_empty():
		var left_group := _group_label_of(a)
		var right_group := _group_label_of(b)
		if left_group != right_group:
			return _group_less(left_group, right_group)
	match _sort_key:
		"name":
			var left := a.localized()
			var right := b.localized()
			if left != right:
				return left < right
		"owned":
			var own_a := GameState.get_amount(a.get_key())
			var own_b := GameState.get_amount(b.get_key())
			if own_a != own_b:
				return own_a > own_b
		"price_down":
			if _price_of(a) != _price_of(b):
				return _price_of(a) > _price_of(b)
		_:
			if _price_of(a) != _price_of(b):
				return _price_of(a) < _price_of(b)
	return a.order < b.order


## 一条属于哪一堆。买页按产地、卖页按主题；取不到就归「其他」。
## 「其他」是兜底堆，永远排最后；其余按译文比。
func _group_less(left: String, right: String) -> bool:
	var other := I18n.t("ui.filter.other")
	if left == other:
		return false
	if right == other:
		return true
	return left < right


func _group_label_of(item: ItemDef) -> String:
	if _group_key.is_empty():
		return ""
	if _group_key == "kind":
		if item.is_material() and item.material_kind == ItemDef.MaterialKind.INTERMEDIATE:
			return I18n.t("ui.merchant.group_intermediate")
		return I18n.t("ui.merchant.group_food")
	if _group_key == "source":
		var harvest := GameState.get_harvest_for_material(item.get_key())
		return harvest.localized() if harvest != null else I18n.t("ui.filter.other")
	if _group_key == "category":
		if item.is_material():
			var family := ItemIcons.material_path(item).get_file().get_basename()
			return I18n.t("ui.merchant.family_%s" % family)
		return I18n.t("ui.merchant.group_food")
	var theme_def := def_of(item.theme)
	return theme_def.localized() if theme_def != null else I18n.t("ui.filter.other")


func _is_for_sale(def: GameDef) -> bool:
	var material := def as ItemDef
	if material == null or not material.is_material():
		return false
	return not material.is_free() and material.merchant_price > 0


func _is_food_for_sale(def: GameDef) -> bool:
	var food := def as ItemDef
	return food != null and food.is_food() and food.sell_price > 0


## 中间材料也进卖页：它们是玩家花时间和原料做出来的，不该只能烂在仓里
func _is_intermediate_for_sale(def: GameDef) -> bool:
	var material := def as ItemDef
	return material != null and material.is_material() \
			and material.material_kind == ItemDef.MaterialKind.INTERMEDIATE \
			and material.sell_price > 0


func _is_sellable(def: GameDef) -> bool:
	return _is_food_for_sale(def) or _is_intermediate_for_sale(def)


## 「卖」页的档位：成品菜 0，中间材料 1，其余兜底 2。
## 分组抬头与不分组时的排序都读这一份，两处不会各排各的（反馈 3）。
func _kind_rank(item: ItemDef) -> int:
	if item == null:
		return 2
	if item.is_food():
		return 0
	if item.is_material() and item.material_kind == ItemDef.MaterialKind.INTERMEDIATE:
		return 1
	return 2


func _on_card_activated(item_key: String, card: ShopCard) -> void:
	var item := def_of(item_key) as ItemDef
	if item == null:
		return
	Sfx.play(Sfx.Intent.TAB)
	_open_trade(item, card)


## 点卡先选中，再弹交易确认。买卖仍走原来的 _buy / _sell，不在这里重写经济逻辑。
func _open_trade(item: ItemDef, card: ShopCard) -> void:
	_close_trade_popup()
	if is_instance_valid(card):
		card.set_selected(true)

	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup.add_child(margin)
	var box := PanelKit.vbox(7)
	box.custom_minimum_size.x = 300
	margin.add_child(box)

	box.add_child(PanelKit.label(item.localized(), 20))
	var price := _price_of(item)
	var price_key := "ui.merchant.each_price" if _tab == 0 else "ui.merchant.per_portion"
	box.add_child(PanelKit.label(I18n.t(price_key, [price]), 16, PanelKit.INK_SOFT))
	box.add_child(PanelKit.divider())
	if _tab == 0:
		_add_buy_actions(box, popup, item)
	else:
		_add_sell_actions(box, popup, item)

	var cancel := PanelKit.button(I18n.t("ui.merchant.trade_cancel"), Sfx.Intent.CLICK)
	cancel.pressed.connect(popup.hide)
	box.add_child(cancel)
	add_child(popup)
	_trade_popup = popup
	popup.popup_hide.connect(_on_trade_popup_hidden.bind(card, popup))
	popup.popup_centered.call_deferred()


func _add_buy_actions(box: VBoxContainer, popup: PopupPanel, item: ItemDef) -> void:
	var stock := GameState.get_shop_stock(item.get_key())
	var price := item.merchant_price
	if stock <= 0:
		box.add_child(PanelKit.hint(I18n.t("ui.merchant.shop_sold_out")))
		return
	if price <= 0:
		return
	var affordable := GameState.coins / price
	var max_count := mini(stock, affordable)
	_add_trade_button(box, popup, I18n.t("ui.merchant.buy_button", [1, price]),
			GameState.coins >= price, func() -> void: _buy(item, 1))
	if max_count > 1:
		_add_trade_button(box, popup, I18n.t("ui.merchant.buy_button", [max_count, price * max_count]),
				true, func() -> void: _buy(item, max_count))
	elif affordable < 1:
		box.add_child(PanelKit.hint(I18n.t("ui.merchant.not_enough_coins")))


func _add_sell_actions(box: VBoxContainer, popup: PopupPanel, item: ItemDef) -> void:
	var owned := GameState.get_amount(item.get_key())
	if owned <= 0:
		box.add_child(PanelKit.hint(I18n.t("ui.merchant.not_enough_items")))
		return
	for amount in [1, 10]:
		if owned < amount:
			continue
		_add_trade_button(box, popup, I18n.t("ui.merchant.sell_button", [amount, item.sell_price * amount]),
				true, func() -> void: _sell(item, amount))
	_add_trade_button(box, popup, I18n.t("ui.merchant.sell_all", [item.sell_price * owned]),
			true, func() -> void: _sell(item, owned))


func _add_trade_button(box: VBoxContainer, popup: PopupPanel, text: String, enabled: bool, action: Callable) -> void:
	var button := PanelKit.button(text, Sfx.Intent.NONE)
	PanelKit.set_disabled(button, not enabled)
	button.pressed.connect(func() -> void:
		popup.hide()
		action.call()
	)
	box.add_child(button)


func _on_trade_popup_hidden(card: ShopCard, popup: PopupPanel) -> void:
	if is_instance_valid(card):
		card.set_selected(false)
	if _trade_popup == popup:
		_trade_popup = null
	popup.queue_free()


func _close_trade_popup() -> void:
	var popup := _trade_popup
	_trade_popup = null
	if popup != null and is_instance_valid(popup):
		popup.hide()


func _buy(material: ItemDef, amount: int) -> void:
	if GameState.buy_material(material.get_key(), amount):
		Sfx.play(Sfx.Intent.BUY)
		show_message(I18n.t("ui.merchant.bought", [material.localized(), amount]), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		var reason := I18n.t("ui.merchant.shop_sold_out") if GameState.is_shop_empty(material.get_key()) else I18n.t("ui.merchant.not_enough_coins")
		show_message(reason, PanelKit.DANGER_DEEP)
	refresh()


func _sell(item: ItemDef, amount: int) -> void:
	if GameState.sell_item(item.get_key(), amount):
		Sfx.play(Sfx.Intent.SELL)
		show_message(I18n.t("ui.merchant.sold", [item.localized(), amount]), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.merchant.not_enough_items"), PanelKit.DANGER_DEEP)
	refresh()
