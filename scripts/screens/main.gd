class_name MainScreen
extends Control
## 主画面：一间屋子。左墙是「把东西做出来」的地方，右墙是「查看与成长」，桌面只摆正在发生的事。
##
## 为什么桌面不铺材料清单：那是一排数字，不是生活空间。材料多少属于「检查」时才需要的信息，
## 所以收进仓库，桌面只留一个「看看仓库」的快捷入口——想点数了再看。

## 桌面进度条的刷新间隔（秒）：秒级进度不必每帧重画
const TABLE_TICK := 0.2
## 房间的固定尺寸：窗口尺寸变了，房间不变，多出来的地方交给背景
const ROOM_SIZE := Vector2(1280.0, 720.0)

const EVENT_MATERIAL := &"MaterialChangedEvent"
const EVENT_CRAFT := &"CraftCompletedEvent"
const EVENT_RESEARCH_DONE := &"ResearchCompletedEvent"
const EVENT_DISCOVERED := &"CatalogDiscoveredEvent"
const EVENT_RESTORED := &"StateRestoredEvent"
const EVENT_LANGUAGE := &"LanguageChangedEvent"
const EVENT_CATALOG_SEEN := &"CatalogSeenEvent"
const EVENT_LETTER_READ := &"LetterReadEvent"

## 房间里的入口。左列管产出，右列管查看与成长。
## `title` / `subtitle` 是翻译键，卡片文案在 `_build_hotspots` 里取。
const LEFT_HOTSPOTS := [
	{
		"panel": UIKeys.CRAFT,
		"title": "ui.hotspot.stove_title",
		"subtitle": "ui.hotspot.stove_subtitle",
		"icon": "food/water_cup.svg",
		"tilt": -1.6,
		"accent": Color(0.949, 0.851, 0.769),
	},
	{
		"panel": UIKeys.FACILITY,
		"title": "ui.hotspot.equipment_title",
		"subtitle": "ui.hotspot.equipment_subtitle",
		"icon": "ui/adjust.svg",
		"tilt": 0.9,
		"accent": Color(0.835, 0.890, 0.937),
	},
	{
		"panel": UIKeys.MERCHANT,
		"title": "ui.hotspot.merchant_title",
		"subtitle": "ui.hotspot.merchant_subtitle",
		"icon": "ui/shop.svg",
		"tilt": -0.8,
		"accent": Color(0.910, 0.890, 0.784),
	},
]

const RIGHT_HOTSPOTS := [
	{
		"panel": UIKeys.CATALOG,
		"title": "ui.hotspot.shelf_title",
		"subtitle": "ui.hotspot.shelf_subtitle",
		"icon": "ui/book.svg",
		"tilt": 1.2,
		"accent": Color(0.812, 0.886, 0.902),
	},
	{
		"panel": UIKeys.MAIL,
		"title": "ui.hotspot.mail_title",
		"subtitle": "ui.hotspot.mail_subtitle",
		"icon": "ui/bookmark.svg",
		"tilt": -1.1,
		"accent": Color(0.878, 0.851, 0.925),
	},
	{
		"panel": UIKeys.RESEARCH,
		"title": "ui.hotspot.research_title",
		"subtitle": "ui.hotspot.research_subtitle",
		"icon": "ui/puzzle.svg",
		"tilt": 0.7,
		"accent": Color(0.827, 0.902, 0.835),
	},
]

@onready var _hud: GameHud = $HudLayer/Hud
@onready var _hud_layer: CanvasLayer = $HudLayer
@onready var _bridge: GameBridge = $GameBridge
@onready var _room: Control = $Room
@onready var _left_rail: VBoxContainer = $Room/Desktop/LeftRail
@onready var _right_rail: VBoxContainer = $Room/Desktop/RightRail
@onready var _table_box: VBoxContainer = $Room/Desktop/Table/Front/TableBox
@onready var _table: Control = $Room/Desktop/Table
@onready var _harvest: HarvestLayer = $Room/Harvest

