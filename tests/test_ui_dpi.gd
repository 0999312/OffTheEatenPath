extends GutTest
## 用户 2026-11-03 报的两个高分辨率 UI BUG 的回归：
## 1) 设置页折叠标题的箭头突然极大（与分辨率无关）；
## 2) 滑杆把手在全屏高分辨率下糊边。
##
## 根因都是「引擎按纹理原始像素贴图」：4.7 的 FoldableContainer / Slider 没有
## icon_max_width / grabber_max_size，而 PanelKit 为高分屏把 SVG 栅格化成了 2–6 倍。
## 修法是让主题纹理保持逻辑尺寸（布局、命中区不变），再由子类把高分辨率源缩进去画。
## 这里守住两条：主题纹理尺寸固定、源纹理确实比逻辑尺寸大。

const THEME_PATH := "res://resources/themes/paper_theme.tres"


func test_fold_arrow_is_drawn_at_its_logical_size() -> void:
	var section := PanelKit.fold_section("通用")
	assert_true(section is PaperFoldSection, "折叠标题要用自绘箭头的子类")
	var arrow := section.get_theme_icon("expanded_arrow")
	assert_not_null(arrow, "主题里要留一张透明占位，否则引擎会画出默认箭头")
	if arrow != null:
		var want := Vector2(PaperFoldSection.ICON_SIZE, PaperFoldSection.ICON_SIZE)
		assert_eq(arrow.get_size(), want,
				"箭头纹理必须是 14×14；引擎按纹理尺寸贴图，纹理多大箭头就多大")
	section.free()


func test_slider_grabber_keeps_layout_and_gets_a_high_res_source() -> void:
	var host := Control.new()
	host.theme = load(THEME_PATH)
	add_child_autofree(host)
	var slider := PaperSlider.new()
	host.add_child(slider)
	await wait_process_frames(1)
	assert_eq(slider.get_theme_icon("grabber").get_size(), PaperSlider.GRABBER_SIZE,
			"占位纹理保持 20×20，滑杆的最小尺寸与命中区才不变")
	var source := slider.get("_grabber_texture") as Texture2D
	assert_not_null(source, "主题里的渐变把手要重采样成高分源纹理")
	if source != null:
		assert_gt(source.get_width(), int(PaperSlider.GRABBER_SIZE.x),
				"源纹理要比逻辑尺寸大，高分屏才有东西可缩")
