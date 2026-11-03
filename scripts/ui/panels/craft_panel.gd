class_name CraftPanel
extends GamePanel
## 灶台：选配方 → 看材料够不够 → 开做；下方显示正在做的东西。
##
## 刷新策略：GamePanel 每 0.3 秒调一次 refresh()，如果每次都整块重建，
## 选中态、滚动位置和鼠标悬停都会跟着抖。所以这里把「结构」和「进度」分开：
## 结构（选了哪道菜、有没有空位、材料够不够、几个任务）变了才重建，
## 否则只改「还剩几秒」这类文字。

var _selected: String = ""
var _recipes: Array[RecipeDef] = []

## 这一批做几份（只对中间品配方有效；换配方时归 1）
var _batch: int = 1

## 上次重建时的结构指纹；相同就只更新进度文字
var _structure_signature: String = ""
## 配方键 → 左列卡；进度更新只改已有卡片，不重建
var _cards: Dictionary = {}
## 当前待办点名要做的配方（只用于卡片上的「委托」标记，不改变筛选）
var _guided_recipe_keys: Dictionary = {}

## 左列滚动条归零会让人丢了「我刚才在看哪道菜」，重建时把它接回来
var _list_scroll: ScrollContainer = null
var _pending_scroll := -1

## 左列分组：半成品排最前、简单菜其后、正餐排最后；认不出的 `group` 退回饮品
const GROUPS := [
	{"id": "semi", "key": "ui.craft.group_semi"},
	{"id": "simple", "key": "ui.craft.group_simple"},
	{"id": "drink", "key": "ui.craft.group_drink"},
	{"id": "bake", "key": "ui.craft.group_bake"},
	{"id": "steam", "key": "ui.craft.group_steam"},
	{"id": "meal", "key": "ui.craft.group_meal"},
]
## 每组是否收起；重建左列时照这个还原（FoldableContainer 本身不记得）
var _folded: Dictionary = {}

## 首次打开时只展开「当前选中那道菜」所在的组：241 道菜全铺出来，左列要滚好几屏
var _fold_defaults_done := false

## 筛选三档：全部 / 可做 / 未记录。未记录必然可做——图鉴没记过、且当下材料与设备都够，
## 才值得列出来找空白。空位与产线不算「做不了」，不参与这里的判断。
enum Filter { ALL, CRAFTABLE, UNRECORDED }
var _filter_mode: int = Filter.ALL
## 搜索词、主题与标签：两百多道菜光靠滚动太慢（试玩第二轮问题 4）
var _keyword := ""
var _theme_key := ""
## "" = 所有标签；否则是完整标签键（game:tag/...）。与主题、关键词叠加。
var _tag_key := ""
## 工具条复用书架那条 `FilterBar`；面板重建时它跟着被释放，所以每次重建重取
var _bar: FilterBar = null
## 筛选刚变过：左列换了一批内容，选中项要重新找落点
var _filters_dirty := true

## 懒加载用：组 id → 内容容器 / 成员配方 / 是否已建过按钮。
## 收起的组只留标题，展开时才把按钮补进去（_fill_group）。
var _group_boxes: Dictionary = {}
var _group_members: Dictionary = {}
var _group_filled: Dictionary = {}


## 外层不滚：左列列表和右列详情各自滚。外层再套 ScrollContainer 时，
## 滚轮会先被外层吃掉，两列一起上下跑（试玩第三轮反馈 2）。
func wants_outer_scroll() -> bool:
	return false


func _on_init() -> void:
	# 「还剩几秒」随时间变，但结构不用重建——交给基类的轻 Timer 只改文字
	tick_interval = 0.25


func _on_open(data: Dictionary = {}) -> void:
	# 上次的筛选先接回来：它决定这次选中项还能不能被左列看见（第八轮反馈 3）
	_filter_mode = SettingsStore.get_craft_filter()
	# 选中项由 _sync_recipes 兜底（它会落在第一道「筛完还看得见」的菜上）；
	# 这里再补一句 _recipes[0] 会把「可做」段空掉时的右列写成一道看不见的菜
	_sync_recipes()
	# 重新打开时先校正一次：上次开着「只看可做」选中的菜，这回未必还做得了
	_filters_dirty = true
	# 订单卡「去做」带来的指定菜（显式参数）优先；没有就回到玩家上次停留的菜。
	# 指定菜即便当下缺料、缺设备也要看得见，所以把它所在的组展开、关掉「只看可做」
	# （第七轮反馈 24）；记忆里的菜不强行改筛选，跟着当前筛选模式走（第八轮反馈 3）
	var explicit_recipe := String(data.get("recipe", ""))
	var wanted := explicit_recipe if not explicit_recipe.is_empty() else SettingsStore.get_craft_recipe()
	var wanted_def := def_of(wanted) as RecipeDef
	if wanted_def != null:
		_selected = wanted
		if not explicit_recipe.is_empty():
			_filter_mode = Filter.ALL
		_folded[_group_of(wanted_def)] = false
	_seed_fold_defaults()
	_structure_signature = ""
	super._on_open(data)
	_ensure_selection_visible()


