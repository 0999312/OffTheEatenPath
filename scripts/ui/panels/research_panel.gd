class_name ResearchPanel
extends GamePanel
## 研究台：从候选材料里挑 2–4 样丢进槽位，试着凑出还没解锁的做法。
##
## 交互形状是「槽位」而不是「勾选框」：候选是一排可以点的材料牌，点一下进槽位，
## 点槽位再取出来。勾选框看起来像设置项，说不清「这东西被放进去了」；
## 槽位一眼就能看出「我丢了哪几样、还差几样」。
##
## 刷新策略与灶台一致：结构与进度分开。挑选状态存在 `_picked` 里（不放进控件），
## 只有「挑选变了 / 候选变了 / 任务数变了」才重建，否则只改剩余秒数 ——
## 否则重建会把玩家刚放进去的东西清掉。

## 一次研究放几样（决策：2–4 样）。上限放宽到 4 是为了让四样输入的菜也能进研究台；
## 水、清汤这类免费材料算一样，但不用扣库存。
const MIN_PICKS := 2
const MAX_PICKS := 4
## 槽位方块的边长
const SLOT_SIZE := Vector2(96.0, 96.0)
## 三段页签：候选材料 / 台面（挑选 + 进行中）/ 记录
const TAB_CANDIDATES := 0
const TAB_DESK := 1
const TAB_RECORDS := 2

## 已经放进槽位的材料键，按放入顺序
var _picked: Array[String] = []
## 上次重建时的结构指纹
var _structure_signature: String = ""
## 进行中任务的文字标签 ↔ 任务对象
var _job_rows: Array[Dictionary] = []
## 当前页签；默认停在台面——真正要动手的地方
var _tab_index := TAB_DESK
## 是否已经决定过首屏页签（只在第一次建页签时决定）
var _tab_chosen := false
## 候选页是否铺全集；默认只看手上有货的
var _show_all_candidates := false
## 首启三步引导是否还开着（点「知道了」就收起来，并写进存档）
var _guide_open := false
## 候选页筛选：搜索词与材料族（空 = 全部）
var _candidate_query := ""
var _candidate_family := ""
var _candidate_filter: FilterBar = null


func _on_init() -> void:
	# 「还剩几秒」随时间变，但结构不用重建——交给基类的轻 Timer 只改文字
	tick_interval = 0.25


func _on_open(data: Dictionary = {}) -> void:
	_structure_signature = ""
	super._on_open(data)
	# 第一次打开研究台：把三步说明贴出来（D10）。存档记「看过」，之后不再自动弹。
	if not GameState.has_seen_research_guide():
		_guide_open = true
		_structure_signature = ""
		refresh()



func refresh() -> void:
	_prune_picks()
	var signature := _structure_signature_now()
	if signature == _structure_signature:
		_update_job_rows()
		return
	_structure_signature = signature
	_rebuild()


## 切语言：外框与提示都要重译，清掉结构签名强制重建
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	_structure_signature = ""
	refresh()


func _on_tick() -> void:
	_update_job_rows()


## 候选池会随着解锁变窄（解锁后那条配方的池子就不该再出现在这里）
func _prune_picks() -> void:
	var candidates := GameState.get_research_candidates()
	var kept: Array[String] = []
	for key in _picked:
		if candidates.has(key):
			kept.append(key)
	_picked = kept


func _structure_signature_now() -> String:
	var parts: Array[String] = []
	parts.append("n=%d" % GameState.get_research_candidates().size())
	parts.append("p=%s" % "+".join(_picked))
	parts.append("l=%d" % GameState.get_research_desk_level())
	parts.append("a=%s" % str(_show_all_candidates))
	for job in GameState.get_research_jobs():
		parts.append(job.signature)
	return "|".join(parts)


