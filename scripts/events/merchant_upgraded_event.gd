class_name MerchantUpgradedEvent
extends Event
## 商人升了一级：槽位与补货速度变了，商人与 HUD 要跟着刷新。

var level: int


func _init(p_level: int = 1) -> void:
	level = p_level