var _table_accumulator := 0.0
var _table_signature := ""
## 桌面小动效的时钟：只驱动透明度呼吸，不参与任何数值结算
var _ambient_time := 0.0
## 与桌面上的进度条一一对应，用来就地更新（重建会让进度条闪一下）
var _bar_jobs: Array[RefCounted] = []
var _bars: Array[ProgressBar] = []
var _time_labels: Array[Label] = []
## 画卡片时研究提示是否亮着：只要还有没试出来的菜就亮着，全部试完才收掉
var _research_hint_active := false
## 房间入口卡：按面板 ID 记住，图鉴有新发现时给对应卡片点红点
var _hotspot_cards: Dictionary = {}
## 三步引导条（新档才出现；老档 tutorial_done 为真时自己收起）
var _tutorial_bar: TutorialBar


func _ready() -> void:
	_build_tutorial_bar()
	_layout_room()
	resized.connect(_layout_room)
	_hud.panel_requested.connect(_on_panel_requested)
	_research_hint_active = GameState.has_unresearched_recipes()
	_build_hotspots(_left_rail, LEFT_HOTSPOTS)
	_add_table_shadow()
	_add_tape()
	_build_hotspots(_right_rail, RIGHT_HOTSPOTS)
	EventBus.subscribe(EVENT_MATERIAL, _on_table_changed)
	EventBus.subscribe(EVENT_CRAFT, _on_table_changed)
	EventBus.subscribe(EVENT_RESEARCH_DONE, _on_table_changed)
	EventBus.subscribe(EVENT_DISCOVERED, _on_table_changed)
	EventBus.subscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.subscribe(EVENT_CATALOG_SEEN, _on_catalog_seen)
	EventBus.subscribe(EVENT_LETTER_READ, _on_letter_read)
	_refresh_hotspot_locks()
	_refresh_hotspot_dots()
	_rebuild_table()
	if _tutorial_bar != null:
		_tutorial_bar.refresh_target()


## 引导条挂在 HUD 同一层：跟房间一起居中，固定在纸面下沿。
func _build_tutorial_bar() -> void:
	_tutorial_bar = TutorialBar.new()
	_tutorial_bar.name = "TutorialBar"
	_tutorial_bar.target_provider = _tutorial_target_for
	_tutorial_bar.target_requested.connect(_on_tutorial_target_requested)
	_tutorial_bar.progress_changed.connect(_on_tutorial_progress_changed)
	_hud_layer.add_child(_tutorial_bar)


func _exit_tree() -> void:
	EventBus.unsubscribe(EVENT_MATERIAL, _on_table_changed)
	EventBus.unsubscribe(EVENT_CRAFT, _on_table_changed)
	EventBus.unsubscribe(EVENT_RESEARCH_DONE, _on_table_changed)
	EventBus.unsubscribe(EVENT_DISCOVERED, _on_table_changed)
	EventBus.unsubscribe(EVENT_RESTORED, _on_state_restored)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)
	EventBus.unsubscribe(EVENT_CATALOG_SEEN, _on_catalog_seen)
	EventBus.unsubscribe(EVENT_LETTER_READ, _on_letter_read)


func _process(delta: float) -> void:
	_ambient_time += delta
	_breathe_bars()
	_table_accumulator += delta
	if _table_accumulator < TABLE_TICK:
		return
	_table_accumulator = 0.0
	_refresh_table()


## 进行中的进度条轻轻呼吸：不做重建、不改进度值，只让「正在干活」这件事有生命感
func _breathe_bars() -> void:
	if _bars.is_empty():
		return
	var pulse := 0.90 + 0.10 * (0.5 + 0.5 * sin(_ambient_time * 2.4))
	for bar in _bars:
		if bar != null and is_instance_valid(bar):
			bar.modulate.a = pulse


func _on_panel_requested(panel_id: String, data: Dictionary) -> void:
	# 带参数的入口（图鉴定位最新、信箱直达待办）走 open_panel：不能因为面板恰好开过就 toggle 掉。
	if data.is_empty():
		_bridge.toggle_panel(panel_id)
	else:
		_bridge.open_panel(panel_id, data)


func _on_tutorial_target_requested(panel_id: String) -> void:
	_bridge.toggle_panel(panel_id)


## 引导每推进一步就落盘一次：跳过/走完后立刻关窗口也不会再弹（不是每帧写）
func _on_tutorial_progress_changed() -> void:
	_bridge.save_now()