func refresh() -> void:
	var signature := _structure_signature_now()
	if signature == _structure_signature:
		_update_job_rows()
		return
	_structure_signature = signature
	_rebuild()


## 切语言要整块重建，否则标题与提示仍是旧的；结构签名清掉即可
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	_structure_signature = ""
	refresh()


func _on_tick() -> void:
	_update_job_rows()
	if _pending_scroll >= 0 and is_instance_valid(_list_scroll):
		_list_scroll.scroll_vertical = _pending_scroll
		_pending_scroll = -1


func _rebuild() -> void:
	_bar = null
	_sync_recipes()
	if _filters_dirty:
		# 只有筛选刚变过才校正选中项：玩家自己点了一道当下做不了的菜，
		# 详情该留着（按钮自己会灰），不该在下一帧把他跳走
		_filters_dirty = false
		_ensure_selection_visible()
	set_title(I18n.t("ui.craft.title"))
	set_subtitle(I18n.t("ui.craft.subtitle"))
	_build_toolbar()
	_rebuild_content()


## 只重排内容、不动工具条：搜索框里的光标和已输入的词都属于玩家，
## 每敲一个字就重建工具条会把焦点踢走（第七轮反馈 12，抄商人/仓库面板的写法）。
func _rebuild_content() -> void:
	clear_content()
	_cards.clear()
	# 进行中的东西固定在页脚：它不该跟着详情一起滚出屏幕
	PanelKit.clear(footer)
	_build_job_footer()
	_group_boxes.clear()
	_group_members.clear()
	_group_filled.clear()
	if _recipes.is_empty():
		content.add_child(PanelKit.hint(I18n.t("ui.craft.empty")))
		return
	# 左列自己滚、右列不画滚动条：这样整张面板只有一根滚动条，
	# 而且它只属于「配方列表」，详情不会跟着一起动。
	# 记住左列滚到哪儿了：换一道菜不该把列表甩回顶部
	var keep_scroll := _pending_scroll
	if keep_scroll < 0 and is_instance_valid(_list_scroll):
		keep_scroll = _list_scroll.scroll_vertical

	var row := PanelKit.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var list_scroll := ScrollContainer.new()
	# 左列固定拿 1.5 份、右列 1.0 份：810 可用宽下 ≈474 / 316，左列 ≥ 面板一半（规范①）
	list_scroll.custom_minimum_size = Vector2(0, 320)
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 1.5
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	row.add_child(list_scroll)
	_list_scroll = list_scroll
	if keep_scroll > 0:
		_pending_scroll = keep_scroll

	var list := PanelKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	# 39 道菜平铺太长：按组折起来，选中那道所在的组永远保持展开，
	# 否则程序性换选中（研究解锁、首次进入）会把当前这道菜藏起来
	var selected_recipe := def_of(_selected) as RecipeDef
	var selected_group := _group_of(selected_recipe) if selected_recipe != null else ""
	var any_listed := false
	var listed_total := 0
	for group in GROUPS:
		var group_id := String(group["id"])
		var members := _members_of(group_id)
		if members.is_empty():
			continue
		any_listed = true
		listed_total += members.size()
		var folded := bool(_folded.get(group_id, false)) and group_id != selected_group
		var section := PanelKit.fold_section(_group_title(group_id, members.size()), folded)
		section.folding_changed.connect(_on_group_folding_changed.bind(group_id))
		# 每行永远三列：HFlowContainer 会随宽度一会 2 一会 3（Q2 已否决）
		var inner := GridContainer.new()
		inner.columns = 3
		inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_theme_constant_override("h_separation", 10)
		inner.add_theme_constant_override("v_separation", 10)
		section.add_child(inner)
		# 收起的组不建按钮：等玩家展开时由 _on_group_folding_changed 补
		_group_boxes[group_id] = inner
		_group_members[group_id] = members
		_group_filled[group_id] = false
		if not folded:
			_fill_group(group_id)
		list.add_child(section)
	if not any_listed:
		# 筛太窄和「真的没得做」是两回事：说错一句，玩家会以为材料全没了
		var narrowed := _filter_mode != Filter.ALL \
				or not _theme_key.is_empty() or not _tag_key.is_empty() \
				or not _keyword.strip_edges().is_empty()
		# 筛空 → 统一文案；本来就没有可做的 → 灶台自己的那句（2026-10-28 统一检索 §5）。
		list.add_child(PanelKit.hint(I18n.t("ui.filter.empty" if narrowed else "ui.craft.nothing_craftable"), 240.0))
	# 结果计数只放工具条末尾（统一检索 §4：座位固定为 搜索→状态→分类→分组→排序→计数）
	if _bar != null:
		_bar.set_result_text("" if listed_total <= 0 else I18n.t("ui.filter.result_count", [listed_total]))

	# 右侧详情：可以滚，但不画滚动条（面板里只留左列那一条）
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(300, 320)
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_stretch_ratio = 1.0
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	row.add_child(detail_scroll)

	var detail := PanelKit.vbox(8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail)
	_build_detail(detail)


