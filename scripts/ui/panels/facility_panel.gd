class_name FacilityPanel
extends GamePanel
## 设备：看等级、提速倍数、并行位，花铜币与材料升级。

func _on_open(data: Dictionary = {}) -> void:
	super._on_open(data)


func refresh() -> void:
	clear_content()
	set_title(I18n.t("ui.facility.title"))
	set_subtitle(I18n.t("ui.facility.subtitle"))
	content.add_child(_kitchen_row())
	content.add_child(PanelKit.divider())
	var facilities := defs_of("facility").filter(_is_craft_facility)
	# 还没到手的设备（等信件添置的冰箱）不进列表，信到了才出现
	facilities = facilities.filter(func(def: GameDef) -> bool: return GameState.get_facility_level(def.get_key()) >= 1)
	if facilities.is_empty():
		content.add_child(PanelKit.hint(I18n.t("ui.facility.empty")))
	else:
		for def in facilities:
			content.add_child(_facility_row(def as FacilityDef))
	content.add_child(_facility_section())


## 厨房扩建：店能同时开几条产线。和设备升级分开，只花铜币、不用交材料，
## 这样「设备更快」与「同时开更多灶」是两条互不重叠的取舍。
func _kitchen_row() -> VBoxContainer:
	var row := PanelKit.vbox(6)
	var head := PanelKit.hbox(12)
	head.add_child(PanelKit.label(I18n.t("ui.facility.kitchen_title"), 20))
	head.add_child(PanelKit.spacer())
	head.add_child(PanelKit.label(
			I18n.t("ui.facility.level", [GameState.get_kitchen_level(), GameState.KITCHEN_MAX_LEVEL]),
			18, PanelKit.INK_SOFT))
	row.add_child(head)
	if GameState.get_kitchen_level() >= GameState.KITCHEN_MAX_LEVEL:
		row.add_child(PanelKit.hint(I18n.t("ui.facility.kitchen_lanes_max",
				[GameState.get_kitchen_level(), GameState.get_lane_count()]), 640))
	else:
		row.add_child(PanelKit.hint(I18n.t("ui.facility.kitchen_lanes",
				[GameState.get_kitchen_level(), GameState.get_lane_count(),
				GameState.get_kitchen_level() + 1, GameState.get_lane_count() + 1]), 640))
	row.add_child(PanelKit.hint(I18n.t("ui.facility.kitchen_parallel_hint"), 640))

	var cost := GameState.get_kitchen_upgrade_cost()
	if cost < 0:
		row.add_child(PanelKit.label(I18n.t("ui.facility.kitchen_maxed"), 17, PanelKit.INK_SOFT))
		return row

	var button := PanelKit.button(
			I18n.t("ui.facility.kitchen_upgrade", [GameState.get_kitchen_level() + 1, PanelKit.coins_text(cost)]),
			Sfx.Intent.NONE)
	PanelKit.set_disabled(button, not GameState.can_upgrade_kitchen())
	button.pressed.connect(func() -> void:
		if GameState.upgrade_kitchen():
			show_message(I18n.t("ui.facility.upgraded",
					[I18n.t("ui.facility.kitchen_title"), GameState.get_kitchen_level()]), PanelKit.INK_SOFT)
		else:
			Sfx.play(Sfx.Intent.DENY)
			show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
		refresh()
	)
	# 和下面的设备行同一套结构：差多少直接写在按钮旁边，不让人自己减（报告 P2-4）
	var action := PanelKit.hbox(10)
	action.add_child(button)
	if GameState.coins < cost:
		var short := PanelKit.label(I18n.t("ui.common.coins_short", [cost - GameState.coins]), 17, PanelKit.INK_SOFT)
		short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action.add_child(short)
	row.add_child(action)
	return row


## 研究台有自己的面板（研究台页），仓库有自己的仓页面，都不在这里重复一遍
func _is_craft_facility(def: GameDef) -> bool:
	var facility := def as FacilityDef
	if facility == null:
		return false
	return facility.category != "research" and facility.category != "storage"


