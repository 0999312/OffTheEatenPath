class_name WarehousePanel
extends GamePanel
## 仓库：手上有什么、各有多少、能卖给商人多少钱。
##
## 这里不进货——进货是商人那边的事；仓库只做「清点 + 出手」。
## 收购价来自 ItemDef.sell_price，与商人「卖」页是同一份价，不另设一套，
## 免得同一个盘子在这屋卖 8 铜、在那屋卖 10 铜。
##
## 三页签：材料 / 成品 / 产地。材料与成品只列手上真有的（存量 > 0）——
## 仓库不是图鉴，「你还没有的东西」留给书架去展示。
## 第四轮反馈后，单样容量统一由仓库设施等级决定；产地升级也收在这一页，
## 不再在每样材料的图鉴行尾各挂一个 ↑ 按钮。

const PAGE_SIZE := 20
const TABS: Array[Dictionary] = [
	{"id": "material", "key": "ui.warehouse.tab_material"},
	{"id": "food", "key": "ui.warehouse.tab_food"},
	{"id": "harvest", "key": "ui.warehouse.tab_harvest"},
]

var _tab: int = 0
var _page: int = 0
## 检索状态。换页签时分组与排序回到该页默认值，搜索词留着——框里的字还在，
## 被悄悄清空更让人困惑（与商人同一套规矩）。
var _keyword: String = ""
## 状态段：0 全部 / 1 只看能卖的。仓库里本来都是「手上有」的，
## 「有货 / 无货」在这里没有意义，能卖与不能卖才是玩家关心的那一刀。
var _status_filter := 0
## 分类浮层：材料按标签、成品按主题 + 标签；空串 = 不过滤
var _theme_key := ""
var _tag_key := ""
## "" 不分组；材料按来源、成品按主题
var _group_key: String = ""
## 排序键。空串是初始态，重置函数会按页签填默认值
var _sort_key: String = ""
var _bar: FilterBar = null
## 重建页签栏时补发的 tab_changed 不算玩家操作
var _restoring_tab := false
## 「卖光」两段式：第一次按只把这一行按钮改成确认，再按才真卖。
## 用行内武装而不是模态窗，和设置页清档同一个做法——少一层打断，也能
## 让「卖的是哪一样」始终看得见。
var _armed_all := ""


func _on_open(data: Dictionary = {}) -> void:
	_page = 0
	_armed_all = ""
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
	set_title(I18n.t("ui.warehouse.title"))
	set_subtitle(I18n.t("ui.warehouse.subtitle"))
	_build_toolbar()
	_fill_page()


## 页签钉在工具条上；收购人先做成一个只有一项的下拉——现在只有一位商人，
## 将来第二位进来时这里多 add_item、价格读取才会真的按商人分。
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

	# 产地下拉（商人）只跟材料/成品有关，产地页不摆
	if _tab < 2:
		var buyer := OptionButton.new()
		buyer.add_item(I18n.t("ui.warehouse.buyer_merchant"))
		buyer.tooltip_text = I18n.t("ui.warehouse.buyer_hint")
		buyer.item_selected.connect(func(_index: int) -> void: pass)
		row.add_child(buyer)
		_build_filter_bar()
	else:
		_bar = null


func _build_filter_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		toolbar.remove_child(_bar)
		_bar.queue_free()
	_bar = FilterBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_bar)
	_bar.add_search("ui.warehouse.search_placeholder", 150.0, _keyword)
	# 四维统一检索（2026-10-28 规格 §4）：搜索 → 状态 → 分类 → 分组 → 排序。
	# 这几个控件只记选择、发 changed，怎么筛仍归面板自己决定。
	_bar.add_segments("status", [
		{"value": 0, "key": "ui.warehouse.filter_all"},
		{"value": 1, "key": "ui.warehouse.filter_sellable"},
	], 1 if _status_filter == 1 else 0)
	if _tab == 0:
		_bar.add_menu_group("tag", "ui.warehouse.filter_tag", _tag_options(), _tag_key)
	else:
		_bar.add_menu_group("theme", "ui.warehouse.filter_theme", _theme_options(), _theme_key)
		_bar.add_menu_group("tag", "ui.warehouse.filter_tag", _tag_options(), _tag_key)
	_bar.add_group(_group_options(), _group_key)
	_bar.add_sort(_sort_options(), _sort_key)
	_bar.changed.connect(_on_filters_changed)
	_bar.set_result_text("")


