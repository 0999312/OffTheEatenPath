class_name PanelKit
extends RefCounted
## 面板通用小工具：把「动态生成控件」的重复写法收在一处。
##
## 视觉基调：绘本纸片。冷灰蓝的纸上贴着冷白纸片，纸片有粗墨线描边，
## 按钮是「贴纸」——底边厚一点，按下去会往下沉。图标统一用 assets/icons 里的
## 白色线性图标，靠 modulate 染成墨色（白色 × 墨色 = 墨色）。
##
## 为什么不用 @tool 场景拼装：面板内容随数据变化（配方列表、图鉴条目、信件），
## 静态拼不出来，只能在 _on_open 时按数据重建；这里保证重建出来的样式一致。

const INK := Color(0.133, 0.188, 0.239)        # #22303D 墨线
const INK_SOFT := Color(0.353, 0.420, 0.486)   # #5A6B7C 次墨
const INK_DIM := Color(0.549, 0.604, 0.659)    # #8C9AA8 淡墨
const PAPER := Color(0.788, 0.839, 0.882)      # #C9D6E1 背景纸（冷）
const PAPER_BACK := Color(0.761, 0.816, 0.859) # #C2D0DB 底层纸
const CARD := Color(0.949, 0.965, 0.980)       # #F2F6FA 纸片
const CARD_HI := Color(0.984, 0.988, 0.992)    # #FBFCFD 高光纸
const ACCENT := Color(0.243, 0.545, 0.659)     # #3E8BA8 冷调强调（蓝绿）
## 强调色压深一档：白字压上去 5.0:1（ACCENT 只有 3.7:1）。选中态、悬停态用它。
## 与主题里 PopupMenu 选中底色 `Color(0.207, 0.463, 0.560)` 取同一个值。
const ACCENT_DEEP := Color(0.207, 0.463, 0.560) # #35768F 深一档的强调色
## 选中面的淡强调底：高光纸渗 18% 强调色。压在纸白面板（CARD）上仍看得出「这一块被选中」，
## 又不到「实色块」的程度 —— 白底贴白底时只剩一圈细框，实机看着像没选中（用户 2026-10-27 报）。
const SELECT_FILL := Color(0.851, 0.908, 0.932)  # #D9E8EE 选中面（纸白 + 18% ACCENT）
const COIN := Color(0.878, 0.663, 0.290)       # #E0A94A 铜币
const DANGER := Color(0.824, 0.400, 0.306)     # #D2664E 赭红（只给圆点、边框这类非文字用）
## 赭红压深一档：浅底上的正义字要用它（#D2664E 只有 3.5:1，不到 4.5:1）
const DANGER_DEEP := Color(0.682, 0.322, 0.251) # #AE5240 深赭红：纸片底 4.7:1、高光纸 5.0:1

const ICON_ROOT := "res://assets/icons/"
static var _icon_cache: Dictionary = {}


