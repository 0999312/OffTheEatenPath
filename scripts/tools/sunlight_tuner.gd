extends Control
## 车窗光调参器（开发工具，不进入游戏主流程）。
##
## 直接实例化 main.tscn，把 Backdrop/Sunlight 的材质参数实时写到 shader 上。
## 只操作参数；shader 算法来自用户提供的 GodotShaders God Rays，不改。
##
## 运行：godot --path . res://scenes/tools/sunlight_tuner.tscn
const MAIN_SCENE := preload("res://scenes/screens/main.tscn")
const THEME := preload("res://resources/themes/paper_theme.tres")

const PARAM_SPECS := [
	{"key": "angle", "label": "angle", "min": -2.0, "max": 2.0, "step": 0.01},
	{"key": "position", "label": "position", "min": -1.0, "max": 1.0, "step": 0.01},
	{"key": "spread", "label": "spread", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "cutoff", "label": "cutoff", "min": 0.0, "max": 0.6, "step": 0.005},
	{"key": "falloff", "label": "falloff", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "edge_fade", "label": "edge_fade", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "speed", "label": "speed", "min": 0.0, "max": 4.0, "step": 0.01},
	{"key": "ray1_density", "label": "ray1_density", "min": 1.0, "max": 64.0, "step": 1.0},
	{"key": "ray2_density", "label": "ray2_density", "min": 1.0, "max": 64.0, "step": 1.0},
	{"key": "ray2_intensity", "label": "ray2_intensity", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "seed", "label": "seed", "min": 0.0, "max": 100.0, "step": 1.0},
]

const COPY_ORDER := [
	"angle", "position", "spread", "cutoff", "falloff", "edge_fade", "speed",
	"ray1_density", "ray2_density", "ray2_intensity", "color", "hdr", "seed",
]

const PROPERTY_NAMES := {
	"position": "beam_position",
	"color": "ray_color",
	"seed": "noise_seed",
}

## 试出来的一束主光 + 少量细光，方向按「右侧车窗 → 左侧」。
const RECOMMENDED := {
	"angle": 1.0,
	"position": 0.15,
	"spread": 0.5,
	"cutoff": 0.18,
	"falloff": 0.2,
	"edge_fade": 0.15,
	"speed": 1.0,
	"ray1_density": 4.0,
	"ray2_density": 40.0,
	"ray2_intensity": 0.35,
	"color": Color(1.0, 0.9, 0.65, 0.6),
	"hdr": true,
	"seed": 5.0,
}

## 用户 shader 原版默认值，方便对照。
const ORIGINAL := {
	"angle": -0.3,
	"position": -0.2,
	"spread": 0.5,
	"cutoff": 0.1,
	"falloff": 0.2,
	"edge_fade": 0.15,
	"speed": 1.0,
	"ray1_density": 8.0,
	"ray2_density": 30.0,
	"ray2_intensity": 0.3,
	"color": Color(1.0, 0.9, 0.65, 0.8),
	"hdr": false,
	"seed": 5.0,
}

var _main: Control
var _sun: ColorRect
var _values: Dictionary = {}
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _color_picker: ColorPickerButton
var _color_alpha_slider: HSlider
var _color_alpha_label: Label
var _hdr_check: CheckButton
var _background_check: CheckButton
var _status: Label
var _syncing := false


