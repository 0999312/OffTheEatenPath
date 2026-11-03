class_name PaperSlider
extends HSlider
## 音量滑杆：把手（grabber）由本脚本重绘成「高分屏也清晰」的样子。
##
## 坑：Godot 4.7 的 `Slider` 在 `NOTIFICATION_DRAW` 里 `grabber->draw(...)`，
## 按纹理原始尺寸贴图，没有 `grabber_max_size` 之类的上限（4.7 分支没有）。
## 主题里的 grabber 是 20×20 的渐变纹理；`canvas_items` 拉伸下全屏 2x，
## 它被放大到 40 物理像素，边缘一圈全是双线性插值的糊边（用户 2026-11-03 报）。
##
## 做法：把主题三态图标换成同尺寸透明纹理（最小尺寸、命中区、布局都不变），
## 在 `_draw()` 里用同一张渐变重采样出 160×160 的源纹理，再缩进 20×20 的
## 逻辑框绘制。高分屏拿到的是「缩小」而不是「放大」。
## 不用 `draw_circle`：主题把手是中心实、边缘渐隐的软圆点，实心圆会换掉观感
## （同 `CoinIcon` 里对锯齿的说明：小圆用多边形画更容易露边）。

const GRABBER_SIZE := Vector2(20.0, 20.0)
## 源纹理边长：20 逻辑像素在 4K 下最多 60 物理像素，160 足够「只缩不放」
const GRABBER_RENDER_SIZE := 160

static var _blank_icon: Texture2D = null

var _grabber_texture: Texture2D = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_grabber_texture = _build_grabber_texture()
	if _grabber_texture == null:
		# 主题里没有渐变把手（例如只给默认图标）：保持原样，别把把手抹掉
		return
	var blank := _blank_texture()
	add_theme_icon_override("grabber", blank)
	add_theme_icon_override("grabber_highlight", blank)
	add_theme_icon_override("grabber_disabled", blank)


func _build_grabber_texture() -> Texture2D:
	var source := get_theme_icon("grabber")
	if not source is GradientTexture2D:
		return null
	var gradient_texture := source as GradientTexture2D
	if gradient_texture.gradient == null:
		return null
	var hi_res := GradientTexture2D.new()
	hi_res.gradient = gradient_texture.gradient
	hi_res.width = GRABBER_RENDER_SIZE
	hi_res.height = GRABBER_RENDER_SIZE
	hi_res.fill = gradient_texture.fill
	hi_res.fill_from = gradient_texture.fill_from
	hi_res.fill_to = gradient_texture.fill_to
	hi_res.use_hdr = gradient_texture.use_hdr
	var image := hi_res.get_image()
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _draw() -> void:
	if _grabber_texture == null:
		return
	var ratio := get_as_ratio()
	if is_nan(ratio):
		ratio = 0.0
	var centered := get_theme_constant("center_grabber") != 0
	var area := size.x - (0.0 if centered else GRABBER_SIZE.x)
	var shift := -GRABBER_SIZE.x * 0.5 if centered else 0.0
	var left := (1.0 - ratio if is_layout_rtl() else ratio) * area + shift
	# 与 Slider 源码用同一套整数落点，别和引擎算出来的把手命中区差半像素
	var top := int(size.y) / 2 - int(GRABBER_SIZE.y) / 2 + get_theme_constant("grabber_offset")
	draw_texture_rect(_grabber_texture, Rect2(Vector2(int(left), top), GRABBER_SIZE), false, Color.WHITE)


static func _blank_texture() -> Texture2D:
	if _blank_icon == null:
		var image := Image.create_empty(int(GRABBER_SIZE.x), int(GRABBER_SIZE.y), false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_blank_icon = ImageTexture.create_from_image(image)
	return _blank_icon
