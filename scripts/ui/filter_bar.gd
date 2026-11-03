class_name FilterBar
extends HBoxContainer
## 列表页的检索条：搜索 + 分段筛选 + 「更多筛选」浮层 + 分组 + 排序。
##
## 它只摆控件、记当前选择、发 `changed`；**不碰**筛选逻辑——哪些条目留下、
## 搜索能不能碰到未记录的名字，仍然是各面板自己的事（图鉴的防剧透、
## 商店的持有量都在各自面板里）。
##
## 分级用法（用户 2026-10-27 拍板「检索可以分级」）：
## - 条目少、一眼扫得完：只 `add_search()`；
## - 记录态这类「必须一眼看见」的维度：`add_segments()`；
## - 主题 / 标签这类维度多、平时用不上的：`add_menu_group()`，收进浮层；
## - 想按产地或价格看：`add_group()` / `add_sort()`，都是玩家自己选的下拉。
##
## 浮层用 `PopupPanel` 而不是自绘覆盖层：点外面自动关、自动定位、关掉把焦点
## 还给按钮，这三件引擎已经做好了。自绘一层要自己接鼠标与焦点，B 批刚把焦点
## 链接通，不值得为这点视觉再拆一遍。

## 任何筛选状态变化（搜索词 / 分段 / 浮层里的组 / 分组 / 排序）
signal changed

## 芯片 / 下拉 / 搜索框的基准高。36 → 32（2026-10-28 SC-07）：保住 32px 命中区，
## 同时把工具条压到由搜索框（41px）决定的高度——chip 再矮也不会更低，除非动搜索框。
const CHIP_HEIGHT := 32.0
## 浮层最小宽度：两排八个主题芯片刚好放得下
const MENU_WIDTH := 360.0
## 浮层里组区至少留这么高：再矮就只看得见一行，不如滚一滚
const MENU_MIN_GROUPS_HEIGHT := 120.0
## 浮层高度上限跟着宿主面板走：面板 648 高，浮层窗口约 600 高，比面板矮一点。
## 开集标签会继续变多，这里给的是上限，不是强行拉满——内容少时仍按内容高。
const MENU_PANEL_INSET := 48.0
const MENU_SCREEN_MARGIN := 8.0
## PopupPanel 的 panel stylebox 会在内层尺寸外再留一圈；定位时按实际窗口尺寸留边。
const MENU_HEIGHT_SLACK := 32.0
const MENU_WIDTH_SLACK := 40.0
## 组与组、标题与芯片行、芯片之间的间距，和 _ensure_menu 里保持一致
const MENU_GROUP_GAP := 8.0
const MENU_TITLE_GAP := 8.0
const MENU_CHIP_H_GAP := 8.0
const MENU_CHIP_V_GAP := 6.0
## 估算换行时每行可用宽度的安全余量。ScrollContainer 出现竖向滚动条会吃掉十几像素，
## 而滚动条宽度跟主题与平台有关（Linux 默认主题就比 Windows 宽），自己按芯片宽估行数
## 一旦少算一行，浮层就只露出半截标签 —— CI 上就是这么红的。宁可保守，多算一行。
const MENU_ROW_SAFETY := 16.0

var _search: LineEdit = null
var _search_key: String = ""
var _result_label: Label = null
## 分段维度：id -> 当前值（int）
var _segments: Dictionary = {}
## 分段维度：id -> Array[Button]、id -> Array[String]（与按钮一一对应的翻译键）
var _segment_chips: Dictionary = {}
var _segment_keys: Dictionary = {}
var _menu_button: Button = null
var _menu_popup: PopupPanel = null
var _menu_panel: VBoxContainer = null
var _menu_scroll: ScrollContainer = null
var _menu_groups_box: VBoxContainer = null
var _menu_footer: Control = null
## 浮层里的组：{"id", "title_key", "title", "options", "chips", "keys", "value"}
var _menu_groups: Array[Dictionary] = []
var _group_option: OptionButton = null
var _group_specs: Array = []
var _group_current: String = ""
var _sort_option: OptionButton = null
var _sort_specs: Array = []
var _sort_current: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 10)


# --- 搭积木 ---------------------------------------------------------------


