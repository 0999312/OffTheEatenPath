class_name CatalogPanel
extends GamePanel
## 书架（美食图鉴）：六类条目，每类先给一张简略清单。
##
## 一条只占一行：类型图标 + 名字 + 一句摘要；点「查看」才进完整条目详情。
## 未发现的条目保留影子（？？？ + 线索），不暴露名字与正文。
##
## 刷新纪律：图鉴内容只在「发现新条目 / 解锁新配方」时变化，所以用结构指纹
## 守住重建；指纹没变就直接返回。**不能每 0.3 秒无条件重建**——TabContainer
## 重建时 current_tab 会回到第 1 页，而且 add_child 会补发一次 tab_changed，
## 结果是玩家每 0.3 秒被弹回首页 + 页签音效无限循环（实测过）。

## 每页条目数：食物页 232 条一次铺完要滚很久，分页后一页 20 条
const PAGE_SIZE := 20

## 分类顺序即书页顺序；`type` 同时用来选类型图标，`key` 是页签文案的翻译键
const CATEGORIES := [
	{"type": "material", "key": "ui.catalog.cat_material"},
	{"type": "food", "key": "ui.catalog.cat_food"},
	{"type": "recipe", "key": "ui.catalog.cat_recipe"},
	{"type": "facility", "key": "ui.catalog.cat_facility"},
	{"type": "world", "key": "ui.catalog.cat_world"},
	{"type": "letter", "key": "ui.catalog.cat_letter"},
]

## 每类一个代表图标（assets/icons 下已存在的 SVG）；不再用首字印章冒充图
const TYPE_ICONS := {
	"material": "food/carrot.svg",
	"food": "food/ham.svg",
	"recipe": "ui/clip.svg",
	"facility": "ui/adjust.svg",
	"world": "ui/monitor.svg",
	"letter": "ui/bookmark.svg",
}

## 上次重建时的结构指纹；相同就什么都不做
var _structure_signature: String = ""
## 玩家停在哪个页签；重建后要还原，否则会被弹回首页
var _tab_index: int = 0
## 当前页签里的第几页（0 起）；切页签 / 改搜索 / 改筛选都回到第 1 页
var _page: int = 0
## 重建期间为 true：用来吃掉「程序性切页」补发的 tab_changed
var _restoring_tab: bool = false
## 页签栏：固定在纸上（toolbar），只有这一页的内容在下面的滚动区里
var _tab_bar: TabBar

## 筛选与搜索：只决定「这一页现在显示什么」，不碰图鉴总数、已发现数与里程碑。
## 状态存在面板上、而不是 FilterBar 里——切页签要重建工具条，选择不能跟着丢。
var _keyword: String = ""
## 0 = 全部，1 = 已记录，2 = 未记录
var _filter: int = 0
## "" = 全部主题；否则是完整主题键（game:theme/...）
var _theme_key: String = ""
## "" = 全部标签；否则是完整标签键（game:tag/...）。标签与主题是两个维度：
## 主题单选（这道菜从哪来），标签可叠加（它在什么场合出现），图鉴里各筛一次。
var _tag_key: String = ""
## 分组："" 不分堆，"theme" 按主题，"source" 按采集点。
## 食物页只有主题、材料页只有产地——别的页条目本来就少，不给这个下拉。
var _group_key: String = ""
## 排序："default" 用数据里的 order（策划排好的阅读顺序），"name" 按译文排
var _sort_key: String = "default"
## 检索条：搜索 + 记录态 + 主题标签浮层 + 分组排序，都收在这一个控件里
var _bar: FilterBar = null
## 本次打开前新发现的条目键：只给这些行标红点，打开期间保留，关掉再开就没了。
## 必须在 mark_catalog_seen() 之前抓，否则第一帧就全清。
var _new_keys: Dictionary = {}
## 打开后要定位并滚到的条目键；定位一次就清掉
var _locate_key: String = ""


