class_name ItemBadge
extends Control
## 方形图标章：淡彩底 + 深色图标，没有匹配图标时用同底色 + 首字。
## 图鉴/灶台/商人共用一套语言；尺寸由调用方给，默认 28。
##
## 组合而不是裸图标：白卡上直接放淡彩线性图形，24px 时对比度不够，
## 远看只剩一团颜色（2026-10-30 试玩反馈）。现在底色承担「这是什么族」，
## 深色图形承担「具体是什么」，小尺寸也能认。

const DEFAULT_SIZE := 28.0
## 图形四周留白占比：27% 一侧，图形本体约 46%；再小会糊，再大顶到圆角。
const INNER_RATIO := 0.72

var _icon: Texture2D
var _glyph := ""
var _tint := PanelKit.INK
var _badge_size := DEFAULT_SIZE
## 只有需要点击的章（灶台里按标签要料）才吃鼠标；普通卡内章必须让点击穿透到卡片。
var _interactive := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if _interactive else Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)


## 在 add_child 之前或之后都能调：_ready 会按这个标记决定 mouse_filter。
func set_interactive(value: bool) -> void:
	_interactive = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE


## icon_path 为空 = 画首字印章；text 通常取物品名的第一个字。
## size 要跟卡片一起给，否则 _ready 的默认值会把调用方设的尺寸覆盖掉。
func configure(icon_path: String, text: String, tint: Color, size: float = DEFAULT_SIZE) -> void:
	_badge_size = maxf(10.0, size)
	custom_minimum_size = Vector2(_badge_size, _badge_size)
	_glyph = text.substr(0, 1)
	_tint = tint
	_icon = null
	if not icon_path.is_empty():
		_icon = PanelKit.icon_texture(icon_path, _badge_size)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var radius := maxf(4.0, side * 0.26)
	var background := _tint.lerp(PanelKit.CARD_HI, 0.80)
	var border := _tint.lerp(PanelKit.CARD_HI, 0.38)
	var glyph_color := _tint.darkened(0.34)

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(roundf(radius)))
	draw_style_box(style, rect)

	if _icon != null:
		var inner := side * INNER_RATIO
		var tex_size := _icon.get_size()
		var aspect := tex_size.x / maxf(tex_size.y, 1.0)
		var draw_size := Vector2(inner, inner)
		if aspect > 1.0:
			draw_size.y = inner / aspect
		else:
			draw_size.x = inner * aspect
		var origin := rect.position + (rect.size - draw_size) * 0.5
		draw_texture_rect(_icon, Rect2(origin, draw_size), false, glyph_color)
		return

	if _glyph.is_empty():
		return
	var font := get_theme_font("font", "Label")
	if font == null:
		return
	var glyph_size := clampi(int(side * 0.58), 10, 18)
	var text_size := font.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size)
	var baseline := (size.y + font.get_ascent(glyph_size) - font.get_descent(glyph_size)) * 0.5
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, baseline), _glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, glyph_color)