## 引导要脉冲哪张入口卡：信箱/灶台走房间里的卡，订单板走 HUD 顶部那张。
func _tutorial_target_for(panel_id: String) -> Control:
	if panel_id == UIKeys.MAIL or panel_id == UIKeys.CRAFT:
		return _hotspot_cards.get(panel_id) as Control
	if panel_id == UIKeys.ORDERS:
		return _hud.get_orders_card()
	return null


func _on_table_changed(_event: Event) -> void:
	_refresh_table()
	_refresh_research_hint()
	_refresh_hotspot_dots()


## 图鉴看过了：房间里的书架卡红点跟着 HUD 一起灭
func _on_catalog_seen(_event: Event) -> void:
	_refresh_hotspot_dots()


## 读信后商人可能开张：入口卡从灰化恢复成可点的副标题。
func _on_letter_read(_event: Event) -> void:
	_refresh_hotspot_locks()


## 商人入口在读到杂货商人的信前保持灰化；卡片本身还在，告诉玩家「这里有间铺子」。
func _refresh_hotspot_locks() -> void:
	var card := _hotspot_cards.get(UIKeys.MERCHANT) as HotspotCard
	if card == null:
		return
	var unlocked := GameState.is_merchant_unlocked()
	card.dimmed = not unlocked
	if unlocked:
		var base := String(card.get_meta(&"base_subtitle", "ui.hotspot.merchant_subtitle"))
		card.subtitle = I18n.t(base)
	else:
		card.subtitle = I18n.t("ui.hotspot.merchant_locked")


## 房间入口的红点只有「图鉴」有：新发现是 HUD 与入口卡共用的同一份语义
func _refresh_hotspot_dots() -> void:
	var catalog_card := _hotspot_cards.get(UIKeys.CATALOG) as HotspotCard
	if catalog_card != null and is_instance_valid(catalog_card):
		catalog_card.dot = GameState.get_catalog_new_count() > 0


## 研究台提示只要「还有没试出来的菜」就亮着；全部试出来之后把右栏换回日常文案。
## 只在状态真的翻转时重建三张卡，免得每次材料变化都把卡片闪一遍。
func _refresh_research_hint() -> void:
	var active := GameState.has_unresearched_recipes()
	if active == _research_hint_active:
		return
	_research_hint_active = active
	PanelKit.clear(_right_rail)
	# 右栏重建后 _build_hotspots 会用新卡覆盖字典里的对应项；左栏不重建，别误清。
	_build_hotspots(_right_rail, RIGHT_HOTSPOTS)
	_refresh_hotspot_dots()
	if _tutorial_bar != null:
		_tutorial_bar.refresh_target()


## 读档后桌上的在制品已换成存档里的，签名也作废，重建一次
func _on_state_restored(_event: Event) -> void:
	_table_signature = ""
	_refresh_table()
	_refresh_research_hint()


## 房间是固定 1280×720 的一张桌子：窗口比它宽或比它高时，多出来的地方是纸面与地板，
## 而不是黑边。`window/stretch/aspect="expand"` 只让视口在一个方向上变大，所以这里
## 只需要把房间居中；HUD 也贴着这块矩形，免得它在宽屏上飘到屏幕边缘、跟桌子脱开。
func _layout_room() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var origin := ((viewport_size - ROOM_SIZE) * 0.5).round()
	_room.position = origin
	_room.size = ROOM_SIZE
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.position = origin
	_hud.size = ROOM_SIZE
	if _tutorial_bar != null:
		_tutorial_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_tutorial_bar.position = origin
		_tutorial_bar.size = ROOM_SIZE


# --- 房间入口 -------------------------------------------------------------


## 切语言：房间入口与桌面都要重译；桌面用清签名强制重建
func _on_language_changed(_event: Event) -> void:
	PanelKit.clear(_left_rail)
	PanelKit.clear(_right_rail)
	_hotspot_cards.clear()
	_build_hotspots(_left_rail, LEFT_HOTSPOTS)
	_build_hotspots(_right_rail, RIGHT_HOTSPOTS)
	_refresh_hotspot_dots()
	_table_signature = ""
	_refresh_table()
	if _tutorial_bar != null:
		_tutorial_bar.refresh_target()