func _on_open(data: Dictionary = {}) -> void:
	# 先快照「新发现」，再决定要不要定位：顺序反了红点就永远不亮。
	_new_keys.clear()
	var fresh := GameState.get_new_catalog_keys()
	for key in fresh:
		_new_keys[key] = true

	var focus_newest := String(data.get("focus", "")) == "newest"
	_locate_key = ""
	if focus_newest:
		# 从 HUD 点进来是要「看最新那条」：先把筛选清干净，否则它可能被筛掉、定位不到。
		_keyword = ""
		_filter = 0
		_theme_key = ""
		_tag_key = ""
		_group_key = ""
		_sort_key = "default"
		_page = 0
		_locate_key = String(fresh[0]) if not fresh.is_empty() else GameState.get_newest_discovered_key()
		var wanted_tab := _tab_index_for_key(_locate_key)
		if wanted_tab >= 0:
			_tab_index = wanted_tab
	elif data.has("key"):
		# 从灶台点「？？？」进来：清掉筛选，否则影子行可能被筛掉、定位不到（第八轮反馈 2）
		var target_key := String(data["key"])
		_keyword = ""
		_filter = 0
		_theme_key = ""
		_tag_key = ""
		_group_key = ""
		_sort_key = "default"
		_locate_key = target_key
		var target_tab := _tab_index_for_key(target_key)
		if target_tab >= 0:
			_tab_index = target_tab
	elif data.has("tab"):
		var wanted := String(data["tab"])
		for index in CATEGORIES.size():
			if String(CATEGORIES[index]["type"]) == wanted:
				_tab_index = index
				break
	_structure_signature = ""
	_page = 0
	super._on_open(data)
	# 打开图鉴就把「新发现」清掉：HUD 上那个红点随之收起。
	GameState.mark_catalog_seen()
	_locate_open_target()


## 条目键 → 页签下标。用 DataRegistry 的类型判断，不靠键前缀猜。
func _tab_index_for_key(key: String) -> int:
	if key.is_empty():
		return -1
	var def := def_of(key)
	var type_id := ""
	if def is ItemDef:
		type_id = "food" if (def as ItemDef).is_food() else "material"
	elif def is RecipeDef:
		type_id = "recipe"
	elif def is FacilityDef:
		type_id = "facility"
	elif def is WorldDef:
		type_id = "world"
	elif def is LetterDef:
		type_id = "letter"
	for index in CATEGORIES.size():
		if String(CATEGORIES[index]["type"]) == type_id:
			return index
	return -1


## 打开后定位：翻到目标所在页、找到那一行、滚到可见。找不到就留当前页提示一句，不崩。
func _locate_open_target() -> void:
	if _locate_key.is_empty():
		return
	var key := _locate_key
	_locate_key = ""
	var type_id := _current_type()
	if type_id.is_empty():
		return
	var defs := _filtered_defs(type_id)
	var target_index := -1
	for index in defs.size():
		if defs[index].get_key() == key:
			target_index = index
			break
	if target_index < 0:
		_toast_locate_failed()
		return
	var target_page := target_index / PAGE_SIZE
	if target_page != _page:
		_page = target_page
		_structure_signature = _structure_signature_now()
		_fill_page(_tab_index)
	# 等一帧让容器排好版，ensure_control_visible 才有正确的 rect
	await get_tree().process_frame
	var target := content.find_child(key.validate_node_name(), true, false) as Control
	if target == null:
		_toast_locate_failed()
		return
	if _scroll != null:
		_scroll.ensure_control_visible(target)


func _toast_locate_failed() -> void:
	var toast_id := ResourceLocation.from_string(UIKeys.TOAST_MESSAGE)
	if toast_id == null:
		return
	UIManager.dismiss_all_toasts()
	UIManager.show_toast(toast_id, {"key": "ui.catalog.locate_failed", "accent": false}, 2.4)


func refresh() -> void:
	var signature := _structure_signature_now()
	if signature == _structure_signature:
		return
	_structure_signature = signature
	_rebuild()


## 切语言：页签与外框文案都要换，清掉结构签名强制重建
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	_structure_signature = ""
	refresh()


## 结构指纹：只包含会改变条目内容的信息——已发现数量 + 已解锁配方数量 + 筛选状态
func _structure_signature_now() -> String:
	return "%d|%d|%d|%s|%d|%s|%s|%s|%s|%d" % [
		GameState.get_catalog_discovered_count(),
		GameState.get_next_catalog_target(),
		GameState.get_visible_recipes().size(),
		_keyword,
		_filter,
		_theme_key,
		_tag_key,
		_group_key,
		_sort_key,
		_page,
	]