## 搜到一半改筛选不该丢光标，所以这里只重填列表，不重建工具条
func _on_filters_changed() -> void:
	_keyword = _bar.get_keyword()
	_status_filter = _bar.get_segment("status")
	_theme_key = _bar.get_menu_value("theme") if _tab == 1 else ""
	_tag_key = _bar.get_menu_value("tag")
	_group_key = _bar.get_group()
	_sort_key = _bar.get_sort()
	_page = 0
	_fill_page()


## 换页签时重置：分组维度换了（来源 / 主题），排序默认值也回到「存量多的在前」
func _reset_filters_for_tab() -> void:
	_status_filter = 0
	_theme_key = ""
	_tag_key = ""
	_group_key = ""
	_sort_key = _default_sort()


## 主题浮层：只列已经到站的地方——没到过的地名出现在筛选里本身就是剧透（与书架同一条规矩）
func _theme_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.warehouse.theme_all")}]
	var themes: Array[ThemeDef] = []
	for def in defs_of("theme"):
		if def is ThemeDef and GameState.is_theme_unlocked(def.get_key()):
			themes.append(def as ThemeDef)
	themes.sort_custom(func(a: ThemeDef, b: ThemeDef) -> bool: return a.order < b.order)
	for theme_def in themes:
		options.append({"value": theme_def.get_key(), "label": theme_def.localized()})
	return options


## 材料页筛食材标签（「任意蔬菜」那一类），成品页筛场合标签（「家常 / 宵夜」）。
## 两边各取自己那一半，摆出对方那半只会让人以为筛了却不生效。
func _tag_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.warehouse.tag_all")}]
	var tags: Array[TagDef] = []
	for def in defs_of("tag"):
		var tag := def as TagDef
		if tag != null and tag.is_ingredient() == (_tab == 0):
			tags.append(tag)
	tags.sort_custom(func(a: TagDef, b: TagDef) -> bool: return a.order < b.order)
	for tag in tags:
		options.append({"value": tag.get_key(), "label": tag.localized()})
	return options


func _group_options() -> Array:
	var options: Array = [{"value": "", "key": "ui.warehouse.group_none"}]
	if _tab == 0:
		options.append({"value": "source", "key": "ui.warehouse.group_source"})
	else:
		options.append({"value": "theme", "key": "ui.warehouse.group_theme"})
	return options


func _sort_options() -> Array:
	return [
		{"value": "owned", "key": "ui.warehouse.sort_owned"},
		{"value": "price_down", "key": "ui.warehouse.sort_price_down"},
		{"value": "name", "key": "ui.warehouse.sort_name"},
		{"value": "order", "key": "ui.warehouse.sort_default"},
	]


func _default_sort() -> String:
	return "owned"


## 结果数只在「真的筛过」时出现：没筛的时候它跟页脚那行总数一模一样，白占宽度
func _result_text(total: int) -> String:
	if total <= 0 or not _has_filters():
		return ""
	return I18n.t("ui.filter.result_count", [total])


## 分组和排序只是换个排列，不算「筛」
func _has_filters() -> bool:
	return not _keyword.strip_edges().is_empty() \
			or _status_filter == 1 \
			or not _theme_key.is_empty() \
			or not _tag_key.is_empty()


func _on_tab_changed(index: int) -> void:
	if _restoring_tab:
		return
	_tab = index
	_page = 0
	_armed_all = ""
	Sfx.play(Sfx.Intent.TAB)
	# 换页签 = 换维度：材料按来源分、成品按主题分，检索条与商人下拉整排跟着换。
	# 这里重建整条工具条（而不是只换 FilterBar），产地页才收得掉用不上的控件。
	_reset_filters_for_tab()
	_build_toolbar()
	_fill_page()
	flash_content()