static func label(text: String, font_size: int = 19, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


## 面板标题：大、字距略宽，像绘本封面上的手写标题
static func title(text: String) -> Label:
	var node := label(text, 30, INK)
	node.add_theme_constant_override("outline_size", 0)
	return node


## 小标签：放在纸片角落的说明字，全大写感（中文靠字距与颜色区分）
static func caption(text: String, color: Color = INK_SOFT) -> Label:
	var node := label(text, 15, color)
	return node


static func hint(text: String, min_width: float = 0.0) -> Label:
	var node := label(text, 16, INK_SOFT)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if min_width > 0.0:
		node.custom_minimum_size.x = min_width
	return node


## 单行状态字：页脚计数、「第 N / M 页」这类横向行里的短状态。
## 不能用 hint()——开了自动换行的 Label 在 HBoxContainer 里最小宽度只有 1px，
## 会被挤成 1px 宽逐字竖排，连带把页脚最小高度撑到 200+，把滚动区压成 0 高
## （2026-10-27 自检 S1 实测：图鉴页列表整片空白）。
static func hint_inline(text: String, min_width: float = 0.0) -> Label:
	var node := label(text, 16, INK_SOFT)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	if min_width > 0.0:
		node.custom_minimum_size.x = min_width
	return node


## 白色线性图标，染成指定颜色。路径传空串就得到一个占位（用于先建后填）
##
## 图标源文件是 10×10 的 svg，图形只占画布中间一小块；如果直接把导入后的
## 40×40 纹理塞进小框，或者裁完再硬拉大，边缘都会糊。这里按目标尺寸把 SVG
## 重新栅格化到「2–6 倍」（倍数跟着窗口拉伸走，见 `icon_scale_bucket()`），再裁掉
## alpha 留白，最后缩回目标尺寸——既是矢量精度，又只占目标大小的画框。
static func icon(path: String, size: float = 20.0, color: Color = INK) -> TextureRect:
	var node := TextureRect.new()
	if not path.is_empty():
		node.texture = icon_texture(path, size)
	node.custom_minimum_size = Vector2(size, size)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.modulate = color
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 取得按目标尺寸重新栅格化、并裁掉透明留白的图标纹理。
static func icon_texture(path: String, target_size: float = 34.0) -> Texture2D:
	var full := path if path.begins_with("res://") else ICON_ROOT + path
	var key := "%s@%d#%d" % [full, int(roundf(target_size)), icon_scale_bucket()]
	if _icon_cache.has(key):
		return _icon_cache[key] as Texture2D
	var texture := _rasterize_svg(full, target_size)
	if texture == null:
		# 导出包如果没带 .svg 源，运行时栅格化会失败；退回导入纹理时也裁成方形，
		# 否则 80×80 画布里的小图形缩到 24px 会又小又糊（见 export_presets.cfg 的 include_filter）。
		var imported := load(full) as Texture2D
		if imported != null and full.ends_with(".svg"):
			var imported_image := imported.get_image()
			if imported_image != null:
				var squared := _square_from_image(imported_image)
				if squared != null:
					squared.generate_mipmaps()
					texture = ImageTexture.create_from_image(squared)
		if texture == null:
			texture = imported
	_icon_cache[key] = texture
	return texture


## 图标要多大的源纹理：窗口被 `canvas_items` 拉伸得越狠，同一个逻辑像素背后的
## 物理像素就越多，还按固定 2 倍栅格化的话放大后必然发虚。这里按「物理像素 / 逻辑
## 像素」的比值把倍数抬上去，并夹在 2–6 之间——再高下去只是白烧显存。
static func icon_scale_bucket() -> int:
	return clampi(roundi(2.0 * _pixel_ratio()), 2, 6)


## 当前一个逻辑像素背后有几个物理像素；拿不到窗口时按 1 算（测试、无头环境）
static func _pixel_ratio() -> float:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return 1.0
	var visible := loop.root.get_visible_rect().size
	if visible.x <= 0.0 or visible.y <= 0.0:
		return 1.0
	var window := DisplayServer.window_get_size()
	var ratio := maxf(float(window.x) / visible.x, float(window.y) / visible.y)
	return clampf(ratio, 1.0, 3.0)


## 染色版图标纹理：图标源文件是纯白，把 RGB 换成目标色、保留 alpha 即可。
## `PanelKit.icon()` 用 `modulate` 染色，但主题里的 icon 项（折叠箭头这类）没有节点可挂，
## 只能染色到纹理本身。
static func icon_texture_tinted(path: String, target_size: float, color: Color) -> Texture2D:
	var key := "%s@%d#%s" % [path, int(roundf(target_size)), color.to_html(false)]
	if _icon_cache.has(key):
		return _icon_cache[key] as Texture2D
	var texture := icon_texture(path, target_size)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return texture
	var tinted := image.duplicate() as Image
	for y in tinted.get_height():
		for x in tinted.get_width():
			var pixel := tinted.get_pixel(x, y)
			tinted.set_pixel(x, y, Color(color.r, color.g, color.b, pixel.a))
	tinted.fix_alpha_edges()
	tinted.generate_mipmaps()
	var built := ImageTexture.create_from_image(tinted)
	_icon_cache[key] = built
	return built


## 用 ThorVG 在运行时把 SVG 重新栅格化到 2 倍目标尺寸；不是所有资源都能成功，
## 失败时调用方退回导入纹理。
static func _rasterize_svg(full: String, target_size: float) -> Texture2D:
	if not full.ends_with(".svg"):
		return null
	var bytes := FileAccess.get_file_as_bytes(full)
	if bytes.is_empty():
		return null
	var probe := Image.new()
	if probe.load_svg_from_buffer(bytes, 1.0) != OK:
		return null
	var intrinsic := float(mini(probe.get_width(), probe.get_height()))
	if intrinsic <= 0.0:
		return null
	var image := Image.new()
	# 目标尺寸 × 缩放倍数：4K 全屏下 22px 的图标会拿到 132px 的源纹理，
	# 显示时只缩不放，边缘才干净。
	var render_size := maxf(8.0, target_size * float(icon_scale_bucket()))
	if image.load_svg_from_buffer(bytes, render_size / intrinsic) != OK:
		return null
	var square := _square_from_image(image)
	if square == null:
		return null
	square.generate_mipmaps()
	return ImageTexture.create_from_image(square)


## 裁掉透明留白，再补成透明方画布并居中。图标章的底框是正方形：
## 直接返回 34×21 这种长条，调用方把它画进方框就会横向拉宽/纵向压扁
## （2026-10-30 试玩反馈）。方形纹理让显示端只需要等比缩放。
static func _square_from_image(image: Image) -> Image:
	if image == null:
		return null
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return null
	var cropped := image.get_region(used)
	cropped.convert(Image.FORMAT_RGBA8)
	var side := maxi(cropped.get_width(), cropped.get_height())
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color(0, 0, 0, 0))
	square.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()),
			Vector2i((side - cropped.get_width()) / 2, (side - cropped.get_height()) / 2))
	square.fix_alpha_edges()
	return square


