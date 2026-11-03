class_name ToastMessage
extends UIToast
## 环境提示：做完一样东西、收到一封信、设备升了一级时，在底部轻轻冒一下。
##
## 为什么放进 UIManager 的 TOAST 层而不是自己加个 CanvasLayer：
## 框架已经管好了层级（TOAST = 300，压在面板之上）、自动消隐计时和清理；
## 自己再搭一套就会出现「面板打开时提示被盖住」「切换场景后残留」这类问题。
## 内容在代码里搭，场景里只放一个 Control + 本脚本（和 8 个面板同一套做法）。
##
## 文案存的是**配方**而不是成品字符串（`{"key", "args"}` / `{"build", Callable}`）：
## 切语言时同一个提示还挂在屏幕上，得能就地重新翻一遍，不能停在旧语言。

const THEME_PATH := "res://resources/themes/paper_theme.tres"
## 宽度的上限：长文案到此为止就换行，不再横向铺开
const MAX_WIDTH_RATIO := 0.4
const MIN_WIDTH := 200.0
## 距离屏幕上沿多远、留给自己多高（够放一张两行卡片）
const TOP_MARGIN := 44.0
const BOX_HEIGHT := 60.0

var _card: PanelContainer = null
var _text: Label = null
var _tween: Tween = null
## 这条提示怎么生成文案：`{"key": ..., "args": [...]}`、`{"build": Callable}` 或 `{"text": ...}`
var _spec: Dictionary = {}


func _ready() -> void:
	theme = load(THEME_PATH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶部偏下：贴在最上沿会显得像 HUD 的一部分，往下压到 HUD 下缘更像「临时飘出来
	# 的一句话」。为此允许它盖住 HUD 下半——提示不是常驻要素，遮一两秒无妨
	# （用户 2026-10-27 的取舍）。
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + BOX_HEIGHT
	EventBus.subscribe(&"LanguageChangedEvent", _on_language_changed)


func _on_show(data: Dictionary = {}) -> void:
	if _card == null:
		_build()
	_spec = data.duplicate(true)
	_text.text = message_text(_spec)
	_fit_width()
	var accent := bool(data.get("accent", false))
	_text.add_theme_color_override("font_color", PanelKit.ACCENT_DEEP if accent else PanelKit.INK)
	modulate.a = 0.0
	# 纸片从略小一点「弹」出来，比整块直接出现更轻；缩放不参与布局
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.965, 0.965)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_dismiss() -> void:
	EventBus.unsubscribe(&"LanguageChangedEvent", _on_language_changed)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.22)
	if _card != null:
		_tween.tween_property(_card, "scale", Vector2(0.98, 0.98), 0.22)


## 换了语言就地重翻一遍，提示本身不重建、不动画
func _on_language_changed(_event: Event) -> void:
	if _card == null or _text == null:
		return
	_text.text = message_text(_spec)
	_fit_width()


## 把「文案配方」翻成当前语言的一行字
##
## 参数里允许嵌 `{"t": "data.letter.xxx.title"}`：条目名本身也是翻译键，
## 切语言时得跟着变，所以不能在发提示那一刻就翻死。
static func message_text(spec: Dictionary) -> String:
	var text := _resolve(spec)
	var suffix: Variant = spec.get("suffix")
	if suffix is Dictionary:
		text += _resolve(suffix)
	return text


static func _resolve(spec: Dictionary) -> String:
	var builder: Variant = spec.get("build")
	if builder is Callable:
		return String((builder as Callable).call())
	if spec.has("key"):
		var args: Array = []
		var raw_args: Variant = spec.get("args", [])
		if raw_args is Array:
			for arg in raw_args:
				args.append(_resolve_arg(arg))
		return I18n.t(String(spec["key"]), args)
	return String(spec.get("text", ""))


static func _resolve_arg(arg: Variant) -> String:
	if arg is Dictionary and (arg as Dictionary).has("t"):
		return I18n.t(String((arg as Dictionary)["t"]))
	return str(arg)


## 宽度跟着文案走：短提示贴合文字，长提示到上限就换行。
##
## 原来是「300 最小宽 + MarginContainer 22/22/10/10 + S_card 自带 26/22」三层叠着，
## 一行 12 个字也要撑出 332×89 的白块，字只占 20% 面积（审查报告 §3.5.2）。
## 现在卡片改用主题里的 ToastCard 变体（content_margin 20/12），Label 直接挂上去，
## 只给 Label 一个「期望宽度」—— 短文案约 276×49，长文案换行而不是横向铺开。
func _fit_width() -> void:
	var font := _text.get_theme_font(&"font")
	if font == null:
		return
	var size := _text.get_theme_font_size(&"font_size")
	var natural := font.get_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var cap := maxf(MIN_WIDTH, get_viewport_rect().size.x * MAX_WIDTH_RATIO)
	_text.custom_minimum_size.x = minf(natural, cap)


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.theme_type_variation = &"ToastCard"
	_card.resized.connect(func() -> void: _card.pivot_offset = _card.size * 0.5)
	center.add_child(_card)

	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 18)
	_card.add_child(_text)
