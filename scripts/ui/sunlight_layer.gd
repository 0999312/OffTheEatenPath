extends ColorRect
## 车窗光：直接使用 GodotShaders 的 God Rays（godotshaders.com/shader/god-rays）。
##
## 只做 Godot 4 兼容性改动，光形算法保持原作者版本。全部参数以导出属性暴露，
## 可用 scenes/tools/sunlight_tuner.tscn 实时调参；调好后把这里的默认值改成
## 调参器里复制出来的数值即可。
##
## 节点是 Backdrop 的子节点：screen_texture 在这一层只读到背景板，Room、HUD、
## 入口卡、桌面和面板都画在它上面，不会被染色。
const SHADER := preload("res://resources/shaders/sunlight.gdshader")

## 右侧车窗横射进来的主光 + 少量细光；调参器里的「推荐：一大束」就是这个组合。
@export_range(-3.14, 3.14, 0.01) var angle := 1.0
## shader 里的 position（标量）。脚本里不能叫 position，会与 Control.position 冲突。
@export_range(-2.0, 2.0, 0.01) var beam_position := 0.15
@export_range(0.0, 1.0, 0.01) var spread := 0.5
@export_range(-1.0, 1.0, 0.01) var cutoff := 0.18
@export_range(0.0, 1.0, 0.01) var falloff := 0.2
@export_range(0.0, 1.0, 0.01) var edge_fade := 0.15
@export_range(0.0, 4.0, 0.01) var speed := 1.0
@export_range(1.0, 64.0, 0.1) var ray1_density := 4.0
@export_range(1.0, 64.0, 0.1) var ray2_density := 40.0
@export_range(0.0, 1.0, 0.01) var ray2_intensity := 0.35
## shader 里的 color；脚本里不能叫 color，会与 ColorRect.color 冲突。
@export var ray_color := Color(1.0, 0.9, 0.65, 0.6)
@export var hdr := true
@export_range(0.0, 100.0, 0.1) var noise_seed := 5.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	material = shader_material
	apply_parameters()


## 把导出属性写进材质；调参器也直接调用这个函数。
func apply_parameters() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("angle", angle)
	shader_material.set_shader_parameter("position", beam_position)
	shader_material.set_shader_parameter("spread", spread)
	shader_material.set_shader_parameter("cutoff", cutoff)
	shader_material.set_shader_parameter("falloff", falloff)
	shader_material.set_shader_parameter("edge_fade", edge_fade)
	shader_material.set_shader_parameter("speed", speed)
	shader_material.set_shader_parameter("ray1_density", ray1_density)
	shader_material.set_shader_parameter("ray2_density", ray2_density)
	shader_material.set_shader_parameter("ray2_intensity", ray2_intensity)
	shader_material.set_shader_parameter("color", ray_color)
	shader_material.set_shader_parameter("hdr", hdr)
	shader_material.set_shader_parameter("seed", noise_seed)
