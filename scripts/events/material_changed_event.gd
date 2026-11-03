class_name MaterialChangedEvent
extends Event
## 某个物品的库存数量发生变化（材料或食物，统一用完整键标识）。
##
## 数量是结算后的总量而不是增量：UI 直接显示 `amount`，不用自己累加。

## 完整键，如 `game:item/coffee_bean`、`game:item/espresso`
var key: String
## 变化后的总量
var amount: float
## 本次变化量（可为负）
var delta: float


func _init(p_key: String, p_amount: float, p_delta: float) -> void:
	key = p_key
	amount = p_amount
	delta = p_delta