func _build_hotspots(rail: VBoxContainer, entries: Array) -> void:
	for entry in entries:
		var card := HotspotCard.new()
		var panel_id := String(entry["panel"])
		card.title = I18n.t(String(entry["title"]))
		# 还有没试出来的菜：桌面这张卡换成一句「去试试」。
		# 不补发信（读过的信不会再读一遍），靠桌面这次常驻提醒把人领过去。
		var subtitle_key := String(entry["subtitle"])
		if panel_id == UIKeys.RESEARCH and GameState.has_unresearched_recipes():
			subtitle_key = "ui.hotspot.research_subtitle_hint"
		card.subtitle = I18n.t(subtitle_key)
		card.set_meta(&"base_subtitle", subtitle_key)
		card.icon_path = PanelKit.ICON_ROOT + String(entry["icon"])
		if entry.has("accent"):
			card.accent = entry["accent"]
		if entry.has("tilt"):
			card.tilt = float(entry["tilt"])
		card.pressed.connect(func() -> void: _bridge.toggle_panel(panel_id))
		rail.add_child(card)
		_hotspot_cards[panel_id] = card


## 桌面白纸投下的影子：只有一张纸，右下那圈渐隐说明它离桌面有多高
func _add_table_shadow() -> void:
	var shadow := PanelKit.cast_shadow(6, 1.1)
	_table.add_child(shadow)
	_table.move_child(shadow, 0)


