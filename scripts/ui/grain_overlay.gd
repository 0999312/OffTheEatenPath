extends Control
## 全屏纸纹：一层极淡的颗粒盖在所有东西上面，让界面像「印在同一张纸上」，
## 而不是几块各自干净的矢量色块拼起来的。
##
## 为什么画在最上层而不是背景里：纸纹的意义是统一材质。只画在背景上，
## 纸片、按钮、文字各自是干净的，反而更露馅。
## 颗粒是随机点出来的，但种子固定——同一台机器每次运行纹理都一样。

## 颗粒数量：少了看不出，多了会糊成噪点电视
const GRAIN_COUNT := 2400
const GRAIN_SEED := 880301
## 颗粒半径范围
const GRAIN_RADIUS := Vector2(0.5, 1.5)
## 颗粒颜色：墨色，透明度极低
const GRAIN_TINT := Color(0.11, 0.16, 0.21, 0.055)

## 预生成的颗粒（x, y, 半径），归一化坐标
var _dots: Array[Vector3] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = GRAIN_SEED
	for index in GRAIN_COUNT:
		_dots.append(Vector3(rng.randf(), rng.randf(),
				rng.randf_range(GRAIN_RADIUS.x, GRAIN_RADIUS.y)))


func _draw() -> void:
	var area := size
	for dot in _dots:
		draw_circle(Vector2(dot.x * area.x, dot.y * area.y), dot.z, GRAIN_TINT)