## 顶部常驻的「还差多少」：只给四档区间，不给数字（第六轮反馈）。
## 分母是下一封还没读的图鉴门槛信——玩家不知道门槛也能读懂「过半 / 就差一点」；
## 读掉那封信之后，这句话自然换成下一档。
func _progress_hint() -> String:
	var target := GameState.get_next_catalog_target()
	if target <= 0:
		return I18n.t("ui.catalog.progress_done")
	var ratio := clampf(float(GameState.get_catalog_discovered_count()) / float(target), 0.0, 1.0)
	if ratio < 0.25:
		return I18n.t("ui.catalog.progress_early")
	if ratio < 0.5:
		return I18n.t("ui.catalog.progress_quarter")
	if ratio < 0.75:
		return I18n.t("ui.catalog.progress_half")
	return I18n.t("ui.catalog.progress_near")


## 页签用 TabBar 而不是 TabContainer：TabBar 只是一排标签，不带内容区，
## 这样才能把它钉在 toolbar 上、只让下面的内容滚。
func _rebuild() -> void:
	_restoring_tab = true
	# 工具条整层清掉时 _bar 会跟着被释放：先松手，免得下面拿到一个死引用
	_bar = null
	PanelKit.clear(toolbar)
	clear_content()
	set_title(I18n.t("ui.catalog.title"))
	set_subtitle(I18n.t("ui.catalog.subtitle"))

	_tab_bar = TabBar.new()
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.tab_changed.connect(_on_tab_changed)
	# 页签行右侧常驻一句「还差多少」：只说区间、不说数字（第六轮反馈）。
	# 钉在工具条上，翻页 / 切分类 / 滚列表都不会把它带走。
	var tab_row := PanelKit.hbox(14)
	tab_row.add_child(_tab_bar)
	var progress := PanelKit.hint_inline(_progress_hint())
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tab_row.add_child(progress)
	toolbar.add_child(tab_row)
	for category in CATEGORIES:
		_tab_bar.add_tab(I18n.t(String(category["key"])))
	_build_filter_bar()

	_tab_index = clampi(_tab_index, 0, CATEGORIES.size() - 1)
	_tab_bar.current_tab = _tab_index
	_fill_page(_tab_index)
	_restoring_tab = false


## 工具条第二层：检索。一行放完——搜索 + 记录态 + 筛选浮层 + 分组 + 排序。
##
## 原来是四行（搜索 / 主题 / 标签），占掉卡片高度的三分之一；主题与标签平时
## 根本用不上，收进浮层之后常用的一行就够了。这版按「暂定初版」记录，
## 浮层形态还留着大改的余地（用户 2026-10-27 拍板）。
func _build_filter_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		toolbar.remove_child(_bar)
		_bar.queue_free()
	_bar = FilterBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_bar)

	_bar.add_search("ui.catalog.search_placeholder", 150.0, _keyword)
	_bar.add_segments("record", [
		{"value": 0, "key": "ui.catalog.filter_all"},
		{"value": 1, "key": "ui.catalog.filter_found"},
		{"value": 2, "key": "ui.catalog.filter_missing"},
	], _filter)

	# 主题与标签只有食物页有：别的页没这两个维度，摆出来只会让人白点
	if _current_type() == "food":
		_bar.add_menu_group("theme", "ui.catalog.filter_theme", _theme_options(), _theme_key)
		_bar.add_menu_group("tag", "ui.catalog.filter_tag", _tag_options(), _tag_key)
	if _supports_group():
		_bar.add_group(_group_options(), _group_key)
		_bar.add_sort(_sort_options(), _sort_key)
	_bar.changed.connect(_on_filters_changed)
	_bar.set_result_text("")


## 浮层里的主题组：数据层已经有名字了，直接给译文，不再走翻译键
func _theme_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.catalog.theme_all")}]
	for theme_def in _themes():
		options.append({"value": theme_def.get_key(), "label": theme_def.localized()})
	return options


func _tag_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.catalog.tag_all")}]
	for tag_def in _tags():
		options.append({"value": tag_def.get_key(), "label": tag_def.localized()})
	return options