## 结构变了才重建：页签钉在工具条上，滚动区只画当前这一页
func _rebuild() -> void:
	clear_content()
	PanelKit.clear(toolbar)
	PanelKit.clear(footer)
	set_title(I18n.t("ui.research.title"))
	set_subtitle(I18n.t("ui.research.subtitle"))

	var candidates := GameState.get_research_candidates()
	# 首屏落在台面：候选再多，玩家进来也是要动手的；全研究完了才退到记录
	if not _tab_chosen:
		_tab_index = TAB_DESK if not candidates.is_empty() else TAB_RECORDS
		_tab_chosen = true

	var bar := PanelKit.tab_bar([
		I18n.t("ui.research.tab_candidates", [candidates.size()]),
		I18n.t("ui.research.tab_desk"),
		I18n.t("ui.research.tab_records", [GameState.get_research_record_count()]),
	])
	bar.current_tab = clampi(_tab_index, 0, bar.tab_count - 1)
	# 先设 current_tab 再接信号：重建时不会补发一次 tab_changed（切页音 + 白重画一遍）
	bar.tab_changed.connect(_on_tab_changed)
	# 设备状态挂在页签右边：三个页签都看得见，不占滚动区的高度
	var bar_row := PanelKit.hbox(12)
	bar_row.add_child(bar)
	bar_row.add_child(PanelKit.label(_desk_summary_text(), 15, PanelKit.INK_SOFT))
	toolbar.add_child(bar_row)
	# 常驻提示：还剩几个方向、下一步怎么动手（D10）。候选见底时换成鼓励句，
	# 不写「0 个方向」——那看着像坏了。
	if not candidates.is_empty():
		toolbar.add_child(_usage_hint(candidates.size()))
	_candidate_filter = _build_candidate_filter()
	toolbar.add_child(_candidate_filter)
	_fill_tab(_tab_index)


func _on_tab_changed(index: int) -> void:
	if index == _tab_index:
		return
	Sfx.play(Sfx.Intent.TAB)
	_fill_tab(index)
	flash_content()


func _build_candidate_filter() -> FilterBar:
	var bar := FilterBar.new()
	bar.add_search("ui.research.search_hint", 200.0, _candidate_query)
	bar.add_menu_group("family", "ui.research.family_filter", [
		{"value": "", "key": "ui.research.family_all"},
		{"value": "seafood", "key": "ui.research.family_seafood"},
		{"value": "meat", "key": "ui.research.family_meat"},
		{"value": "fruit", "key": "ui.research.family_fruit"},
		{"value": "veg", "key": "ui.research.family_veg"},
		{"value": "misc", "key": "ui.research.family_misc"},
	], _candidate_family)
	bar.changed.connect(_on_candidate_filter_changed)
	return bar


func _on_candidate_filter_changed() -> void:
	if _candidate_filter == null:
		return
	_candidate_query = _candidate_filter.get_keyword().strip_edges()
	_candidate_family = _candidate_filter.get_menu_value("family")
	_fill_tab(TAB_CANDIDATES)


## 只重画滚动区与页脚：页签、标题都在滚动区外，切页时不该动
func _fill_tab(index: int) -> void:
	_tab_index = clampi(index, 0, TAB_RECORDS)
	clear_content()
	PanelKit.clear(footer)
	_job_rows.clear()
	_scroll.scroll_vertical = 0
	if _candidate_filter != null:
		_candidate_filter.visible = _tab_index == TAB_CANDIDATES
	match _tab_index:
		TAB_CANDIDATES:
			_fill_candidates()
		TAB_RECORDS:
			_fill_records()
		_:
			_fill_desk()
	# 首启引导贴在每一页最上面：切到「候选」也还看得见下一步点哪，直到点掉「知道了」
	if _guide_open:
		var guide := _guide_card()
		content.add_child(guide)
		content.move_child(guide, 0)


## 候选页：默认只列手上有货的；「显示全部」才铺全集。
## 候选有十几样、每张牌都比名字长，横着一排必然出界——所以用自动换行容器。
func _fill_candidates() -> void:
	var candidates := GameState.get_research_candidates()
	# 少于两样就凑不成一次研究。只摆一样「水」会让人以为研究台只能放水——
	# 这里直接说清楚：现在没有可试的组合，先去把菜做出来或解锁新配方（R7.3 反馈 7）。
	if candidates.size() < MIN_PICKS:
		content.add_child(PanelKit.hint(I18n.t("ui.research.no_candidates"), 600))
		return
	var owned: Array[String] = []
	var has_stock := false
	for key in candidates:
		var def := def_of(key)
		if GameState.get_amount(key) > 0:
			owned.append(key)
			has_stock = true
		elif def is ItemDef and def.is_free():
			# 水这类免费资源库存恒为 0，但一直算「手上有」——不然它永远进不了候选页
			owned.append(key)
	# 手上能凑成一次研究的不到两样：别只摆一样水让人以为研究台只能放水。
	# 说清楚现在没组合可试，再给一个「看看全部线索」的入口。
	if has_stock and not _show_all_candidates and owned.size() < MIN_PICKS:
		content.add_child(PanelKit.hint(I18n.t("ui.research.no_candidates"), 600))
		var show_all := PanelKit.button(I18n.t("ui.research.show_all"), Sfx.Intent.CLICK)
		show_all.pressed.connect(func() -> void:
			_show_all_candidates = true
			_structure_signature = ""
			refresh()
		)
		content.add_child(show_all)
		return
	# 手上真的一样都没有时退回全集：只剩免费水也不该把候选页收成一行
	var shown := candidates if (_show_all_candidates or not has_stock) else owned
	shown = _filter_candidates(shown)
	if shown.is_empty():
		content.add_child(PanelKit.hint(I18n.t("ui.research.no_match"), 600))
		return
	content.add_child(_candidate_section(candidates.size(), owned.size(), shown))


