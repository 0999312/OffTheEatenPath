class_name CatalogDiscoveredEvent
extends Event
## 图鉴条目首次被点亮。`type_id` 是定义类型（item / recipe / facility / letter / world）。

var key: String
var type_id: String


func _init(p_key: String, p_type_id: String) -> void:
	key = p_key
	type_id = p_type_id