## 桌角贴一条胶带：纯装饰，让那块白纸看起来是「贴上去的一张纸」
func _add_tape() -> void:
	var strip := PanelContainer.new()
	var style := PanelKit.slab(Color(0.984, 0.988, 0.996, 0.72), Color(0.13, 0.19, 0.24, 0.35), 2, 1)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	strip.add_theme_stylebox_override("panel", style)
	strip.custom_minimum_size = Vector2(104, 26)
	strip.position = Vector2(6, -13)
	strip.pivot_offset = Vector2(52, 13)
	strip.rotation = deg_to_rad(-7.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.add_child(strip)


# --- 桌面 -----------------------------------------------------------------


## 结构变了才重建；没变就只更新进度条，避免每 0.2 秒把节点拆了重装
func _refresh_table() -> void:
	var signature := _table_signature_now()
	if signature != _table_signature:
		_table_signature = signature
		_rebuild_table()
		return
	_update_bars()


func _table_signature_now() -> String:
	var parts: Array[String] = []
	for job in GameState.get_jobs():
		parts.append("c:%s" % job.recipe_key)
	for job in GameState.get_research_jobs():
		parts.append("r:%s" % job.signature)
	parts.append("m:%d" % _owned_material_count())
	return "|".join(parts)


func _rebuild_table() -> void:
	PanelKit.clear(_table_box)
	_bar_jobs.clear()
	_bars.clear()
	_time_labels.clear()

	_table_box.add_child(_table_header())
	_table_box.add_child(PanelKit.divider())

	var jobs := GameState.get_jobs()
	var research_jobs := GameState.get_research_jobs()
	if jobs.is_empty() and research_jobs.is_empty():
		_table_box.add_child(_empty_state())
	else:
		for job in jobs:
			_table_box.add_child(_craft_row(job))
		for job in research_jobs:
			_table_box.add_child(_research_row(job))

	_table_box.add_child(PanelKit.vspacer())
	_table_box.add_child(PanelKit.divider())
	_table_box.add_child(_table_footer())
	_update_bars()


func _table_header() -> Control:
	var row := PanelKit.hbox(10)
	row.add_child(PanelKit.title(I18n.t("ui.table.title")))
	row.add_child(PanelKit.spacer())
	row.add_child(PanelKit.caption(I18n.t("ui.table.caption")))
	return row


## 空桌面也别说教：一幅小画 + 一句状态 + 一个去处
func _empty_state() -> Control:
	var box := PanelKit.vbox(10)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var mark := PanelKit.icon("food/water_cup.svg", 78.0, PanelKit.INK_DIM)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)

	var head := PanelKit.label(I18n.t("ui.table.empty"), 24, PanelKit.INK_SOFT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	var sub := PanelKit.label(I18n.t("ui.table.empty_hint"), 16, PanelKit.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var go := PanelKit.sticker(I18n.t("ui.table.go_stove"), "food/water_cup.svg", Sfx.Intent.CLICK, 18.0)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void: _bridge.toggle_panel(UIKeys.CRAFT))
	box.add_child(go)
	return box


func _craft_row(job: CraftJob) -> Control:
	var recipe := _def_of(job.recipe_key) as RecipeDef
	var output: ItemDef = null
	if recipe != null:
		output = _def_of(recipe.output) as ItemDef
	var name_text := I18n.t("ui.table.thing")
	if output != null:
		name_text = output.localized()
	elif recipe != null:
		name_text = recipe.localized()
	if output != null and recipe != null:
		var icon_path := ItemIcons.path_for(output, recipe.group)
		var badge := ItemBadge.new()
		badge.configure(icon_path, name_text, ItemIcons.accent_for(icon_path), 34.0)
		return _progress_row(badge, name_text, job)
	var fallback := ItemBadge.new()
	fallback.configure("dish/main.svg", name_text, ItemIcons.accent_for("dish/main.svg"), 34.0)
	return _progress_row(fallback, name_text, job)


func _research_row(job: ResearchJob) -> Control:
	var names: Array[String] = []
	for key in job.materials:
		var def := _def_of(key) as ItemDef
		names.append(def.localized() if def != null else key)
	var text := I18n.t("ui.table.research_title", [" + ".join(names)])
	var mark := PanelKit.icon("ui/puzzle.svg", 22.0, PanelKit.ACCENT)
	return _progress_row(mark, text, job)


## 一行「在做的东西」：左边一个记号；右边第一行是名字与倒计时，第二行是进度条
func _progress_row(mark: Control, text: String, job: RefCounted) -> Control:
	var row := PanelKit.hbox(14)

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(44, 44)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10, 2))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(mark)
	row.add_child(holder)

	var center := PanelKit.vbox(5)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(center)

	var head := PanelKit.hbox(10)
	center.add_child(head)
	var title := PanelKit.label(text, 19, PanelKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = text
	head.add_child(title)

	var time_label := PanelKit.label("", 17, PanelKit.INK_SOFT)
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(time_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 10.0
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.add_theme_stylebox_override("background", PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.INK, 5, 1))
	var fill := PanelKit.slab(PanelKit.ACCENT, PanelKit.ACCENT, 5, 0)
	fill.content_margin_top = 0.0
	fill.content_margin_bottom = 0.0
	bar.add_theme_stylebox_override("fill", fill)
	center.add_child(bar)

	_bar_jobs.append(job)
	_bars.append(bar)
	_time_labels.append(time_label)
	return row


func _update_bars() -> void:
	for i in _bars.size():
		if i >= _bar_jobs.size():
			return
		var job := _bar_jobs[i]
		var bar := _bars[i]
		var time_label := _time_labels[i]
		if job == null or bar == null or not is_instance_valid(bar):
			continue
		var remaining := 0.0
		if job is CraftJob:
			remaining = (job as CraftJob).remaining_seconds
		elif job is ResearchJob:
			remaining = (job as ResearchJob).remaining_seconds
		bar.value = _job_progress(job)
		time_label.text = PanelKit.duration_text(remaining)


func _job_progress(job: RefCounted) -> float:
	if job is CraftJob:
		return (job as CraftJob).progress()
	if job is ResearchJob:
		return (job as ResearchJob).progress()
	return 0.0


func _table_footer() -> Control:
	var row := PanelKit.hbox(12)
	row.add_child(PanelKit.caption(I18n.t("ui.table.materials_count", [_owned_material_count()])))
	row.add_child(PanelKit.spacer())
	var button := PanelKit.sticker(I18n.t("ui.table.view_warehouse"), "ui/book.svg", Sfx.Intent.NONE, 18.0)
	button.pressed.connect(_open_warehouse)
	row.add_child(button)
	return row


## 仓库入口：清点手上有什么、卖东西、升级产地，都在这一个面板里
func _open_warehouse() -> void:
	_bridge.open_panel(UIKeys.WAREHOUSE)


# --- 小工具 ---------------------------------------------------------------


func _owned_material_count() -> int:
	var count := 0
	for def in _catalog_materials():
		if GameState.get_amount(def.get_key()) > 0.05:
			count += 1
	return count


func _catalog_materials() -> Array[GameDef]:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return []
	var materials := registry.get_defs_of_type("item")
	materials = materials.filter(func(def: GameDef) -> bool:
		var material := def as ItemDef
		return material != null and material.is_material() and not material.is_free()
	)
	return materials


func _def_of(key: String) -> GameDef:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return null
	return registry.get_def(key)