func _fill_page() -> void:
	clear_content()
	PanelKit.clear(footer)
	if _tab == 2:
		_fill_harvest_page()
		return
	if _tab == 0:
		content.add_child(_capacity_row(false))
		content.add_child(PanelKit.divider())
	var items := _tab_items()
	if _bar != null and is_instance_valid(_bar):
		_bar.set_result_text(_result_text(items.size()))
	if items.is_empty():
		# 搜空了和本来就没有，是两件不同的事：前者要人「换个词」，后者要人「先去拿/做」
		var empty_text := I18n.t("ui.filter.empty") if _has_filters() else _empty_text()
		content.add_child(PanelKit.hint(empty_text))
		return
	var total := items.size()
	var page_count := maxi(1, ceili(float(total) / float(PAGE_SIZE)))
	_page = clampi(_page, 0, page_count - 1)
	var first := _page * PAGE_SIZE
	# 分堆时每换一堆插一条抬头；页与页之间会重复一次抬头，这是有意的：
	# 从第 2 页接着看的人也需要知道自己在哪一堆。
	var last_group := ""
	for item in items.slice(first, mini(first + PAGE_SIZE, total)):
		var group_label := _group_label_of(item)
		if group_label != "" and group_label != last_group:
			content.add_child(PanelKit.group_header(group_label))
			last_group = group_label
		content.add_child(_item_row(item))
	_build_footer(total, page_count)


# --- 仓库容量与产地 -------------------------------------------------------


## 容量概览：仓库等级决定三档单样上限。材料页只读，产地页带升级按钮。
func _capacity_row(with_upgrade: bool) -> VBoxContainer:
	var facility := def_of(GameState.WAREHOUSE_FACILITY) as FacilityDef
	var level := GameState.get_warehouse_level()
	var max_level := facility.max_level if facility != null else GameState.WAREHOUSE_MAX_LEVEL
	var row := PanelKit.vbox(6)

	var head := PanelKit.hbox(12)
	head.add_child(PanelKit.label(I18n.t("ui.warehouse.capacity_title"), 20))
	head.add_child(PanelKit.spacer())
	head.add_child(PanelKit.label(I18n.t("ui.facility.level", [level, max_level]), 18, PanelKit.INK_SOFT))
	row.add_child(head)
	row.add_child(PanelKit.hint(I18n.t("ui.warehouse.capacity_line", [
			GameState.get_warehouse_cap_common(),
			GameState.get_warehouse_cap_rare(),
			GameState.get_warehouse_cap_intermediate()]), 660))
	row.add_child(PanelKit.hint(I18n.t("ui.warehouse.capacity_hint"), 660))

	if not with_upgrade:
		return row
	if facility == null or level >= max_level:
		row.add_child(PanelKit.label(I18n.t("ui.warehouse.upgrade_maxed"), 17, PanelKit.INK_SOFT))
		return row
	var upgrade := facility.get_upgrade(level + 1)
	if upgrade == null:
		return row
	var button := PanelKit.button(I18n.t("ui.warehouse.upgrade", [level + 1, PanelKit.coins_text(upgrade.coin_cost)]), Sfx.Intent.NONE)
	PanelKit.set_disabled(button, GameState.coins < upgrade.coin_cost)
	button.pressed.connect(func() -> void:
		if GameState.upgrade_facility(facility.get_key()):
			show_message(I18n.t("ui.facility.upgraded", [facility.localized(), level + 1]), PanelKit.INK_SOFT)
		else:
			Sfx.play(Sfx.Intent.DENY)
			show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
		refresh()
	)
	var action := PanelKit.hbox(10)
	action.add_child(button)
	if GameState.coins < upgrade.coin_cost:
		var short := PanelKit.label(I18n.t("ui.common.coins_short", [upgrade.coin_cost - GameState.coins]), 17, PanelKit.INK_SOFT)
		short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action.add_child(short)
	row.add_child(action)
	return row


## 产地页：四个采集点一行一条，升级按钮只改这一条产地，不再散在材料图鉴里。
func _fill_harvest_page() -> void:
	content.add_child(_capacity_row(true))
	content.add_child(PanelKit.divider())
	var points := GameState.get_harvest_points()
	if points.is_empty():
		content.add_child(PanelKit.hint(I18n.t("ui.warehouse.empty_harvest")))
		return
	for harvest in points:
		content.add_child(_harvest_row(harvest))