## 工具条：搜索 + 三档筛选 + 主题/标签浮层。固定不滚——想换筛选的人不该先滚回顶部。
## 复用书架那条 `FilterBar`：同一套「检索可以分级」的约定，省得两处各写一套。
func _build_toolbar() -> void:
	PanelKit.clear(toolbar)
	_bar = FilterBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_bar)
	_bar.add_search("ui.craft.search_placeholder", 170.0, _keyword)
	_bar.add_segments("filter", [
		{"value": Filter.ALL, "key": "ui.craft.filter_all"},
		{"value": Filter.CRAFTABLE, "key": "ui.craft.filter_craftable"},
		{"value": Filter.UNRECORDED, "key": "ui.craft.filter_uncrafted"},
	], _filter_mode)
	_bar.add_menu_group("theme", "ui.craft.filter_theme", _theme_options(), _theme_key)
	_bar.add_menu_group("tag", "ui.craft.filter_tag", _tag_options(), _tag_key)
	_bar.changed.connect(_on_filters_changed)
	_bar.set_result_text("")


## 主题浮层：只列已经到站的地方（和书架一致）——没到过的地方出现在筛选里本身就是剧透
func _theme_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.craft.theme_all")}]
	var themes: Array[ThemeDef] = []
	for def in defs_of("theme"):
		if def is ThemeDef and GameState.is_theme_unlocked(def.get_key()):
			themes.append(def as ThemeDef)
	themes.sort_custom(func(a: ThemeDef, b: ThemeDef) -> bool: return a.order < b.order)
	for theme_def in themes:
		options.append({"value": theme_def.get_key(), "label": theme_def.localized()})
	return options


## 标签浮层：只列图鉴那一类（scope=food），按 order 排。
## 食材标签（「任意蔬菜」）是配方输入用的维度，摆进筛菜条会让玩家以为菜也挂它。
func _tag_options() -> Array:
	var options: Array = [{"value": "", "label": I18n.t("ui.craft.tag_all")}]
	var tags: Array[TagDef] = []
	for def in defs_of("tag"):
		if def is TagDef and not (def as TagDef).is_ingredient():
			tags.append(def as TagDef)
	tags.sort_custom(func(a: TagDef, b: TagDef) -> bool: return a.order < b.order)
	for tag_def in tags:
		options.append({"value": tag_def.get_key(), "label": tag_def.localized()})
	return options


func _on_filters_changed() -> void:
	if _bar != null:
		_keyword = _bar.get_keyword()
		_theme_key = _bar.get_menu_value("theme")
		_tag_key = _bar.get_menu_value("tag")
		# 三档共用一个段选：未记录必然可做，不再让两个独立开关互相打架
		_filter_mode = _bar.get_segment("filter")
	# 筛选模式跟着存档走：下次打开还是这个视图（第八轮反馈 3）
	SettingsStore.set_craft_filter(_filter_mode)
	_sync_recipes()
	_ensure_selection_visible()
	_filters_dirty = false
	# 指纹里不再有搜索词/主题（它们只影响列表内容），所以这里算出来的
	# 就是当前结构，之后的 refresh 不会因为输入而整块重建
	_structure_signature = _structure_signature_now()
	_rebuild_content()


