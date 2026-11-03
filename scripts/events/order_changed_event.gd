class_name OrderChangedEvent
extends Event
## 订单板发生变化（刷出新委托 / 交付完成）。UI 收到后重拉 get_orders() 即可。

## "refilled" 或 "delivered"
var reason: String
## 相关的委托编号（-1 = 不针对某一条）
var order_id: int


func _init(p_reason: String = "", p_order_id: int = -1) -> void:
	reason = p_reason
	order_id = p_order_id
