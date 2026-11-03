class_name MarqueeLabel
extends Control
## 长名称悬停跑马灯：只在本卡 hover 时动，离开立刻回位；全局最多一张卡在滚。
## 不用容器里的 Label 直接 tween position —— 容器会重置子节点位置（2026-10-30 货箱教训）。
## 这里 Control 自己 clip_contents，内部 Label 手动定位，容器碰不到。

const HOVER_DELAY := 0.4
const SPEED := 40.0
const MIN_SECONDS := 1.2
const MAX_SECONDS := 3.0
const END_PAUSE := 5.0
const LOOP_PAUSE := 0.6

## 同一时间只允许一张卡滚动
static var _active: MarqueeLabel = null

var _label: Label
var _tween: Tween
var _text := ""
var _font_size := 15
var _color := PanelKit.INK
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size.y = 19.0
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = false
	_label.position = Vector2.ZERO
	add_child(_label)
	_apply_text()
	resized.connect(_on_resized)
	tree_exiting.connect(_stop)


func set_text(value: String, font_size: int = 15, color: Color = PanelKit.INK) -> void:
	_text = value
	_font_size = font_size
	_color = color
	_apply_text()


func get_text() -> String:
	return _text


func set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	if value:
		if _active != null and _active != self:
			_active.set_hovered(false)
		_active = self
		_start()
	else:
		if _active == self:
			_active = null
		_stop()


func _apply_text() -> void:
	if _label == null:
		return
	_label.text = _text
	_label.add_theme_font_size_override("font_size", _font_size)
	_label.add_theme_color_override("font_color", _color)
	_refresh_layout()
	if _hovered:
		_start()


func _refresh_layout() -> void:
	if _label == null:
		return
	var text_width := _label.get_combined_minimum_size().x
	_label.size = Vector2(maxf(size.x, text_width), size.y)
	_label.position.y = 0.0


func _overflow() -> float:
	if _label == null:
		return 0.0
	return maxf(0.0, _label.get_combined_minimum_size().x - size.x)


func _on_resized() -> void:
	if _hovered:
		_start()
	else:
		_refresh_layout()
		if _label != null:
			_label.position.x = 0.0


func _start() -> void:
	_stop_tween()
	if _label == null:
		return
	_refresh_layout()
	_label.position.x = 0.0
	var overflow := _overflow()
	if overflow <= 1.0:
		return
	var seconds := clampf(overflow / SPEED, MIN_SECONDS, MAX_SECONDS)
	_tween = create_tween()
	_tween.tween_interval(HOVER_DELAY)
	_tween.tween_property(_label, "position:x", -overflow, seconds).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_interval(END_PAUSE)
	_tween.tween_property(_label, "position:x", 0.0, seconds).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_interval(LOOP_PAUSE)
	_tween.set_loops()


func _stop() -> void:
	_hovered = false
	if _active == self:
		_active = null
	_stop_tween()
	if _label != null:
		_label.position.x = 0.0


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