## 结构指纹：只包含会改变控件排布与可用性的信息
func _structure_signature_now() -> String:
	var recipe := def_of(_selected) as RecipeDef
	var parts: Array[String] = [_selected]
	# 研究解锁新配方后，左边的列表会多一项，必须重建
	parts.append("v=%d" % GameState.get_visible_recipes().size())
	if recipe != null:
		var ready := (
			GameState.can_consume(recipe.inputs, _batch)
			and GameState.has_free_slot(recipe.facility)
			and GameState.has_free_lane()
		)
		parts.append("c=%s" % ready)
		parts.append("r=%s" % [GameState.get_repeat_recipe() == recipe.get_key()])
		parts.append("b=%d" % _batch)
	parts.append("l=%d" % GameState.get_lane_count())
	# 只要不是「全部」，材料涨落就可能改变这一屏的成员，必须跟着重建
	parts.append("m=%d" % _filter_mode)
	if _filter_mode != Filter.ALL:
		parts.append("ok=%d" % _craftable_keys().hash())
	if _filter_mode == Filter.UNRECORDED:
		# 做出新菜会让「未记录」少一条；发现后必须重建卡片上的「新」标记
		parts.append("uc=%d" % _uncrafted_count())
	# 设备到手（0 级 → 1 级）会把左列的「还没到手」标记清掉，列表必须重排
	parts.append("f=%d" % _locked_facility_count())
	# 接了/办妥了委托，目标卡的「委托」标记要跟着出现或消失
	var guided: Array = _guided_recipe_keys.keys()
	guided.sort()
	parts.append("g=%s" % "+".join(guided))
	for job in GameState.get_jobs():
		parts.append(job.recipe_key)
	return "|".join(parts)


## 现在能做出来的配方键。只看可做开着时才用，拿它的哈希进结构指纹。
func _craftable_keys() -> Array[String]:
	var keys: Array[String] = []
	for recipe in _recipes:
		if _is_craftable_now(recipe):
			keys.append(recipe.get_key())
	return keys


## 当前可见配方里，成品还没进图鉴的条数。发现新菜后要重建卡片标记。
func _uncrafted_count() -> int:
	var count := 0
	for recipe in _recipes:
		var output := def_of(recipe.output) as ItemDef
		if output != null and not GameState.is_discovered(output.get_key()):
			count += 1
	return count


## 现在点下去能成功吗：材料够 + 设备已经到手。
## 手作配方的 `facility` 是空键，`is_facility_ready` 对它恒真。
func _is_craftable_now(recipe: RecipeDef) -> bool:
	return GameState.can_consume(recipe.inputs, 1) and GameState.is_facility_ready(recipe.facility)


## 这道菜要的设备还没到手（0 级）时返回它，否则 null。
## 「显示全部」里这些菜留着可查，但不该被点——和详情里的「X 还没到手」同一口径（决策 2026-10-28 D12）。
func _missing_facility(recipe: RecipeDef) -> FacilityDef:
	if not recipe.needs_facility() or GameState.is_facility_ready(recipe.facility):
		return null
	return def_of(recipe.facility) as FacilityDef


## 左列里被「设备还没到手」挡住的菜数：读数变了才需要重建列表
func _locked_facility_count() -> int:
	var count := 0
	for recipe in _recipes:
		if _missing_facility(recipe) != null:
			count += 1
	return count


## 一道菜过不过当前的筛选：可做 / 主题 / 标签 / 关键词，全都过才算。
func _passes_filters(recipe: RecipeDef) -> bool:
	if _filter_mode != Filter.ALL and not _is_craftable_now(recipe):
		return false
	if _filter_mode == Filter.UNRECORDED:
		var output := def_of(recipe.output) as ItemDef
		if output == null or GameState.is_discovered(output.get_key()):
			return false
	if not _theme_key.is_empty() and GameState.recipe_theme_key(recipe.get_key()) != _theme_key:
		return false
	if not _tag_key.is_empty() and not GameState.has_tag(recipe.output, _tag_key):
		return false
	var needle := _keyword.strip_edges().to_lower()
	if needle.is_empty():
		return true
	# 匹配字段固定「成品名 + 描述」，不搜内部键（统一检索 §5）
	return _output_name(recipe).to_lower().contains(needle) \
			or recipe.localized(&"description").to_lower().contains(needle)


func _update_job_rows() -> void:
	for key in _cards.keys():
		var card := _cards[key] as RecipeCard
		if card == null or not is_instance_valid(card):
			continue
		var recipe_key := String(key)
		var output := _recipe_output(recipe_key)
		if not output.is_empty():
			card.set_have(GameState.get_amount(output))
		card.set_craftable(_is_recipe_craftable(recipe_key))
		card.set_jobs(_jobs_for_recipe(recipe_key))


## 这道菜当下的材料/设备状态：卡片的灰化只跟它走（空位与产线是两个按钮的事）
func _is_recipe_craftable(recipe_key: String) -> bool:
	var recipe := def_of(recipe_key) as RecipeDef
	return recipe != null and _is_craftable_now(recipe)


