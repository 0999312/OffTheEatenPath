class_name CatalogDetailPanel
extends GamePanel
## 图鉴条目详情（POPUP 层）：由书架的一行「查看」打开。
##
## 书架只负责收集概览；完整的描述、配方用量、价格与线索都在这里，
## 一次只读一条，不再把长文塞进列表。

const TYPE_KEYS := {
	"material": "ui.catalog.cat_material",
	"food": "ui.catalog.cat_food",
	"recipe": "ui.catalog.cat_recipe",
	"facility": "ui.catalog.cat_facility",
	"world": "ui.catalog.cat_world",
	"letter": "ui.catalog.cat_letter",
}

const TYPE_ICONS := {
	"material": "food/carrot.svg",
	"food": "food/ham.svg",
	"recipe": "ui/clip.svg",
	"facility": "ui/adjust.svg",
	"world": "ui/monitor.svg",
	"letter": "ui/bookmark.svg",
}

var _key := ""
var _type_id := ""


func _on_open(data: Dictionary = {}) -> void:
	_key = String(data.get("key", ""))
	_type_id = String(data.get("type", ""))
	var def := def_of(_key)
	if def == null:
		push_warning("[CatalogDetailPanel] 找不到图鉴条目：%s" % _key)
		close_self()
		return
	if _type_id.is_empty():
		_type_id = _type_of(def)
	# 图鉴里重读信件也算「读过」：否则玩家在书架上读完正文，HUD 还挂着未读红点。
	# mark_letter_read 自带「只发一次奖励」的保护，重复打开不会重复发东西。
	if def is LetterDef and GameState.is_discovered(_key):
		GameState.mark_letter_read(_key)
	# 条目名放在内容区的大标题里；面板标题只说明「哪一类图鉴」，避免同一行重复两次
	# 标题在 refresh() 里设：切语言时也要重算
	set_subtitle("")
	super._on_open(data)


func refresh() -> void:
	clear_content()
	set_title(I18n.t("ui.catalog.detail_title", [I18n.t(String(TYPE_KEYS.get(_type_id, "ui.catalog.cat_material")))]))
	var def := def_of(_key)
	if def == null:
		content.add_child(PanelKit.hint(I18n.t("ui.catalog.missing"), 660))
		return
	_build(def)


## 主题还没到站的食物：详情页只留一句「还没到那里」。
## 名字、线索、规格全是后半程的内容，这里一个字都不给。
func _is_theme_locked() -> bool:
	if _type_id != "food":
		return false
	if GameState.is_discovered(_key):
		return false
	var item := def_of(_key) as ItemDef
	return item != null and not GameState.is_theme_unlocked(item.theme)


