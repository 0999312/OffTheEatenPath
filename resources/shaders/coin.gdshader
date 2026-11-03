shader_type canvas_item;
render_mode blend_mix;

// 铜板：外圆 + 内圈墨线 + 方孔。全部用距离场算，外缘和孔口都由 fwidth 在当前
// 屏幕像素上做 1px 抗锯齿，所以 34px 和 54px 都不会出现多边形台阶。
uniform vec4 face_color : source_color = vec4(0.878, 0.663, 0.290, 1.0);
uniform vec4 rim_color : source_color = vec4(0.133, 0.188, 0.239, 1.0);
uniform vec4 hole_color : source_color = vec4(0.949, 0.965, 0.980, 1.0);
// 方孔边长占直径的比例
uniform float hole_side : hint_range(0.12, 0.45) = 0.28;
// 墨线宽度占半径的比例
uniform float rim_width : hint_range(0.04, 0.25) = 0.12;
// 一个屏幕像素在 UV 里的宽度：由 CoinIcon 按实际控件尺寸传入，避免依赖 fwidth
uniform float pixel_size = 0.05;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float aa = max(fwidth(radius), pixel_size * 1.5);
	float circle = 1.0 - smoothstep(1.0 - aa, 1.0, radius);
	float rim = smoothstep(1.0 - rim_width - aa, 1.0 - rim_width, radius);
	float hole = 1.0 - smoothstep(hole_side - aa, hole_side + aa, max(abs(p.x), abs(p.y)));
	vec3 color = mix(face_color.rgb, rim_color.rgb, rim);
	color = mix(color, hole_color.rgb, hole);
	COLOR = vec4(color, circle);
}