## 分组下拉：食物按主题分堆，材料按采集点分堆
func _group_options() -> Array:
	var options: Array = [{"value": "", "key": "ui.catalog.group_none"}]
	if _current_type() == "food":
		options.append({"value": "theme", "key": "ui.catalog.group_theme"})
	elif _current_type() == "material":
		options.append({"value": "source", "key": "ui.catalog.group_source"})
		options.append({"value": "category", "key": "ui.catalog.group_category"})
	return options


func _sort_options() -> Array:
	return [
		{"value": "default", "key": "ui.catalog.sort_default"},
		{"value": "name", "key": "ui.catalog.sort_name"},
	]


## 结果数只在「真的筛过」时出现：没筛的时候它跟页脚那行总数一模一样，
## 白占一段宽度，还会把搜索框挤窄（1280 下实测过）。
func _result_text(total: int) -> String:
	if total <= 0 or not _has_filters():
		return ""
	return I18n.t("ui.filter.result_count", [total])


func _has_filters() -> bool:
	return not _keyword.strip_edges().is_empty() or _filter != 0 \
			or not _theme_key.is_empty() or not _tag_key.is_empty()


func _supports_group() -> bool:
	var type_id := _current_type()
	return type_id == "food" or type_id == "material"


## 一条条目属于哪一堆。不分组、或这一页没有这个维度时返回空串，调用方就不插抬头。
func _group_label_of(def: GameDef, type_id: String) -> String:
	if _group_key.is_empty():
		return ""
	if _group_key == "theme" and type_id == "food":
		# 还没到站的那一堆不报地方名，否则按主题分组就等于把后半程的地图摊开了
		if _is_theme_locked(def, type_id):
			return I18n.t("ui.catalog.theme_locked")
		var theme_def := def_of((def as ItemDef).theme)
		return theme_def.localized() if theme_def != null else I18n.t("ui.filter.other")
	if _group_key == "source" and type_id == "material":
		var harvest := GameState.get_harvest_for_material(def.get_key())
		return harvest.localized() if harvest != null else I18n.t("ui.filter.other")
	if _group_key == "category" and type_id == "material":
		var item := def as ItemDef
		if item == null:
			return I18n.t("ui.filter.other")
		var family := ItemIcons.material_path(item).get_file().get_basename()
		return I18n.t("ui.catalog.family_%s" % family)
	return ""


## 主题按 order 排；只列已经到站的——筛选条上出现一个还没到过的地方，本身就是剧透。
## 以后加主题只加 `.tres`，这里不用动。
func _themes() -> Array[ThemeDef]:
	var result: Array[ThemeDef] = []
	for def in defs_of("theme"):
		if def is ThemeDef and GameState.is_theme_unlocked(def.get_key()):
			result.append(def as ThemeDef)
	result.sort_custom(func(a: ThemeDef, b: ThemeDef) -> bool: return a.order < b.order)
	return result


## 主题还没到站的食物：位置留着，名字 / 线索 / 分组名一律不给。
## 和「没发现」是两回事——没发现还能读线索，这里连线索都算剧透。
## 已经收录的照常显示（旧存档里可能有，或者玩家真做出过）。
func _is_theme_locked(def: GameDef, type_id: String) -> bool:
	if type_id != "food":
		return false
	if GameState.is_discovered(def.get_key()):
		return false
	return not GameState.is_theme_unlocked((def as ItemDef).theme)


## 标签按 order 排；加标签只加 `.tres`，这里不用动。
## 只收图鉴那一类（scope=food）：食材标签（「任意蔬菜」）是配方输入用的维度，
## 摆进图鉴筛选条只会让人以为「这也能筛」，其实一道菜并不挂它。
func _tags() -> Array[TagDef]:
	var result: Array[TagDef] = []
	for def in defs_of("tag"):
		if def is TagDef and not (def as TagDef).is_ingredient():
			result.append(def as TagDef)
	result.sort_custom(func(a: TagDef, b: TagDef) -> bool: return a.order < b.order)
	return result


func _current_type() -> String:
	if _tab_index < 0 or _tab_index >= CATEGORIES.size():
		return ""
	return String(CATEGORIES[_tab_index]["type"])