func _filter_candidates(keys: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var needle := _candidate_query.to_lower()
	for key in keys:
		var def := def_of(key) as ItemDef
		if def == null:
			continue
		if not needle.is_empty() and not def.localized().to_lower().contains(needle):
			continue
		if not _candidate_family.is_empty():
			var family := ItemIcons.material_path(def).get_file().get_basename()
			if family != _candidate_family:
				continue
		out.append(key)
	return out


## 台面页：进行中的任务 → 三个槽位 → 设备摘要；「试一试」与升级都钉在页脚。
## 任务排在最上面，是因为「我这一组试得怎么样了」比「我手里有哪几样」更急。
func _fill_desk() -> void:
	content.add_child(_job_section())
	content.add_child(PanelKit.divider())
	content.add_child(_slot_section())
	# 凑不成一次研究就没什么可试的，按钮留着只会显得坏掉
	if GameState.get_research_candidates().size() >= MIN_PICKS:
		footer.add_child(_action_row())


func _fill_records() -> void:
	content.add_child(_record_section())



# --- 台面 -----------------------------------------------------------------


## 设备摘要一行：等级、同时能试几组、失败损耗。挂在页签右边，任何页签都看得见。
func _desk_summary_text() -> String:
	var level := GameState.get_research_desk_level()
	var parts: Array[String] = [
		"Lv.%d" % level,
		I18n.t("ui.research.desk_level", [maxi(1, level)]),
		I18n.t("ui.research.burn_rate", [GameState.get_research_burn_count()]),
	]
	# 分隔用中点而不是 line_sep：那句分隔符在英文里是空格，三句话会黏成一句
	return " · ".join(parts)


## 升级研究台的按钮：满级或查不到下一级时返回 null（调用方自己判空）。
func _desk_upgrade_button() -> Button:
	var level := GameState.get_research_desk_level()
	var facility := GameState.get_research_desk_facility()
	if facility == null or GameState.get_facility_level(facility.get_key()) >= facility.max_level:
		return null
	var upgrade := facility.get_upgrade(level + 1)
	if upgrade == null:
		return null
	var button := PanelKit.sticker(I18n.t("ui.research.upgrade_button", [PanelKit.coins_text(upgrade.coin_cost)]),
			"ui/progress_bar.svg", Sfx.Intent.NONE, 18.0)
	PanelKit.set_disabled(button, GameState.coins < upgrade.coin_cost or not GameState.can_consume(upgrade.materials))
	# 页脚宽度有限，那句「少损耗、同时多试一组」的说明挂在 tooltip 上
	PanelKit.tooltip(button, I18n.t("ui.research.upgrade_hint"))
	button.pressed.connect(func() -> void:
		if GameState.upgrade_facility(facility.get_key()):
			show_message(I18n.t("ui.research.upgraded", [upgrade.target_level]), PanelKit.INK_SOFT)
		else:
			show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
		_structure_signature = ""
		refresh()
	)
	return button


# --- 候选材料 --------------------------------------------------------------


func _candidate_section(total: int, owned_count: int, shown: Array[String]) -> VBoxContainer:
	var box := PanelKit.vbox(10)
	var head := PanelKit.hbox(10)
	head.add_child(PanelKit.label(I18n.t("ui.research.candidates"), 18, PanelKit.INK_SOFT))
	head.add_child(PanelKit.badge("%d / %d" % [owned_count, total]))
	head.add_child(PanelKit.spacer())
	var toggle := CheckButton.new()
	toggle.text = I18n.t("ui.research.only_owned")
	toggle.button_pressed = not _show_all_candidates
	toggle.toggled.connect(func(on: bool) -> void:
		_show_all_candidates = not on
		_structure_signature = ""
		refresh()
	)
	head.add_child(toggle)
	head.add_child(PanelKit.label(I18n.t("ui.research.pick_hint"), 15, PanelKit.INK_SOFT))
	box.add_child(head)

	# 自动换行：十几张牌横着排会一路顶到卡片外面去
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for key in shown:
		flow.add_child(_candidate_chip(key))
	box.add_child(flow)
	return box


## 一张候选材料牌：名字 + 库存。已经放进槽位的变灰（不能放两次）。
## 能顶「按标签要料」位置的材料，牌下面挂一枚标签章（反馈 8）：点开是成员列表，
## 玩家不用猜「任意蔬菜」到底包括什么，也不会以为非得是某一种菜。
func _candidate_chip(key: String) -> Control:
	var def := def_of(key)
	var name_text := def.localized() if def != null else key
	var taken := _picked.has(key)
	var amount_text := PanelKit.big_number_text(GameState.get_amount(key))
	if def is ItemDef and def.is_free():
		amount_text = I18n.t("ui.research.free_badge")
	var chip := Button.new()
	var item := def as ItemDef
	var icon_path := ItemIcons.path_for(item) if item != null else ""
	if not icon_path.is_empty():
		chip.icon = PanelKit.icon_texture(icon_path, 22.0)
		chip.add_theme_constant_override("icon_max_width", 22)
	chip.text = "%s  %s" % [name_text, amount_text]
	PanelKit.set_disabled(chip, taken)
	chip.add_theme_font_size_override("font_size", 17)
	var bg := PanelKit.tint_of(name_text).lerp(PanelKit.CARD_HI, 0.45)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := PanelKit.slab(bg if state != "disabled" else PanelKit.PAPER_BACK,
				PanelKit.INK if state != "disabled" else PanelKit.INK_DIM, 10, 2)
		style.content_margin_left = 14.0
		style.content_margin_top = 9.0
		style.content_margin_right = 14.0
		style.content_margin_bottom = 9.0
		if state == "pressed":
			style.border_width_bottom = 1
			style.border_width_top = 3
		chip.add_theme_stylebox_override(state, style)
	chip.pressed.connect(func() -> void:
		Sfx.play(Sfx.Intent.CLICK)
		_add_pick(key)
	)
	var tags := GameState.get_research_wildcard_tags(key)
	if tags.is_empty():
		return chip
	# 有标签的材料多一层「这枚能替代哪些位置」的说明，牌与章一起排进流式容器
	var column := PanelKit.vbox(4)
	column.add_child(chip)
	for tag_key in tags:
		column.add_child(_candidate_tag_seal(tag_key))
	return column


## 候选牌下的通配章：与灶台配料行同一套标签章，点开是成员列表（反馈 8 / 22）
func _candidate_tag_seal(tag_key: String) -> Control:
	var tag := def_of(tag_key) as TagDef
	var name_text := tag.localized() if tag != null and not tag.localized().is_empty() else tag_key
	var seal := PanelKit.badge(name_text, PanelKit.CARD_HI, PanelKit.INK_SOFT)
	seal.mouse_filter = Control.MOUSE_FILTER_STOP
	seal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	seal.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
				show_tag_members(tag_key)
				accept_event()
	)
	return seal