## 搜索框。宽度给个下限：再窄就看不到自己打了几个字；但不封顶，剩下的空间都归它。
## 下限压到 150（不是 190）：英文图鉴一行要放下搜索 + 三个记录态 + 筛选 + 两个下拉，
## 搜索框给 190 会把整条顶出面板（实测英文面板被撑宽 64px）。
func add_search(placeholder_key: String, min_width: float = 150.0, initial: String = "") -> LineEdit:
	_search_key = placeholder_key
	_search = LineEdit.new()
	_search.placeholder_text = I18n.t(placeholder_key)
	_search.text = initial
	_search.custom_minimum_size = Vector2(min_width, CHIP_HEIGHT)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.text_changed.connect(_on_search_changed)
	add_child(_search)
	return _search


## 一排常驻的单选芯片（记录态这类）。`options` 是 [{"value": 0, "key": "ui.…"}]，
## 第一项即默认值。芯片文案存的是翻译键，切语言时能就地重翻。
func add_segments(id: String, options: Array, initial: int = 0) -> void:
	if options.is_empty():
		return
	_segments[id] = initial
	var group := ButtonGroup.new()
	var chips: Array[Button] = []
	var keys: Array[String] = []
	for spec in options:
		var value := int(spec["value"])
		var key := String(spec["key"])
		var chip := _chip(I18n.t(key), value == initial, group)
		chip.pressed.connect(_on_segment_pressed.bind(id, value))
		add_child(chip)
		chips.append(chip)
		keys.append(key)
	_segment_chips[id] = chips
	_segment_keys[id] = keys


## 浮层里的一个组（主题、标签这类）。第一次调用时把「筛选」按钮建出来，
## 所以它要排在分段芯片之后、分组下拉之前调用。
## `options` 用 `label`（数据层已经翻好的名字）或 `key`（翻译键）都行。
func add_menu_group(group_id: String, title_key: String, options: Array, initial: String = "") -> void:
	_ensure_menu()
	var current := initial
	var title := PanelKit.label(I18n.t(title_key), 17, PanelKit.INK_SOFT)
	_menu_groups_box.add_child(title)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	_menu_groups_box.add_child(row)
	var group := ButtonGroup.new()
	var chips: Array[Button] = []
	for spec in options:
		var key := String(spec["value"])
		var chip := _chip(_option_label(spec), key == current, group)
		chip.pressed.connect(_on_menu_pressed.bind(group_id, key))
		row.add_child(chip)
		chips.append(chip)
	_menu_groups.append({
		"id": group_id,
		"title_key": title_key,
		"title": title,
		"options": options,
		"chips": chips,
		"value": current,
	})
	_refresh_menu_button_text()


## 分组下拉：玩家自己决定这一屏按什么分堆。`options` 是 [{"value": "", "key": "ui.…"}]。
func add_group(options: Array, current: String = "") -> OptionButton:
	_group_specs = options
	_group_current = current
	_group_option = PanelKit.option_button(112.0)
	_group_option.custom_minimum_size.y = CHIP_HEIGHT
	_group_option.add_theme_font_size_override("font_size", 13)
	_group_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PanelKit.tooltip(_group_option, I18n.t("ui.filter.group_tip"))
	_fill_option(_group_option, options, current)
	_group_option.item_selected.connect(_on_group_selected)
	add_child(_group_option)
	return _group_option


## 排序下拉：同一份数据按什么顺序摊开。
func add_sort(options: Array, current: String = "") -> OptionButton:
	_sort_specs = options
	_sort_current = current
	_sort_option = PanelKit.option_button(112.0)
	_sort_option.custom_minimum_size.y = CHIP_HEIGHT
	_sort_option.add_theme_font_size_override("font_size", 13)
	_sort_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PanelKit.tooltip(_sort_option, I18n.t("ui.filter.sort_tip"))
	_fill_option(_sort_option, options, current)
	_sort_option.item_selected.connect(_on_sort_selected)
	add_child(_sort_option)
	return _sort_option


