class_name TooltipLayer
extends Control
## 全局提示浮层，替代引擎自带的 `Control.tooltip_text`。
##
## 引擎版有三个毛病：宽度没有上限（长文案横向铺开，越界或压住邻接控件）、
## 位置只跟鼠标走（永远从指针右下 +12 弹出，不避让）、只认鼠标悬停（键盘焦点不触发）。
## 这一层同时解决三件：宽度到 MAX_WIDTH 就折行、贴边翻到控件上方、焦点也显示。
##
## 由 `PanelKit.tooltip()` 惰性创建并复用，挂在主场景根节点下 —— 主题是挂在那一层上的，
## 挂到 root 下会退回引擎默认字体。

const MAX_WIDTH := 268.0
const GAP := 8.0
const EDGE := 8.0
const DELAY_MS := 380

var _card: PanelContainer
var _label: Label
var _hover_timer: Timer
var _current: Control
var _token := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	# 浮层挂在 CanvasLayer 下（否则压不过面板），主题继承链在那里断了：
	# 从最近的 Control 祖先把主题接过来，否则 TooltipCard 会退回空 StyleBox。
	var ancestor: Node = get_parent()
	while ancestor != null and not (ancestor is Control):
		ancestor = ancestor.get_parent()
	if ancestor is Control:
		theme = (ancestor as Control).theme
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", get_theme_font("font", "TooltipLabel"))
	_label.add_theme_font_size_override("font_size", get_theme_font_size("font_size", "TooltipLabel"))
	_label.add_theme_color_override("font_color", get_theme_color("font_color", "TooltipLabel"))
	_card = PanelContainer.new()
	_card.theme_type_variation = &"TooltipCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_card.add_child(_label)
	add_child(_card)
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = DELAY_MS / 1000.0
	_hover_timer.timeout.connect(_show_current)
	add_child(_hover_timer)


## 把一个控件和一段文案绑起来。重复调用只更新文案（切语言时会走到这里）。
func bind(control: Control, text: String) -> void:
	if control == null:
		return
	control.set_meta(&"tooltip_layer_text", text)
	if control.has_meta(&"tooltip_layer_bound"):
		return
	control.set_meta(&"tooltip_layer_bound", true)
	control.mouse_entered.connect(_on_pointer_in.bind(control))
	control.mouse_exited.connect(_on_pointer_out.bind(control))
	control.focus_entered.connect(_on_focus_in.bind(control))
	control.focus_exited.connect(_on_pointer_out.bind(control))


func hide_now() -> void:
	_token += 1
	if _hover_timer != null:
		_hover_timer.stop()
	_current = null
	_card.visible = false


func _on_pointer_in(control: Control) -> void:
	if _hover_timer == null:
		return
	_current = control
	_hover_timer.start()


func _on_pointer_out(control: Control) -> void:
	if _current == control:
		hide_now()


func _on_focus_in(control: Control) -> void:
	if _card == null:
		return
	_current = control
	_show_current()


func _show_current() -> void:
	var control := _current
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	var text := String(control.get_meta(&"tooltip_layer_text", ""))
	if text.is_empty():
		return
	_token += 1
	var token := _token
	_label.text = text
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	var natural := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label.custom_minimum_size.x = minf(natural, MAX_WIDTH)
	_card.visible = true
	_card.reset_size()
	# Label 在拿到宽度之前按「一个字一行」估算最小高度，第一帧的高度会虚高。
	# 等一帧让折行真正发生，再收一次尺寸。
	await get_tree().process_frame
	if token != _token or not is_instance_valid(control):
		return
	_card.reset_size()
	_place(control)


## 优先放在控件下方居中；下方放不下就翻到上方；左右都收进屏幕内。
func _place(control: Control) -> void:
	var view := get_viewport_rect().size
	var card_size := _card.size
	var rect := control.get_global_rect()
	var pos := Vector2(rect.get_center().x - card_size.x * 0.5, rect.end.y + GAP)
	if pos.y + card_size.y > view.y - EDGE:
		pos.y = rect.position.y - card_size.y - GAP
	pos.y = clampf(pos.y, EDGE, maxf(EDGE, view.y - card_size.y - EDGE))
	pos.x = clampf(pos.x, EDGE, maxf(EDGE, view.x - card_size.x - EDGE))
	_card.position = pos - get_global_rect().position
