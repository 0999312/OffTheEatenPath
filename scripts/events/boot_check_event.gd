extends Event
class_name BootCheckEvent
## 启动自检专用事件：只为验证 EventBus 的发布 / 订阅链路是否贯通。
##
## 玩法事件不要复用本类型 —— P1 起各系统发布自己的事件类
## （如 material_changed、food_crafted）。

## 自检标记值，订阅方回读后与发布值比对
var marker: int = 0

func _init(p_marker: int = 0) -> void:
	marker = p_marker