func _ready() -> void:
	theme = THEME
	_build_game()
	_build_panel()
	_sync_controls()
	_apply_to_layer()
	_status.text = "实时调参：拖动滑杆即可。复制参数后贴回 sunlight_layer.gd。"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _build_game() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bridge := _main.get_node_or_null("GameBridge")
	if bridge != null:
		bridge.set("save", SaveGame.new("user://sunlight_tuner_save.json"))
		bridge.set_process(false)
		bridge.set_physics_process(false)
	GameState.reset()
	UIManager.close_all()
	_sun = _main.get_node_or_null("Backdrop/Sunlight") as ColorRect
	if _sun == null:
		push_error("SunlightTuner: 找不到 Backdrop/Sunlight")
		return
	_values = {
		"angle": float(_sun.get("angle")),
		"position": float(_sun.get("beam_position")),
		"spread": float(_sun.get("spread")),
		"cutoff": float(_sun.get("cutoff")),
		"falloff": float(_sun.get("falloff")),
		"edge_fade": float(_sun.get("edge_fade")),
		"speed": float(_sun.get("speed")),
		"ray1_density": float(_sun.get("ray1_density")),
		"ray2_density": float(_sun.get("ray2_density")),
		"ray2_intensity": float(_sun.get("ray2_intensity")),
		"color": _sun.get("ray_color") as Color,
		"hdr": bool(_sun.get("hdr")),
		"seed": float(_sun.get("noise_seed")),
	}


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TunerLayer"
	layer.layer = 500
	add_child(layer)

	var dock := PanelContainer.new()
	dock.name = "Dock"
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.0
	dock.anchor_bottom = 1.0
	dock.offset_left = -396.0
	dock.offset_right = -12.0
	dock.offset_top = 12.0
	dock.offset_bottom = -12.0
	dock.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(dock)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	dock.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := PanelKit.label("God Rays 调参", 24, PanelKit.INK)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := PanelKit.button("退出")
	close_button.pressed.connect(get_tree().quit)
	header.add_child(close_button)
	column.add_child(header)

	var subtitle := PanelKit.hint("灯光工具：只改参数，不改光形。调好后点「复制参数」。", 0.0)
	column.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for spec in PARAM_SPECS:
		list.add_child(_make_numeric_row(spec))

	list.add_child(HSeparator.new())
	list.add_child(_make_color_row())
	list.add_child(_make_color_alpha_row())
	list.add_child(_make_hdr_row())

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	var recommended := PanelKit.primary_button("推荐：一大束")
	recommended.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recommended.tooltip_text = "右侧车窗入射的一束主光 + 少量细光"
	recommended.pressed.connect(_apply_recommended)
	preset_row.add_child(recommended)
	var original := PanelKit.button("原版默认")
	original.pressed.connect(_apply_original)
	preset_row.add_child(original)
	list.add_child(preset_row)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	var copy_button := PanelKit.primary_button("复制参数")
	copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button.pressed.connect(_copy_params)
	action_row.add_child(copy_button)
	var reset_button := PanelKit.button("重置")
	reset_button.pressed.connect(_apply_original)
	action_row.add_child(reset_button)
	list.add_child(action_row)

	_background_check = CheckButton.new()
	_background_check.text = "只看背景（隐藏房间和 UI）"
	_background_check.add_theme_color_override("font_color", PanelKit.INK_SOFT)
	_background_check.add_theme_color_override("font_hover_color", PanelKit.INK)
	_background_check.add_theme_color_override("font_pressed_color", PanelKit.INK)
	_background_check.toggled.connect(_on_background_only_toggled)
	list.add_child(_background_check)

	_status = PanelKit.hint("", 0.0)
	list.add_child(_status)


