class_name LetterReadEvent
extends Event
## 一封信被读过了。未读数因此减少，可能同时解锁了下一封信。
##
## 为什么不复用 LetterUnlockedEvent：解锁是「有新东西」，已读是「新东西看完了」，
## 两者的听众与刷新内容不同（HUD 红点只关心前者与后者，图鉴只关心前者）。

var letter_key: String


func _init(p_letter_key: String) -> void:
	letter_key = p_letter_key
