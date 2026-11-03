class_name JobBars
extends Control
## 卡片末行的制作进度：1 份 = 整条，N 份 = 等分 N 段，最多 4 段 + 「+N」。
## 只重画，不建节点；颜色来自设备标志色（FacilityDef.display_accent）。

const TRACK_COLOR := Color(0.14, 0.19, 0.24, 0.16)
const SEGMENT_GAP := 2.0
const MAX_SEGMENTS := 4
const EXTRA_WIDTH := 20.0

var _segments: Array[Dictionary] = []
var _extra := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 8.0


## segments: [{progress: float 0..1, color: Color}]
func set_segments(segments: Array[Dictionary], extra: int = 0) -> void:
	_segments = segments
	_extra = maxi(0, extra)
	queue_redraw()


func _draw() -> void:
	var height := size.y
	if height <= 0.0 or size.x <= 0.0:
		return
	# 没有活就不画轨道：空轨道看起来像「进度 0%」的制作中，容易误读。
	# 高度由外层固定 13px 的容器保留，行高照样不跳。
	if _segments.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, height)), TRACK_COLOR)
	var right_margin := EXTRA_WIDTH if _extra > 0 else 0.0
	var count := mini(_segments.size(), MAX_SEGMENTS)
	var available := maxf(0.0, size.x - right_margin)
	var gap := SEGMENT_GAP * maxf(0.0, count - 1)
	var segment_width := maxf(0.0, (available - gap) / float(count))
	for i in count:
		var segment: Dictionary = _segments[i]
		var x := float(i) * (segment_width + SEGMENT_GAP)
		var rect := Rect2(Vector2(x, 0.0), Vector2(segment_width, height))
		draw_rect(rect, Color(0.14, 0.19, 0.24, 0.10))
		var progress := clampf(float(segment.get("progress", 0.0)), 0.0, 1.0)
		if progress > 0.0:
			draw_rect(Rect2(rect.position, Vector2(segment_width * progress, height)),
					segment.get("color", PanelKit.ACCENT) as Color)
	if _extra > 0:
		var font := get_theme_font("font", "Label")
		if font != null:
			var text := "+%d" % _extra
			var baseline := (height + font.get_ascent(9) - font.get_descent(9)) * 0.5
			draw_string(font, Vector2(size.x - EXTRA_WIDTH + 2.0, baseline), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PanelKit.INK_SOFT)
