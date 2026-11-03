class_name KitchenUpgradedEvent
extends Event
## 厨房扩建升了一级：产线条数变了，制作面板与设备面板要跟着刷新。

var level: int


func _init(new_level: int = 1) -> void:
	level = new_level