## 检索条里任何一项变了：抄回面板字段、回第一页、只重填列表。
## **不重建工具条**——搜索框就在工具条里，一重建光标就丢了。
func _on_filters_changed() -> void:
	_keyword = _bar.get_keyword()
	_filter = _bar.get_segment("record")
	_theme_key = _bar.get_menu_value("theme")
	_tag_key = _bar.get_menu_value("tag")
	_group_key = _bar.get_group()
	_sort_key = _bar.get_sort()
	_page = 0
	_structure_signature = _structure_signature_now()
	_fill_page(_tab_index)


func _on_tab_changed(index: int) -> void:
	# 重建/还原页签时补发的那一次不算玩家操作，不该有音效，也不该覆盖记录
	if _restoring_tab:
		return
	_tab_index = index
	_page = 0
	Sfx.play(Sfx.Intent.TAB)
	# 换页签 = 换维度：食物有主题标签、材料按产地分堆，检索条整条跟着换
	_build_filter_bar()
	_structure_signature = _structure_signature_now()
	_fill_page(index)
	flash_content()

## 换页 = 换内容，页签栏本身不动
func _fill_page(index: int) -> void:
	clear_content()
	PanelKit.clear(footer)
	if _scroll != null:
		_scroll.scroll_vertical = 0
	if index < 0 or index >= CATEGORIES.size():
		return
	content.add_child(_build_page(String(CATEGORIES[index]["type"])))


## 一页该显示哪些定义。`"material"` / `"food"` 是**页面 id**（不是数据类型）：
## 数据层只有 `item` 一种定义，材料与食物按 `kind` 分家，其余页面 id 就是类型本身。
func _defs_of_page(type_id: String) -> Array[GameDef]:
	if type_id != "material" and type_id != "food":
		return defs_of(type_id)
	var want_food := type_id == "food"
	var items := defs_of("item")
	return items.filter(func(def: GameDef) -> bool:
		var item := def as ItemDef
		return item != null and item.is_food() == want_food
	)


## 当前页签、当前筛选下该显示的条目，已排序。分页与页脚都用这一份，避免两处算出不同结果。
func _filtered_defs(type_id: String) -> Array[GameDef]:
	var defs := _defs_of_page(type_id)
	defs = defs.filter(_is_cataloged)
	defs = defs.filter(func(def: GameDef) -> bool: return _matches(def, type_id))
	# 分组维度跟着页签走（食物看主题、材料看产地），类型要绑进比较函数 ——
	# 不能让它去读 _current_type()，那会把「排哪一页」和「面板停在哪一页」绑死。
	defs.sort_custom(_sort_less.bind(type_id))
	return defs


## 默认顺序是策划在数据里排的阅读顺序；「按名字」才是玩家自己找东西时的顺序。
## 名字比译文（切英文后按英文名），否则排出来的顺序会跟着语言跳。
## 分组是排序的一级关键字：抬头只在换堆时插一次，同堆条目必须先排到一起，
## 否则同一堆会被别的堆隔开，抬头反复出现、看着就像根本没分组（用户 2026-10-27 报）。
func _sort_less(a: GameDef, b: GameDef, type_id: String) -> bool:
	if not _group_key.is_empty():
		var left_group := _group_label_of(a, type_id)
		var right_group := _group_label_of(b, type_id)
		if left_group != right_group:
			return _group_less(left_group, right_group)
	if _sort_key == "name":
		var left := a.localized()
		var right := b.localized()
		if left != right:
			return left < right
	return _order_of(a) < _order_of(b)


## 「其他」是兜底堆，永远排最后：夹在正经分组中间只会让人以为它也是个正经分类。
## 其余按译文比，切语言后顺序跟着名字走，和「按名字」排序的直觉一致。
func _group_less(left: String, right: String) -> bool:
	var other := I18n.t("ui.filter.other")
	if left == other:
		return false
	if right == other:
		return true
	return left < right


