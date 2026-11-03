class_name RecipeCard
extends PanelContainer
## 灶台左列的菜卡：图标章 + 持有数 / 整宽名称（悬停跑马灯）/ 进度条。
## 名称用成品名（ItemDef.localized），配方动词名只在右列详情当副标题。

signal activated(recipe_key: String)

# 左列 474 宽、减去内部滚动条 10，三列加两道 10 间距后每张约 148（规范①）
const CARD_SIZE := Vector2(147, 86)
const BADGE_SIZE := 28.0
# 小卡片不套面板那种 20/16 的大边距，否则 86 高会被撑到 109
const CARD_MARGIN := Vector2(6, 4)

var recipe_key := ""
var _marquee: MarqueeLabel
var _badge: ItemBadge
var _have_label: Label
var _need_label: Label
var _guided_label: Label
var _uncrafted_label: Label
var _bars: JobBars
var _output_name := ""
var _selected := false
var _craftable := true
var _missing_facility := ""
var _guided := false
## 图鉴里还没记录过：右上角挂一个「新」字提示，不改变可做性与顺序
var _uncrafted := false
var _have_amount := -1
var _pending_recipe: RecipeDef
var _pending_output: ItemDef


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	_refresh_style()
	if _pending_recipe != null:
		_apply_setup(_pending_recipe, _pending_output)
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
	_guided_label = PanelKit.label(I18n.t("ui.craft.card_guided"), 11, PanelKit.ACCENT_DEEP)
	_guided_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_guided_label.visible = false
	top.add_child(_guided_label)
	_uncrafted_label = PanelKit.label(I18n.t("ui.craft.card_new"), 14, PanelKit.ACCENT_DEEP)
	_uncrafted_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_uncrafted_label.visible = false
	top.add_child(_uncrafted_label)
	top.add_child(PanelKit.spacer())
	_have_label = PanelKit.label("--", 14, PanelKit.INK_SOFT)
	_have_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_have_label)
	column.add_child(top)

	_marquee = MarqueeLabel.new()
	_marquee.custom_minimum_size.y = 21.0
	_marquee.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_marquee)

	# 末行固定 15 高：有活时画进度段，缺设备时盖一行小字。
	# 两者共用同一块高度，行高才不会因为配方不同跳来跳去（规范②）。
	var bottom := Control.new()
	bottom.custom_minimum_size.y = 15.0
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	_bars = JobBars.new()
	_bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bars.offset_top = 2.0
	_bars.offset_bottom = -3.0
	bottom.add_child(_bars)
	_need_label = PanelKit.label("", 12, PanelKit.DANGER_DEEP)
	_need_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_need_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_need_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_need_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_need_label.visible = false
	bottom.add_child(_need_label)


func setup(recipe: RecipeDef, output: ItemDef, selected: bool, craftable: bool, missing_facility: String) -> void:
	recipe_key = recipe.get_key()
	_selected = selected
	_craftable = craftable
	_missing_facility = missing_facility
	_output_name = output.localized() if output != null else recipe.localized()
	_pending_recipe = recipe
	_pending_output = output
	if _marquee != null:
		_apply_setup(recipe, output)


func _apply_setup(recipe: RecipeDef, output: ItemDef) -> void:
	if _marquee == null:
		return
	_marquee.set_text(_output_name, 17, PanelKit.INK)
	PanelKit.tooltip(self, _output_name)
	if output != null:
		var icon_path := ItemIcons.path_for(output, recipe.group)
		_badge.configure(icon_path, _output_name, ItemIcons.accent_for(icon_path), BADGE_SIZE)
	set_selected(_selected)
	set_craftable(_craftable)
	set_missing_facility(_missing_facility)
	set_guided(_guided)
	set_uncrafted(_uncrafted)


## 图标归类统一走 ItemIcons：五族材料 / 六族菜品，不在卡片里另写一份规则。

func set_selected(value: bool) -> void:
	_selected = value
	_refresh_style()


func set_craftable(value: bool) -> void:
	if _craftable == value:
		return
	_craftable = value
	_update_tint()


func set_missing_facility(facility_name: String) -> void:
	_missing_facility = facility_name
	if _need_label != null:
		_need_label.text = "" if facility_name.is_empty() else I18n.t("ui.craft.card_need_facility", [facility_name])
		_need_label.visible = not facility_name.is_empty()
	if _bars != null:
		_bars.visible = facility_name.is_empty()


## 这张卡是当前委托点名要做的菜：左上角加一个「委托」，不改变筛选与顺序。
func set_guided(value: bool) -> void:
	_guided = value
	if _guided_label != null:
		_guided_label.visible = value


## 图鉴还没收过这道菜：挂「新」提醒；只是标记，不改可做性、不改顺序。
func set_uncrafted(value: bool) -> void:
	_uncrafted = value
	if _uncrafted_label != null:
		_uncrafted_label.visible = value


func set_have(amount: int) -> void:
	if _have_label == null or _have_amount == amount:
		return
	_have_amount = amount
	_have_label.text = "--" if amount <= 0 else "×%d" % amount


func set_jobs(jobs: Array[CraftJob]) -> void:
	if _bars == null:
		return
	if jobs.is_empty():
		_bars.set_segments([], 0)
		return
	var segments: Array[Dictionary] = []
	for job in jobs:
		segments.append({
			"progress": clampf(job.progress(), 0.0, 1.0),
			"color": _job_color(job),
		})
	var extra := maxi(0, segments.size() - JobBars.MAX_SEGMENTS)
	if segments.size() > JobBars.MAX_SEGMENTS:
		segments = segments.slice(0, JobBars.MAX_SEGMENTS)
	_bars.set_segments(segments, extra)


func _job_color(job: CraftJob) -> Color:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	var facility: FacilityDef = null
	if registry != null:
		facility = registry.get_def(job.facility_key) as FacilityDef
	return facility.display_accent() if facility != null else PanelKit.ACCENT


func _refresh_style() -> void:
	if not is_inside_tree():
		return
	var base := PanelKit.slab(PanelKit.CARD, PanelKit.INK, 8, 2)
	var active := PanelKit.selection_box(8, 6, false, PanelKit.SELECT_FILL)
	for box in [base, active]:
		var slab := box as StyleBoxFlat
		slab.content_margin_left = CARD_MARGIN.x
		slab.content_margin_right = CARD_MARGIN.x
		slab.content_margin_top = CARD_MARGIN.y
		slab.content_margin_bottom = CARD_MARGIN.y
	add_theme_stylebox_override("panel", active if _selected else base)
	_update_tint()


func _update_tint() -> void:
	if not _selected:
		modulate = Color(1, 1, 1, 1) if _craftable else Color(0.62, 0.62, 0.62, 1.0)
	else:
		modulate = Color(1, 1, 1, 1)


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
	activated.emit(recipe_key)