func _build_locked() -> void:
	var head := PanelKit.hbox(16)
	var mark := PanelKit.icon(String(TYPE_ICONS.get(_type_id, "ui/book.svg")), 54.0, PanelKit.INK_SOFT)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	var titles := PanelKit.vbox(3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(PanelKit.label(I18n.t("ui.catalog.unknown"), 30))
	head.add_child(titles)
	content.add_child(head)
	content.add_child(PanelKit.divider())
	content.add_child(PanelKit.hint(I18n.t("ui.catalog.theme_locked"), 660))


func _build(def: GameDef) -> void:
	if _is_theme_locked():
		_build_locked()
		return
	var discovered := GameState.is_discovered(_key)

	var head := PanelKit.hbox(16)
	var icon_tint := PanelKit.tint_of(_type_id) if discovered else PanelKit.INK_SOFT
	var mark := PanelKit.icon(String(TYPE_ICONS.get(_type_id, "ui/book.svg")), 54.0, icon_tint)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)

	var titles := PanelKit.vbox(3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(PanelKit.label(def.localized() if discovered else I18n.t("ui.catalog.unknown"), 30))
	var subtitle := _subtitle_of(def)
	if not subtitle.is_empty():
		titles.add_child(PanelKit.label(subtitle, 16, PanelKit.INK_SOFT))
	head.add_child(titles)

	var status := PanelKit.label(I18n.t("ui.catalog.recorded_badge") if discovered else I18n.t("ui.catalog.not_recorded"), 16,
			PanelKit.ACCENT_DEEP if discovered else PanelKit.INK_SOFT)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	content.add_child(head)
	content.add_child(PanelKit.divider())

	if not discovered:
		content.add_child(PanelKit.hint(_hint_of(def), 660))
		var flavor := _flavor_of(def)
		if not flavor.is_empty():
			content.add_child(PanelKit.hint(flavor, 660))
		content.add_child(PanelKit.hint(I18n.t("ui.catalog.first_meet"), 660))
	elif not def.localized(&"description").is_empty():
		var body := PanelKit.label(def.localized(&"description"), 18)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 660
		content.add_child(body)

	# 信件不只是图鉴里的一行「第几封」：已经收到的信，正文也应该能在书架上重读。
	# 这里只展示，不调用 mark_letter_read——重读旧信不该再发一次奖励，也不该替玩家
	# 把「未读」状态消掉；要正式读信仍然走信箱。
	if discovered and def is LetterDef:
		var letter := def as LetterDef
		if not letter.localized(&"body").is_empty():
			content.add_child(PanelKit.divider())
			var letter_body := PanelKit.label(letter.localized(&"body"), 18)
			letter_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			letter_body.custom_minimum_size.x = 660
			content.add_child(letter_body)

	# 事实按区块排：来源 / 价值 / 做法 / 规格，各带小标题与「标签 · 值」两列。
	# 未记录的条目也留着骨架，值全显示成「？？？」——它告诉玩家记下来之后能查到什么。
	for section in _sections_of(def):
		_add_section(section, discovered)

	# 「它可以做…」：这件材料 / 这道菜 / 这条配方的产物还能拿去做什么（第十轮反馈 5）。
	# 与灶台共用同一份折叠段；图鉴只列已经记录过的下游，没做过的不报名字、整段跳过。
	if discovered:
		var used_in := _used_in_of(def)
		if used_in != null:
			content.add_child(used_in)

	if discovered:
		var hint := _hint_of(def)
		if not hint.is_empty():
			content.add_child(PanelKit.divider())
			content.add_child(PanelKit.hint(hint, 660))


func _row(label_key: String, value: String) -> Dictionary:
	return {"label": I18n.t(label_key), "value": value}


## 反查这件东西的下游配方：材料与食物查它自己，配方查它的主产物。
## 只列已经记录过的下游——这一页是「查到过什么」，不是「接下来该做什么」。
func _used_in_of(def: GameDef) -> Control:
	if def is ItemDef:
		return used_in_section(def.get_key(), _open_recipe_entry, Callable(), true)
	if def is RecipeDef:
		var recipe := def as RecipeDef
		return used_in_section(recipe.output, _open_recipe_entry, Callable(), true)
	return null


## 点「它可以做…」里的下游：就地换成那条配方的详情。
## 不走 UIManager.open_panel——书架和这份详情都还在栈上，同 id 重开会被防重复
## 挡掉（第十轮反馈 5）；就地换一条也是同一个阅读动线。
func _open_recipe_entry(recipe_key: String) -> void:
	if def_of(recipe_key) == null:
		return
	_key = recipe_key
	_type_id = "recipe"
	refresh()
	if _scroll != null:
		_scroll.scroll_vertical = 0


## 一条图鉴记录能说的事实，按「来源 / 价值 / 做法 / 规格」分块。
## 之前是一串同字号同颜色的句子，「在哪采」和「值多少钱」看起来一样重；
## 分块以后玩家扫一眼就知道往哪儿看。
func _sections_of(def: GameDef) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	if def is ItemDef and (def as ItemDef).is_material():
		var material := def as ItemDef
		var origin: Array[Dictionary] = []
		var intro := ""
		var harvest := GameState.get_harvest_for_material(material.get_key())
		if harvest != null:
			var level := GameState.get_harvest_level(harvest.get_key())
			origin.append(_row("ui.catalog.row_source", harvest.localized()))
			origin.append(_row("ui.catalog.row_speed",
					I18n.t("ui.catalog.value_speed", [PanelKit.number_text(harvest.cooldown_at(level))])))
			# 池子里现在能摇出哪几样（等级把它们一个个放进来）
			var pool: Array[String] = []
			for item in GameState.harvest_pool(harvest):
				pool.append(item.localized())
			if not pool.is_empty():
				origin.append(_row("ui.catalog.row_pool", I18n.list_sep().join(pool)))
			var cap := GameState.get_material_cap(material.get_key())
			if cap > 0:
				origin.append(_row("ui.catalog.row_cap", I18n.t("ui.catalog.value_cap", [cap])))
			var trickle := harvest.trickle_at(level)
			if trickle > 0.0:
				origin.append(_row("ui.catalog.row_trickle",
						I18n.t("ui.catalog.value_trickle", [PanelKit.number_text(1.0 / trickle)])))
			if not harvest.unlock_facility.is_empty():
				var facility := def_of(harvest.unlock_facility) as FacilityDef
				var facility_name := facility.localized() if facility != null else harvest.unlock_facility
				origin.append(_row("ui.catalog.row_unlock",
						I18n.t("ui.catalog.value_unlock", [facility_name, harvest.unlock_level])))
			if not harvest.unlock_letter.is_empty():
				var unlock_letter := def_of(harvest.unlock_letter) as LetterDef
				var unlock_title := unlock_letter.localized(&"title") if unlock_letter != null else harvest.unlock_letter
				origin.append(_row("ui.catalog.row_unlock",
						I18n.t("ui.catalog.value_unlock_letter", [unlock_title])))
			intro = harvest.localized(&"description")
		if not origin.is_empty():
			sections.append({"title": I18n.t("ui.catalog.section_origin"), "intro": intro, "rows": origin})
		var worth: Array[Dictionary] = []
		if material.merchant_price > 0:
			worth.append(_row("ui.catalog.row_price",
					I18n.t("ui.catalog.value_price", [PanelKit.coins_text(material.merchant_price)])))
		if material.sell_price > 0:
			worth.append(_row("ui.catalog.row_sell",
					I18n.t("ui.catalog.value_price", [PanelKit.coins_text(material.sell_price)])))
		if not worth.is_empty():
			sections.append({"title": I18n.t("ui.catalog.section_value"), "rows": worth})
	elif def is ItemDef:
		var food := def as ItemDef
		# 口味已经在标题下面当副标题了，价值这里只留一句收购价
		var worth: Array[Dictionary] = []
		if food.sell_price > 0:
			worth.append(_row("ui.catalog.row_sell",
					I18n.t("ui.catalog.value_price", [PanelKit.coins_text(food.sell_price)])))
		if not worth.is_empty():
			sections.append({"title": I18n.t("ui.catalog.section_value"), "rows": worth})
		# 「这菜怎么做」是翻图鉴时最想知道的，之前只散落在配方页里
		var makers: Array[String] = []
		for recipe_def in defs_of("recipe"):
			var maker := recipe_def as RecipeDef
			if maker != null and maker.output == food.get_key():
				makers.append(maker.localized())
		if not makers.is_empty():
			sections.append({"title": I18n.t("ui.catalog.section_method"),
				"rows": [_row("ui.catalog.row_made_by", I18n.list_sep().join(makers))]})
	elif def is RecipeDef:
		var recipe := def as RecipeDef
		var method: Array[Dictionary] = []
		method.append(_row("ui.catalog.row_duration", PanelKit.duration_text(recipe.duration_seconds)))
		var inputs: Array[String] = []
		for stack in recipe.inputs:
			inputs.append("%s × %d" % [stack_name(stack), stack.amount])
		method.append(_row("ui.catalog.row_inputs", I18n.list_sep().join(inputs)))
		var output := def_of(recipe.output)
		if output != null:
			method.append(_row("ui.catalog.row_output", output.localized()))
		sections.append({"title": I18n.t("ui.catalog.section_method"), "rows": method})
		if recipe.needs_research() and not GameState.is_recipe_unlocked(recipe.get_key()):
			sections.append({"title": I18n.t("ui.catalog.section_origin"),
					"rows": [_row("ui.catalog.row_unlock", research_clue(recipe))]})
	elif def is FacilityDef:
		var facility := def as FacilityDef
		var spec: Array[Dictionary] = []
		if not facility.category.is_empty():
			var category_key := "ui.catalog.category_%s" % facility.category
			var category_text := I18n.t(category_key)
			spec.append(_row("ui.catalog.row_category",
					category_text if category_text != category_key else facility.category))
		spec.append(_row("ui.catalog.row_max_level", str(facility.max_level)))
		sections.append({"title": I18n.t("ui.catalog.section_spec"), "rows": spec})
	elif def is WorldDef:
		var body := (def as WorldDef).localized(&"body")
		if not body.is_empty():
			sections.append({"title": "", "intro": body, "rows": []})
	elif def is LetterDef:
		sections.append({"title": I18n.t("ui.catalog.section_spec"),
			"rows": [_row("ui.catalog.row_order", str((def as LetterDef).order))]})
	return sections


## 一块事实：小标题 + 若干「标签 / 值」两列行。标签固定 96px，值占满剩余宽度并自动换行——
## 长清单（比如一条配方的用料）不会把面板撑宽。
func _add_section(section: Dictionary, discovered: bool) -> void:
	var rows: Array = section.get("rows", [])
	var title := String(section.get("title", ""))
	var intro := String(section.get("intro", ""))
	if rows.is_empty() and intro.is_empty():
		return
	content.add_child(PanelKit.divider())
	if not title.is_empty():
		content.add_child(PanelKit.label(title, 17, PanelKit.INK_SOFT))
	if discovered and not intro.is_empty():
		var note := PanelKit.label(intro, 16, PanelKit.INK_SOFT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 660
		content.add_child(note)
	for row in rows:
		var line := PanelKit.hbox(12)
		var tag := PanelKit.label(String(row["label"]), 16, PanelKit.INK_SOFT)
		tag.custom_minimum_size.x = 96.0
		line.add_child(tag)
		var value_text := String(row["value"]) if discovered else I18n.t("ui.catalog.unknown")
		var value := PanelKit.label(value_text, 17, PanelKit.INK if discovered else PanelKit.INK_SOFT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(value)
		content.add_child(line)

func _subtitle_of(def: GameDef) -> String:
	if def is ItemDef:
		var item := def as ItemDef
		if item.is_food():
			return item.localized(&"taste")
		return I18n.t("ui.catalog.gathered") if item.material_kind == ItemDef.MaterialKind.BASE else I18n.t("ui.catalog.semi_finished")
	if def is RecipeDef:
		return I18n.t("ui.catalog.cost_time", [PanelKit.duration_text((def as RecipeDef).duration_seconds)])
	if def is FacilityDef:
		# category 是数据层的英文枚举（coffee_machine），图鉴里要翻成人话
		var category := (def as FacilityDef).category
		var key := "ui.catalog.category_%s" % category
		var text := I18n.t(key)
		return text if text != key else category
	if def is WorldDef:
		return (def as WorldDef).localized(&"subtitle")
	if def is LetterDef:
		return I18n.t("ui.catalog.from_letter")
	return ""


func _hint_of(def: GameDef) -> String:
	if def is ItemDef:
		var item := def as ItemDef
		if not item.is_food():
			if not GameState.is_discovered(item.get_key()):
				return material_hint(item, true)
			return item.localized(&"description")
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
		# 打开详情时已经 mark_letter_read；这里不再补一句会自相矛盾的提示。
		return ""
	if def is WorldDef:
		var world_hint := (def as WorldDef).localized(&"catalog_hint")
		return world_hint if not world_hint.is_empty() else I18n.t("ui.catalog.hint_world")
	return I18n.t("ui.catalog.hint_unknown")


## 未记录的研究配方再补一句它自己的氛围 hint——材料句在 `_hint_of()` 里，
## 两句一起出现才既有方向又有味道（用户 2026-10-29 说只有描述也不行）。
func _flavor_of(def: GameDef) -> String:
	if def is RecipeDef:
		var recipe := def as RecipeDef
		if recipe.needs_research() and not GameState.is_recipe_unlocked(recipe.get_key()):
			return research_flavor(recipe)
	return ""


func _type_of(def: GameDef) -> String:
	if def is ItemDef:
		return "food" if (def as ItemDef).is_food() else "material"
	if def is RecipeDef:
		return "recipe"
	if def is FacilityDef:
		return "facility"
	if def is WorldDef:
		return "world"
	if def is LetterDef:
		return "letter"
	return "material"