func _build_page(type_id: String) -> Control:
	var list := PanelKit.vbox(7)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var defs := _filtered_defs(type_id)
	# 结果数是「筛选有多窄」的唯一即时反馈：没有它，玩家只能靠翻页猜
	if _bar != null and is_instance_valid(_bar):
		_bar.set_result_text(_result_text(defs.size()))
	# 筛空了也要留住页脚：否则玩家会以为这一页坏了，而不是「筛选太窄」
	if defs.is_empty():
		# 筛空了统一用 ui.filter.empty（2026-10-28 统一检索 §5）：三处同一句话，
		# 玩家在书架 / 灶台 / 商店看到的是同一个「换个词，或者放宽一点」。
		list.add_child(PanelKit.hint(I18n.t("ui.filter.empty")))
		footer.add_child(PanelKit.divider())
		footer.add_child(PanelKit.hint(I18n.t("ui.catalog.recorded", [0, 0])))
		return list
	var total := defs.size()
	var page_count := maxi(1, ceili(float(total) / float(PAGE_SIZE)))
	_page = clampi(_page, 0, page_count - 1)
	var first := _page * PAGE_SIZE
	var shown := defs.slice(first, mini(first + PAGE_SIZE, total))
	# 完成度是整页分类的，不是当前这一屏的：翻页时这个数字不该跟着变
	var recorded := 0
	for def in defs:
		if GameState.is_discovered(def.get_key()):
			recorded += 1
	# 分堆时每换一堆就插一条抬头。页与页之间会重复一次抬头，
	# 这是有意的：从第 2 页接着看的人也需要知道自己在哪一堆。
	var last_group := ""
	for def in shown:
		var group_label := _group_label_of(def, type_id)
		if group_label != "" and group_label != last_group:
			list.add_child(PanelKit.group_header(group_label))
			last_group = group_label
		list.add_child(_entry_row(def, type_id))
	# 完成度属于「这一页的抬头」，不是列表的最后一行：放进固定页脚，
	# 这样滚到列表底部时数字仍然留在纸上，不会被滚走。
	footer.add_child(PanelKit.divider())
	var bar := PanelKit.hbox(10)
	bar.add_child(PanelKit.hint_inline(I18n.t("ui.catalog.recorded", [recorded, total])))
	bar.add_child(PanelKit.spacer())
	var prev := PanelKit.button(I18n.t("ui.catalog.prev"), Sfx.Intent.TAB)
	PanelKit.set_disabled(prev, _page <= 0)
	prev.pressed.connect(_on_page_step.bind(-1))
	bar.add_child(prev)
	# 页码是这一组里的「当前位置」，比两侧按钮小一号会被读成标签（报告 P2-5）
	var page_label := PanelKit.label(I18n.t("ui.catalog.page", [_page + 1, page_count]), 17, PanelKit.INK_SOFT)
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(page_label)
	var next_button := PanelKit.button(I18n.t("ui.catalog.next"), Sfx.Intent.TAB)
	PanelKit.set_disabled(next_button, _page >= page_count - 1)
	next_button.pressed.connect(_on_page_step.bind(1))
	bar.add_child(next_button)
	footer.add_child(bar)
	return list


## 翻页：只换列表与页脚，页签与筛选条不动。
## `_page` 进结构指纹，所以 0.3 秒一次的时钟刷新重建不会把玩家丢回第 1 页。
func _on_page_step(delta: int) -> void:
	var defs := _filtered_defs(_current_type())
	var page_count := maxi(1, ceili(float(defs.size()) / float(PAGE_SIZE)))
	var next_page := clampi(_page + delta, 0, page_count - 1)
	if next_page == _page:
		return
	_page = next_page
	_structure_signature = _structure_signature_now()
	_fill_page(_tab_index)


## 一条条目要不要出现在当前页：三档记录筛选 + 主题 + 关键词，三者都过才算。
## 未记录的条目只能靠线索搜到——不能拿真名去匹配，否则搜索框等于剧透。
func _matches(def: GameDef, type_id: String) -> bool:
	var discovered := GameState.is_discovered(def.get_key())
	if _filter == 1 and not discovered:
		return false
	if _filter == 2 and discovered:
		return false
	if type_id == "food" and not _theme_key.is_empty():
		if (def as ItemDef).theme != _theme_key:
			return false
	# 标签与主题是两个维度，可以叠着筛：东亚 + 街边 = 能拿着走的东亚菜
	if type_id == "food" and not _tag_key.is_empty():
		if not has_tag(def.get_key(), _tag_key):
			return false
	var needle := _keyword.strip_edges().to_lower()
	# 还没到站的地方只有一个占位：搜索框不该能把它试出来（线索也不行）
	if _is_theme_locked(def, type_id):
		return needle.is_empty()
	if needle.is_empty():
		return true
	var fields: Array[String] = [_hint_of(def)]
	if discovered:
		fields.append(def.localized())
		fields.append(def.localized(&"description"))
		fields.append(_subtitle_of(def))
		fields.append(_summary_of(def))
	for text in fields:
		if String(text).to_lower().contains(needle):
			return true
	return false