## 命中条数，挂在最右边。面板每次重填列表时写进来，FilterBar 只负责显示。
func set_result_text(text: String) -> void:
	if text.is_empty():
		if _result_label != null:
			_result_label.text = ""
		return
	if _result_label == null:
		_result_label = PanelKit.hint_inline("")
		_result_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_result_label)
	_result_label.text = text


## 把光标送回搜索框（工具条重建之后调用）
func focus_search() -> void:
	if _search == null:
		return
	_search.grab_focus()
	_search.caret_column = _search.text.length()


# --- 读状态 ---------------------------------------------------------------


func get_keyword() -> String:
	return "" if _search == null else _search.text


func get_segment(id: String) -> int:
	return int(_segments.get(id, 0))


func get_menu_value(group_id: String) -> String:
	return _menu_value(group_id)


func get_group() -> String:
	return _group_current


func get_sort() -> String:
	return _sort_current


## 浮层开着的组数，给「筛选」按钮加角标用
func active_menu_count() -> int:
	var total := 0
	for group in _menu_groups:
		if not String(group["value"]).is_empty():
			total += 1
	return total


# --- 内部 -----------------------------------------------------------------


func _on_search_changed(_text: String) -> void:
	changed.emit()


func _on_segment_pressed(id: String, value: int) -> void:
	if int(_segments.get(id, 0)) == value:
		return
	_segments[id] = value
	changed.emit()


func _on_menu_pressed(group_id: String, key: String) -> void:
	for group in _menu_groups:
		if String(group["id"]) == group_id:
			group["value"] = key
			break
	_refresh_menu_button_text()
	changed.emit()


func _on_group_selected(index: int) -> void:
	_group_current = String(_group_option.get_item_metadata(index))
	changed.emit()


func _on_sort_selected(index: int) -> void:
	_sort_current = String(_sort_option.get_item_metadata(index))
	changed.emit()


func _menu_value(group_id: String) -> String:
	for group in _menu_groups:
		if String(group["id"]) == group_id:
			return String(group["value"])
	return ""


## 选项文字：数据层翻好的名字（label）优先，否则按翻译键取
func _option_label(spec: Dictionary) -> String:
	if spec.has("label"):
		return String(spec["label"])
	return I18n.t(String(spec["key"]))


## 芯片：选中是纸白底 + 强调色框，未选中是压在底下的浅纸 + 墨框（`PanelKit.selection_box()`，报告 §5.8）。
## hover 只把框换成强调色，底色不动 —— 免得悬停和选中分不出来。
func _chip(text: String, selected: bool, group: ButtonGroup) -> Button:
	var button := PanelKit.button(text, Sfx.Intent.NONE)
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	var off := PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.INK, 8, 2, false)
	var hover := PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.ACCENT, 8, 2, false)
	var on := PanelKit.selection_box(8)
	for style in [off, hover, on]:
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
	button.add_theme_stylebox_override("normal", off)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", on)
	button.add_theme_stylebox_override("hover_pressed", on)
	button.add_theme_color_override("font_color", PanelKit.INK)
	button.add_theme_color_override("font_hover_color", PanelKit.ACCENT_DEEP)
	button.add_theme_color_override("font_pressed_color", PanelKit.INK)
	button.add_theme_color_override("font_hover_pressed_color", PanelKit.INK)
	return button


func _fill_option(option: OptionButton, options: Array, current: String) -> void:
	if option == null:
		return
	option.clear()
	var selected := 0
	for index in options.size():
		var spec: Dictionary = options[index]
		option.add_item(_option_label(spec))
		option.set_item_metadata(index, String(spec["value"]))
		if String(spec["value"]) == current:
			selected = index
	option.selected = selected


