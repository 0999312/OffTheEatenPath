extends Control
## 房间背景：冷色纸上画一层很淡的装饰——水彩晕、纸纹颗粒、墙地交线。
##
## 全部用 _draw() 程序化画（渐变贴图也是运行时生成的）：项目里没有背景美术，
## 「画面不像表格」这件事得靠版式与层次来做，这里负责把底子从纯色纸变成有厚度、会呼吸的纸。

## 水彩晕：位置用相对坐标（0–1），随窗口缩放
const WASHES: Array[Dictionary] = [
	{"pos": Vector2(0.08, 0.10), "radius": 0.34, "tint": Color(0.55, 0.74, 0.84, 0.30)},
	{"pos": Vector2(0.95, 0.14), "radius": 0.26, "tint": Color(0.62, 0.80, 0.78, 0.26)},
	{"pos": Vector2(0.88, 0.92), "radius": 0.30, "tint": Color(0.58, 0.70, 0.86, 0.24)},
	{"pos": Vector2(0.12, 0.94), "radius": 0.24, "tint": Color(0.66, 0.78, 0.86, 0.22)},
]

const GRAIN_COUNT := 520
const GRAIN_SEED := 20251024
const FLOOR_LINE_RATIO := 0.80

## 水彩晕重画的间隔：漂移是二三十秒一轮的慢动作，20 帧/秒已经比肉眼更细。
## 不跟屏幕同频，是因为每帧都要把颗粒点和水彩晕重新提交一遍，画面上却看不出区别。
const WASH_REDRAW_INTERVAL := 1.0 / 20.0

## 水彩晕的软边用一张程序生成的径向渐变贴图来画，而不是几个同心圆。
## 同心圆会在低透明度下留下色阶，渐变贴图在漂移时是连续变化的，看起来才像颜料在纸上洇开。
const WASH_TEXTURE_SIZE := 128
## 中心 45% 是不透明的核心，往外用 smoothstep 淡出。
## 水彩的边缘比中心更有存在感；把变化集中在外圈，漂移才看得出来。
const WASH_CORE_RATIO := 0.45
## 渐变贴图的外缘正好落在 1.35 倍半径处；原先硬边的外圈是 1.32 倍
const WASH_OUTER_RATIO := 1.35

## 漂移幅度按画面尺寸取比例：1280×720 下最大约 77×65 像素，
## 主周期约 26–33 秒；再叠一个更慢的次分量，避免圆心停在端点时看起来「没在动」。
## 可视的只是四边窄条，大团水彩如果只挪十几像素，在窄条里根本看不出来，所以幅度要够大。
const WASH_DRIFT_RATIO := Vector2(0.060, 0.090)
const WASH_DRIFT_SPEED := Vector2(0.24, 0.19)
const WASH_DRIFT_SECONDARY_SPEED := Vector2(0.14, 0.11)
const WASH_DRIFT_SECONDARY_WEIGHT := 0.32
## 半径和透明度也在呼吸，但幅度小于漂移，免得整块背景像在「喘气」
const WASH_BREATH_SPEED := 0.17
const WASH_BREATH_AMOUNT := 0.035
const WASH_ALPHA_SPEED := 0.13
const WASH_ALPHA_AMOUNT := 0.10

var _grain: Array[Vector3] = []
var _wash_texture: Texture2D
## 从进树开始累计的时间：驱动水彩晕的相位，不用 Timer 也不依赖系统时钟
var _time := 0.0
var _redraw_left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_grain()
	_wash_texture = _build_wash_texture()
	resized.connect(_on_resized)


func _process(delta: float) -> void:
	_time += delta
	_redraw_left -= delta
	if _redraw_left > 0.0:
		return
	_redraw_left = WASH_REDRAW_INTERVAL
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


## 预先算好颗粒点，避免每帧重新随机（窗口高频重绘时会抖）
func _build_grain() -> void:
	_grain.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = GRAIN_SEED
	for i in GRAIN_COUNT:
		_grain.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.7, 1.9)))


## 白色径向渐变：中心不透明，边缘透明；绘制时靠 modulate 上色。
## 用贴图而不是画几十个同心圆，是为了让半透明边缘在移动时连续、不出现色阶。
func _build_wash_texture() -> Texture2D:
	var tex_size := WASH_TEXTURE_SIZE
	var img := Image.create_empty(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var half := float(tex_size - 1) * 0.5
	for y in tex_size:
		for x in tex_size:
			var offset := Vector2(float(x) - half, float(y) - half)
			var falloff := clampf(offset.length() / half, 0.0, 1.0)
			var edge := clampf((falloff - WASH_CORE_RATIO) / (1.0 - WASH_CORE_RATIO), 0.0, 1.0)
			var alpha := 1.0 - (edge * edge * (3.0 - 2.0 * edge))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var area := size
	if area.x <= 0.0 or area.y <= 0.0:
		return

	# 地板：下半部分压深一点，暗示「站在屋里」
	var floor_y := area.y * FLOOR_LINE_RATIO
	draw_rect(Rect2(0.0, floor_y, area.x, area.y - floor_y),
			Color(0.70, 0.76, 0.82, 0.35))

	# 墙地交线：一条淡淡的墨线，两端渐隐
	draw_line(Vector2(area.x * 0.02, floor_y), Vector2(area.x * 0.98, floor_y),
			Color(0.13, 0.19, 0.24, 0.16), 2.0)

	# 水彩晕：一张软边渐变贴图，像颜料在纸上洇开。
	# 圆心做不同相位的慢漂移、半径和透明度轻轻呼吸——像纸吸了水之后还在慢慢洇开，
	# 而不是一张印死的背景。幅度压在画面几个百分点内，不抢前面的内容。
	if _wash_texture != null:
		for i in WASHES.size():
			var wash: Dictionary = WASHES[i]
			var phase := float(i) * 1.7
			var primary_weight := 1.0 - WASH_DRIFT_SECONDARY_WEIGHT
			var drift := Vector2(
				sin(_time * WASH_DRIFT_SPEED.x + phase) * primary_weight
					+ sin(_time * WASH_DRIFT_SECONDARY_SPEED.x + phase * 2.3) * WASH_DRIFT_SECONDARY_WEIGHT,
				cos(_time * WASH_DRIFT_SPEED.y + phase * 1.31) * primary_weight
					+ cos(_time * WASH_DRIFT_SECONDARY_SPEED.y + phase * 1.7) * WASH_DRIFT_SECONDARY_WEIGHT
			) * Vector2(area.x * WASH_DRIFT_RATIO.x, area.y * WASH_DRIFT_RATIO.y)
			var center: Vector2 = Vector2(wash["pos"]) * area + drift
			var breath := 1.0 + sin(_time * WASH_BREATH_SPEED + phase) * WASH_BREATH_AMOUNT
			var radius: float = wash["radius"] * minf(area.x, area.y) * breath
			var tint: Color = wash["tint"]
			# 透明度也呼吸，但始终保底 90%：水彩要「淡」，不能忽隐忽现
			tint.a *= 1.0 + sin(_time * WASH_ALPHA_SPEED + phase * 0.8) * WASH_ALPHA_AMOUNT
			var diameter := radius * 2.0 * WASH_OUTER_RATIO
			var rect := Rect2(center - Vector2.ONE * (diameter * 0.5), Vector2.ONE * diameter)
			draw_texture_rect(_wash_texture, rect, false, tint)

	# 纸纹颗粒
	var grain_color := Color(0.13, 0.19, 0.24, 0.055)
	for point in _grain:
		draw_circle(Vector2(point.x * area.x, point.y * area.y), point.z, grain_color)