func _is_cataloged(def: GameDef) -> bool:
	if def is ItemDef:
		return (def as ItemDef).in_catalog
	if def is RecipeDef:
		return (def as RecipeDef).in_catalog
	return true


func _order_of(def: GameDef) -> int:
	if def is ItemDef:
		return (def as ItemDef).order
	if def is RecipeDef:
		return (def as RecipeDef).order
	if def is LetterDef:
		return (def as LetterDef).order
	if def is WorldDef:
		return (def as WorldDef).order
	return 0


## 一条简略记录：左边类型图标，中间名字 + 一句摘要，右边「查看」。
## 未发现时图标变灰、名字换成「？？？」加一个空心圈，仍可点开看线索；
## 已发现且是本次打开前新收录的，名字后面亮一个红点（关掉再开就没了）。
func _entry_row(def: GameDef, type_id: String) -> PanelContainer:
	var key := def.get_key()
	var discovered := GameState.is_discovered(key)
	var card := PanelContainer.new()
	# 行根节点用条目键命名：HUD 「定位最新」靠 find_child 抓这一行
	card.name = key.validate_node_name()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PanelKit.slab(PanelKit.CARD_HI if discovered else PanelKit.PAPER_BACK,
			PanelKit.INK if discovered else PanelKit.INK_SOFT, 8, 2)
	style.content_margin_left = 14.0
	style.content_margin_top = 9.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 9.0
	card.add_theme_stylebox_override("panel", style)

	var row := PanelKit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var icon_tint := PanelKit.tint_of(type_id) if discovered else PanelKit.INK_SOFT
	var mark := PanelKit.icon(String(TYPE_ICONS.get(type_id, "ui/book.svg")), 28.0, icon_tint)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	var text_block := PanelKit.vbox(2)
	text_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if discovered:
		var head := PanelKit.hbox(8)
		var entry_name := def.localized()
		head.add_child(PanelKit.label(entry_name, 19))
		# 副标题与名字撞车是数据撞车不是玩家需要的信息：设备页「咖啡机 咖啡机」、
		# 世界页「白纸空间 一间没有墙的房间 / 一间没有墙的房间」都是这么来的。
		var subtitle := _subtitle_of(def)
		if not subtitle.is_empty() and subtitle != entry_name:
			head.add_child(PanelKit.label(subtitle, 14, PanelKit.INK_SOFT))
		if _new_keys.has(key):
			head.add_child(_new_dot())
		text_block.add_child(head)
		var body := _summary_of(def)
		if not body.is_empty() and body != entry_name and body != subtitle:
			var body_label := PanelKit.hint(body)
			body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body_label.max_lines_visible = 1
			# 一行放不下就给省略号：英文描述最长是中文的 4.75 倍，直接裁掉会像打错字。
			# 全文在详情页（那里是 autowrap 全显示），列表里不必为它再让出一行高。
			body_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			text_block.add_child(body_label)
	elif _is_theme_locked(def, type_id):
		# 还没到站：连红点都不点——红点说的是「你有新信」，这里只是「你还没到」
		text_block.add_child(PanelKit.label(I18n.t("ui.catalog.unknown"), 19, PanelKit.INK_SOFT))
		text_block.add_child(PanelKit.hint(I18n.t("ui.catalog.theme_locked")))
	else:
		var unknown_row := PanelKit.hbox(6)
		unknown_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unknown_row.add_child(PanelKit.label(I18n.t("ui.catalog.unknown"), 19, PanelKit.INK_SOFT))
		unknown_row.add_child(_hollow_dot())
		text_block.add_child(unknown_row)
		var hint := PanelKit.hint(_hint_of(def))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = 1
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_block.add_child(hint)
	row.add_child(text_block)

	var view := PanelKit.button(I18n.t("ui.catalog.view"), Sfx.Intent.NONE)
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 未收录也允许点开：详情页本来就会显示「？？？」和提示，锁住反而让人看不出还差什么。
	view.pressed.connect(func() -> void:
		Sfx.play(Sfx.Intent.CLICK)
		UIManager.open_panel(ResourceLocation.from_string(UIKeys.CATALOG_DETAIL), {"key": def.get_key(), "type": type_id})
	)
	row.add_child(view)
	return card


