class_name HotspotCard
extends PanelContainer
## 房间里的一个「能点的地方」：灶台、书架、门…… 做成一张挂着的纸牌。
##
## 为什么不是 Button：Button 只能把图标与文字左右并排、字号统一，
## 做不出「大图标 + 名称 + 一句说明」的层次。这里用 PanelContainer 自绘卡片，
## 自己接鼠标事件——外观完全可控，点击行为与 Button 一致（按下即触发）。
##
## 内容是竖排居中的：横排会让卡片更像一条菜单项，竖排才像墙上挂着的牌子。

signal pressed

const CARD_SIZE := Vector2(186.0, 145.0)
const ICON_BOX_SIZE := Vector2(56.0, 56.0)
## 悬停/聚焦时抬起来的那一点点：再大就像按钮浮起来，纸牌不该离开桌面
const HOVER_LIFT := 1.018

var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value

var subtitle: String = "":
	set(value):
		subtitle = value
		if _subtitle_label != null:
			_subtitle_label.text = value

var icon_path: String = "":
	set(value):
		icon_path = value
		if _icon != null:
			_icon.texture = PanelKit.icon_texture(value, 34.0) if not value.is_empty() else null

## 轻微倾斜：纸是手贴上去的，不会正得一丝不差。单位是度，0 表示摆正。
var tilt := 0.0:
	set(value):
		tilt = value
		_apply_tilt()

## 这张牌的主色：图标底框用它，六个入口各有各的颜色，画面才不像一排灰按钮
var accent := PanelKit.CARD_HI:
	set(value):
		accent = value
		_apply_style()

## 右上角的小红点：这个入口有新内容没看过（目前只有「图鉴」用）
var dot := false:
	set(value):
		dot = value
		queue_redraw()

## 卡片被划掉（比如这个入口暂时没有内容）
var dimmed := false:
	set(value):
		dimmed = value
		_apply_style()
		_refresh_lift()

var _icon: TextureRect
var _title_label: Label
var _subtitle_label: Label
var _icon_box: StyleBoxFlat
var _hovered := false
var _focused := false
## hover / focus 的缩放；和 _process 里压回 rotation 的那套互不干扰
var _lift_tween: Tween = null


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 可聚焦：键盘/手柄要能 Tab 到每一张入口卡，回车等同点一下
	focus_mode = Control.FOCUS_ALL
	_build()
	_apply_style()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _build() -> void:
	var box := PanelKit.vbox(7)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	# 图标底框：固定大小的方块，内边距清零（纸片默认的 20/16 会把它撑成 78 宽）
	_icon_box = PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 5, 2, false)
	_icon_box.content_margin_left = 0.0
	_icon_box.content_margin_top = 0.0
	_icon_box.content_margin_right = 0.0
	_icon_box.content_margin_bottom = 0.0
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _icon_box)
	frame.custom_minimum_size = ICON_BOX_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)

	_icon = PanelKit.icon("", 34.0)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_child(_icon)

	_title_label = PanelKit.label("", 21, PanelKit.INK)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title_label)

	_subtitle_label = PanelKit.label("", 14, PanelKit.INK_SOFT)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_subtitle_label)


## 红点画在卡片右上角：PanelContainer 会把所有子控件撑满内容区，
## 所以不塞一个 Panel 进去，直接用自绘（子节点会盖住它，但右上角本来就没有内容）。
func _draw() -> void:
	if dot:
		draw_circle(Vector2(size.x - 14.0, 14.0), 4.0, Color(0.82, 0.27, 0.20))


func _apply_style() -> void:
	var bg := PanelKit.CARD
	var border := PanelKit.INK
	var border_width := 2
	if _hovered and not dimmed:
		bg = PanelKit.CARD_HI
		border = PanelKit.ACCENT
	if _focused and not dimmed:
		# 键盘焦点比悬停再重一档：白纸 + 3px 蓝边，扫一眼就知道现在选中哪张
		bg = PanelKit.CARD_HI
		border = PanelKit.ACCENT
		border_width = 3
	if dimmed:
		bg = PanelKit.CARD.darkened(0.06)
		border = PanelKit.INK_DIM

	var style := PanelKit.slab(bg, border, 5, border_width)
	style.content_margin_left = 16.0
	style.content_margin_top = 14.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", style)

	if _icon_box != null:
		_icon_box.bg_color = accent.darkened(0.12) if dimmed else accent
		_icon_box.border_color = border
	if _icon != null:
		_icon.modulate = PanelKit.INK_DIM if dimmed else PanelKit.INK
	if _title_label != null:
		_title_label.add_theme_color_override("font_color",
				PanelKit.INK_DIM if dimmed else PanelKit.INK)


func _ready() -> void:
	resized.connect(queue_redraw)
	_apply_tilt()
	focus_entered.connect(func() -> void:
		_focused = true
		_apply_style()
		_refresh_lift()
	)
	focus_exited.connect(func() -> void:
		_focused = false
		_apply_style()
		_refresh_lift()
	)


## 容器在第一次布局时会把子节点的旋转摆正（实测：进树那一帧设好的 rotation 会变回 0，
## 之后再设就稳定了）。这里每帧对一下，不一致就压回去——六个卡片一次浮点比较，开销可忽略。
func _process(_delta: float) -> void:
	var wanted := deg_to_rad(tilt)
	if not is_equal_approx(rotation, wanted):
		_apply_tilt()


func _apply_tilt() -> void:
	pivot_offset = CARD_SIZE * 0.5
	rotation = deg_to_rad(tilt)


func _on_mouse_entered() -> void:
	_hovered = true
	_apply_style()
	_refresh_lift()


func _on_mouse_exited() -> void:
	_hovered = false
	_apply_style()
	_refresh_lift()


## 悬停/聚焦时整张牌轻轻抬一点。缩放不参与容器布局，不会被 VBox 摆回去。
func _refresh_lift() -> void:
	var target := HOVER_LIFT if (_hovered or _focused) and not dimmed else 1.0
	if not is_inside_tree():
		scale = Vector2(target, target)
		return
	if is_equal_approx(scale.x, target):
		return
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	pivot_offset = CARD_SIZE * 0.5
	_lift_tween = create_tween()
	_lift_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_property(self, "scale", Vector2(target, target), 0.16)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		accept_event()
		if dimmed:
			return
		Sfx.play(Sfx.Intent.OPEN)
		pressed.emit()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	accept_event()
	if dimmed:
		return
	Sfx.play(Sfx.Intent.OPEN)
	pressed.emit()
