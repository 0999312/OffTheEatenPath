class_name VfxKit
extends RefCounted
## 一次性小特效的统一工厂：一小撮粒子碎屑 + 一圈扩散的涟漪。
##
## 为什么集中在这里：采集和捡铜板要的是同一种「纸面上轻轻溅开」的语言；各写一份，
## 迟早一个改了点另一个没改。粒子仍只用 GPUParticles2D（项目约束）。
##
## 传入的 `at` 是 parent 的局部坐标。节点自己收尾，调用方不需要保存引用。

## 铜板碎屑的金色；采集材料时由调用方按材料颜色覆盖
const GOLD := Color(0.86, 0.62, 0.30)

## 8×8 的小圆点只生成一次：为几个像素的粒子单独放一张贴图不划算
static var _dot_texture_cache: Texture2D = null


## 粒子用的小圆点（白点 + 边缘渐隐，颜色由 ParticleProcessMaterial 染）
static func dot_texture() -> Texture2D:
	if _dot_texture_cache != null:
		return _dot_texture_cache
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var distance := Vector2(x - 3.5, y - 3.5).length()
			var alpha := clampf(1.0 - distance / 3.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_dot_texture_cache = ImageTexture.create_from_image(image)
	return _dot_texture_cache


## 原地炸开一小撮碎屑：一眨眼就没了，不挡点击。
static func sparkle(parent: CanvasItem, at: Vector2, color: Color = GOLD,
		amount: int = 10, speed: float = 40.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var particles := GPUParticles2D.new()
	particles.name = "Sparkle"
	particles.position = at
	particles.texture = dot_texture()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = maxi(amount, 1)
	particles.lifetime = 0.5
	# 粒子会飞出默认矩形；不给足可见矩形，2D 剔除会在相机移动/窗口缩放时把它整团抹掉
	particles.visibility_rect = Rect2(-96.0, -120.0, 192.0, 220.0)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 2.0
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 180.0
	material.initial_velocity_min = speed * 0.7
	material.initial_velocity_max = speed * 1.6
	material.gravity = Vector3(0.0, 90.0, 0.0)
	material.scale_min = 0.8
	material.scale_max = 1.6
	material.color = color
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_texture := CurveTexture.new()
	fade_texture.curve = fade
	material.alpha_curve = fade_texture
	particles.process_material = material
	particles.z_index = 5
	parent.add_child(particles)
	particles.emitting = true
	parent.get_tree().create_timer(1.0).timeout.connect(particles.queue_free)


## 一圈很快扩开、随即淡掉的圆环。用于「点到了」「刚就绪」这种一瞬间的确认。
static func ring(parent: Control, at: Vector2, color: Color = GOLD,
		size: float = 26.0, duration: float = 0.42) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var ripple := Panel.new()
	ripple.name = "Ring"
	ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ripple.size = Vector2(size, size)
	ripple.position = at - ripple.size * 0.5
	ripple.pivot_offset = ripple.size * 0.5
	ripple.scale = Vector2(0.35, 0.35)
	ripple.modulate.a = 0.7
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = color
	style.set_corner_radius_all(int(size * 0.5))
	ripple.add_theme_stylebox_override("panel", style)
	ripple.z_index = 4
	parent.add_child(ripple)

	var tween := ripple.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ripple, "scale", Vector2(1.8, 1.8), duration)
	tween.tween_property(ripple, "modulate:a", 0.0, duration)
	tween.finished.connect(ripple.queue_free)
