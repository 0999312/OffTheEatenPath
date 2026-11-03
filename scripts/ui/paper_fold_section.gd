class_name PaperFoldSection
extends FoldableContainer
## 折叠分组：标题栏箭头由本脚本按 14×14 逻辑尺寸重绘。
##
## 坑：Godot 4.7 的 `FoldableContainer` 在 `NOTIFICATION_DRAW` 里直接
## `icon->draw(...)`，按纹理原始像素贴图，没有 `icon_max_width` 之类的上限
## （4.7 分支没有，master 才有）。而 `PanelKit` 为了让高分屏清晰，会把箭头 SVG
## 按 2–6 倍栅格化再染色——纹理实际有 28–84px。引擎照原始尺寸贴，箭头就会比
## 标题还大、把标题栏一起撑高（用户 2026-11-03 报「菜单箭头突然变得极大」）。
##
## 做法：主题里的 `expanded_arrow` / `folded_arrow` 换成 14×14 透明纹理，
## 让布局、标题栏高度、点击区仍然按 14px 算；再在 `_draw()`（引擎绘制之后由
## CanvasItem 调用）里把高分辨率源纹理缩进 14×14 的逻辑矩形。
## 高分屏是「缩小」而不是「放大」，边缘干净，尺寸也不再跟着纹理走。

## 箭头在标题栏里占的逻辑边长；与 PanelKit.fold_section 传进来的源纹理目标一致
const ICON_SIZE := 14.0

static var _blank_icon: Texture2D = null

var _arrow_open: Texture2D = null
var _arrow_folded: Texture2D = null


## 由 `PanelKit.fold_section` 调用：两张高分辨率（2–6 倍）的染色箭头纹理
func setup_arrows(open_texture: Texture2D, folded_texture: Texture2D) -> void:
	_arrow_open = open_texture
	_arrow_folded = folded_texture
	add_theme_icon_override("expanded_arrow", _blank_texture())
	add_theme_icon_override("folded_arrow", _blank_texture())
	queue_redraw()


func _draw() -> void:
	var texture := _arrow_folded if folded else _arrow_open
	if texture == null:
		return
	var style := get_theme_stylebox("title_collapsed_panel" if folded else "title_panel")
	if style == null:
		return
	var text_height := _text_height()
	# 引擎的落点：title_rect.position + (margin, max((title_h - style_h - icon_h) / 2, 0) + margin)
	# 而 title_h = style_h + MAX(行高, 图标高)，style_h 在算式里抵消，只剩行高与图标高的差。
	var icon_offset_y := maxf((maxf(text_height, ICON_SIZE) - ICON_SIZE) * 0.5, 0.0)
	var icon_offset_x := style.get_margin(SIDE_LEFT)
	var title_top := 0.0
	var style_offset_y := style.get_margin(SIDE_TOP)
	if title_position == FoldableContainer.POSITION_BOTTOM:
		style_offset_y = style.get_margin(SIDE_BOTTOM)
		title_top = size.y - (style.get_minimum_size().y + maxf(text_height, ICON_SIZE))
	if is_layout_rtl():
		icon_offset_x = size.x - style.get_margin(SIDE_RIGHT) - ICON_SIZE
	var icon_pos := Vector2(icon_offset_x, title_top + icon_offset_y + style_offset_y)
	draw_texture_rect(texture, Rect2(icon_pos, Vector2(ICON_SIZE, ICON_SIZE)), false, Color.WHITE)


## 标题行高：与引擎 text_buf 的 size.height 同一来源（字体 + 字号）
func _text_height() -> float:
	if title.is_empty():
		return 0.0
	var font := get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_height(get_theme_font_size("font_size"))


static func _blank_texture() -> Texture2D:
	if _blank_icon == null:
		var image := Image.create_empty(int(ICON_SIZE), int(ICON_SIZE), false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_blank_icon = ImageTexture.create_from_image(image)
	return _blank_icon