## 本次打开前新收录：红点。打开期间保留，关掉再开就清（HUD 红点同一份语义）
func _new_dot() -> Panel:
	var dot := Panel.new()
	dot.name = "NewDot"
	dot.custom_minimum_size = Vector2(7.0, 7.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PanelKit.DANGER
	style.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", style)
	return dot


## 未收录：空心灰圈，只说「这里还有个空位」，不是「你有新东西」
func _hollow_dot() -> Panel:
	var dot := Panel.new()
	dot.name = "EmptyDot"
	dot.custom_minimum_size = Vector2(7.0, 7.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	var ink := PanelKit.INK
	ink.a = 0.35
	style.border_color = ink
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", style)
	return dot


func _subtitle_of(def: GameDef) -> String:
	if def is ItemDef:
		var item := def as ItemDef
		if item.is_food():
			return item.localized(&"taste")
		return I18n.t("ui.catalog.gathered") if item.material_kind == ItemDef.MaterialKind.BASE else I18n.t("ui.catalog.semi_finished")
	if def is RecipeDef:
		return I18n.t("ui.catalog.cost_time", [PanelKit.duration_text((def as RecipeDef).duration_seconds)])
	if def is FacilityDef:
		return _facility_category_text((def as FacilityDef).category)
	if def is LetterDef:
		return I18n.t("ui.catalog.from_letter")
	if def is WorldDef:
		return (def as WorldDef).localized(&"subtitle")
	return ""


## 列表里只放一句，完整描述留给详情弹层
func _summary_of(def: GameDef) -> String:
	if def is ItemDef:
		return def.localized(&"description")
	if def is RecipeDef:
		return I18n.t("ui.catalog.recipe_summary")
	if def is FacilityDef:
		return I18n.t("ui.catalog.facility_summary", [(def as FacilityDef).max_level])
	if def is WorldDef:
		return (def as WorldDef).localized(&"subtitle")
	if def is LetterDef:
		return def.localized(&"description")
	return def.localized(&"description")


## 设备类别是数据层的英文枚举（coffee_machine 等），图鉴里要翻成人话；
## 键不存在时退回原文，新设备不至于变成空白
func _facility_category_text(category: String) -> String:
	var key := "ui.catalog.category_%s" % category
	var text := I18n.t(key)
	return text if text != key else category


func _hint_of(def: GameDef) -> String:
	if def is ItemDef:
		var item := def as ItemDef
		if not item.is_food():
			# 还没遇见的材料别拿描述糊过去（用户 2026-10-29 报）：写清哪来——能造写配方、能买写价钱、能采写采集点。
			if not GameState.is_discovered(item.get_key()):
				return material_hint(item)
			return item.localized(&"description")
		# 还没吃到的菜如果卡在研究上，直接把材料方向写进列表——
		# 只给一句氛围线索的话，玩家不知道该往研究台放什么（用户 2026-10-29 报）。
		if not GameState.is_discovered(item.get_key()):
			var maker := research_recipe_for_food(item.get_key())
			if maker != null:
				return research_clue(maker)
		var food_hint := item.localized(&"catalog_hint")
		return food_hint if not food_hint.is_empty() else I18n.t("ui.catalog.hint_food")
	if def is RecipeDef:
		var recipe := def as RecipeDef
		if recipe.needs_research() and not GameState.is_recipe_unlocked(recipe.get_key()):
			return research_clue(recipe)
		return I18n.t("ui.catalog.hint_recipe")
	if def is FacilityDef:
		return I18n.t("ui.catalog.hint_facility")
	if def is LetterDef:
		return I18n.t("ui.catalog.hint_letter")
	if def is WorldDef:
		var world_hint := (def as WorldDef).localized(&"catalog_hint")
		return world_hint if not world_hint.is_empty() else I18n.t("ui.catalog.hint_world")
	return I18n.t("ui.catalog.hint_unknown")
