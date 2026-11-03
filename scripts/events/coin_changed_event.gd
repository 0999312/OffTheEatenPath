class_name CoinChangedEvent
extends Event
## 铜币数量变化。`reason` 是给 UI 做飘字用的中文短语（如「首次制作」「设备升级」）。

var coins: int
var delta: int
var reason: String


func _init(p_coins: int, p_delta: int, p_reason: String) -> void:
	coins = p_coins
	delta = p_delta
	reason = p_reason