func _facility_row(facility: FacilityDef) -> VBoxContainer:
	var key := facility.get_key()
	var level := GameState.get_facility_level(key)
	var row := PanelKit.vbox(6)

	var head := PanelKit.hbox(12)
	head.add_child(PanelKit.label(facility.localized(), 20))
	head.add_child(PanelKit.spacer())
	head.add_child(PanelKit.label(I18n.t("ui.facility.level", [level, facility.max_level]), 18, PanelKit.INK_SOFT))
	row.add_child(head)

	var speed := GameState.get_speed_factor(key)
	row.add_child(PanelKit.hint(I18n.t("ui.facility.speed", [level, "%.2f" % speed]), 640))
	if not facility.localized(&"description").is_empty():
		row.add_child(PanelKit.hint(facility.localized(&"description"), 640))

	var upgrade := facility.get_upgrade(level + 1)
	if upgrade != null:
		row.add_child(PanelKit.hint(I18n.t("ui.facility.next_level",
				[upgrade.target_level, upgrade.target_level,
				"%.2f" % facility.get_speed_factor(upgrade.target_level)]), 640))
	if upgrade == null:
		row.add_child(PanelKit.label(I18n.t("ui.facility.maxed"), 17, PanelKit.INK_SOFT))
	else:
		row.add_child(_upgrade_row(facility, upgrade))
	row.add_child(PanelKit.divider())
	return row


func _upgrade_row(facility: FacilityDef, upgrade: FacilityUpgrade) -> HBoxContainer:
	var row := PanelKit.hbox(10)
	var cost: Array[String] = [PanelKit.coins_text(upgrade.coin_cost)]
	for stack in upgrade.materials:
		if stack == null:
			continue
		cost.append("%s × %d" % [stack_name(stack), stack.amount])
	var button := PanelKit.button(I18n.t("ui.facility.upgrade_button", [upgrade.target_level, I18n.list_sep().join(cost)]), Sfx.Intent.NONE)
	PanelKit.set_disabled(button, not _can_upgrade(facility, upgrade))
	button.pressed.connect(func() -> void:
		if GameState.upgrade_facility(facility.get_key()):
			show_message(I18n.t("ui.facility.upgraded", [facility.localized(), upgrade.target_level]), PanelKit.INK_SOFT)
		else:
			Sfx.play(Sfx.Intent.DENY)
			show_message(I18n.t("ui.common.not_enough"), PanelKit.DANGER_DEEP)
		refresh()
	)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.y = 38
	row.add_child(button)
	if GameState.coins < upgrade.coin_cost:
		# 这一行是 HBox，不能自动换行，否则会被挤成一列字
		var short := PanelKit.label(I18n.t("ui.common.coins_short", [upgrade.coin_cost - GameState.coins]), 17, PanelKit.INK_SOFT)
		short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(short)
	return row


func _can_upgrade(facility: FacilityDef, upgrade: FacilityUpgrade) -> bool:
	if GameState.get_facility_level(facility.get_key()) >= facility.max_level:
		return false
	if GameState.coins < upgrade.coin_cost:
		return false
	return GameState.can_consume(upgrade.materials)


## 设施入口：仓库 / 研究台 / 订单容量。
## 这些能力以前只藏在各自的页里，反馈 9/13/15 找不到，所以集中列一区。
func _facility_section() -> VBoxContainer:
	var section := PanelKit.vbox(8)
	section.add_child(PanelKit.divider())
	section.add_child(PanelKit.group_header(I18n.t("ui.facility.section")))
	section.add_child(_link_row(
			"ui.facility.warehouse_title",
			I18n.t("ui.facility.warehouse_body", [
				GameState.get_warehouse_level(),
				GameState.get_warehouse_cap_common(),
				GameState.get_warehouse_cap_rare(),
			]),
			UIKeys.WAREHOUSE,
			"ui.facility.warehouse_button"))
	section.add_child(_link_row(
			"ui.facility.research_title",
			I18n.t("ui.facility.research_body"),
			UIKeys.RESEARCH,
			"ui.facility.research_button"))
	# 订单板在第九封信后才开放：解锁前这一行不出现，避免从设备页绕过入口。
	if GameState.is_orders_unlocked():
		section.add_child(_link_row(
				"ui.facility.orders_title",
				I18n.t("ui.facility.orders_body", [
					GameState.get_orders().size(), GameState.get_order_capacity(),
					GameState.ORDER_CAPACITY_MAX,
				]),
				UIKeys.ORDERS,
				"ui.facility.orders_button"))
	return section


func _link_row(title_key: String, body: String, panel_id: String, button_key: String) -> VBoxContainer:
	var row := PanelKit.vbox(5)
	var head := PanelKit.hbox(12)
	head.add_child(PanelKit.label(I18n.t(title_key), 18))
	head.add_child(PanelKit.spacer())
	var button := PanelKit.button(I18n.t(button_key))
	button.custom_minimum_size.y = 34
	button.pressed.connect(func() -> void:
		UIManager.open_panel(ResourceLocation.from_string(panel_id))
	)
	head.add_child(button)
	row.add_child(head)
	row.add_child(PanelKit.hint(body, 640))
	return row