func _harvest_row(harvest: HarvestDef) -> VBoxContainer:
	var key := harvest.get_key()
	var level := GameState.get_harvest_level(key)
	var max_level := harvest.max_level()
	var row := PanelKit.vbox(6)
	var head := PanelKit.hbox(12)
	head.add_child(PanelKit.label(harvest.localized(), 20))
	head.add_child(PanelKit.spacer())
	head.add_child(PanelKit.label(I18n.t("ui.facility.level", [level, max_level]), 18, PanelKit.INK_SOFT))
	row.add_child(head)

	if not GameState.is_harvest_unlocked(harvest):
		row.add_child(PanelKit.hint(_harvest_lock_text(harvest), 640))
		row.add_child(PanelKit.divider())
		return row

	var description := harvest.localized(&"description")
	if not description.is_empty():
		row.add_child(PanelKit.hint(description, 640))
	row.add_child(PanelKit.hint(I18n.t("ui.warehouse.harvest_stats", [
			harvest.yield_at(level), int(ceil(harvest.cooldown_at(level)))]), 640))
	var trickle := harvest.trickle_at(level)
	if trickle > 0.0:
		row.add_child(PanelKit.hint(I18n.t("ui.warehouse.harvest_trickle", [PanelKit.number_text(1.0 / trickle)]), 640))
	row.add_child(_harvest_upgrade_row(harvest, level))
	row.add_child(PanelKit.divider())
	return row


func _harvest_upgrade_row(harvest: HarvestDef, level: int) -> Control:
	var target := level + 1
	if target > harvest.max_level():
		return PanelKit.label(I18n.t("ui.warehouse.harvest_maxed"), 17, PanelKit.INK_SOFT)
	var coin_cost := harvest.coin_cost_to(target)
	var item_cost := harvest.item_cost_to(target)
	if coin_cost < 0:
		return PanelKit.label(I18n.t("ui.warehouse.harvest_maxed"), 17, PanelKit.INK_SOFT)
	var action := PanelKit.hbox(10)
	var button := PanelKit.button(I18n.t("ui.warehouse.harvest_upgrade", [target, PanelKit.coins_text(coin_cost)]), Sfx.Intent.NONE)
	var enough_items := true
	if item_cost > 0:
		var stack := MaterialStack.new()
		stack.by_tag = harvest.tag
		stack.amount = item_cost
		enough_items = GameState.count_for(stack) >= item_cost
		var tag_def := def_of(harvest.tag)
		var tag_name := tag_def.localized() if tag_def != null else harvest.tag
		action.add_child(PanelKit.hint_inline(I18n.t("ui.warehouse.harvest_items", [item_cost, tag_name])))
	PanelKit.set_disabled(button, GameState.coins < coin_cost or not enough_items)
	var harvest_key := harvest.get_key()
	button.pressed.connect(func() -> void:
		if GameState.upgrade_harvest(harvest_key):
			show_message(I18n.t("ui.warehouse.harvest_upgraded", [harvest.localized(), target]), PanelKit.INK_SOFT)
		else:
			Sfx.play(Sfx.Intent.DENY)
			show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
		refresh()
	)
	action.add_child(button)
	return action


func _harvest_lock_text(harvest: HarvestDef) -> String:
	if not harvest.unlock_letter.is_empty():
		var letter := def_of(harvest.unlock_letter) as LetterDef
		var title := letter.localized(&"title") if letter != null else harvest.unlock_letter
		return I18n.t("ui.warehouse.harvest_need_letter", [title])
	if not harvest.unlock_facility.is_empty():
		var facility := def_of(harvest.unlock_facility) as FacilityDef
		var facility_name := facility.localized() if facility != null else harvest.unlock_facility
		return I18n.t("ui.warehouse.harvest_need_facility", [facility_name, harvest.unlock_level])
	return I18n.t("ui.warehouse.harvest_locked")


func _build_footer(total: int, page_count: int) -> void:
	footer.add_child(PanelKit.divider())
	var bar := PanelKit.hbox(10)
	bar.add_child(PanelKit.hint_inline(I18n.t("ui.warehouse.count", [total])))
	bar.add_child(PanelKit.spacer())
	var prev := PanelKit.button(I18n.t("ui.warehouse.prev"), Sfx.Intent.TAB)
	PanelKit.set_disabled(prev, _page <= 0)
	prev.pressed.connect(_on_page_step.bind(-1))
	bar.add_child(prev)
	var page_label := PanelKit.label(I18n.t("ui.warehouse.page", [_page + 1, page_count]), 17, PanelKit.INK_SOFT)
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(page_label)
	var next_button := PanelKit.button(I18n.t("ui.warehouse.next"), Sfx.Intent.TAB)
	PanelKit.set_disabled(next_button, _page >= page_count - 1)
	next_button.pressed.connect(_on_page_step.bind(1))
	bar.add_child(next_button)
	footer.add_child(bar)


