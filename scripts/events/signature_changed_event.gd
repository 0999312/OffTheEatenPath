class_name SignatureChangedEvent
extends Event
## 招牌菜的选择变了（设置面板里换了一道，或清空回到自动）。
## 氛围层收到后重拉 `GameState.get_signature_slots()` 重写便条。

## 改动发生在第几个槽位（0 起；-1 = 整体刷新）
var slot: int


func _init(p_slot: int = -1) -> void:
	slot = p_slot