func _recipe_output(recipe_key: String) -> String:
	var recipe := def_of(recipe_key) as RecipeDef
	return recipe.output if recipe != null else ""


## 玩家看到的名字一律是成品名（「美式」），不是配方名（「萃取美式」）。
## 配方名只在右列当一行副标题，说明这道菜是怎么做的。
func _output_name(recipe: RecipeDef) -> String:
	if recipe == null:
		return ""
	var output := def_of(recipe.output) as ItemDef
	return output.localized() if output != null else recipe.localized()


## 主产物 + 副产物的「每批产出」一行文案（不含「产出：」前缀）。
func _outputs_text(recipe: RecipeDef) -> String:
	var parts: Array[String] = []
	for row in recipe.output_stacks():
		var key := String(row.get("material", ""))
		var amount := int(row.get("amount", 0))
		if key.is_empty() or amount <= 0:
			continue
		var target := def_of(key) as ItemDef
		var name := target.localized() if target != null else key
		parts.append("%s ×%d" % [name, amount])
	return " · ".join(parts)


func _jobs_for_recipe(recipe_key: String) -> Array[CraftJob]:
	var out: Array[CraftJob] = []
	for job in GameState.get_jobs():
		if job.recipe_key == recipe_key:
			out.append(job)
	return out


## 左边只列「已经知道」的配方（中间材料与教学线 + 研究解出来的）
func _sync_recipes() -> void:
	_guided_recipe_keys.clear()
	for key in GameState.get_active_task_recipe_keys():
		_guided_recipe_keys[key] = true
	_recipes = GameState.get_visible_recipes()
	if _recipes.is_empty():
		_selected = ""
		return
	for recipe in _recipes:
		if recipe.get_key() == _selected:
			return
	# 当前选中不在这一批里：落到第一道「筛完还看得见」的，而不是列表第一条。
	# 列表第一条很可能正被「可做」筛掉——那样左列空着、右列却讲着一道看不见的菜。
	# 玩家自己点开的那道不会走到这里：它仍在 _recipes 里，上面那层循环就返回了。
	_selected = ""
	_ensure_selection_visible()


## 筛完之后当前选中的那道可能已经不在左列里：换成第一道看得见的，
## 否则右边详情一直在讲一道左列根本找不到的菜。
func _ensure_selection_visible() -> void:
	for recipe in _recipes:
		if recipe.get_key() == _selected and _passes_filters(recipe):
			return
	for recipe in _recipes:
		if _passes_filters(recipe):
			_selected = recipe.get_key()
			_batch = 1
			return


## 分组 id：认不出就归饮品（饮品是最大的一组，归错也不至于藏起来）
func _group_of(recipe: RecipeDef) -> String:
	for group in GROUPS:
		if String(group["id"]) == recipe.group:
			return recipe.group
	return "drink"


## 一个组里该显示的配方。只看可做开着时，只留材料够的。
func _members_of(group_id: String) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for def in _recipes:
		var recipe := def as RecipeDef
		if recipe == null or _group_of(recipe) != group_id:
			continue
		if not _passes_filters(recipe):
			continue
		out.append(recipe)
	return out


## 标题带条数：收起时也能知道这一节里还有几道
func _group_title(group_id: String, count: int) -> String:
	for group in GROUPS:
		if String(group["id"]) == group_id:
			return I18n.t("ui.craft.group_title", [I18n.t(String(group["key"])), count])
	return group_id


## 展开某个组时才把卡片建出来；已经建过的不重复建
func _fill_group(group_id: String) -> void:
	if bool(_group_filled.get(group_id, false)):
		return
	var box := _group_boxes.get(group_id) as GridContainer
	if box == null or not is_instance_valid(box):
		return
	_group_filled[group_id] = true
	var members: Array[RecipeDef] = []
	members.assign(_group_members.get(group_id, []))
	for recipe in members:
		var key := recipe.get_key()
		var card := RecipeCard.new()
		box.add_child(card)
		var missing := _missing_facility(recipe)
		var output := def_of(recipe.output) as ItemDef
		card.setup(recipe, output, key == _selected, _is_craftable_now(recipe),
			missing.localized() if missing != null else "")
		card.set_have(GameState.get_amount(recipe.output))
		card.set_jobs(_jobs_for_recipe(key))
		card.set_guided(_guided_recipe_keys.has(key))
		card.set_uncrafted(output != null and not GameState.is_discovered(output.get_key()))
		card.activated.connect(_select_recipe)
		_cards[key] = card