## 动态按钮：默认带一点按键声（`Sfx.Intent.CLICK`），需要静音或换声音时传第二个参数
static func button(text: String, sound: int = Sfx.Intent.CLICK) -> Button:
	var node := Button.new()
	node.text = text
	# 可聚焦：键盘/手柄是鼠标的替补（用户 2026-10-27 拍板），Tab 要能走到每个按钮
	node.focus_mode = Control.FOCUS_ALL
	node.custom_minimum_size.y = 42
	node.add_theme_font_size_override("font_size", 18)
	if sound != Sfx.Intent.NONE:
		node.pressed.connect(func() -> void: Sfx.play(sound))
	attach_press_motion(node)
	return node


## 贴纸按钮：图标 + 文字，扁平、按下去会沉。用于面板入口与主要动作。
static func sticker(text: String, icon_path: String = "", sound: int = Sfx.Intent.CLICK,
		icon_size: float = 22.0) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_ALL
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size.y = 42
	node.add_theme_font_size_override("font_size", 18)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not icon_path.is_empty():
		node.icon = icon_texture(icon_path, icon_size)
		node.expand_icon = true
		node.add_theme_constant_override("icon_max_width", int(icon_size))
		# 图标源文件是白色实心，靠主题色染成墨色——不染的话在白按钮上完全看不见
		node.add_theme_color_override("icon_normal_color", INK)
		node.add_theme_color_override("icon_hover_color", INK)
		node.add_theme_color_override("icon_pressed_color", INK)
		node.add_theme_color_override("icon_disabled_color", INK_DIM)
	if sound != Sfx.Intent.NONE:
		node.pressed.connect(func() -> void: Sfx.play(sound))
	attach_press_motion(node)
	return node


## 主操作按钮：实底强调色 + 白字 + 底边加厚。一页里最多一个——「主」之所以是主，
## 靠的是唯一性。用于「做一份」「交付」「收下」这类一步到位的动作。
##
## 禁用时**保留实底形状**、只把颜色退到低饱和，而不是换成灰块：订单卡曾经因为禁用的
## 「交付」是浅灰块、旁边的「拒」是墨边按钮，视觉重心整个落到次操作上（报告 P1-6）。
static func primary_button(text: String, sound: int = Sfx.Intent.NONE, min_height: float = 46.0) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_ALL
	node.custom_minimum_size = Vector2(0.0, min_height)
	node.add_theme_font_size_override("font_size", 20)
	node.add_theme_stylebox_override("normal", _primary_box(ACCENT_DEEP))
	node.add_theme_stylebox_override("hover", _primary_box(ACCENT_DEEP.lightened(0.12)))
	node.add_theme_stylebox_override("pressed", _primary_box(ACCENT_DEEP.darkened(0.10)))
	# 禁用底退到 84% 纸白：72% 那档在实机截图里压着次墨字只有 3.7:1，整颗按钮看着发雾（E 批复查）。
	# 形状与描边不动，玩家仍认得出这是主操作。
	node.add_theme_stylebox_override("disabled", _primary_box(ACCENT_DEEP.lerp(CARD_HI, 0.84)))
	# 主题的 Button/focus 是「白实底 + 蓝边」，叠在实底主按钮上会把底色整个盖成纸白，
	# 再配上面那行 font_focus_color = CARD_HI，就是一颗白底白字的空按钮（实机截图抓到过）。
	# 焦点态只借它的外框：底色不画，让 normal 的实底透出来。
	var focus_box := _primary_box(ACCENT_DEEP)
	focus_box.draw_center = false
	focus_box.border_color = ACCENT
	focus_box.border_width_left = 3
	focus_box.border_width_right = 3
	focus_box.border_width_top = 3
	focus_box.border_width_bottom = 5
	node.add_theme_stylebox_override("focus", focus_box)
	for key in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		node.add_theme_color_override(key, CARD_HI)
	node.add_theme_color_override(&"font_disabled_color", INK_SOFT)
	if sound != Sfx.Intent.NONE:
		node.pressed.connect(func() -> void: Sfx.play(sound))
	attach_press_motion(node)
	return node


