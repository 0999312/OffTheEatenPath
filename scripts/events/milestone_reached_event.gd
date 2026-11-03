class_name MilestoneReachedEvent
extends Event
## 图鉴进度跨过一个里程碑档位：发过铜币、UI 冒一条提示。

var tier: int
var threshold: int
var coins_granted: int


func _init(p_tier: int, p_threshold: int, p_coins_granted: int) -> void:
	tier = p_tier
	threshold = p_threshold
	coins_granted = p_coins_granted