## 第一次打开时把除「选中菜所在组」以外的组都收起来。
## 只做一次：之后玩家自己折过哪一组，重建时都照原样还回去。
func _seed_fold_defaults() -> void:
	if _fold_defaults_done:
		return
	_fold_defaults_done = true
	var selected_recipe := def_of(_selected) as RecipeDef
	var selected_group := _group_of(selected_recipe) if selected_recipe != null else ""
	for group in GROUPS:
		var group_id := String(group["id"])
		_folded[group_id] = group_id != selected_group


func _on_group_folding_changed(is_folded: bool, group_id: String) -> void:
	_folded[group_id] = is_folded
	if not is_folded:
		_fill_group(group_id)


## 选中一道菜：卡片的点击/回车都走这里，统一出按键声并重建右列。
func _select_recipe(recipe_key: String) -> void:
	Sfx.play(Sfx.Intent.TAB)
	_selected = recipe_key
	SettingsStore.set_craft_recipe(recipe_key)
	_batch = 1
	_structure_signature = ""
	refresh()


func _build_detail(detail: VBoxContainer) -> void:
	var recipe := def_of(_selected) as RecipeDef
	if recipe == null:
		# 「左边选一样做做看」只有在左列真有东西时成立；「可做」段空着的时候
		# 这句话等于让人去点一片空白，得换成「先弄点材料回来」
		var narrowed := not _theme_key.is_empty() or not _keyword.strip_edges().is_empty()
		var key := "ui.craft.pick_craftable" if _filter_mode != Filter.ALL and not narrowed else "ui.craft.pick"
		detail.add_child(PanelKit.hint(I18n.t(key)))
		return
	detail.add_child(PanelKit.label(_output_name(recipe), 22))
	# 成品名与配方名不同时，配方名退到副标题（例如「美式」下面写「萃取美式」）。
	if recipe.localized() != _output_name(recipe):
		detail.add_child(PanelKit.hint(recipe.localized(), 300))
	if not recipe.localized(&"description").is_empty():
		# 430 会把右列最小宽撑到 430、把整张 880 的面板挤到 1010（2026-10-30 截图实测）；
		# 右列目标 316，描述按 300 换行足够。
		detail.add_child(PanelKit.hint(recipe.localized(&"description"), 300))
	detail.add_child(PanelKit.divider())
	detail.add_child(PanelKit.label(I18n.t("ui.craft.needs"), 18, PanelKit.INK_SOFT))
	for stack in recipe.inputs:
		detail.add_child(_ingredient_row(stack))
	# 主产物 >1 或有副产物时才多一行，普通 1:1 配方保持原来的信息密度
	if recipe.output_amount > 1 or not recipe.extra_outputs.is_empty():
		detail.add_child(PanelKit.hint(I18n.t("ui.craft.output_line", [_outputs_text(recipe)]), 300))

	var limit := GameState.max_batches(recipe.get_key())
	_batch = clampi(_batch, 1, maxi(1, limit))
	if limit > 1:
		detail.add_child(_batch_row(recipe, limit))

	detail.add_child(PanelKit.label(_facility_line(recipe), 17, PanelKit.INK_SOFT))
	var output := def_of(recipe.output) as ItemDef
	if output != null and output.is_food():
		# 同描述行：430 的最小宽会把右列和整张面板一起撑宽
		detail.add_child(PanelKit.hint(I18n.t("ui.craft.food_meta",
			[str(output.order_weight), PanelKit.coins_text(output.sell_price)]), 300))
	var used_in := _used_in_section(recipe)
	if used_in != null:
		detail.add_child(used_in)
	var can_craft := (
		GameState.can_consume(recipe.inputs, _batch)
		and GameState.has_free_slot(recipe.facility)
		and GameState.has_free_lane()
		and GameState.is_facility_ready(recipe.facility)
	)
	# 成功是「开始做了」的确认音、失败是拒绝音，都不再叠默认按键声
	var label := I18n.t("ui.craft.craft_button")
	if _batch > 1:
		label = I18n.t("ui.craft.craft_button_batch", [_batch])
	# 主操作样式统一在 PanelKit：禁用时保留实底形状，不会在灰掉之后让旁边的次级按钮显得更重
	var craft_button := PanelKit.primary_button(label, Sfx.Intent.NONE, 50.0)
	craft_button.add_theme_font_size_override("font_size", 21)
	PanelKit.set_disabled(craft_button, not can_craft)
	craft_button.pressed.connect(func() -> void: _craft(recipe))
	# 「连续做」和主按钮同一行：它本来就是「再做一份」的补充条件，
	# 单独占一行会把详情区顶出可视范围（720p 下正好卡在边界上）。
	craft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var action := PanelKit.hbox(10)
	action.add_child(craft_button)
	action.add_child(_repeat_check(recipe))
	detail.add_child(action)