func _make_numeric_row(spec: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := PanelKit.label(str(spec["label"]), 14, PanelKit.INK_SOFT)
	label.custom_minimum_size.x = 96.0
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = float(spec["min"])
	slider.max_value = float(spec["max"])
	slider.step = float(spec["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0.0, 18.0)
	slider.value = float(_values.get(spec["key"], 0.0))
	slider.value_changed.connect(_on_numeric_changed.bind(str(spec["key"])))
	row.add_child(slider)
	_sliders[spec["key"]] = slider

	var value_label := PanelKit.label("", 13, PanelKit.INK_SOFT)
	value_label.custom_minimum_size.x = 58.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)
	_value_labels[spec["key"]] = value_label
	_update_value_label(str(spec["key"]))
	return row


func _make_color_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := PanelKit.label("color", 14, PanelKit.INK_SOFT)
	label.custom_minimum_size.x = 96.0
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_color_picker = ColorPickerButton.new()
	# alpha 单独用一条滑杆；ColorPickerButton 带 edit_alpha 时在当前主题里只显示棋盘格。
	_color_picker.edit_alpha = false
	_color_picker.color = _opaque_color(_values.get("color", Color.WHITE) as Color)
	_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_picker.custom_minimum_size = Vector2(0.0, 30.0)
	_color_picker.color_changed.connect(_on_color_changed)
	row.add_child(_color_picker)
	return row


func _make_color_alpha_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := PanelKit.label("color.a", 14, PanelKit.INK_SOFT)
	label.custom_minimum_size.x = 96.0
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_color_alpha_slider = HSlider.new()
	_color_alpha_slider.min_value = 0.0
	_color_alpha_slider.max_value = 1.0
	_color_alpha_slider.step = 0.01
	_color_alpha_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_alpha_slider.custom_minimum_size = Vector2(0.0, 18.0)
	_color_alpha_slider.value = (_values.get("color", Color.WHITE) as Color).a
	_color_alpha_slider.value_changed.connect(_on_color_alpha_changed)
	row.add_child(_color_alpha_slider)
	_color_alpha_label = PanelKit.label("", 13, PanelKit.INK_SOFT)
	_color_alpha_label.custom_minimum_size.x = 58.0
	_color_alpha_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_color_alpha_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_color_alpha_label)
	_update_color_alpha_label()
	return row


func _make_hdr_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := PanelKit.label("hdr", 14, PanelKit.INK_SOFT)
	label.custom_minimum_size.x = 96.0
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_hdr_check = CheckButton.new()
	_hdr_check.text = "不钳制 ray1 + ray2（更亮）"
	_hdr_check.add_theme_color_override("font_color", PanelKit.INK_SOFT)
	_hdr_check.add_theme_color_override("font_hover_color", PanelKit.INK)
	_hdr_check.add_theme_color_override("font_pressed_color", PanelKit.INK)
	_hdr_check.button_pressed = bool(_values.get("hdr", false))
	_hdr_check.toggled.connect(_on_hdr_toggled)
	row.add_child(_hdr_check)
	return row


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PanelKit.CARD
	style.border_color = PanelKit.INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _on_numeric_changed(value: float, key: String) -> void:
	if _syncing:
		return
	_values[key] = value
	_update_value_label(key)
	_apply_to_layer()


func _on_color_changed(color: Color) -> void:
	if _syncing:
		return
	var alpha := (_values.get("color", Color.WHITE) as Color).a
	_values["color"] = Color(color.r, color.g, color.b, alpha)
	_apply_to_layer()


func _on_color_alpha_changed(value: float) -> void:
	if _syncing:
		return
	var color := _values.get("color", Color.WHITE) as Color
	color.a = value
	_values["color"] = color
	_update_color_alpha_label()
	_apply_to_layer()


func _on_hdr_toggled(toggled: bool) -> void:
	if _syncing:
		return
	_values["hdr"] = toggled
	_apply_to_layer()


func _update_value_label(key: String) -> void:
	if not _value_labels.has(key):
		return
	var value := float(_values.get(key, 0.0))
	var text := "%.2f" % value
	if key in ["ray1_density", "ray2_density", "seed"]:
		text = "%.0f" % value
	elif key in ["angle", "position"]:
		text = "%+.2f" % value
	(_value_labels[key] as Label).text = text


func _update_color_alpha_label() -> void:
	if _color_alpha_label == null:
		return
	_color_alpha_label.text = "%.2f" % (_values.get("color", Color.WHITE) as Color).a


func _opaque_color(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)


func _sync_controls() -> void:
	_syncing = true
	for key in _sliders.keys():
		(_sliders[key] as HSlider).value = float(_values.get(key, 0.0))
		_update_value_label(key)
	if _color_picker != null:
		_color_picker.color = _opaque_color(_values.get("color", Color.WHITE) as Color)
	if _color_alpha_slider != null:
		_color_alpha_slider.value = (_values.get("color", Color.WHITE) as Color).a
		_update_color_alpha_label()
	if _hdr_check != null:
		_hdr_check.button_pressed = bool(_values.get("hdr", false))
	_syncing = false


func _apply_to_layer() -> void:
	if _sun == null:
		return
	for key in COPY_ORDER:
		var prop := str(PROPERTY_NAMES.get(key, key))
		_sun.set(prop, _values[key])
	if _sun.has_method("apply_parameters"):
		_sun.call("apply_parameters")


func _apply_recommended() -> void:
	_apply_set(RECOMMENDED)
	_status.text = "已应用：一大束主光 + 少量细光（右侧车窗）。"


func _apply_original() -> void:
	_apply_set(ORIGINAL)
	_status.text = "已应用：用户 shader 原版默认值。"


func _apply_set(values: Dictionary) -> void:
	for key in values:
		_values[key] = values[key]
	_sync_controls()
	_apply_to_layer()


func _on_background_only_toggled(toggled: bool) -> void:
	_main.get_node("Room").visible = not toggled
	_main.get_node("HudLayer/Hud").visible = not toggled
	_main.get_node("GrainLayer/Grain").visible = not toggled
	UIManager.close_all()


func _copy_params() -> void:
	var lines := PackedStringArray()
	lines.append("# 粘贴到 scripts/ui/sunlight_layer.gd 的导出属性默认值")
	for key in COPY_ORDER:
		var prop := str(PROPERTY_NAMES.get(key, key))
		lines.append("%s = %s" % [prop, _format_for_copy(key)])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	_status.text = "已复制参数到剪贴板。"
	print(text)


func _format_for_copy(key: String) -> String:
	var value: Variant = _values[key]
	match key:
		"color":
			var c := value as Color
			return "Color(%.3f, %.3f, %.3f, %.3f)" % [c.r, c.g, c.b, c.a]
		"hdr":
			return "true" if bool(value) else "false"
		"ray1_density", "ray2_density", "seed":
			return "%.0f" % float(value)
		_:
			return "%.2f" % float(value)