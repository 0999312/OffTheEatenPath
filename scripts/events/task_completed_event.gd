class_name TaskCompletedEvent
extends Event
## 待办里的一件委托办妥了：报酬已经发进账，提示与音效由 GameBridge 补上。

## 信件完整键（game:letter/xxx）
var letter_key: String


func _init(p_letter_key: String) -> void:
	letter_key = p_letter_key