## 「它可以做…」：这道菜的成品还能被哪些配方当输入（反查走 GameState 的同一份索引）。
## 折叠段本身与图鉴共用 GamePanel.used_in_section（第十轮反馈 5），这里只接两个回调：
## 已解锁的切到那条配方，要研究的去图鉴看线索（第八轮反馈 2）。
func _used_in_section(recipe: RecipeDef) -> Control:
	return used_in_section(recipe.output, _select_recipe, _open_catalog_recipe)


## 从灶台跳到图鉴的配方条目：定位复用图鉴的 _locate_key（第八轮反馈 2）。
func _open_catalog_recipe(recipe_key: String) -> void:
	var catalog_id := ResourceLocation.from_string(UIKeys.CATALOG)
	if catalog_id == null:
		return
	UIManager.open_panel(catalog_id, {"key": recipe_key})


## 批处理步进器：中间品才能一次多份，份数上限只看设备等级（Lv1 → 2 … Lv4 → 5）。
## 用 −/+ 而不是长按加倍，是为了让「为什么加不上去」直接写在旁边。
func _batch_row(recipe: RecipeDef, limit: int) -> VBoxContainer:
	var box := PanelKit.vbox(4)
	var row := PanelKit.hbox(10)
	row.add_child(PanelKit.label(I18n.t("ui.craft.batches", [_batch, limit]), 17, PanelKit.INK_SOFT))

	# 用字面的 −/+ 而不是图标：缩放图标在 34px 上读起来像放大镜
	var minus := PanelKit.button("−", Sfx.Intent.CLICK)
	minus.custom_minimum_size = Vector2(38.0, 34.0)
	PanelKit.set_disabled(minus, _batch <= 1)
	minus.pressed.connect(func() -> void:
		_batch = maxi(1, _batch - 1)
		_structure_signature = ""
		refresh()
	)
	var plus := PanelKit.button("+", Sfx.Intent.CLICK)
	plus.custom_minimum_size = Vector2(38.0, 34.0)
	PanelKit.set_disabled(plus, _batch >= limit)
	plus.pressed.connect(func() -> void:
		_batch = mini(limit, _batch + 1)
		_structure_signature = ""
		refresh()
	)
	row.add_child(minus)
	row.add_child(plus)
	box.add_child(row)
	return box


## 「连续做」：勾上之后，这道菜每做完一份就自动再开一份，直到材料不够或没空位。
## 状态存在 GameState 里（不是这个面板），所以关掉面板也继续生效。
func _repeat_check(recipe: RecipeDef) -> CheckButton:
	var repeat := CheckButton.new()
	repeat.text = I18n.t("ui.craft.repeat")
	repeat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	repeat.button_pressed = GameState.get_repeat_recipe() == recipe.get_key()
	repeat.toggled.connect(func(on: bool) -> void:
		var key := recipe.get_key()
		GameState.set_repeat_recipe(key if on else "")
		_structure_signature = ""
		show_message(I18n.t("ui.craft.repeat_on", [_output_name(recipe)]) if on else I18n.t("ui.craft.repeat_off"), PanelKit.INK_SOFT)
		refresh()
	)
	return repeat