func _ensure_menu() -> void:
	if _menu_popup != null:
		return
	_menu_button = PanelKit.button(I18n.t("ui.filter.more"), Sfx.Intent.NONE)
	_menu_button.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	_menu_button.add_theme_font_size_override("font_size", 13)
	# 工具条高度由最高的子控件决定：按钮默认样式（字号 19 + 11/13 内边距）会把整条
	# 撑到 45px，和 chip 的 32 打架。给它和 chip 同一套紧凑内边距，工具条高度
	# 就回落到搜索框的 41px（2026-10-28 SC-07，实测 45 → 41）。
	var compact_off := PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.INK, 8, 2, false)
	var compact_hover := PanelKit.slab(PanelKit.PAPER_BACK, PanelKit.ACCENT, 8, 2, false)
	for style in [compact_off, compact_hover]:
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
	_menu_button.add_theme_stylebox_override("normal", compact_off)
	_menu_button.add_theme_stylebox_override("hover", compact_hover)
	_menu_button.add_theme_stylebox_override("pressed", compact_hover)
	_menu_button.pressed.connect(_open_menu)
	add_child(_menu_button)

	_menu_popup = PopupPanel.new()
	_menu_popup.add_theme_stylebox_override("panel",
			PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 6, 2, false))
	_menu_popup.popup_hide.connect(_on_menu_hidden)
	add_child(_menu_popup)

	# PopupPanel 不是容器，内外边距要自己铺一层
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	_menu_popup.add_child(pad)

	_menu_panel = VBoxContainer.new()
	_menu_panel.custom_minimum_size = Vector2(MENU_WIDTH - 32.0, 0.0)
	_menu_panel.add_theme_constant_override("separation", 10)
	pad.add_child(_menu_panel)

	# 主题 / 标签是开集（内容会增，Mod 还会再添）：组区单独装进滚动框，
	# 浮层高度只跟屏幕走，不跟内容走。
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_panel.add_child(_menu_scroll)

	_menu_groups_box = VBoxContainer.new()
	_menu_groups_box.add_theme_constant_override("separation", 8)
	_menu_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(_menu_groups_box)

	var footer := PanelKit.hbox(10)
	footer.add_child(PanelKit.spacer())
	var done := PanelKit.button(I18n.t("ui.filter.done"), Sfx.Intent.NONE)
	done.custom_minimum_size.y = CHIP_HEIGHT
	done.pressed.connect(func() -> void: _menu_popup.hide())
	footer.add_child(done)
	_menu_footer = footer
	_menu_panel.add_child(footer)


## 浮层高度由屏幕决定，不由内容决定：主题从 11 个涨到 40 个、或者 Mod 又塞进来
## 两打标签，浮层也只是里面滚一滚，不会顶出屏幕。
func _open_menu() -> void:
	if _menu_popup == null:
		return
	_menu_popup.popup(_menu_geometry(_menu_button.get_global_rect()))


func _menu_geometry(anchor: Rect2) -> Rect2i:
	const PAD_Y := 28.0        # MarginContainer 上下 14+14
	const SEPARATION := 10.0   # _menu_panel 的行距
	var view := get_viewport_rect().size
	# HFlowContainer 的 minimum_size 要等它真正有宽度并按宽度换行之后才算得准；
	# 首次打开时直接读它，会把「三行标签」当成「一行」，浮层就只有一条缝。
	# 这里按芯片实际最小宽高自己算行数，首开就是最终高度，不需要二次 popup。
	var groups_wanted := _menu_groups_height()
	var footer_height := _menu_footer.get_combined_minimum_size().y
	var max_total := _menu_max_total_height()
	var groups_room := maxf(0.0, max_total - PAD_Y - footer_height - SEPARATION)
	var groups_height := minf(groups_wanted, maxf(MENU_MIN_GROUPS_HEIGHT, groups_room))
	_menu_scroll.custom_minimum_size.y = groups_height
	var wanted_height := groups_height + PAD_Y + footer_height + SEPARATION
	var host := _host_panel_rect()
	# 浮层可以比工具条下方那块空白更高：上限取宿主面板高度（面板本身已居中留边）。
	# PopupPanel 的 panel stylebox 会在 _menu_panel 外再留一圈，定位时按实际窗口补 slack。
	var top_floor := MENU_SCREEN_MARGIN
	var top_limit := view.y - wanted_height - MENU_SCREEN_MARGIN - MENU_HEIGHT_SLACK
	if host.size.y > 0.0:
		top_floor = maxf(top_floor, host.position.y + MENU_SCREEN_MARGIN)
		top_limit = minf(top_limit, host.end.y - wanted_height - MENU_SCREEN_MARGIN - MENU_HEIGHT_SLACK)
	var top := anchor.end.y + 6.0
	if top_limit >= top_floor:
		top = clampf(top, top_floor, top_limit)
	else:
		top = top_floor
	var wanted_width := maxf(_menu_panel.get_combined_minimum_size().x + 32.0, MENU_WIDTH)
	var left := anchor.position.x
	if host.size.x > 0.0:
		left = clampf(left, host.position.x + MENU_SCREEN_MARGIN,
				host.end.x - wanted_width - MENU_WIDTH_SLACK - MENU_SCREEN_MARGIN)
	else:
		left = clampf(left, MENU_SCREEN_MARGIN,
				view.x - wanted_width - MENU_WIDTH_SLACK - MENU_SCREEN_MARGIN)
	return Rect2i(int(left), int(top), int(wanted_width), int(wanted_height))


