extends UIPanel
class_name DiagnosticPanel
## 框架自检用的最小面板。
##
## P0 用它验证「UIRegistry 注册 → instantiate_panel → 打开 → 关闭」整条链路，
## 同时充当 P3 业务面板的模板：根节点 Control + 继承 UIPanel 的脚本 + 生命周期回调。
## 正常游戏流程不会打开本面板（只有自检会），因此不含玩法逻辑。

## 提示文字（由打开时传入的 data 覆盖）
@onready var _hint_label: Label = $Center/Card/Layout/Hint

## 本实例被打开的次数（自检用于确认生命周期被调用）
var open_count: int = 0

func _on_open(data: Dictionary = {}) -> void:
	open_count += 1
	if _hint_label != null and data.has("hint"):
		_hint_label.text = str(data["hint"])