## 一味材料：左边一枚色章，右边「名字 + 需要的量」，最右是手上还有多少。
## 不够的那一行整条变红——比在句子里塞一句「手上有 0」更快被看见。
## 中间品不够时补一行「先做一份 X」：它买不到，也不在采集点里。
func _ingredient_row(stack: MaterialStack) -> VBoxContainer:
	var box := PanelKit.vbox(3)
	var row := PanelKit.hbox(10)
	box.add_child(row)
	# 按标签要料时没有具体物品键，不能拿空键去查定义（会打一条「找不到」的错）
	var target: GameDef = null if stack.material.is_empty() else def_of(stack.material)
	var name := stack_name(stack)
	var free := target is ItemDef and (target as ItemDef).is_free()
	var enough := true
	var have := 0
	if not free:
		# 按标签要料时「手上有多少」是标签成员的合计，够不够由 count_for 统一算
		have = GameState.count_for(stack)
		enough = have >= stack.amount

	# 材料也走 ItemIcons 的五族图标，并和菜品卡共用 ItemBadge 的「底 + 图」组合章：
	# 以前这里是裸图标压在色块上，24~30px 时和卡片上的章不是一套语言。
	# 缺料时整枚章换红，比在句子里塞「手上有 0」更快被看见。
	# 按标签要料时用标签对应的族；真的认不出来（无效引用）才回落到首字。
	var icon_path := ""
	if not stack.by_tag.is_empty():
		icon_path = ItemIcons.tag_path(stack.by_tag)
	else:
		icon_path = ItemIcons.path_for(target as ItemDef)
	var badge := ItemBadge.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var accent := ItemIcons.accent_for(icon_path) if enough else PanelKit.DANGER_DEEP
	badge.configure(icon_path, name, accent, 30.0)
	row.add_child(badge)
	if not stack.by_tag.is_empty():
		# 入树后再接点击：ItemBadge._ready 默认把 mouse_filter 设为 IGNORE，
		# 先设会被覆盖，标签成员清单就点不开了。
		_make_tag_seal(badge, stack.by_tag)

	row.add_child(PanelKit.label(name, 17, PanelKit.INK if enough else PanelKit.DANGER_DEEP))
	row.add_child(PanelKit.spacer())
	var amount_text := "× %d" % stack.amount
	if not free:
		amount_text += I18n.t("ui.craft.ingredient_have", [PanelKit.big_number_text(have)])
	else:
		amount_text += I18n.t("ui.craft.ingredient_free")
	row.add_child(PanelKit.label(amount_text, 16, PanelKit.INK_SOFT if enough else PanelKit.DANGER_DEEP))
	if (not free) and (not enough) and target is ItemDef:
		if (target as ItemDef).material_kind == ItemDef.MaterialKind.INTERMEDIATE:
			var tip := PanelKit.hint(I18n.t("ui.craft.need_first", [name]), 300)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.add_theme_font_size_override("font_size", 14)
			box.add_child(tip)
	return box


## 「随便一种蔬菜」这类按标签要料的色章：点开能看见标签下到底有哪些东西（反馈 22）。
## 指名材料的行不弹——它自己就是答案，没有第二层可解释的。
func _make_tag_seal(seal: Control, tag_key: String) -> void:
	# ItemBadge 入树时会把 mouse_filter 重置成 IGNORE（普通卡片要让点击穿透），
	# 标签章必须同时把它的 _interactive 置位，否则这一枚还是点不开。
	if seal.has_method("set_interactive"):
		seal.call("set_interactive", true)
	seal.mouse_filter = Control.MOUSE_FILTER_STOP
	seal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	seal.gui_input.connect(_on_tag_seal_input.bind(tag_key))


func _on_tag_seal_input(event: InputEvent, tag_key: String) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			show_tag_members(tag_key)
			accept_event()


func _facility_line(recipe: RecipeDef) -> String:
	var facility_text := I18n.t("ui.craft.handmade")
	if recipe.needs_facility():
		var facility := def_of(recipe.facility) as FacilityDef
		if facility != null:
			var level := GameState.get_facility_level(recipe.facility)
			if level < 1:
				# 0 级 = 还没到手（等信件添置的设备）
				facility_text = I18n.t("ui.craft.facility_locked", [facility.localized()])
			else:
				facility_text = I18n.t("ui.craft.facility_level", [facility.localized(), level])
		else:
			facility_text = recipe.facility
	var seconds := recipe.duration_seconds * GameState.get_speed_factor(recipe.facility)
	# 一次做多份时，这里报的是整批时间（含 0.65 的批量折扣）
	if _batch > 1:
		seconds *= float(_batch) * GameState.BATCH_TIME_FACTOR
	return I18n.t("ui.craft.facility_line", [facility_text, PanelKit.duration_text(seconds)])


## 页脚只留总览：具体进度已经在左列卡片上了，这里不再画第二套进度条（规范②）。
## 空闲时也留着这一块，灶台有没有活，页脚都该在同一个位置。
func _build_job_footer() -> void:
	var jobs := GameState.get_jobs()
	footer.add_child(PanelKit.divider())
	var head := PanelKit.hbox(10)
	head.add_child(PanelKit.label(I18n.t("ui.craft.in_progress"), 18, PanelKit.INK_SOFT))
	head.add_child(PanelKit.spacer())
	if jobs.is_empty():
		head.add_child(PanelKit.hint_inline(I18n.t("ui.craft.lanes_idle", [GameState.get_lane_count()])))
	else:
		head.add_child(PanelKit.hint_inline(
			I18n.t("ui.craft.lanes_in_use", [jobs.size(), GameState.get_lane_count()])))
	footer.add_child(head)


func _craft(recipe: RecipeDef) -> void:
	if GameState.start_craft(recipe.get_key(), _batch):
		Sfx.play(Sfx.Intent.CONFIRM)
		show_message(I18n.t("ui.craft.started", [_output_name(recipe)]), PanelKit.INK_SOFT)
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.craft.cant_craft"), PanelKit.DANGER_DEEP)
	_structure_signature = ""
	refresh()