## 「选中」的统一底：强调色描边 + 墨字，底色按「压在哪层纸上」挑。分页签、筛选芯片、
## 列表行三处共用一套语言，差别只在加粗哪条边 —— 页签加粗顶边（表示「你在哪一页」）、
## 列表行加粗左边（表示「你选哪一行」）、芯片不加粗（只是一颗开关）。
## 大色块（`ACCENT_DEEP` 实底白字）留给主操作按钮，选中不再用实底。
## 页签由主题 `TabBar/styles/tab_selected` 承担，值与本函数对齐（报告 §5.8）。
##
## `fill` 是「选中块浮在哪层纸上」的答案：页签与芯片坐在深纸（PAPER_BACK）上，纸白比底纸亮，
## 用 CARD_HI 最突出；列表行坐在纸白面板（CARD）上，再用纸白就贴成一片，改用 SELECT_FILL。
## 规则一句话：底色永远朝「离容器更远」的方向走，亮容器上压暗、暗容器上提亮。
static func selection_box(corner_radius: int, cap_width: int = 0, cap_top: bool = false,
		fill: Color = CARD_HI) -> StyleBoxFlat:
	var box := slab(fill, ACCENT, corner_radius, 2, false)
	if cap_width > 0:
		if cap_top:
			box.border_width_top = cap_width
		else:
			box.border_width_left = cap_width
	return box


## 主按钮的纸片：颜色换、形状不换（圆角 12、墨边、底边 5 像一叠纸的厚度）。
## 上下内边距比 `slab()` 的默认值小：那块默认边距是给容器内容留的，套在按钮上会把它撑高。
## 按钮最终高度取 max(`custom_minimum_size.y`, 内边距 + 字高)，所以同一套样式能长能短。
static func _primary_box(bg: Color) -> StyleBoxFlat:
	var box := slab(bg, INK, 12, 2)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 10.0
	box.border_width_bottom = 5
	return box

## 下拉框：外观交给主题（OptionButton 继承 Button 的纸片样式），这里只补主题管不到的两件——
## 弹层的宽度跟随按钮（否则选项短的时候弹出一个比按钮窄一截的小条），
## 以及别让它把弹层宽度算进布局。
static func option_button(min_width: float = 0.0) -> OptionButton:
	var node := OptionButton.new()
	if min_width > 0.0:
		node.custom_minimum_size.x = min_width
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sync_popup_width(node)
	node.resized.connect(func() -> void: _sync_popup_width(node))
	return node


static func _sync_popup_width(node: OptionButton) -> void:
	var popup := node.get_popup()
	popup.min_size.x = int(maxf(node.size.x, node.custom_minimum_size.x))


## 由名字决定的淡彩：同一个名字永远同一个颜色（图鉴印章、材料色块都用它）
static func tint_of(text: String, saturation := 0.32, value := 0.95) -> Color:
	var phase := float(abs(text.hash()) % 1000) / 1000.0
	return Color.from_hsv(0.02 + phase * 0.62, saturation, value)