func _on_page_step(delta: int) -> void:
	var total := _tab_items().size()
	var page_count := maxi(1, ceili(float(total) / float(PAGE_SIZE)))
	var next_page := clampi(_page + delta, 0, page_count - 1)
	if next_page == _page:
		return
	_page = next_page
	_armed_all = ""
	_fill_page()


## 当前页签该列的货：种类对、手上有、过检索条，最后排序。
## 分页与页脚共用这一份，避免两处算出不同结果。
func _tab_items() -> Array[ItemDef]:
	var items: Array[ItemDef] = []
	for def in defs_of("item"):
		var item := def as ItemDef
		if item == null or not _is_tab_item(item):
			continue
		if GameState.get_amount(item.get_key()) <= 0:
			continue
		if _status_filter == 1 and item.sell_price <= 0:
			continue
		if not _theme_key.is_empty() and GameState.item_theme_key(item.get_key()) != _theme_key:
			continue
		if not _tag_key.is_empty() and not item.tags.has(_tag_key):
			continue
		if not _matches_keyword(item):
			continue
		items.append(item)
	items.sort_custom(_sort_less)
	return items


func _is_tab_item(item: ItemDef) -> bool:
	if _tab == 0:
		return item.is_material()
	if _tab == 1:
		return item.is_food()
	return false


## 关键词只比名字与描述——仓库里的东西都见过了，不需要图鉴那种「线索」机制
func _matches_keyword(item: ItemDef) -> bool:
	var needle := _keyword.strip_edges().to_lower()
	if needle.is_empty():
		return true
	if item.localized().to_lower().contains(needle):
		return true
	return item.localized(&"description").to_lower().contains(needle)


## 排序。名字用译文比，否则切英文后顺序会跳。
## 分组是排序的一级关键字：抬头只在换堆时插一次，同堆条目必须先排到一起。
func _sort_less(a: ItemDef, b: ItemDef) -> bool:
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
			if a.sell_price != b.sell_price:
				return a.sell_price > b.sell_price
		_:
			if a.order != b.order:
				return a.order < b.order
	return a.order < b.order


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
	if _group_key == "source":
		var harvest := GameState.get_harvest_for_material(item.get_key())
		return harvest.localized() if harvest != null else I18n.t("ui.filter.other")
	var theme_def := def_of(item.theme)
	return theme_def.localized() if theme_def != null else I18n.t("ui.filter.other")


## 一行：名字 + 种类 + 存量 + 来源 + 卖按钮。
## 来源先说「从哪来」，再说「记没记下」——仓库是清点地方，来源比图鉴状态更常用。
func _item_row(item: ItemDef) -> Control:
	var key := item.get_key()
	var amount := GameState.get_amount(key)
	var row := PanelKit.vbox(4)
	var head := PanelKit.hbox(12)
	# 仓库也走同一枚组合图标章：食材看 5 族，成品/半成品沿用配方的 6 族。
	# 反查配方只为了拿 group；找不到就退回按物品键判断，不能让行变空。
	var recipe := _recipe_of(key)
	var icon_path := ItemIcons.path_for(item, recipe.group if recipe != null else "")
	var item_badge := ItemBadge.new()
	item_badge.custom_minimum_size = Vector2(30, 30)
	item_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_badge.configure(icon_path, item.localized(), ItemIcons.accent_for(icon_path), 30.0)
	head.add_child(item_badge)
	head.add_child(PanelKit.label(item.localized(), 20))
	head.add_child(PanelKit.badge(
			I18n.t("ui.warehouse.kind_material") if item.is_material() else I18n.t("ui.warehouse.kind_food"),
			PanelKit.CARD_HI, PanelKit.INK_SOFT))
	head.add_child(PanelKit.spacer())
	if item.is_material():
		var cap := GameState.get_material_cap(key)
		if cap > 0:
			head.add_child(PanelKit.label(I18n.t("ui.warehouse.capacity", [cap]), 16, PanelKit.INK_SOFT))
	head.add_child(PanelKit.label(I18n.t("ui.warehouse.owned", [PanelKit.big_number_text(amount)]), 17, PanelKit.INK_SOFT))
	row.add_child(head)

	row.add_child(PanelKit.label(_source_text(item), 16, PanelKit.INK_SOFT))

	var buttons := PanelKit.hbox(8)
	if item.sell_price > 0:
		buttons.add_child(_sell_button(item, 1))
		if amount >= 10:
			buttons.add_child(_sell_button(item, 10))
		buttons.add_child(PanelKit.spacer())
		buttons.add_child(_sell_all_button(item))
	else:
		buttons.add_child(PanelKit.hint_inline(I18n.t("ui.warehouse.no_buyer")))
	row.add_child(buttons)
	row.add_child(PanelKit.divider())
	return row