## HFlowContainer 在首次显示前拿不到真实换行高度，自己按芯片最小宽度估行数。
## 标题高、标题到芯片行、组与组、芯片之间的间距必须和 _ensure_menu 的常数一致。
func _menu_groups_height() -> float:
	var total := 0.0
	for index in _menu_groups.size():
		var group: Dictionary = _menu_groups[index]
		if index > 0:
			total += MENU_GROUP_GAP
		var title := group["title"] as Label
		total += title.get_combined_minimum_size().y + MENU_TITLE_GAP
		total += _menu_row_height(group["chips"])
	return total


func _menu_row_height(chips: Array) -> float:
	var width := 0.0
	var rows := 1
	for node in chips:
		var chip := node as Button
		var chip_width := chip.get_combined_minimum_size().x
		if width > 0.0 and width + MENU_CHIP_H_GAP + chip_width > MENU_WIDTH - 32.0 - MENU_ROW_SAFETY:
			rows += 1
			width = chip_width
		else:
			width += (MENU_CHIP_H_GAP if width > 0.0 else 0.0) + chip_width
	return rows * CHIP_HEIGHT + (rows - 1) * MENU_CHIP_V_GAP


## 浮层总高上限：优先跟随宿主面板，面板不在（测试或独立使用）时退回屏幕。
func _menu_max_total_height() -> float:
	var cap := get_viewport_rect().size.y - MENU_SCREEN_MARGIN * 2.0
	var host := _host_panel_rect()
	if host.size.y > 0.0:
		cap = minf(cap, host.size.y - MENU_PANEL_INSET)
	return cap


## 往上找 GamePanel：浮层挂在工具条上，但尺寸和位置要跟整张纸对齐。
func _host_panel_rect() -> Rect2:
	var node := get_parent()
	while node != null:
		if node is GamePanel:
			var panel := node as GamePanel
			# 面板根节点铺满视口；真正有边界的是居中那张纸。
			var paper := panel.get_paper_rect()
			if paper.size.x > 0.0 and paper.size.y > 0.0:
				return paper
			return panel.get_global_rect()
		node = node.get_parent()
	return Rect2()


func _on_menu_hidden() -> void:
	# 关掉浮层把焦点还给按钮：不然键盘玩家会停在一个「不存在的窗口」上
	if _menu_button != null and is_instance_valid(_menu_button):
		_menu_button.grab_focus()


func _refresh_menu_button_text() -> void:
	if _menu_button == null:
		return
	var active := active_menu_count()
	if active <= 0:
		_menu_button.text = I18n.t("ui.filter.more")
	else:
		_menu_button.text = I18n.t("ui.filter.more_count", [active])


## 切语言：芯片、下拉、占位符按存下来的翻译键重算一遍，不重建控件。
## 浮层里的组用的是数据层翻好的名字，切语言时整个工具条本来就会重建，这里不必管。
func retranslate() -> void:
	if _search != null:
		_search.placeholder_text = I18n.t(_search_key)
	for id in _segment_chips:
		var chips: Array = _segment_chips[id]
		var keys: Array = _segment_keys[id]
		for index in chips.size():
			(chips[index] as Button).text = I18n.t(String(keys[index]))
	_fill_option(_group_option, _group_specs, _group_current)
	_fill_option(_sort_option, _sort_specs, _sort_current)
	_refresh_menu_button_text()

