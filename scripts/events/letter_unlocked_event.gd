class_name LetterUnlockedEvent
extends Event
## 一封信解开了（还在邮箱里，未必读过）。

var letter_key: String
var title: String


func _init(p_letter_key: String, p_title: String) -> void:
	letter_key = p_letter_key
	title = p_title
