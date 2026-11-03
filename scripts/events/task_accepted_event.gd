class_name TaskAcceptedEvent
extends Event
## 玩家在信件详情里按下了「接下这件事」：委托进了待办，HUD 的角标跟着变。
##
## 为什么和 LetterReadEvent 分开：读信是被动发生的（打开就算），接委托是玩家的一次承诺，
## 两者的听众不同——只有后者该让「待办」多一条。

## 信件完整键（game:letter/xxx）
var letter_key: String


func _init(p_letter_key: String) -> void:
	letter_key = p_letter_key