## 方形图标按钮：设置、关闭这类只有一个图标的按钮。
## 必须单独给 StyleBox——普通贴纸按钮的左右内边距会把图标挤得只剩几像素。
static func icon_button(icon_path: String, size: float = 46.0, icon_size: float = 22.0) -> Button:
	var node := Button.new()
	node.focus_mode = Control.FOCUS_ALL
	node.custom_minimum_size = Vector2(size, size)

	# 不用 Button.icon 来画：没有文字时它按 text_size（=0）算图标落点，再叠上
	# expand_icon 的放大与 icon_max_width 的截断，图标会离开中心（设置钮与关闭钮都偏）。
	# 这里直接放一个锚在正中的 TextureRect，位置只由本节点的 anchors 决定。
	var glyph := icon(icon_path, icon_size, INK)
	glyph.name = "Glyph"
	glyph.set_anchors_preset(Control.PRESET_CENTER)
	glyph.offset_left = -icon_size * 0.5
	glyph.offset_top = -icon_size * 0.5
	glyph.offset_right = icon_size * 0.5
	glyph.offset_bottom = icon_size * 0.5
	node.add_child(glyph)
	node.mouse_entered.connect(func() -> void: glyph.modulate = ACCENT)
	node.mouse_exited.connect(func() -> void: glyph.modulate = INK)
	node.button_down.connect(func() -> void: glyph.modulate = ACCENT)
	node.button_up.connect(func() -> void: glyph.modulate = ACCENT if node.is_hovered() else INK)

	var base := slab(CARD_HI, INK, 5, 2)
	var hover := slab(CARD_HI, ACCENT, 5, 2)
	var press := slab(CARD_HI, ACCENT, 5, 2)
	press.border_width_top = 4
	press.border_width_bottom = 2
	for style in [base, hover, press]:
		style.content_margin_left = 0.0
		style.content_margin_top = 0.0
		style.content_margin_right = 0.0
		style.content_margin_bottom = 0.0
	node.add_theme_stylebox_override("normal", base)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", press)
	node.add_theme_stylebox_override("disabled", base)
	# 焦点环：底色不变，只把描边换成强调色并加粗——图标按钮的「框」就是它唯一的轮廓
	var focused := slab(CARD_HI, ACCENT, 5, 3)
	focused.content_margin_left = 0.0
	focused.content_margin_top = 0.0
	focused.content_margin_right = 0.0
	focused.content_margin_bottom = 0.0
	node.add_theme_stylebox_override("focus", focused)
	attach_press_motion(node)
	return node


## 给所有 BaseButton 挂「按下去缩一点、松开弹回来」。集中在这里，四个工厂一次覆盖全 UI；
## 缩放不参与容器布局，按钮不会被 HBox/VBox 摆回原位。
static func attach_press_motion(node: BaseButton) -> void:
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)
	node.button_down.connect(func() -> void: _animate_press(node, 0.97))
	node.button_up.connect(func() -> void: _animate_press(node, 1.0))
	node.mouse_exited.connect(func() -> void: _animate_press(node, 1.0))
	node.focus_exited.connect(func() -> void: _animate_press(node, 1.0))