func _add_pick(key: String) -> void:
	if _picked.size() >= MAX_PICKS or _picked.has(key):
		return
	_picked.append(key)
	_structure_signature = ""
	refresh()


func _remove_pick(key: String) -> void:
	if not _picked.has(key):
		return
	_picked.erase(key)
	Sfx.play(Sfx.Intent.CLICK)
	_structure_signature = ""
	refresh()


# --- 槽位 -----------------------------------------------------------------


func _slot_section() -> VBoxContainer:
	var box := PanelKit.vbox(8)
	var head := PanelKit.hbox(10)
	head.add_child(PanelKit.label(I18n.t("ui.research.picked"), 18, PanelKit.INK_SOFT))
	head.add_child(PanelKit.badge("%d / %d" % [_picked.size(), MAX_PICKS]))
	box.add_child(head)

	var row := PanelKit.hbox(12)
	for index in MAX_PICKS:
		if index < _picked.size():
			row.add_child(_filled_slot(_picked[index]))
		else:
			row.add_child(_empty_slot())
	box.add_child(row)
	return box


func _filled_slot(key: String) -> PanelContainer:
	var def := def_of(key)
	var name_text := def.localized() if def != null else key
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PanelKit.tooltip(slot, I18n.t("ui.research.slot_tooltip"))
	var style := PanelKit.slab(PanelKit.tint_of(name_text), PanelKit.INK, 10, 2)
	style.content_margin_left = 6.0
	style.content_margin_top = 6.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 6.0
	slot.add_theme_stylebox_override("panel", style)

	var stack := PanelKit.vbox(2)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	var item := def as ItemDef
	var icon_path := ItemIcons.path_for(item) if item != null else ""
	var badge := ItemBadge.new()
	badge.configure(icon_path, name_text, ItemIcons.accent_for(icon_path), 34.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(badge)
	var name_label := PanelKit.label(name_text, 14, PanelKit.INK_SOFT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(name_label)
	slot.add_child(stack)

	slot.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_remove_pick(key)
	)
	return slot


func _empty_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	# 空槽的边用次墨：淡墨在纸面上只有 2.7:1，看不出来「这里能点」（第一轮第 1 条）
	var style := PanelKit.slab(Color(PanelKit.PAPER_BACK, 0.55), PanelKit.INK_SOFT, 10, 2)
	style.content_margin_left = 6.0
	style.content_margin_top = 6.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 6.0
	slot.add_theme_stylebox_override("panel", style)
	var glyph := PanelKit.label("+", 30, PanelKit.INK_SOFT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(glyph)
	return slot


# --- 动作 -----------------------------------------------------------------


## 页脚：左边「试一试」+ 一句为什么不能试，右边升级研究台（没有下一级就不放）。
func _action_row() -> HBoxContainer:
	var row := PanelKit.hbox(12)
	var box := PanelKit.vbox(6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var can_try := _picked.size() >= MIN_PICKS and _picked.size() <= MAX_PICKS \
		and GameState.has_free_research_slot() and _has_materials(_picked)
	var button := PanelKit.sticker(I18n.t("ui.research.try_button", [_picked.size()]), "", Sfx.Intent.NONE)
	PanelKit.set_disabled(button, not can_try)
	button.pressed.connect(func() -> void: _try(_picked.duplicate()))
	box.add_child(button)

	var lines: Array[String] = []
	if _picked.size() < MIN_PICKS:
		lines.append(I18n.t("ui.research.need_more", [MIN_PICKS - _picked.size()]))
	elif _picked.size() > MAX_PICKS:
		lines.append(I18n.t("ui.research.too_many", [MAX_PICKS]))
	elif not GameState.has_free_research_slot():
		lines.append(I18n.t("ui.research.desk_busy"))
	elif not _has_materials(_picked):
		lines.append(I18n.t("ui.research.no_materials"))
	else:
		lines.append(I18n.t("ui.research.cost_hint", [GameState.get_research_burn_count()]))
	box.add_child(PanelKit.hint(I18n.t("ui.research.line_sep").join(lines), 460))
	row.add_child(box)
	var upgrade := _desk_upgrade_button()
	if upgrade != null:
		upgrade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(upgrade)
	return row


func _job_section() -> VBoxContainer:
	var box := PanelKit.vbox(8)
	box.add_child(PanelKit.label(I18n.t("ui.research.in_progress"), 18, PanelKit.INK_SOFT))
	var jobs := GameState.get_research_jobs()
	if jobs.is_empty():
		box.add_child(PanelKit.hint(I18n.t("ui.research.desk_empty")))
		return box
	for job in jobs:
		var card := PanelKit.paper(PanelKit.CARD_HI, 10)
		var row := PanelKit.hbox(12)
		var text := PanelKit.label(_job_text(job), 17, PanelKit.INK_SOFT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var cancel := PanelKit.button(I18n.t("ui.research.cancel"))
		cancel.pressed.connect(func() -> void:
			if GameState.cancel_research(job.signature):
				show_message(I18n.t("ui.research.cancelled"), PanelKit.INK_SOFT)
			_structure_signature = ""
			refresh()
		)
		row.add_child(cancel)
		card.add_child(row)
		box.add_child(card)
		_job_rows.append({"label": text, "job": job})
	return box


func _record_section() -> VBoxContainer:
	var box := PanelKit.vbox(8)
	var history := GameState.get_research_history()
	box.add_child(PanelKit.label(I18n.t("ui.research.records", [GameState.get_research_record_count()]),
			15, PanelKit.INK_SOFT))
	if history.is_empty():
		box.add_child(PanelKit.hint(I18n.t("ui.research.records_empty"), 600))
		return box
	# 最近 20 条，最新的在最上面；滚动交给外层滚动区（D10）
	for record in history:
		box.add_child(_record_row(record))
	return box


## 一条历史：组合 / 结论 / 消耗与用时。结论复用 `describe_research`，四档文案只有一份。
func _record_row(record: Dictionary) -> PanelContainer:
	var card := PanelKit.paper(PanelKit.CARD_HI, 8)
	var box := PanelKit.vbox(3)
	var head := PanelKit.hbox(10)
	head.add_child(PanelKit.label(_materials_text(record.get("materials", [])), 17, PanelKit.INK))
	head.add_child(PanelKit.spacer())
	var seconds := float(record.get("seconds", 0.0))
	if seconds > 0.0:
		head.add_child(PanelKit.label(PanelKit.duration_text(seconds), 15, PanelKit.INK_DIM))
	box.add_child(head)
	var verdict := PanelKit.label(GameState.describe_research(String(record.get("signature", ""))),
			16, PanelKit.INK_SOFT)
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(verdict)
	box.add_child(PanelKit.hint(_cost_text(record), 560))
	card.add_child(box)
	return card


func _materials_text(keys: Array) -> String:
	var names: Array[String] = []
	for key in keys:
		var def := def_of(String(key)) as ItemDef
		names.append(def.localized() if def != null else String(key))
	return " + ".join(names)


## 这次试错付了什么：成功 = 全算学费；失败 = 烧掉的那几样。
func _cost_text(record: Dictionary) -> String:
	if bool(record.get("succeeded", false)):
		return I18n.t("ui.research.history_tuition")
	var burned: Array = record.get("burned", [])
	if burned.is_empty():
		return I18n.t("ui.research.history_no_burn")
	var counts := {}
	for key in burned:
		counts[String(key)] = int(counts.get(String(key), 0)) + 1
	var parts: Array[String] = []
	for key in counts:
		var def := def_of(String(key)) as ItemDef
		var name_text := def.localized() if def != null else String(key)
		parts.append("%s ×%d" % [name_text, int(counts[key])])
	return I18n.t("ui.research.history_cost", ["、".join(parts)])


## 常驻提示：还剩几个方向 + 怎么用；候选见底时换成鼓励句。
func _usage_hint(count: int) -> Label:
	var text := I18n.t("ui.research.usage_hint", [count]) if count > 2 else I18n.t("ui.research.empty_hint")
	return PanelKit.hint(text, 620)


## 首启三步引导。不做控件高亮：三步都要点的地方就在页签下面，
## 高亮框得跟着布局跑，一改布局就错位——文字说清楚更稳。
func _guide_card() -> PanelContainer:
	var card := PanelKit.paper(PanelKit.CARD_HI, 10)
	var box := PanelKit.vbox(4)
	box.add_child(PanelKit.label(I18n.t("ui.research.guide_title"), 18, PanelKit.INK))
	for index in 3:
		box.add_child(PanelKit.hint(I18n.t("ui.research.guide_step_%d" % (index + 1)), 620))
	var row := PanelKit.hbox(10)
	row.add_child(PanelKit.spacer())
	var ok := PanelKit.button(I18n.t("ui.research.guide_ok"))
	ok.pressed.connect(_dismiss_guide)
	row.add_child(ok)
	box.add_child(row)
	card.add_child(box)
	return card


func _dismiss_guide() -> void:
	GameState.mark_research_guide_seen()
	_guide_open = false
	_structure_signature = ""
	refresh()


func _has_materials(keys: Array[String]) -> bool:
	for key in keys:
		var def := def_of(key) as ItemDef
		if def != null and def.is_free():
			continue
		if GameState.get_amount(key) + GameState.EPSILON < 1.0:
			return false
	return true


func _try(picked: Array[String]) -> void:
	if GameState.start_research(picked):
		Sfx.play(Sfx.Intent.CONFIRM)
		show_message(I18n.t("ui.research.started"), PanelKit.INK_SOFT)
		_picked.clear()
	else:
		Sfx.play(Sfx.Intent.DENY)
		show_message(I18n.t("ui.research.cant_start"), PanelKit.DANGER_DEEP)
	_structure_signature = ""
	refresh()


func _job_text(job: ResearchJob) -> String:
	var names: Array[String] = []
	for key in job.materials:
		var def := def_of(key)
		names.append(def.localized() if def != null else key)
	return I18n.t("ui.research.job", [" + ".join(names), int(job.progress() * 100.0), PanelKit.duration_text(job.remaining_seconds)])


func _update_job_rows() -> void:
	for entry in _job_rows:
		var label: Label = entry["label"]
		var job: ResearchJob = entry["job"]
		if is_instance_valid(label):
			label.text = _job_text(job)
