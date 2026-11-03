class_name CoinIcon
extends Control
## 铜板：外圈墨线、铜色圆面、中间一个方形孔。
##
## 为什么不用 draw_circle：34px 的圆用多边形画出来边缘会一段一段的，放大后全是
## 锯齿；这里用 `resources/shaders/coin.gdshader` 的距离场在屏幕像素上做 1px
## 抗锯齿，方孔也用同一个场算，转动时孔口同样平滑。
## 孔用背景色填充，调用方要按所在纸面的颜色设置 `hole_color`。

const COIN_SHADER := preload("res://resources/shaders/coin.gdshader")

@export var face_color := PanelKit.COIN
@export var rim_color := PanelKit.INK
@export var hole_color := PanelKit.CARD
## 方孔边长占短边的比例
@export_range(0.12, 0.45, 0.01) var hole_ratio := 0.28

var _material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(34.0, 34.0)
	_material = ShaderMaterial.new()
	_material.shader = COIN_SHADER
	material = _material
	_sync_material()
	resized.connect(_on_resized)


func _sync_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("face_color", face_color)
	_material.set_shader_parameter("rim_color", rim_color)
	_material.set_shader_parameter("hole_color", hole_color)
	_material.set_shader_parameter("hole_side", hole_ratio)
	var side := maxf(1.0, minf(size.x, size.y))
	_material.set_shader_parameter("pixel_size", 2.0 / side)


func _on_resized() -> void:
	_sync_material()
	queue_redraw()


func _draw() -> void:
	# 距离场只关心 UV，真正让圆铺满控件；矩形本身的颜色由 shader 完全覆盖。
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