static func _animate_press(node: BaseButton, target: float) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
		return
	var tween: Tween = null
	if node.has_meta(&"_press_tween"):
		tween = node.get_meta(&"_press_tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	if is_equal_approx(node.scale.x, target):
		return
	node.pivot_offset = node.size * 0.5
	tween = node.create_tween()
	node.set_meta(&"_press_tween", tween)
	var pressed := target < 1.0
	tween.tween_property(node, "scale", Vector2(target, target), 0.08 if pressed else 0.16) \
			.set_trans(Tween.TRANS_QUAD if pressed else Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)


static func hbox(separation: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func vbox(separation: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


## 横向撑开的空白，把后面的控件推到右边
static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 纵向撑开的空白，把后面的控件压到底部
static func vspacer() -> Control:
	var node := Control.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 一条淡色分隔线：压在纸面上能看见，又不会抢过正文。0.28 在 1280 宽下几乎消失（P1-5）
static func divider() -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(INK.r, INK.g, INK.b, 0.36)
	node.custom_minimum_size.y = 1.0
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 分组抬头：一行次墨小字 + 一条撑开的细线。
## 小一号是为了让它像书页里的分隔标题，而不是另一条内容——
## 八堆条目各顶一个 19px 标题会把一页挤散。
static func group_header(text: String) -> Control:
	var row := hbox(10)
	row.add_child(label(text, 17, INK_SOFT))
	var line := divider()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


## 清空容器里的动态内容（节点延迟释放，立刻能重新填充）
static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- 纸片 -----------------------------------------------------------------


## 一张纸片：几乎方的角 + 粗墨线描边 + 一道朝下的淡影。用 PanelContainer 盛内容。
##
## 圆角要小：纸是裁出来的，不是吹出来的。圆角一大就变成网页卡片，
## 「贴在墙上的便签」那种感觉全靠角留得利落。
## 影子是纸浮在纸面上的唯一提示——颜色要淡（alpha 0.2 上下），偏移朝下，
## 太大太黑会像按钮的浮雕。
static func slab(bg: Color = CARD, border: Color = INK, radius: int = 4,
		border_width: int = 2, shadow: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 20.0
	box.content_margin_top = 16.0
	box.content_margin_right = 20.0
	box.content_margin_bottom = 16.0
	if shadow:
		box.shadow_color = Color(0.09, 0.13, 0.18, 0.16)
		box.shadow_size = 3
		box.shadow_offset = Vector2(1, 3)
	return box


## 一张纸离开桌面的投影，分三层叠出来：近处实、远处虚、越远越散。
## 为什么不用单层 StyleBoxFlat 的 shadow：它的投影是「硬边等距扩散」，
## 只偏移几个像素的话，看起来就是右下方又贴了一张同形状的纸——两张纸，
## 而不是一张纸的影子。让三层各自的扩散半径和透明度一起衰减，
## 边缘才有一段渐隐，眼睛才会把它读成「高度差」。
const SHADOW_LAYERS: Array[Dictionary] = [
	{"offset": Vector2(2.0, 3.0), "size": 4, "alpha": 0.17},
	{"offset": Vector2(7.0, 11.0), "size": 11, "alpha": 0.09},
	{"offset": Vector2(14.0, 22.0), "size": 22, "alpha": 0.05},
]


## 投影层：铺满父控件，不参与布局、不吃鼠标，放在纸片下面即可。
static func cast_shadow(radius: int = 6, strength: float = 1.0) -> Control:
	var root := Control.new()
	root.name = "Shadow"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for layer in SHADOW_LAYERS:
		var box := slab(Color(1, 1, 1, 0.004), Color(0, 0, 0, 0), radius, 0, false)
		box.shadow_color = Color(0.07, 0.11, 0.16, float(layer["alpha"]) * strength)
		box.shadow_size = int(layer["size"])
		box.shadow_offset = layer["offset"]
		var node := PanelContainer.new()
		node.add_theme_stylebox_override("panel", box)
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(node)
	return root


## 纸片容器（贴在图上的那种）
static func paper(bg: Color = CARD, radius: int = 4) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", slab(bg, INK, radius))
	return node


## 「叠纸」：底层一张斜错开的深色纸 + 上层白纸，绘本里的层次感
static func stacked_paper() -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_theme_constant_override("margin_left", 0)
	wrap.add_theme_constant_override("margin_top", 0)
	wrap.add_theme_constant_override("margin_right", 8)
	wrap.add_theme_constant_override("margin_bottom", 8)

	var back := PanelContainer.new()
	var back_box := slab(PAPER_BACK, INK, 10)
	back.add_theme_stylebox_override("panel", back_box)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.offset_left = 8
	back.offset_top = 8
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(back)

	var front := PanelContainer.new()
	front.add_theme_stylebox_override("panel", slab(CARD, INK, 10))
	front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	front.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(front)
	return wrap


## 一条胶带：贴在纸片左上角，纯装饰
static func tape(text: String = "") -> Control:
	var holder := HBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip := ColorRect.new()
	strip.color = Color(0.984, 0.988, 0.992, 0.72)
	strip.custom_minimum_size = Vector2(18, 18)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.rotation = deg_to_rad(-6.0)
	holder.add_child(strip)
	if not text.is_empty():
		holder.add_child(caption(text))
	return holder


## 空槽位：研究台放材料的凹槽，虚线感靠浅色底 + 粗描边表达
static func slot(size: Vector2 = Vector2(88, 88)) -> PanelContainer:
	var node := PanelContainer.new()
	var box := slab(Color(0.898, 0.933, 0.961), Color(INK.r, INK.g, INK.b, 0.55), 8)
	box.content_margin_left = 8.0
	box.content_margin_top = 8.0
	box.content_margin_right = 8.0
	box.content_margin_bottom = 8.0
	node.add_theme_stylebox_override("panel", box)
	node.custom_minimum_size = size
	return node


## 折叠小节：长面板先分组再滚动（设置页的「通用 / 音频 / 存档 / 关于 / 调试」）。
##
## 用引擎内置的 `FoldableContainer`（4.5 起）而不是手写「Button + VBox 显隐」：
## 开合状态、键盘/手柄焦点、标题栏上的箭头都由引擎管，手写版要再实现一遍。
## 但它默认吃的是深色主题（白字深底），放进纸片主题必须整条重画——
## 标题栏给一张压边的小纸片，正文区给空样式（正文直接摊在纸面上，不能多铺一层底板）。
## 箭头交给 `PaperFoldSection`：引擎按纹理原始尺寸贴图，高分辨率源会把标题栏撑爆。
static func fold_section(title_text: String, folded := false) -> FoldableContainer:
	var node := PaperFoldSection.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.title = title_text
	node.folded = folded
	node.add_theme_font_size_override("font_size", 19)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("hover_font_color", ACCENT_DEEP)
	node.add_theme_color_override("collapsed_font_color", INK)
	node.add_theme_constant_override("h_separation", 12)
	node.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# 焦点环要画出来，但只描边不铺底：Focus 样式盖住的是整个节点（含展开的正文），
	# 有底色会把标题栏那张纸片抹平，整节变成一块白板。
	var fold_focus := slab(Color(0, 0, 0, 0), ACCENT, 6, 3, false)
	node.add_theme_stylebox_override("focus", fold_focus)
	# 四个标题栏状态：展开/悬停用高光纸，收起时压暗一档，眼睛才看得出「这一节还关着」
	var states := [
		["title_panel", CARD_HI, INK],
		["title_hover_panel", CARD_HI, ACCENT],
		["title_collapsed_panel", PAPER_BACK, INK_SOFT],
		["title_collapsed_hover_panel", PAPER_BACK, ACCENT],
	]
	for state in states:
		var style := slab(state[1], state[2], 6, 2, false)
		style.content_margin_left = 14.0
		style.content_margin_top = 9.0
		style.content_margin_right = 14.0
		style.content_margin_bottom = 9.0
		node.add_theme_stylebox_override(String(state[0]), style)
	# 箭头是纯白 SVG，直接画在白纸上等于没有——给染过色的高分辨率源纹理，
	# 由 PaperFoldSection 缩进 14×14 的逻辑框里画（见该类的注释）
	node.setup_arrows(
			icon_texture_tinted("arrow/arrow_down.svg", PaperFoldSection.ICON_SIZE, INK_SOFT),
			icon_texture_tinted("arrow/arrow_right.svg", PaperFoldSection.ICON_SIZE, INK_SOFT))
	return node


## 给一个控件套内边距。容器里「别贴边」是常态，四处 margin 各写一遍太吵。
static func pad(child: Control, left: int = 0, top: int = 0, right: int = 0,
		bottom: int = 0) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", left)
	node.add_theme_constant_override("margin_top", top)
	node.add_theme_constant_override("margin_right", right)
	node.add_theme_constant_override("margin_bottom", bottom)
	if child != null:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.add_child(child)
	return node


## 一排页签（不带内容区）：钉在固定工具条上，只有下面的内容换。
## 用 `TabBar` 而不是 `TabContainer`——后者自带内容底板，等于在纸片上又套一张纸。
static func tab_bar(names: Array[String]) -> TabBar:
	var node := TabBar.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab_name in names:
		node.add_tab(tab_name)
	return node


## 小圆牌：数量、等级这类短数字
static func badge(text: String, bg: Color = CARD_HI, fg: Color = INK) -> PanelContainer:
	var node := PanelContainer.new()
	var box := slab(bg, INK, 6, 2)
	box.content_margin_left = 9.0
	box.content_margin_top = 3.0
	box.content_margin_right = 9.0
	box.content_margin_bottom = 3.0
	node.add_theme_stylebox_override("panel", box)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.add_child(label(text, 14, fg))
	return node


# --- 文本格式 -------------------------------------------------------------


## 数量显示：整数不带小数点，其余保留一位
static func number_text(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return "%d" % int(roundf(value))
	return "%.1f" % value


## 进度条：轨道与填充的样式统一在主题里（ProgressBar 的 background / fill），
## 这里只管尺寸和取值。高度由调用方给；不显示百分比文字，因为旁边通常已经写了「还剩几秒」。
static func progress_bar(height: float = 10.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	return bar


## 耗时显示
static func duration_text(seconds: float) -> String:
	if seconds <= 0.0:
		return I18n.t("ui.common.instant")
	if seconds < 60.0:
		return I18n.t("ui.common.seconds", ["%.1f" % seconds])
	return I18n.t("ui.common.minutes_seconds", [int(seconds / 60.0), int(seconds) % 60])


## 大数显示：中文不满 1 万照常，1 万起用「万」，1 亿起用「亿」；
## 英文用 k / M / B。这样铜币、材料、未来货币都能共用同一套读法，界面不会被长数字撑破。
static func big_number_text(value: int) -> String:
	var n := absi(value)
	var sign := "-" if value < 0 else ""
	if I18n.is_zh():
		if n < 10000:
			return "%s%d" % [sign, n]
		if n < 100000000:
			return sign + _trim_zeros("%.1f" % (float(n) / 10000.0)) + "万"
		return sign + _trim_zeros("%.2f" % (float(n) / 100000000.0)) + "亿"
	if n < 1000:
		return "%s%d" % [sign, n]
	if n < 1000000:
		return sign + _trim_zeros("%.1f" % (float(n) / 1000.0)) + "k"
	if n < 1000000000:
		return sign + _trim_zeros("%.1f" % (float(n) / 1000000.0)) + "M"
	return sign + _trim_zeros("%.1f" % (float(n) / 1000000000.0)) + "B"


static func _trim_zeros(text: String) -> String:
	var result := text
	while result.contains(".") and result.ends_with("0"):
		result = result.left(result.length() - 1)
	if result.ends_with("."):
		result = result.left(result.length() - 1)
	return result


## 铜币显示
static func coins_text(amount: int) -> String:
	return I18n.t("ui.common.coins_amount", [big_number_text(amount)])


# --- 键盘焦点 -------------------------------------------------------------


## 让一张自绘卡片能被 Tab 到、能按回车。焦点时换一圈强调色描边，回车等于点一下。
## Button 之外的入口（HUD 订单卡、底部采集卡）都靠它接上键盘：用户 2026-10-27 拍板
## 「键盘和手柄是鼠标的替补」，所以鼠标能做的事键盘必须也能做。
## 要求 `control` 是 PanelContainer（有 `panel` stylebox 可以改描边）。
static func make_focusable(control: Control, activated: Callable) -> void:
	var card := control as PanelContainer
	if card == null:
		return
	var base := card.get_theme_stylebox("panel")
	if not base is StyleBoxFlat:
		return
	var focused := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	focused.border_color = ACCENT
	focused.set_border_width_all(3)
	card.focus_mode = Control.FOCUS_ALL
	card.focus_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", focused))
	card.focus_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", base))
	card.gui_input.connect(func(event: InputEvent) -> void:
		# 鼠标点过的卡片不该继续挂着键盘焦点环：Godot 的点击会先让控件 grab_focus，
		# 之后这圈强调色描边会一直亮着，看起来像 hover 卡住了（用户 2026-10-27 报）。
		if event is InputEventMouseButton:
			card.release_focus()
			return
		if event.is_action_pressed("ui_accept"):
			card.accept_event()
			activated.call()
	)

## 禁用按钮顺便退出焦点链：Godot 不会自动跳过 disabled 的按钮，Tab 仍会停在上面，
## 焦点环套在灰字按钮上看起来像坏掉了（B 批实测：设备面板 Tab 停在缺料的升级钮）。
static func set_disabled(button: BaseButton, value: bool) -> void:
	if button == null:
		return
	button.disabled = value
	button.focus_mode = Control.FOCUS_NONE if value else Control.FOCUS_ALL


# --- 提示浮层 -------------------------------------------------------------


## 给控件挂一段提示。走 `TooltipLayer` 而不是 `Control.tooltip_text`：宽度有上限会折行、
## 贴边会翻到控件上方、键盘焦点也能触发（见 scripts/ui/tooltip_layer.gd）。
static func tooltip(control: Control, text: String) -> void:
	if control == null:
		return
	var layer := _tooltip_layer()
	if layer == null:
		control.tooltip_text = text
		return
	layer.call("bind", control, text)


## 场景里那个唯一的浮层（`Main/TooltipCanvas/TooltipLayer`）。放在最高层的 CanvasLayer 里，
## 否则会被 HUD 与面板盖住；找不到时调用方回落到引擎自带的 `tooltip_text`。
static func _tooltip_layer() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.find_child("TooltipLayer", true, false)