## 来源：材料看采集点 / 商人 / 免费，成品看是哪道配方做出来的；末尾附图鉴状态。
func _source_text(item: ItemDef) -> String:
	var parts: Array[String] = []
	if item.is_material():
		var harvest := GameState.get_harvest_for_material(item.get_key())
		if harvest != null:
			parts.append(harvest.localized())
		if item.merchant_price > 0:
			parts.append(I18n.t("ui.warehouse.source_merchant"))
		if item.is_free():
			parts.append(I18n.t("ui.warehouse.source_free"))
	else:
		var recipe := _recipe_of(item.get_key())
		if recipe != null:
			parts.append(I18n.t("ui.warehouse.source_recipe", [recipe.localized()]))
	if item.in_catalog and GameState.is_discovered(item.get_key()):
		parts.append(I18n.t("ui.warehouse.known"))
	if parts.is_empty():
		parts.append(I18n.t("ui.warehouse.source_unknown"))
	return I18n.t("ui.warehouse.source_line", [" · ".join(parts)])


## 这道菜是哪条配方做的。同一道菜若有多种做法，取 order 最靠前的一条。
func _recipe_of(key: String) -> RecipeDef:
	var found: RecipeDef = null
	for def in defs_of("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or recipe.output != key:
			continue
		if found == null or recipe.order < found.order:
			found = recipe
	return found


func _sell_button(item: ItemDef, amount: int) -> Button:
	var priced := item.sell_price * amount
	var button := PanelKit.button(I18n.t("ui.warehouse.sell_button", [amount, priced]), Sfx.Intent.NONE)
	PanelKit.set_disabled(button, GameState.get_amount(item.get_key()) < amount)
	button.pressed.connect(func() -> void: _sell(item, amount))
	return button


## 「卖光」按钮：武装后只改自己的字（不整页重建，滚动位置和光标都留着）
func _sell_all_button(item: ItemDef) -> Button:
	var amount := GameState.get_amount(item.get_key())
	var armed := _armed_all == item.get_key()
	var text := I18n.t("ui.warehouse.sell_all", [amount])
	if armed:
		text = I18n.t("ui.warehouse.sell_all_armed", [amount * item.sell_price])
	var button := PanelKit.button(text, Sfx.Intent.NONE)
	if armed:
		button.add_theme_color_override("font_color", PanelKit.DANGER_DEEP)
	button.pressed.connect(func() -> void: _on_sell_all(item, button))
	return button


func _on_sell_all(item: ItemDef, button: Button) -> void:
	var key := item.get_key()
	var amount := GameState.get_amount(key)
	if _armed_all != key:
		_armed_all = key
		button.text = I18n.t("ui.warehouse.sell_all_armed", [amount * item.sell_price])
		button.add_theme_color_override("font_color", PanelKit.DANGER_DEEP)
		show_message(I18n.t("ui.warehouse.sell_armed"), PanelKit.DANGER_DEEP)
		return
	_armed_all = ""
	_sell(item, amount)


func _sell(item: ItemDef, amount: int) -> void:
	var total := item.sell_price * amount
	if GameState.sell_item(item.get_key(), amount):
		Sfx.play(Sfx.Intent.SELL)
		show_message(I18n.t("ui.warehouse.sold", [item.localized(), amount, total]), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.warehouse.not_enough"), PanelKit.DANGER_DEEP)
	# 卖完数量变了，按钮与页脚都要跟着回填
	refresh()


func _empty_text() -> String:
	if _tab == 0:
		return I18n.t("ui.warehouse.empty_material")
	return I18n.t("ui.warehouse.empty_food")
