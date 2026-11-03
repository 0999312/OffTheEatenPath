class_name CraftCompletedEvent
extends Event
## 一份配方做完并入库：食物与半成品都走这个事件。
##
## 为什么不再区分「食物完成」和「制作完成」：音效属于「这一炉出来了」，
## 半成品同样该响；而 toast 只属于成品菜。事件带 is_food，订阅方按需分支。

## 产物完整键，如 `game:item/latte` 或 `game:item/dough`
var output_key: String
## 产物是不是成品食物（Kind.FOOD）
var is_food: bool
## 是否第一次做出这个食物（只有成品食物才可能为 true）
var first_time: bool


func _init(p_output_key: String, p_is_food: bool, p_first_time: bool = false) -> void:
	output_key = p_output_key
	is_food = p_is_food
	first_time = p_first_time
