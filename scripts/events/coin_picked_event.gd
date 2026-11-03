class_name CoinPickedEvent
extends Event
## 玩家亲手点走了桌角那枚铜板：界面据此弹一句「+1 铜板」。
## 超时自动收下的不发，只有玩家真的伸手了才是那点小庆幸。

var amount: int


func _init(p_amount: int = 0) -> void:
	amount = p_amount
